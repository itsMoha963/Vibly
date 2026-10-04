import Foundation

final class PresetStore {
    private let defaults: UserDefaults

    private enum Key {
        static let lastConfiguration = "lastPresenceConfiguration"
        static let presets = "presencePresets"
        static let applicationID = "discordApplicationID"
        static let automaticRule = "automaticAppPresenceRule"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func loadLastConfiguration() -> PresenceConfiguration {
        guard
            let data = defaults.data(forKey: Key.lastConfiguration),
            let configuration = try? JSONDecoder().decode(PresenceConfiguration.self, from: data)
        else {
            return .example
        }

        return configuration
    }

    func saveLastConfiguration(_ configuration: PresenceConfiguration) {
        guard let data = try? JSONEncoder().encode(configuration) else { return }
        defaults.set(data, forKey: Key.lastConfiguration)
    }

    func loadPresets() -> [PresencePreset] {
        guard
            let data = defaults.data(forKey: Key.presets),
            let presets = try? JSONDecoder().decode([PresencePreset].self, from: data),
            !presets.isEmpty
        else {
            return PresencePreset.builtIns
        }

        return presets
    }

    func savePresets(_ presets: [PresencePreset]) {
        guard let data = try? JSONEncoder().encode(presets) else { return }
        defaults.set(data, forKey: Key.presets)
    }

    func loadApplicationID() -> String {
        defaults.string(forKey: Key.applicationID) ?? ""
    }

    func saveApplicationID(_ applicationID: String) {
        defaults.set(applicationID.trimmingCharacters(in: .whitespacesAndNewlines), forKey: Key.applicationID)
    }

    func loadAutomaticRule() -> AppPresenceRule {
        guard
            let data = defaults.data(forKey: Key.automaticRule),
            let rule = try? JSONDecoder().decode(AppPresenceRule.self, from: data)
        else {
            return .empty
        }

        return rule
    }

    func saveAutomaticRule(_ rule: AppPresenceRule) {
        guard let data = try? JSONEncoder().encode(rule) else { return }
        defaults.set(data, forKey: Key.automaticRule)
    }
}
