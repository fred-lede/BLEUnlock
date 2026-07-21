import Foundation

protocol HTTPTransport {
    func perform(_ request: URLRequest,
                 completion: @escaping (Result<(Data, HTTPURLResponse), Error>) -> Void)
}

protocol TelegramSending {
    func sendText(credentials: TelegramCredentials,
                  text: String,
                  completion: @escaping (Result<Void, TelegramError>) -> Void)
    func sendPhoto(credentials: TelegramCredentials,
                   photoURL: URL,
                   caption: String,
                   completion: @escaping (Result<Void, TelegramError>) -> Void)
}

enum TelegramError: LocalizedError, Equatable {
    case invalidRequest
    case unreadablePhoto
    case transport
    case httpStatus(Int)
    case rejected(String)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .invalidRequest:
            return "The Telegram request could not be created."
        case .unreadablePhoto:
            return "The captured photo could not be read."
        case .transport:
            return "Telegram could not be reached."
        case .httpStatus(let code):
            return "Telegram returned HTTP status \(code)."
        case .rejected(let description):
            return description
        case .invalidResponse:
            return "Telegram returned an invalid response."
        }
    }
}

final class TelegramNotifier: TelegramSending {
    private let transport: HTTPTransport

    init(transport: HTTPTransport) {
        self.transport = transport
    }

    func sendText(credentials: TelegramCredentials,
                  text: String,
                  completion: @escaping (Result<Void, TelegramError>) -> Void) {
        guard let request = makeTextRequest(credentials: credentials, text: text) else {
            completion(.failure(.invalidRequest))
            return
        }
        perform(request, completion: completion)
    }

    func sendPhoto(credentials: TelegramCredentials,
                   photoURL: URL,
                   caption: String,
                   completion: @escaping (Result<Void, TelegramError>) -> Void) {
        guard let request = try? makePhotoRequest(credentials: credentials,
                                                  photoURL: photoURL,
                                                  caption: caption) else {
            completion(.failure(.unreadablePhoto))
            return
        }
        perform(request, completion: completion)
    }

    private func makeTextRequest(credentials: TelegramCredentials, text: String) -> URLRequest? {
        guard let url = URL(string: "https://api.telegram.org/bot\(credentials.token)/sendMessage") else {
            return nil
        }
        var components = URLComponents()
        components.queryItems = [
            URLQueryItem(name: "chat_id", value: credentials.chatID),
            URLQueryItem(name: "text", value: text)
        ]
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = components.percentEncodedQuery?.data(using: .utf8)
        return request
    }

    private func makePhotoRequest(credentials: TelegramCredentials,
                                  photoURL: URL,
                                  caption: String) throws -> URLRequest {
        let data = try Data(contentsOf: photoURL)
        guard let url = URL(string: "https://api.telegram.org/bot\(credentials.token)/sendPhoto") else {
            throw TelegramError.invalidRequest
        }
        let boundary = "BLEUnlock-\(UUID().uuidString)"
        var body = Data()
        body.appendMultipartField(name: "chat_id", value: credentials.chatID, boundary: boundary)
        body.appendMultipartField(name: "caption", value: caption, boundary: boundary)
        body.appendMultipartFile(name: "photo",
                                 filename: photoURL.lastPathComponent,
                                 mimeType: "image/jpeg",
                                 bytes: data,
                                 boundary: boundary)
        body.append(Data("--\(boundary)--\r\n".utf8))
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)",
                         forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        return request
    }

    private func perform(_ request: URLRequest,
                         completion: @escaping (Result<Void, TelegramError>) -> Void) {
        transport.perform(request) { result in
            switch result {
            case .failure:
                completion(.failure(.transport))
            case .success(let (data, response)):
                guard (200..<300).contains(response.statusCode) else {
                    completion(.failure(.httpStatus(response.statusCode)))
                    return
                }
                guard let decoded = try? JSONDecoder().decode(TelegramResponse.self, from: data) else {
                    completion(.failure(.invalidResponse))
                    return
                }
                decoded.ok
                    ? completion(.success(()))
                    : completion(.failure(.rejected(
                        decoded.description ?? "Telegram rejected the request."
                    )))
            }
        }
    }
}

private struct TelegramResponse: Decodable {
    let ok: Bool
    let description: String?
}

private extension Data {
    mutating func appendMultipartField(name: String, value: String, boundary: String) {
        append(Data("--\(boundary)\r\n".utf8))
        append(Data("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".utf8))
        append(Data("\(value)\r\n".utf8))
    }

    mutating func appendMultipartFile(name: String,
                                      filename: String,
                                      mimeType: String,
                                      bytes: Data,
                                      boundary: String) {
        append(Data("--\(boundary)\r\n".utf8))
        append(Data("Content-Disposition: form-data; name=\"\(name)\"; filename=\"\(filename)\"\r\n".utf8))
        append(Data("Content-Type: \(mimeType)\r\n\r\n".utf8))
        append(bytes)
        append(Data("\r\n".utf8))
    }
}

final class URLSessionTransport: HTTPTransport {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func perform(_ request: URLRequest,
                 completion: @escaping (Result<(Data, HTTPURLResponse), Error>) -> Void) {
        session.dataTask(with: request) { data, response, error in
            if error != nil {
                completion(.failure(TelegramError.transport))
                return
            }
            guard let data = data, let response = response as? HTTPURLResponse else {
                completion(.failure(TelegramError.invalidResponse))
                return
            }
            completion(.success((data, response)))
        }.resume()
    }
}
