import Foundation

struct SynologyCredentials: Equatable {
    let webhookURL: String
    let username: String
    let password: String
    let channelID: String
}

protocol SynologySending {
    func sendText(credentials: SynologyCredentials,
                  text: String,
                  completion: @escaping (Result<Void, SynologyError>) -> Void)
    func sendPhoto(credentials: SynologyCredentials,
                   photoURL: URL,
                   caption: String,
                   completion: @escaping (Result<Void, SynologyError>) -> Void)
}

enum SynologyError: LocalizedError, Equatable {
    case invalidRequest
    case unreadablePhoto
    case transport
    case httpStatus(Int)
    case invalidResponse
    case loginFailed
    case uploadFailed
    case postFailed
    case rejected

    var errorDescription: String? {
        switch self {
        case .invalidRequest:
            return t("synology_error_invalid_request")
        case .unreadablePhoto:
            return t("telegram_error_unreadable_photo")
        case .transport:
            return t("synology_error_transport")
        case .httpStatus(let code):
            return String(format: t("synology_error_http_status"), code)
        case .invalidResponse:
            return t("synology_error_invalid_response")
        case .loginFailed:
            return t("synology_error_login")
        case .uploadFailed:
            return t("synology_error_upload")
        case .postFailed:
            return t("synology_error_post")
        case .rejected:
            return t("synology_error_invalid_response")
        }
    }
}

private struct SynologyLoginResponse: Decodable {
    let success: Bool
    let data: SynologyLoginData?
}

private struct SynologyLoginData: Decodable {
    let sid: String?
    let synotoken: String?
}

private struct SynologySuccessResponse: Decodable {
    let success: Bool
    let data: SynologyPostData?
}

private struct SynologyPostData: Decodable {
    let post_id: Int64?
}

private struct SynologySession {
    let sid: String
    let synoToken: String
}

final class SynologyNotifier: SynologySending {
    private let transport: HTTPTransport

    init(transport: HTTPTransport) {
        self.transport = transport
    }

    func sendText(credentials: SynologyCredentials,
                  text: String,
                  completion: @escaping (Result<Void, SynologyError>) -> Void) {
        guard let url = URL(string: credentials.webhookURL) else {
            completion(.failure(.invalidRequest))
            return
        }
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let json = (try? JSONSerialization.data(withJSONObject: ["text": text])) ?? Data()
        request.httpBody = formEncoded([("payload", String(decoding: json, as: UTF8.self))])

        transport.perform(request) { result in
            switch result {
            case .failure:
                completion(.failure(.transport))
            case .success(let (data, response)):
                guard (200..<300).contains(response.statusCode) else {
                    completion(.failure(.httpStatus(response.statusCode)))
                    return
                }
                guard let decoded = try? JSONDecoder().decode(SynologySuccessResponse.self, from: data) else {
                    completion(.failure(.invalidResponse))
                    return
                }
                guard decoded.success else {
                    completion(.failure(.rejected))
                    return
                }
                completion(.success(()))
            }
        }
    }

    func sendPhoto(credentials: SynologyCredentials,
                   photoURL: URL,
                   caption: String,
                   completion: @escaping (Result<Void, SynologyError>) -> Void) {
        guard let baseURL = baseURL(from: credentials.webhookURL) else {
            completion(.failure(.invalidRequest))
            return
        }
        guard let data = try? Data(contentsOf: photoURL) else {
            completion(.failure(.unreadablePhoto))
            return
        }

        login(baseURL: baseURL, credentials: credentials) { [transport] result in
            switch result {
            case .failure(let error):
                completion(.failure(error))
            case .success(let session):
                guard let uploadRequest = self.makeUploadRequest(baseURL: baseURL,
                                                                 session: session,
                                                                 credentials: credentials,
                                                                 photoURL: photoURL,
                                                                 data: data) else {
                    completion(.failure(.invalidRequest))
                    return
                }
                transport.perform(uploadRequest) { uploadResult in
                    switch uploadResult {
                    case .failure:
                        completion(.failure(.transport))
                    case .success(let (data, response)):
                        guard (200..<300).contains(response.statusCode) else {
                            completion(.failure(.httpStatus(response.statusCode)))
                            return
                        }
                        guard let decoded = try? JSONDecoder().decode(SynologySuccessResponse.self, from: data),
                              decoded.success,
                              decoded.data?.post_id != nil else {
                            completion(.failure(.uploadFailed))
                            return
                        }
                        guard let postRequest = self.makePostRequest(baseURL: baseURL,
                                                                     session: session,
                                                                     credentials: credentials,
                                                                     caption: caption) else {
                            completion(.failure(.invalidRequest))
                            return
                        }
                        transport.perform(postRequest) { postResult in
                            switch postResult {
                            case .failure:
                                completion(.failure(.transport))
                            case .success(let (data, response)):
                                guard (200..<300).contains(response.statusCode) else {
                                    completion(.failure(.httpStatus(response.statusCode)))
                                    return
                                }
                                guard let decoded = try? JSONDecoder().decode(SynologySuccessResponse.self, from: data),
                                      decoded.success else {
                                    completion(.failure(.postFailed))
                                    return
                                }
                                completion(.success(()))
                            }
                        }
                    }
                }
            }
        }
    }

