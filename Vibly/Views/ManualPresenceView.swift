import Foundation
import SwiftUI
import UniformTypeIdentifiers

struct ManualPresenceView: View {
    @EnvironmentObject private var model: PresenceViewModel
    @State private var showingImageImporter = false
    @State private var showingApplicationImporter = false
    @State private var selectedImageName: String?
    @State private var imageImportMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            GlassCard {
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Label("New presence", systemImage: "slider.horizontal.3")
                            .font(.headline)
                        Spacer()
                        Text(model.automaticRule.enabled ? "Tracking" : "Custom")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(model.automaticRule.enabled ? .green : .secondary)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 5)
                            .background(.thinMaterial, in: Capsule())
                    }

                    Toggle("Track a selected app", isOn: $model.automaticRule.enabled)
                        .toggleStyle(.switch)
                        .onChange(of: model.automaticRule.enabled) { _, _ in
                            model.persistAutomaticRule()
                        }

                    if model.automaticRule.enabled || !model.automaticRule.applicationDisplayName.isEmpty {
                        HStack(spacing: 12) {
                            Image(systemName: model.automaticRule.applicationDisplayName.isEmpty ? "app.badge" : "app.fill")
                                .font(.title2)
                                .foregroundStyle(.tint)
                                .frame(width: 34, height: 34)
                                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))

                            VStack(alignment: .leading, spacing: 3) {
                                if model.automaticRule.applicationDisplayName.isEmpty {
                                    Text("Choose an application")
                                        .foregroundStyle(.secondary)
                                } else {
                                    Text(model.automaticRule.applicationDisplayName)
                                        .font(.body.weight(.medium))
                                    Text("Activity name while this app is active")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }

                            Spacer()

                            Button("Choose app") {
                                showingApplicationImporter = true
                            }
                            .buttonStyle(.bordered)
                        }

                        if model.automaticRule.enabled {
                            HStack(spacing: 8) {
                                Circle()
                                    .fill(Color.green)
                                    .frame(width: 7, height: 7)
                                Text(model.automaticStatus)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 13) {
                        if model.automaticRule.enabled {
                            readonlyField(
                                "Activity",
                                value: model.automaticRule.applicationDisplayName.isEmpty
                                    ? "Choose an application"
                                    : model.automaticRule.applicationDisplayName
                            )
                            Text("The selected app supplies the activity name. Customize the fields below.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            field("Activity", text: $model.configuration.activity, prompt: "What are you doing?")
                            Text("This becomes the activity name shown in Discord.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        field("Details", text: $model.configuration.details, prompt: "Optional details")
                        field("State", text: $model.configuration.state, prompt: "Optional state")
                    }
                }
            }

            GlassCard {
                VStack(alignment: .leading, spacing: 13) {
                    Label("Timing", systemImage: "clock")
                        .font(.headline)

                    Toggle("Show elapsed time", isOn: $model.configuration.showElapsedTime)
                        .toggleStyle(.switch)
                        .onChange(of: model.configuration.showElapsedTime) { _, _ in
                            model.persistForm()
                        }

                    Toggle("Use a custom start time", isOn: $model.configuration.useCustomStartTime)
                        .toggleStyle(.switch)
                        .onChange(of: model.configuration.useCustomStartTime) { _, enabled in
                            if enabled && model.configuration.customStartAt == nil {
                                model.configuration.customStartAt = Date()
                            }
                            model.persistForm()
                        }

                    if model.configuration.useCustomStartTime {
                        HStack(spacing: 10) {
                            DatePicker(
                                "Started at",
                                selection: Binding(
                                    get: { model.configuration.customStartAt ?? Date() },
                                    set: { model.configuration.customStartAt = $0; model.persistForm() }
                                ),
                                displayedComponents: [.date, .hourAndMinute]
                            )
                            .font(.callout)

                            Button("Now") {
                                model.configuration.customStartAt = Date()
                                model.persistForm()
                            }
                            .buttonStyle(.bordered)
                        }

                        Text("Changes the Discord timer only; your Mac's clock stays untouched.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            GlassCard {
                DisclosureGroup {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Upload artwork in Discord's Developer Portal, then enter its exact asset key here. Large is the main image; small appears as its badge.")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        HStack(spacing: 10) {
                            Button {
                                showingImageImporter = true
                            } label: {
                                Label("Choose image file", systemImage: "photo.on.rectangle")
                            }
                            .buttonStyle(.bordered)

                            if let selectedImageName {
                                Text(selectedImageName)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }

                        if let imageImportMessage {
                            Text(imageImportMessage)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Link(
                            "Open Discord Developer Portal",
                            destination: URL(string: "https://discord.com/developers/applications")!
                        )
                        .font(.caption)

                        field("Main image asset key", text: Binding(
                            get: { model.configuration.largeImageKey ?? "" },
                            set: { model.configuration.largeImageKey = $0.isEmpty ? nil : $0 }
                        ), prompt: "For example: studying")
                        field("Main image hover text", text: Binding(
                            get: { model.configuration.largeImageText ?? "" },
                            set: { model.configuration.largeImageText = $0.isEmpty ? nil : $0 }
                        ), prompt: "Optional hover text")
                        field("Badge image asset key", text: Binding(
                            get: { model.configuration.smallImageKey ?? "" },
                            set: { model.configuration.smallImageKey = $0.isEmpty ? nil : $0 }
                        ), prompt: "Optional small image")
                        field("Badge hover text", text: Binding(
                            get: { model.configuration.smallImageText ?? "" },
                            set: { model.configuration.smallImageText = $0.isEmpty ? nil : $0 }
                        ), prompt: "Optional hover text")

                        Text("Badge hover text appears when you hover over the small image in Discord.")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        if let assetValidationError = model.configuration.assetValidationError {
                            Label(assetValidationError, systemImage: "exclamationmark.triangle")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }

                        Button(model.isPublishing ? "Applying…" : "Apply images to Discord") {
                            model.setPresence(restartTimer: false)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(model.isPublishing)

                        if let errorMessage = model.errorMessage {
                            Text(errorMessage)
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                        if let warning = model.publicationWarning {
                            Label(warning, systemImage: "exclamationmark.triangle")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                    }
                    .padding(.top, 12)
                } label: {
                    Label("Rich Presence images", systemImage: "photo.stack")
                        .font(.headline)
                }
            }

            GlassCard {
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Label("Publish", systemImage: "paperplane")
                            .font(.headline)
                        Spacer()
                        Picker("Preset", selection: $model.selectedPresetID) {
                            Text("Custom").tag(UUID?.none)
                            ForEach(model.presets) { preset in
                                Text(preset.name).tag(Optional(preset.id))
                            }
                        }
                        .labelsHidden()
                        .onChange(of: model.selectedPresetID) { _, newValue in
                            guard let id = newValue,
                                  let preset = model.presets.first(where: { $0.id == id }) else { return }
                            model.selectPreset(preset)
                        }
                    }

                    if model.hasUnpublishedChanges {
                        Label("Draft changes not published to Discord yet.", systemImage: "exclamationmark.circle")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }

                    HStack(spacing: 10) {
                        Button("Publish to Discord") {
                            model.setPresence()
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .disabled(model.isPublishing)

                        Button("Clear") {
                            model.clearPresence()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.large)

                        Button("Save preset") {
                            model.savePreset()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                    }
                }
            }

            if let errorMessage = model.errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .foregroundStyle(.red)
                    .padding(.horizontal, 4)
            } else if let message = model.message {
                Label(message, systemImage: "checkmark.circle.fill")
                    .font(.callout)
                    .foregroundStyle(.green)
                    .padding(.horizontal, 4)
            }

            CurrentPresenceView(presence: model.currentPresence)

            GlassCard {
                VStack(alignment: .leading, spacing: 12) {
                    Label("Discord connection", systemImage: "link")
                        .font(.headline)

                    HStack(spacing: 10) {
                        TextField("Paste your Application ID", text: $model.applicationID)
                            .textFieldStyle(.plain)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 9)
                            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .strokeBorder(.primary.opacity(0.10), lineWidth: 1)
                            }

                        Button("Connect") {
                            model.connectDiscord()
                        }
                        .buttonStyle(.bordered)
                    }

                    Text("Create an application in the Discord Developer Portal and paste its Application ID here.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    HStack {
                        ConnectionBadge(state: model.connectionState)
                        Spacer()
                        Button("Retry") {
                            model.start()
                        }
                        .buttonStyle(.link)
                    }
                }
            }
        }
        .onChange(of: model.configuration.activity) { _, _ in model.persistForm() }
        .onChange(of: model.configuration.details) { _, _ in model.persistForm() }
        .onChange(of: model.configuration.state) { _, _ in model.persistForm() }
        .onChange(of: model.configuration.largeImageKey) { _, _ in model.persistForm() }
        .onChange(of: model.configuration.largeImageText) { _, _ in model.persistForm() }
        .onChange(of: model.configuration.smallImageKey) { _, _ in model.persistForm() }
        .onChange(of: model.configuration.smallImageText) { _, _ in model.persistForm() }
        .fileImporter(
            isPresented: $showingImageImporter,
            allowedContentTypes: [.image],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                let key = suggestedAssetKey(for: url)
                selectedImageName = url.lastPathComponent
                model.configuration.largeImageKey = key
                model.persistForm()
                imageImportMessage = "Suggested key: \(key). Upload the image in Discord using this exact key."
            case .failure(let error):
                imageImportMessage = "Could not choose that image: \(error.localizedDescription)"
            }
        }
        .fileImporter(
            isPresented: $showingApplicationImporter,
            allowedContentTypes: [.application],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                model.selectAutomaticApplication(at: url)
            case .failure(let error):
                model.automaticStatus = "Could not choose that application: \(error.localizedDescription)"
            }
        }
    }

    private func field(_ title: String, text: Binding<String>, prompt: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.subheadline.weight(.medium))
            TextField(prompt, text: text)
                .textFieldStyle(.plain)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(.primary.opacity(0.10), lineWidth: 1)
            }
        }
    }

    private func readonlyField(_ title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.subheadline.weight(.medium))
            Text(value)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .foregroundStyle(.primary)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(.primary.opacity(0.10), lineWidth: 1)
                }
        }
    }

    private func suggestedAssetKey(for url: URL) -> String {
        let filename = url.deletingPathExtension().lastPathComponent
        let key = filename
            .lowercased()
            .replacingOccurrences(of: " ", with: "_")
        return key.isEmpty ? "vibly_asset" : key
    }
}

