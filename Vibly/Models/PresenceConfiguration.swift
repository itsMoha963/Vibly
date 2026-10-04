import Foundation

struct PresenceConfiguration: Codable, Equatable {
    var activity: String
    var details: String
    var state: String
    var showElapsedTime: Bool
    var startedAt: Date?
    var largeImageKey: String?
    var largeImageText: String?
    var useCustomStartTime: Bool
    var customStartAt: Date?
    var smallImageKey: String?
    var smallImageText: String?

    private enum CodingKeys: String, CodingKey {
        case activity, details, state, showElapsedTime, startedAt
        case largeImageKey, largeImageText, useCustomStartTime, customStartAt
        case smallImageKey, smallImageText
    }

    init(
        activity: String,
        details: String,
        state: String,
        showElapsedTime: Bool,
        startedAt: Date?,
        largeImageKey: String?,
        largeImageText: String?,
        useCustomStartTime: Bool = false,
        customStartAt: Date? = nil,
        smallImageKey: String? = nil,
        smallImageText: String? = nil
    ) {
        self.activity = activity
        self.details = details
        self.state = state
        self.showElapsedTime = showElapsedTime
        self.startedAt = startedAt
        self.largeImageKey = largeImageKey
        self.largeImageText = largeImageText
        self.useCustomStartTime = useCustomStartTime
        self.customStartAt = customStartAt
        self.smallImageKey = smallImageKey
        self.smallImageText = smallImageText
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        activity = try values.decode(String.self, forKey: .activity)
        details = try values.decode(String.self, forKey: .details)
        state = try values.decode(String.self, forKey: .state)
        showElapsedTime = try values.decode(Bool.self, forKey: .showElapsedTime)
        startedAt = try values.decodeIfPresent(Date.self, forKey: .startedAt)
        largeImageKey = try values.decodeIfPresent(String.self, forKey: .largeImageKey)
        largeImageText = try values.decodeIfPresent(String.self, forKey: .largeImageText)
        useCustomStartTime = try values.decodeIfPresent(Bool.self, forKey: .useCustomStartTime) ?? false
        customStartAt = try values.decodeIfPresent(Date.self, forKey: .customStartAt)
        smallImageKey = try values.decodeIfPresent(String.self, forKey: .smallImageKey)
        smallImageText = try values.decodeIfPresent(String.self, forKey: .smallImageText)
    }

    static let example = PresenceConfiguration(
        activity: "Studying",
        details: "Algorithms & Data Structures",
        state: "Preparing for exam",
        showElapsedTime: true,
        startedAt: nil,
        largeImageKey: nil,
        largeImageText: nil
    )

    static let empty = PresenceConfiguration(
        activity: "",
        details: "",
        state: "",
        showElapsedTime: true,
        startedAt: nil,
        largeImageKey: nil,
        largeImageText: nil
    )

    var trimmedActivity: String {
        activity.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var assetValidationError: String? {
        let largeKeyIsEmpty = largeImageKey?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true
        let largeTextIsFilled = !(largeImageText?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
        if largeKeyIsEmpty && largeTextIsFilled {
            return "Large image tooltip has text, but Large image key is empty. Put the Discord asset key in Large image key."
        }

        let smallKeyIsEmpty = smallImageKey?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true
        let smallTextIsFilled = !(smallImageText?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
        if smallKeyIsEmpty && smallTextIsFilled {
            return "Small image tooltip has text, but Small image key is empty. Put the Discord asset key in Small image key."
        }

        return nil
    }

    var validationError: String? {
        guard !trimmedActivity.isEmpty else {
            return "Enter an activity before setting your presence."
        }

        if trimmedActivity.count > 128 {
            return "Activity must be 128 characters or fewer."
        }

        return assetValidationError
    }

    func startingNow() -> PresenceConfiguration {
        var copy = self
        copy.startedAt = showElapsedTime ? (useCustomStartTime ? (customStartAt ?? Date()) : Date()) : nil
        return copy
    }
}
