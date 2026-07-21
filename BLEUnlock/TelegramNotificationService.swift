import Foundation

protocol TelegramNotificationHandling {
    func handle(_ context: TelegramEventContext)
    func sendTest(hostName: String,
                  completion: @escaping (Result<Void, Error>) -> Void)
}

protocol TelegramMessageFormatting {
    func message(for context: TelegramEventContext) -> String
}

protocol FailureReporting {
    func report(category: String, message: String)
}

protocol FailureNotificationDelivering {
    func deliver(message: String)
}

final class UserNotificationFailureDelivery: FailureNotificationDelivering {
    private let notificationCenter: NSUserNotificationCenter

    init(notificationCenter: NSUserNotificationCenter = .default) {
        self.notificationCenter = notificationCenter
    }

    func deliver(message: String) {
        let notification = NSUserNotification()
        notification.title = "BLEUnlock"
        notification.subtitle = "Telegram notification failed"
        notification.informativeText = message
        notificationCenter.deliver(notification)
    }
}

final class TelegramMessageFormatter: TelegramMessageFormatting {
    func message(for context: TelegramEventContext) -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.locale = .current
        dateFormatter.dateStyle = .medium
        dateFormatter.timeStyle = .medium

        var lines = [
            "\(context.hostName) — \(localizedDescription(for: context.event))",
            "Time: \(dateFormatter.string(from: context.timestamp))"
        ]
        if let rssi = context.rssi {
            lines.append("RSSI: \(rssi) dBm")
        }
        return lines.joined(separator: "\n")
    }

    private func localizedDescription(for event: TelegramEvent) -> String {
        let key: String
        let fallback: String
        switch event {
        case .away:
            key = "telegram_event_away"
            fallback = "Device Away"
        case .lost:
            key = "telegram_event_lost"
            fallback = "Signal Lost"
        case .unlocked:
            key = "telegram_event_unlocked"
            fallback = "Unlocked by BLEUnlock"
        case .intruded:
            key = "telegram_event_intruded"
            fallback = "Manually Unlocked"
        }
        return NSLocalizedString(key, value: fallback, comment: "Telegram event description")
    }
}

final class RateLimitedFailureReporter: FailureReporting {
    private let now: () -> Date
    private let interval: TimeInterval
    private let notificationDelivery: FailureNotificationDelivering
    private let lock = NSLock()
    private var lastShown: [String: Date] = [:]

    convenience init(now: @escaping () -> Date = Date.init,
                     interval: TimeInterval = 300,
                     notificationCenter: NSUserNotificationCenter = .default) {
        self.init(now: now,
                  interval: interval,
                  notificationDelivery: UserNotificationFailureDelivery(
                      notificationCenter: notificationCenter
                  ))
    }

    init(now: @escaping () -> Date,
         interval: TimeInterval,
         notificationDelivery: FailureNotificationDelivering) {
        self.now = now
        self.interval = interval
        self.notificationDelivery = notificationDelivery
    }

    func report(category: String, message: String) {
        let category = sanitizedCategory(category)
        NSLog("BLEUnlock Telegram notification failure category: %@", category)

        let current = now()
        lock.lock()
        if let previous = lastShown[category],
           current.timeIntervalSince(previous) < interval {
            lock.unlock()
            return
        }
        lastShown[category] = current
        lock.unlock()

        notificationDelivery.deliver(message: message)
    }

    private func sanitizedCategory(_ category: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let sanitized = category.unicodeScalars
            .map { allowed.contains($0) ? String($0) : "_" }
            .joined()
        return String((sanitized.isEmpty ? "unknown" : sanitized).prefix(64))
    }
}

private enum TelegramNotificationServiceError: LocalizedError {
    case notConfigured
    case settingsUnavailable

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "Telegram is not configured."
        case .settingsUnavailable:
            return "Telegram settings could not be read."
        }
    }
}

final class TelegramNotificationService: TelegramNotificationHandling {
    private let settings: TelegramSettings
    private let sender: TelegramSending
    private let camera: PhotoCapturing
    private let removeFile: (URL) throws -> Void
    private let reporter: FailureReporting
    private let formatter: TelegramMessageFormatting

    init(settings: TelegramSettings,
         sender: TelegramSending,
         camera: PhotoCapturing,
         removeFile: @escaping (URL) throws -> Void = {
             try FileManager.default.removeItem(at: $0)
         },
         reporter: FailureReporting,
         formatter: TelegramMessageFormatting = TelegramMessageFormatter()) {
        self.settings = settings
        self.sender = sender
        self.camera = camera
        self.removeFile = removeFile
        self.reporter = reporter
        self.formatter = formatter
    }

    func handle(_ context: TelegramEventContext) {
        guard settings.isEnabled, settings.isEventEnabled(context.event),
              let credentials = try? settings.credentials() else {
            return
        }

        let message = formatter.message(for: context)
        if context.event == .intruded && settings.takePhotoOnIntruded {
            sendPhotoOrFallback(credentials: credentials, message: message, completion: nil)
        } else {
            sendText(credentials: credentials, message: message, completion: nil)
        }
    }

    func sendTest(hostName: String,
                  completion: @escaping (Result<Void, Error>) -> Void) {
        let credentials: TelegramCredentials
        do {
            guard let storedCredentials = try settings.credentials() else {
                completion(.failure(TelegramNotificationServiceError.notConfigured))
                return
            }
            credentials = storedCredentials
        } catch {
            completion(.failure(TelegramNotificationServiceError.settingsUnavailable))
            return
        }

        let message = formatter.message(for: .init(event: .intruded,
                                                    hostName: hostName,
                                                    timestamp: Date(),
                                                    rssi: nil))
        if settings.takePhotoOnIntruded {
            sendPhotoOrFallback(credentials: credentials,
                                message: message,
                                completion: completion)
        } else {
            sendText(credentials: credentials, message: message, completion: completion)
        }
    }

    private func sendPhotoOrFallback(credentials: TelegramCredentials,
                                     message: String,
                                     completion: ((Result<Void, Error>) -> Void)?) {
        camera.capture { [sender, removeFile, reporter] captureResult in
            switch captureResult {
            case .failure(let error):
                reporter.report(category: "camera", message: error.localizedDescription)
                self.sendText(credentials: credentials,
                              message: message,
                              completion: completion)
            case .success(let photoURL):
                sender.sendPhoto(credentials: credentials,
                                 photoURL: photoURL,
                                 caption: message) { result in
                    do {
                        try removeFile(photoURL)
                    } catch {
                        reporter.report(category: "file",
                                        message: "The captured photo could not be deleted.")
                    }
                    if case .failure(let error) = result {
                        reporter.report(category: "telegram", message: error.localizedDescription)
                    }
                    completion?(result.mapError { $0 as Error })
                }
            }
        }
    }

    private func sendText(credentials: TelegramCredentials,
                          message: String,
                          completion: ((Result<Void, Error>) -> Void)?) {
        sender.sendText(credentials: credentials, text: message) { [reporter] result in
            if case .failure(let error) = result {
                reporter.report(category: "telegram", message: error.localizedDescription)
            }
            completion?(result.mapError { $0 as Error })
        }
    }
}