struct AutomaticPresenceView: View {
    @EnvironmentObject private var model: PresenceViewModel
    @State private var showingApplicationImporter = false

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Label("Automatic", systemImage: "sparkles")
                        .font(.headline)
                    Spacer()
                    Text(model.automaticRule.enabled ? "On" : "Off")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(model.automaticRule.enabled ? .green : .secondary)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(.thinMaterial, in: Capsule())
                }

                Text(model.automaticRule.mode == .fake
                     ? "Choose an app and Vibly will publish its name to Discord even when it is closed."
                     : "Choose an app and Vibly will publish its name while it is the frontmost app.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Picker("Behavior", selection: $model.automaticRule.mode) {
                    ForEach([AutomaticAppMode.fake, .frontmostOnly], id: \.self) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)

                Text(model.automaticRule.mode.explanation)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack(spacing: 12) {
                    Image(systemName: model.automaticRule.applicationDisplayName.isEmpty ? "app.badge" : "app.fill")
                        .font(.title2)
                        .foregroundStyle(.tint)
                        .frame(width: 34, height: 34)
                        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))

                    VStack(alignment: .leading, spacing: 3) {
                        if model.automaticRule.applicationDisplayName.isEmpty {
                            Text("No application selected")
                                .foregroundStyle(.secondary)
                        } else {
                            Text(model.automaticRule.applicationDisplayName)
                                .font(.body.weight(.medium))
                            Text(model.automaticRule.applicationBundleIdentifier)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }

                    Spacer()

                    Button("Choose app") {
                        showingApplicationImporter = true
                    }
                    .buttonStyle(.bordered)
                }

                automaticField(
                    "Custom description",
                    text: Binding(
                        get: { model.automaticRule.customDescription },
                        set: { model.automaticRule.customDescription = $0 }
                    ),
                    prompt: "For example: Deep work"
                )

                Toggle("Enable automatic updates", isOn: $model.automaticRule.enabled)
                    .toggleStyle(.switch)

                HStack(spacing: 8) {
                    Circle()
                        .fill(model.automaticRule.enabled ? Color.green : Color.secondary)
                        .frame(width: 7, height: 7)
                    Text(model.automaticStatus)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let frontmostApplicationName = model.frontmostApplicationName {
                    Text("Frontmost now: \(frontmostApplicationName)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .onChange(of: model.automaticRule) { _, _ in
            model.persistAutomaticRule()
        }
        .fileImporter(
            isPresented: $showingApplicationImporter,
            allowedContentTypes: [.application],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                model.selectAutomaticApplication(at: url)
            case .failure(let error):
                model.automaticStatus = "Could not choose that application: \(error.localizedDescription)"
            }
        }
    }

    private func automaticField(_ title: String, text: Binding<String>, prompt: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.subheadline.weight(.medium))
            TextField(prompt, text: text)
                .textFieldStyle(.plain)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(.primary.opacity(0.10), lineWidth: 1)
                }
        }
    }
}
