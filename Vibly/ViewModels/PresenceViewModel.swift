import Combine
import Foundation
import AppKit

@MainActor
final class PresenceViewModel: ObservableObject {
    @Published var configuration: PresenceConfiguration
    @Published var applicationID: String
    @Published private(set) var currentPresence: PresenceConfiguration?
    @Published private(set) var presets: [PresencePreset]
    @Published var selectedPresetID: UUID?
    @Published private(set) var connectionState: DiscordConnectionState
    @Published var message: String?
    @Published var errorMessage: String?
    @Published private(set) var publicationWarning: String?
    @Published private(set) var hasUnpublishedChanges = false
    @Published private(set) var isPublishing = false
    @Published var automaticRule: AppPresenceRule
    @Published var automaticStatus = "Choose an application to begin."
    @Published private(set) var frontmostApplicationName: String?

    private let store: PresetStore
    private let discord: DiscordPresenceProviding
    private var automaticObserver: NSObjectProtocol?
    private var automaticSignature: String?
    private var automaticPresence: PresenceConfiguration?
    private var discordHasStarted = false

    init(
        store: PresetStore = PresetStore(),
        discord: DiscordPresenceProviding = DiscordPresenceService()
    ) {
        self.store = store
        self.discord = discord
        self.configuration = store.loadLastConfiguration()
        let savedApplicationID = store.loadApplicationID()
        self.applicationID = savedApplicationID
        self.presets = store.loadPresets()
        self.selectedPresetID = nil
        var savedAutomaticRule = store.loadAutomaticRule()
        savedAutomaticRule.mode = .frontmostOnly
        self.automaticRule = savedAutomaticRule
        discord.configure(applicationID: savedApplicationID)
        self.connectionState = discord.state
    }

    var selectedPresetName: String {
        presets.first(where: { $0.id == selectedPresetID })?.name ?? "Custom"
    }

    func start() {
        beginAutomaticTracking()
        store.saveApplicationID(applicationID)
        discord.configure(applicationID: applicationID)
        connectionState = .starting
        Task {
            do {
                try await discord.start()
                connectionState = discord.state
                discordHasStarted = true
                refreshAutomaticPresence()
            } catch {
                discordHasStarted = false
                connectionState = .error(error.localizedDescription)
            }
        }
    }

    func connectDiscord() {
        start()
    }

    func selectPreset(_ preset: PresencePreset) {
        selectedPresetID = preset.id
        configuration = preset.configuration
        hasUnpublishedChanges = true
        errorMessage = nil
    }

    func setPresence(restartTimer: Bool = true) {
        guard !isPublishing else { return }
        let draft = configuration
        let rule = automaticRule
        var configurationToPublish = draft
        if automaticRule.enabled, !automaticRule.applicationDisplayName.isEmpty {
            configurationToPublish.activity = automaticRule.applicationDisplayName
        }

        guard configurationToPublish.validationError == nil else {
            errorMessage = configurationToPublish.validationError
            message = nil
            return
        }

        var startedConfiguration = configurationToPublish.startingNow()
        if !restartTimer, let currentPresence,
           currentPresence.activity == startedConfiguration.activity,
           currentPresence.showElapsedTime == draft.showElapsedTime,
           currentPresence.useCustomStartTime == draft.useCustomStartTime,
           currentPresence.customStartAt == draft.customStartAt {
            startedConfiguration.startedAt = currentPresence.startedAt
        }
        store.saveLastConfiguration(configuration)
        isPublishing = true
        message = nil

        Task {
            defer { isPublishing = false }
            do {
                publicationWarning = try await discord.setPresence(startedConfiguration)
                currentPresence = startedConfiguration
                hasUnpublishedChanges = configuration != draft || automaticRule != rule
                message = "Presence updated."
                errorMessage = nil
                connectionState = discord.state
            } catch {
                errorMessage = error.localizedDescription
                message = nil
                connectionState = discord.state
            }
        }
    }

    func clearPresence() {
        Task {
            do {
                try await discord.clearPresence()
                currentPresence = nil
                publicationWarning = nil
                automaticPresence = nil
                automaticSignature = nil
                hasUnpublishedChanges = false
                message = "Presence cleared."
                errorMessage = nil
                connectionState = discord.state
            } catch {
                errorMessage = error.localizedDescription
                message = nil
                connectionState = discord.state
            }
        }
    }

    func persistAutomaticRule() {
        store.saveAutomaticRule(automaticRule)
        automaticSignature = nil
        hasUnpublishedChanges = true

        if automaticRule.enabled {
            refreshAutomaticPresence()
        } else {
            automaticStatus = "Automatic updates are off."
            clearAutomaticPresenceIfNeeded()
        }
    }

