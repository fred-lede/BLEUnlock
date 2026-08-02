import Foundation

enum NotificationEvent: String, CaseIterable {
    case away, lost, unlocked, intruded

    var defaultEnabled: Bool { self != .unlocked }
    var defaultsKey: String { "telegram.event.\(rawValue)" }
}

struct NotificationEventContext: Equatable {
    let event: NotificationEvent
    let hostName: String
    let timestamp: Date
    let rssi: Int?
}

struct TelegramCredentials: Equatable {
    let token: String
    let chatID: String
}
