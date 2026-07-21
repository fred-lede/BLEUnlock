import Foundation
@testable import BLEUnlock

final class MemorySecretStore: SecretStoring {
    var values: [String: String] = [:]
    func string(for account: String) throws -> String? { values[account] }
    func set(_ value: String, for account: String) throws { values[account] = value }
    func removeValue(for account: String) throws { values.removeValue(forKey: account) }
}

final class ThrowingSecretStore: SecretStoring {
    let error: Error

    init(error: Error) {
        self.error = error
    }

    func string(for account: String) throws -> String? { throw error }
    func set(_ value: String, for account: String) throws { throw error }
    func removeValue(for account: String) throws { throw error }
}

final class RecordingHTTPTransport: HTTPTransport {
    var requests: [URLRequest] = []
    var result: Result<(Data, HTTPURLResponse), Error>!

    func perform(_ request: URLRequest,
                 completion: @escaping (Result<(Data, HTTPURLResponse), Error>) -> Void) {
        requests.append(request)
        completion(result)
    }
}

final class RecordingTelegramSender: TelegramSending {
    struct TextCall {
        let credentials: TelegramCredentials
        let text: String
    }

    struct PhotoCall {
        let credentials: TelegramCredentials
        let photoURL: URL
        let caption: String
    }

    var textResult: Result<Void, TelegramError> = .success(())
    var photoResult: Result<Void, TelegramError> = .success(())
    private(set) var textCalls: [TextCall] = []
    private(set) var photoCalls: [PhotoCall] = []

    func sendText(credentials: TelegramCredentials,
                  text: String,
                  completion: @escaping (Result<Void, TelegramError>) -> Void) {
        textCalls.append(.init(credentials: credentials, text: text))
        completion(textResult)
    }

    func sendPhoto(credentials: TelegramCredentials,
                   photoURL: URL,
                   caption: String,
                   completion: @escaping (Result<Void, TelegramError>) -> Void) {
        photoCalls.append(.init(credentials: credentials,
                                photoURL: photoURL,
                                caption: caption))
        completion(photoResult)
    }
}

final class StubPhotoCapturer: PhotoCapturing {
    var result: Result<URL, CameraCaptureError> = .failure(.captureFailed)
    private(set) var captureCalls = 0

    func capture(completion: @escaping (Result<URL, CameraCaptureError>) -> Void) {
        captureCalls += 1
        completion(result)
    }
}

final class RecordingFailureReporter: FailureReporting {
    private(set) var categories: [String] = []
    private(set) var messages: [String] = []

    func report(category: String, message: String) {
        categories.append(category)
        messages.append(message)
    }
}

final class RecordingFileRemover {
    private(set) var calls: [URL] = []
    var error: Error?

    func remove(_ url: URL) throws {
        calls.append(url)
        if let error = error {
            throw error
        }
    }
}

final class RecordingFailureNotificationDelivery: FailureNotificationDelivering {
    private(set) var messages: [String] = []

    func deliver(message: String) {
        messages.append(message)
    }
}