    func selectAutomaticApplication(at url: URL) {
        guard let bundle = Bundle(url: url), let bundleIdentifier = bundle.bundleIdentifier else {
            automaticStatus = "That file is not a recognizable macOS application."
            return
        }

        let displayName =
            (bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
            ?? (bundle.object(forInfoDictionaryKey: "CFBundleName") as? String)
            ?? url.deletingPathExtension().lastPathComponent

        automaticRule.applicationBundleIdentifier = bundleIdentifier
        automaticRule.applicationDisplayName = displayName
        automaticRule.enabled = false
        automaticSignature = nil
        hasUnpublishedChanges = true
        store.saveAutomaticRule(automaticRule)
        automaticStatus = "Ready to track \(displayName)."
    }

    private func beginAutomaticTracking() {
        guard automaticObserver == nil else {
            refreshAutomaticPresence()
            return
        }

        automaticObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let application = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            let bundleIdentifier = application?.bundleIdentifier
            let displayName = application?.localizedName
            Task { @MainActor [weak self] in
                self?.handleFrontmostApplication(
                    bundleIdentifier: bundleIdentifier,
                    displayName: displayName
                )
            }
        }

        let application = NSWorkspace.shared.frontmostApplication
        handleFrontmostApplication(
            bundleIdentifier: application?.bundleIdentifier,
            displayName: application?.localizedName
        )
    }

    private func refreshAutomaticPresence() {
        let application = NSWorkspace.shared.frontmostApplication
        handleFrontmostApplication(
            bundleIdentifier: application?.bundleIdentifier,
            displayName: application?.localizedName
        )
    }

    private func handleFrontmostApplication(bundleIdentifier: String?, displayName: String?) {
        frontmostApplicationName = displayName

        guard automaticRule.enabled else {
            automaticStatus = automaticRule.applicationDisplayName.isEmpty
                ? "Choose an application to begin."
                : "Automatic updates are off."
            return
        }

        guard !automaticRule.applicationBundleIdentifier.isEmpty else {
            automaticStatus = "Choose an application to begin."
            return
        }

        guard discordHasStarted else {
            automaticStatus = "Waiting for Discord connection."
            return
        }

        guard bundleIdentifier == automaticRule.applicationBundleIdentifier else {
            automaticStatus = "Waiting for \(automaticRule.applicationDisplayName) to become active."
            clearAutomaticPresenceIfNeeded()
            return
        }

        publishAutomaticPresence(displayName: displayName)
    }

    private func publishAutomaticPresence(displayName: String?) {
        let activityName = displayName ?? automaticRule.applicationDisplayName
        var automaticConfiguration = configuration
        automaticConfiguration.activity = activityName

        guard automaticConfiguration.validationError == nil else {
            errorMessage = automaticConfiguration.validationError
            automaticStatus = "Fix the image fields before automatic updates can publish."
            return
        }

        let signature = [
            automaticRule.applicationBundleIdentifier,
            automaticConfiguration.activity,
            automaticConfiguration.details,
            automaticConfiguration.state,
            automaticConfiguration.largeImageKey ?? "",
            automaticConfiguration.largeImageText ?? "",
            automaticConfiguration.smallImageKey ?? "",
            automaticConfiguration.smallImageText ?? "",
            String(automaticConfiguration.showElapsedTime),
            String(automaticConfiguration.customStartAt?.timeIntervalSince1970 ?? 0)
        ].joined(separator: "|")

        guard signature != automaticSignature else { return }
        automaticSignature = signature

        automaticConfiguration = automaticConfiguration.startingNow()

        Task {
            do {
                publicationWarning = try await discord.setPresence(automaticConfiguration)
                currentPresence = automaticConfiguration
                automaticPresence = automaticConfiguration
                hasUnpublishedChanges = false
                message = "Automatic presence updated."
                errorMessage = nil
                connectionState = discord.state
                automaticStatus = "\(activityName) is active."
            } catch {
                automaticSignature = nil
                errorMessage = error.localizedDescription
                message = nil
                connectionState = discord.state
                automaticStatus = "Could not update automatic presence."
            }
        }
    }

    private func clearAutomaticPresenceIfNeeded() {
        let presenceToClear = automaticPresence ?? (automaticRule.enabled ? currentPresence : nil)
        guard let presenceToClear else { return }

        automaticPresence = nil
        automaticSignature = nil

        guard currentPresence == presenceToClear else { return }

        Task {
            do {
                try await discord.clearPresence()
                currentPresence = nil
                hasUnpublishedChanges = false
                connectionState = discord.state
            } catch {
                errorMessage = error.localizedDescription
                connectionState = discord.state
            }
        }
    }

    func savePreset() {
        guard configuration.validationError == nil else {
            errorMessage = configuration.validationError
            return
        }

        let name = selectedPresetName == "Custom" ? configuration.trimmedActivity : selectedPresetName
        let preset = PresencePreset(name: name, configuration: configuration)
        presets.append(preset)
        selectedPresetID = preset.id
        store.savePresets(presets)
        message = "Preset saved."
        errorMessage = nil
    }

    func persistForm() {
        store.saveLastConfiguration(configuration)
        hasUnpublishedChanges = true
        message = nil
        if automaticRule.enabled {
            automaticSignature = nil
            refreshAutomaticPresence()
        }
    }
}
