import Foundation
@testable import BLEUnlock

final class MemorySecretStore: SecretStoring {
    var values: [String: String] = [:]
    func string(for account: String) throws -> String? { values[account] }
    func set(_ value: String, for account: String) throws { values[account] = value }
    func removeValue(for account: String) throws { values.removeValue(forKey: account) }
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
