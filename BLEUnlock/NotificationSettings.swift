import Foundation

protocol SecretStoring {
    func string(for account: String) throws -> String?
    func set(_ value: String, for account: String) throws
    func removeValue(for account: String) throws
}

enum NotificationChannel: String, CaseIterable {
    case telegram
    case synologyChat
}

final class NotificationSettings {
    private enum Key {
        static let channel = "notification.channel"

        static let telegramEnabled = "telegram.enabled"
        static let telegramTakePhoto = "telegram.takePhotoOnIntruded"
        static let telegramAttachMacLocation = "telegram.attachMacLocation"

        static let synologyEnabled = "notification.enabled.synologyChat"
        static let synologyTakePhoto = "notification.takePhoto.synologyChat"
        static let synologyAttachMacLocation = "notification.attachLocation.synologyChat"

        static let telegramToken = "botToken"
        static let telegramChatID = "chatID"

        static let synologyWebhookURL = "webhookURL"
        static let synologyUsername = "username"
        static let synologyPassword = "password"
        static let synologyChannelID = "channelID"
    }

    private let defaults: UserDefaults
    private let telegramSecrets: SecretStoring
    private let synologySecrets: SecretStoring

    init(defaults: UserDefaults = .standard,
         telegramSecrets: SecretStoring,
         synologySecrets: SecretStoring) {
        self.defaults = defaults
        self.telegramSecrets = telegramSecrets
        self.synologySecrets = synologySecrets
    }

    var selectedChannel: NotificationChannel {
        get {
            NotificationChannel(rawValue: defaults.string(forKey: Key.channel) ?? "")
                ?? .telegram
        }
        set { defaults.set(newValue.rawValue, forKey: Key.channel) }
    }

    func isEnabled(_ channel: NotificationChannel) -> Bool {
        defaults.bool(forKey: channel == .telegram ? Key.telegramEnabled : Key.synologyEnabled)
    }

    func setEnabled(_ enabled: Bool, for channel: NotificationChannel) {
        defaults.set(enabled,
                     forKey: channel == .telegram ? Key.telegramEnabled : Key.synologyEnabled)
    }

    func takePhotoOnIntruded(_ channel: NotificationChannel) -> Bool {
        let key = channel == .telegram ? Key.telegramTakePhoto : Key.synologyTakePhoto
        return defaults.object(forKey: key) as? Bool ?? true
    }

    func setTakePhotoOnIntruded(_ enabled: Bool, for channel: NotificationChannel) {
        defaults.set(enabled,
                     forKey: channel == .telegram ? Key.telegramTakePhoto : Key.synologyTakePhoto)
    }

    func attachMacLocation(_ channel: NotificationChannel) -> Bool {
        let key = channel == .telegram ? Key.telegramAttachMacLocation : Key.synologyAttachMacLocation
        return defaults.object(forKey: key) as? Bool ?? false
    }

    func setAttachMacLocation(_ enabled: Bool, for channel: NotificationChannel) {
        defaults.set(enabled,
                     forKey: channel == .telegram ? Key.telegramAttachMacLocation : Key.synologyAttachMacLocation)
    }

    func isEventEnabled(_ event: NotificationEvent) -> Bool {
        defaults.object(forKey: event.defaultsKey) as? Bool ?? event.defaultEnabled
    }

    func setEvent(_ event: NotificationEvent, enabled: Bool) {
        defaults.set(enabled, forKey: event.defaultsKey)
    }

    func isConfigured(_ channel: NotificationChannel) throws -> Bool {
        switch channel {
        case .telegram: return try telegramCredentials() != nil
        case .synologyChat: return try synologyCredentials() != nil
        }
    }

    func telegramCredentials() throws -> TelegramCredentials? {
        guard let token = try telegramSecrets.string(for: Key.telegramToken), !token.isEmpty,
              let chatID = try telegramSecrets.string(for: Key.telegramChatID), !chatID.isEmpty else { return nil }
        return TelegramCredentials(token: token, chatID: chatID)
    }

    func saveTelegramCredentials(replacementToken: String?, chatID: String) throws {
        let replacement = replacementToken?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let replacement = replacement, !replacement.isEmpty {
            try telegramSecrets.set(replacement, for: Key.telegramToken)
        }
        try telegramSecrets.set(chatID.trimmingCharacters(in: .whitespacesAndNewlines),
                                for: Key.telegramChatID)
    }

    func synologyCredentials() throws -> SynologyCredentials? {
        guard let webhookURL = try synologySecrets.string(for: Key.synologyWebhookURL),
              !webhookURL.isEmpty,
              let username = try synologySecrets.string(for: Key.synologyUsername),
              !username.isEmpty,
              let password = try synologySecrets.string(for: Key.synologyPassword),
              !password.isEmpty,
              let channelID = try synologySecrets.string(for: Key.synologyChannelID),
              !channelID.isEmpty else { return nil }
        return SynologyCredentials(webhookURL: webhookURL,
                                   username: username,
                                   password: password,
                                   channelID: channelID)
    }

    func saveSynologyCredentials(webhookURL: String,
                                 username: String,
                                 password: String?,
                                 channelID: String) throws {
        try synologySecrets.set(webhookURL.trimmingCharacters(in: .whitespacesAndNewlines),
                                for: Key.synologyWebhookURL)
        try synologySecrets.set(username.trimmingCharacters(in: .whitespacesAndNewlines),
                                for: Key.synologyUsername)
        if let password = password?.trimmingCharacters(in: .whitespacesAndNewlines),
           !password.isEmpty {
            try synologySecrets.set(password, for: Key.synologyPassword)
        }
        try synologySecrets.set(channelID.trimmingCharacters(in: .whitespacesAndNewlines),
                                for: Key.synologyChannelID)
    }
}