    private func login(baseURL: URL,
                       credentials: SynologyCredentials,
                       completion: @escaping (Result<SynologySession, SynologyError>) -> Void) {
        guard let url = URL(string: "\(baseURL.absoluteString)/webapi/auth.cgi") else {
            completion(.failure(.invalidRequest))
            return
        }
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "api", value: "SYNO.API.Auth"),
            URLQueryItem(name: "version", value: "6"),
            URLQueryItem(name: "method", value: "login"),
            URLQueryItem(name: "enable_syno_token", value: "yes"),
            URLQueryItem(name: "format", value: "sid"),
            URLQueryItem(name: "session", value: "Chat")
        ]
        guard let loginURL = components?.url else {
            completion(.failure(.invalidRequest))
            return
        }
        var request = URLRequest(url: loginURL, timeoutInterval: 15)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = formEncoded([
            ("account", credentials.username),
            ("passwd", credentials.password)
        ])

        transport.perform(request) { result in
            switch result {
            case .failure:
                completion(.failure(.transport))
            case .success(let (data, response)):
                guard (200..<300).contains(response.statusCode) else {
                    completion(.failure(.httpStatus(response.statusCode)))
                    return
                }
                guard let decoded = try? JSONDecoder().decode(SynologyLoginResponse.self, from: data),
                      decoded.success,
                      let loginData = decoded.data,
                      let sid = loginData.sid, !sid.isEmpty else {
                    completion(.failure(.loginFailed))
                    return
                }
                completion(.success(.init(sid: sid, synoToken: loginData.synotoken ?? "")))
            }
        }
    }

    private func makeUploadRequest(baseURL: URL,
                                   session: SynologySession,
                                   credentials: SynologyCredentials,
                                   photoURL: URL,
                                   data: Data) -> URLRequest? {
        guard let url = entryURL(baseURL: baseURL,
                                 session: session,
                                 channelID: credentials.channelID) else { return nil }
        var request = URLRequest(url: url, timeoutInterval: 30)
        request.httpMethod = "POST"
        request.setValue(session.synoToken, forHTTPHeaderField: "X-SYNO-TOKEN")
        request.setValue("id=\(session.sid)", forHTTPHeaderField: "Cookie")

        let boundary = "BLEUnlock-\(UUID().uuidString)"
        var body = Data()
        body.appendMultipartField(name: "type", value: "file", boundary: boundary)
        body.appendMultipartField(name: "message", value: "", boundary: boundary)
        body.appendMultipartField(name: "conn_id", value: "", boundary: boundary)
        body.appendMultipartFile(name: "file",
                                 filename: photoURL.lastPathComponent,
                                 mimeType: "application/octet-stream",
                                 bytes: data,
                                 boundary: boundary)
        body.append(Data("--\(boundary)--\r\n".utf8))
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        return request
    }

    private func makePostRequest(baseURL: URL,
                                 session: SynologySession,
                                 credentials: SynologyCredentials,
                                 caption: String) -> URLRequest? {
        guard let url = entryURL(baseURL: baseURL,
                                 session: session,
                                 channelID: credentials.channelID) else { return nil }
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue(session.synoToken, forHTTPHeaderField: "X-SYNO-TOKEN")
        request.httpBody = formEncoded([
            ("message", caption)
        ])
        return request
    }

    private func entryURL(baseURL: URL,
                          session: SynologySession,
                          channelID: String) -> URL? {
        var components = URLComponents(url: baseURL.appendingPathComponent("webapi/entry.cgi"),
                                       resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "api", value: "SYNO.Chat.Post"),
            URLQueryItem(name: "method", value: "create"),
            URLQueryItem(name: "version", value: "5"),
            URLQueryItem(name: "channel_id", value: channelID),
            URLQueryItem(name: "_sid", value: session.sid)
        ]
        return components?.url
    }

    private func baseURL(from webhookURL: String) -> URL? {
        guard let url = URL(string: webhookURL),
              let scheme = url.scheme,
              let host = url.host else { return nil }
        var components = URLComponents()
        components.scheme = scheme
        components.host = host
        components.port = url.port
        return components.url
    }

    private func formEncoded(_ fields: [(String, String)]) -> Data {
        let body = fields
            .map { "\(formPercentEncoded($0.0))=\(formPercentEncoded($0.1))" }
            .joined(separator: "&")
        return Data(body.utf8)
    }

    private func formPercentEncoded(_ value: String) -> String {
        value.utf8.map { byte in
            switch byte {
            case 0x41...0x5A, 0x61...0x7A, 0x30...0x39, 0x2D, 0x2E, 0x5F, 0x7E:
                return String(UnicodeScalar(byte))
            default:
                return String(format: "%%%02X", byte)
            }
        }.joined()
    }
}
