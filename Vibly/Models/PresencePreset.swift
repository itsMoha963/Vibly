import Foundation

struct PresencePreset: Codable, Identifiable, Equatable {
    let id: UUID
    var name: String
    var configuration: PresenceConfiguration

    init(id: UUID = UUID(), name: String, configuration: PresenceConfiguration) {
        self.id = id
        self.name = name
        self.configuration = configuration
    }

    static let builtIns: [PresencePreset] = [
        PresencePreset(name: "Study", configuration: .example),
        PresencePreset(
            name: "Coding",
            configuration: PresenceConfiguration(
                activity: "Coding",
                details: "Building Vibly",
                state: "SwiftUI + macOS",
                showElapsedTime: true,
                startedAt: nil,
                largeImageKey: nil,
                largeImageText: nil
            )
        ),
        PresencePreset(
            name: "Working",
            configuration: PresenceConfiguration(
                activity: "Working",
                details: "Focused work",
                state: "Making progress",
                showElapsedTime: true,
                startedAt: nil,
                largeImageKey: nil,
                largeImageText: nil
            )
        ),
        PresencePreset(
            name: "Gaming",
            configuration: PresenceConfiguration(
                activity: "Gaming",
                details: "Playing a game",
                state: "Having fun",
                showElapsedTime: true,
                startedAt: nil,
                largeImageKey: nil,
                largeImageText: nil
            )
        ),
        PresencePreset(
            name: "Watching",
            configuration: PresenceConfiguration(
                activity: "Watching",
                details: "Watching something",
                state: "Taking a break",
                showElapsedTime: true,
                startedAt: nil,
                largeImageKey: nil,
                largeImageText: nil
            )
        ),
        PresencePreset(name: "Custom", configuration: .empty)
    ]
}

struct AppPresenceRule: Codable, Equatable {
    var applicationBundleIdentifier: String
    var applicationDisplayName: String
    var customDescription: String
    var enabled: Bool
    var mode: AutomaticAppMode

    private enum CodingKeys: String, CodingKey {
        case applicationBundleIdentifier
        case applicationDisplayName
        case customDescription
        case enabled
        case mode
    }

    init(
        applicationBundleIdentifier: String,
        applicationDisplayName: String,
        customDescription: String,
        enabled: Bool,
        mode: AutomaticAppMode = .fake
    ) {
        self.applicationBundleIdentifier = applicationBundleIdentifier
        self.applicationDisplayName = applicationDisplayName
        self.customDescription = customDescription
        self.enabled = enabled
        self.mode = mode
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        applicationBundleIdentifier = try values.decode(String.self, forKey: .applicationBundleIdentifier)
        applicationDisplayName = try values.decode(String.self, forKey: .applicationDisplayName)
        customDescription = try values.decode(String.self, forKey: .customDescription)
        enabled = try values.decodeIfPresent(Bool.self, forKey: .enabled) ?? false
        mode = try values.decodeIfPresent(AutomaticAppMode.self, forKey: .mode) ?? .fake
    }

    static let empty = AppPresenceRule(
        applicationBundleIdentifier: "",
        applicationDisplayName: "",
        customDescription: "",
        enabled: false,
        mode: .fake
    )
}

enum AutomaticAppMode: String, Codable, Equatable {
    case fake
    case frontmostOnly

    var title: String {
        switch self {
        case .fake: return "Fake app"
        case .frontmostOnly: return "Only when active"
        }
    }

    var explanation: String {
        switch self {
        case .fake:
            return "Publishes the selected app even when it is closed."
        case .frontmostOnly:
            return "Publishes only while the selected app is frontmost."
        }
    }
}
