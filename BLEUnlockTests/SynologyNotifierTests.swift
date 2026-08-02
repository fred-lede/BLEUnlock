import Foundation
import XCTest
@testable import BLEUnlock

final class SynologyNotifierTests: XCTestCase {
    private var transport: QueuedHTTPTransport!
    private var notifier: SynologyNotifier!

    override func setUp() {
        super.setUp()
        transport = QueuedHTTPTransport()
        notifier = SynologyNotifier(transport: transport)
    }

    private var credentials: SynologyCredentials {
        SynologyCredentials(webhookURL: "https://nas.local:5001/webapi/entry.cgi?api=SYNO.Chat.External&method=incoming&version=2&token=webhook-SECRET",
                            username: "user-SECRET",
                            password: "password-SECRET",
                            channelID: "42")
    }

    private func response(status: Int = 200) -> HTTPURLResponse {
        HTTPURLResponse(url: URL(string: "https://nas.local:5001")!,
                        statusCode: status,
                        httpVersion: nil,
                        headerFields: nil)!
    }

    private func assertSanitized(_ error: SynologyError,
                                 file: StaticString = #filePath,
                                 line: UInt = #line) {
        let description = String(describing: error)
        let combined = "\(description) \(error.localizedDescription)"
        for secret in ["webhook-SECRET", "user-SECRET", "password-SECRET", "sid-SECRET"] {
            XCTAssertFalse(combined.contains(secret), file: file, line: line)
        }
    }

    // MARK: - Text (incoming webhook)

    func testSendTextPostsFormEncodedPayloadToWebhookURL() throws {
        transport.results = [.success((Data(#"{"success":true}"#.utf8), response()))]
        let done = expectation(description: "completion")

        notifier.sendText(credentials: credentials, text: "Door opened") { result in
            guard case .success = result else {
                return XCTFail("Expected success, got \(result)")
            }
            done.fulfill()
        }

        wait(for: [done], timeout: 1)
        let request = try XCTUnwrap(transport.requests.first)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url?.absoluteString, credentials.webhookURL)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"),
                       "application/x-www-form-urlencoded")
        let body = String(decoding: try XCTUnwrap(request.httpBody), as: UTF8.self)
        XCTAssertTrue(body.hasPrefix("payload="))
        let encodedPayload = body.dropFirst("payload=".count).removingPercentEncoding
        let decoded = try XCTUnwrap(encodedPayload)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(decoded.utf8)) as? [String: String])
        XCTAssertEqual(json["text"], "Door opened")
    }

    func testSendTextRejectsWebhookFailure() throws {
        transport.results = [.success((Data(#"{"success":false}"#.utf8), response()))]
        let done = expectation(description: "completion")

        notifier.sendText(credentials: credentials, text: "x") { result in
            defer { done.fulfill() }
            guard case .failure(let error) = result else {
                return XCTFail("Expected failure")
            }
            XCTAssertEqual(error, .rejected)
            self.assertSanitized(error)
        }

        wait(for: [done], timeout: 1)
    }

    func testSendTextMalformedResponseFails() {
        transport.results = [.success((Data("not json".utf8), response()))]
        let done = expectation(description: "completion")

        notifier.sendText(credentials: credentials, text: "x") { result in
            defer { done.fulfill() }
            guard case .failure(let error) = result else {
                return XCTFail("Expected failure")
            }
            XCTAssertEqual(error, .invalidResponse)
            self.assertSanitized(error)
        }

        wait(for: [done], timeout: 1)
    }

    func testSendTextHTTPErrorMapsToHTTPStatus() {
        transport.results = [.success((Data(#"{}"#.utf8), response(status: 500)))]
        let done = expectation(description: "completion")

        notifier.sendText(credentials: credentials, text: "x") { result in
            defer { done.fulfill() }
            guard case .failure(let error) = result else {
                return XCTFail("Expected failure")
            }
            XCTAssertEqual(error, .httpStatus(500))
        }

        wait(for: [done], timeout: 1)
    }

    // MARK: - Photo (SYNO.Chat.Post flow)

    func testSendPhotoPerformsLoginUploadThenPostWithSanitizedSecrets() throws {
        let photoBytes = Data([0xFF, 0xD8, 0x00, 0x7F, 0xD9])
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let photoURL = directory.appendingPathComponent("capture.jpg")
        try photoBytes.write(to: photoURL)

        transport.results = [
            .success((Data(#"{"success":true,"data":{"sid":"sid-SECRET","synotoken":"token-SECRET"}}"#.utf8), response())),
            .success((Data(#"{"success":true,"data":{"post_id":25769803789,"file_props":{"name":"capture.jpg"}}}"#.utf8), response())),
            .success((Data(#"{"success":true,"data":{"post_id":25769803790}}"#.utf8), response()))
        ]
        let done = expectation(description: "completion")

        notifier.sendPhoto(credentials: credentials, photoURL: photoURL, caption: "Door opened") { result in
            defer { done.fulfill() }
            guard case .success = result else {
                return XCTFail("Expected success, got \(result)")
            }
        }

        wait(for: [done], timeout: 1)
        XCTAssertEqual(transport.requests.count, 3)

        let login = transport.requests[0]
        XCTAssertEqual(login.httpMethod, "POST")
        XCTAssertEqual(login.url?.path, "/webapi/auth.cgi")
        var query = try XCTUnwrap(URLComponents(url: try XCTUnwrap(login.url), resolvingAgainstBaseURL: false)?.queryItems)
        XCTAssertEqual(query.first(where: { $0.name == "api" })?.value, "SYNO.API.Auth")
        XCTAssertEqual(query.first(where: { $0.name == "version" })?.value, "6")
        XCTAssertEqual(query.first(where: { $0.name == "method" })?.value, "login")
        XCTAssertEqual(query.first(where: { $0.name == "format" })?.value, "sid")
        XCTAssertEqual(query.first(where: { $0.name == "session" })?.value, "Chat")
        let loginBody = String(decoding: try XCTUnwrap(login.httpBody), as: UTF8.self)
        XCTAssertTrue(loginBody.contains("account=user-SECRET"))
        XCTAssertTrue(loginBody.contains("passwd=password-SECRET"))

        let upload = transport.requests[1]
        XCTAssertEqual(upload.url?.path, "/webapi/entry.cgi")
        query = try XCTUnwrap(URLComponents(url: try XCTUnwrap(upload.url), resolvingAgainstBaseURL: false)?.queryItems)
        XCTAssertEqual(query.first(where: { $0.name == "api" })?.value, "SYNO.Chat.Post")
        XCTAssertEqual(query.first(where: { $0.name == "method" })?.value, "create")
        XCTAssertEqual(query.first(where: { $0.name == "version" })?.value, "5")
        XCTAssertEqual(query.first(where: { $0.name == "channel_id" })?.value, "42")
        XCTAssertEqual(query.first(where: { $0.name == "_sid" })?.value, "sid-SECRET")
        XCTAssertEqual(upload.value(forHTTPHeaderField: "X-SYNO-TOKEN"), "token-SECRET")
        XCTAssertTrue(upload.value(forHTTPHeaderField: "Cookie")?.contains("id=sid-SECRET") == true)
        let contentType = try XCTUnwrap(upload.value(forHTTPHeaderField: "Content-Type"))
        XCTAssertTrue(contentType.hasPrefix("multipart/form-data; boundary="))
        let body = try XCTUnwrap(upload.httpBody)
        let bodyString = String(decoding: body, as: UTF8.self)
        XCTAssertTrue(bodyString.contains("name=\"type\"\r\n\r\nfile"))
        XCTAssertTrue(bodyString.contains("name=\"file\"; filename=\"capture.jpg\""))
        XCTAssertTrue(bodyString.contains("application/octet-stream"))
        XCTAssertTrue(body.range(of: photoBytes) != nil)

        let post = transport.requests[2]
        XCTAssertEqual(post.url?.path, "/webapi/entry.cgi")
        query = try XCTUnwrap(URLComponents(url: try XCTUnwrap(post.url), resolvingAgainstBaseURL: false)?.queryItems)
        XCTAssertEqual(query.first(where: { $0.name == "_sid" })?.value, "sid-SECRET")
        XCTAssertEqual(post.value(forHTTPHeaderField: "X-SYNO-TOKEN"), "token-SECRET")
        let postBody = String(decoding: try XCTUnwrap(post.httpBody), as: UTF8.self)
        XCTAssertTrue(postBody.contains("message=Door%20opened"))
        XCTAssertFalse(postBody.contains("file_id"))
    }

    func testSendPhotoLoginFailureMapsToLoginFailedWithoutFurtherRequests() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let photoURL = directory.appendingPathComponent("capture.jpg")
        try Data([0xFF, 0xD8, 0xFF, 0xD9]).write(to: photoURL)

        transport.results = [.success((Data(#"{"success":false,"error":{"code":401}}"#.utf8), response()))]
        let done = expectation(description: "completion")

        notifier.sendPhoto(credentials: credentials, photoURL: photoURL, caption: "x") { result in
            defer { done.fulfill() }
            guard case .failure(let error) = result else {
                return XCTFail("Expected failure")
            }
            XCTAssertEqual(error, .loginFailed)
            self.assertSanitized(error)
        }

        wait(for: [done], timeout: 1)
        XCTAssertEqual(transport.requests.count, 1)
    }

    func testSendPhotoUploadFailureMapsToUploadFailed() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let photoURL = directory.appendingPathComponent("capture.jpg")
        try Data([0xFF, 0xD8, 0xFF, 0xD9]).write(to: photoURL)

        transport.results = [
            .success((Data(#"{"success":true,"data":{"sid":"sid-SECRET","synotoken":"token-SECRET"}}"#.utf8), response())),
            .success((Data(#"{"success":false,"error":{"code":103}}"#.utf8), response()))
        ]
        let done = expectation(description: "completion")

        notifier.sendPhoto(credentials: credentials, photoURL: photoURL, caption: "x") { result in
            defer { done.fulfill() }
            guard case .failure(let error) = result else {
                return XCTFail("Expected failure")
            }
            XCTAssertEqual(error, .uploadFailed)
            self.assertSanitized(error)
        }

        wait(for: [done], timeout: 1)
        XCTAssertEqual(transport.requests.count, 2)
    }

    func testSendPhotoUploadWithoutPostDataMapsToUploadFailed() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let photoURL = directory.appendingPathComponent("capture.jpg")
        try Data([0xFF, 0xD8, 0xFF, 0xD9]).write(to: photoURL)

        transport.results = [
            .success((Data(#"{"success":true,"data":{"sid":"sid-SECRET","synotoken":"token-SECRET"}}"#.utf8), response())),
            .success((Data(#"{"success":true}"#.utf8), response()))
        ]
        let done = expectation(description: "completion")

        notifier.sendPhoto(credentials: credentials, photoURL: photoURL, caption: "x") { result in
            defer { done.fulfill() }
            guard case .failure(let error) = result else {
                return XCTFail("Expected failure")
            }
            XCTAssertEqual(error, .uploadFailed)
            self.assertSanitized(error)
        }

        wait(for: [done], timeout: 1)
        XCTAssertEqual(transport.requests.count, 2)
    }

    func testSendPhotoPostFailureMapsToPostFailed() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let photoURL = directory.appendingPathComponent("capture.jpg")
        try Data([0xFF, 0xD8, 0xFF, 0xD9]).write(to: photoURL)

        transport.results = [
            .success((Data(#"{"success":true,"data":{"sid":"sid-SECRET","synotoken":"token-SECRET"}}"#.utf8), response())),
            .success((Data(#"{"success":true,"data":{"post_id":25769803789,"file_props":{"name":"capture.jpg"}}}"#.utf8), response())),
            .success((Data(#"{"success":false,"error":{"code":119}}"#.utf8), response()))
        ]
        let done = expectation(description: "completion")

        notifier.sendPhoto(credentials: credentials, photoURL: photoURL, caption: "x") { result in
            defer { done.fulfill() }
            guard case .failure(let error) = result else {
                return XCTFail("Expected failure")
            }
            XCTAssertEqual(error, .postFailed)
            self.assertSanitized(error)
        }

        wait(for: [done], timeout: 1)
        XCTAssertEqual(transport.requests.count, 3)
    }

    func testSendPhotoTransportErrorMapsToTransport() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let photoURL = directory.appendingPathComponent("capture.jpg")
        try Data([0xFF, 0xD8, 0xFF, 0xD9]).write(to: photoURL)

        transport.results = [.failure(NSError(domain: "https://nas.local:5001/webapi/auth.cgi?account=user-SECRET&passwd=password-SECRET", code: -1009, userInfo: [NSLocalizedDescriptionKey: "https://nas.local:5001/webapi/auth.cgi?account=user-SECRET"]))]
        let done = expectation(description: "completion")

        notifier.sendPhoto(credentials: credentials, photoURL: photoURL, caption: "x") { result in
            defer { done.fulfill() }
            guard case .failure(let error) = result else {
                return XCTFail("Expected failure")
            }
            XCTAssertEqual(error, .transport)
            self.assertSanitized(error)
        }

        wait(for: [done], timeout: 1)
        XCTAssertEqual(transport.requests.count, 1)
    }

    func testSendPhotoInvalidWebhookURLFailsWithoutRequests() throws {
        let credentials = SynologyCredentials(webhookURL: "not a url",
                                              username: "u",
                                              password: "p",
                                              channelID: "1")
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let photoURL = directory.appendingPathComponent("capture.jpg")
        try Data([0xFF, 0xD8, 0xFF, 0xD9]).write(to: photoURL)
        let done = expectation(description: "completion")

        notifier.sendPhoto(credentials: credentials, photoURL: photoURL, caption: "x") { result in
            defer { done.fulfill() }
            guard case .failure(let error) = result else {
                return XCTFail("Expected failure")
            }
            XCTAssertEqual(error, .invalidRequest)
        }

        wait(for: [done], timeout: 1)
        XCTAssertTrue(transport.requests.isEmpty)
    }

    func testSendPhotoUnreadableFileFailsWithoutRequests() {
        let done = expectation(description: "completion")
        notifier.sendPhoto(credentials: credentials,
                           photoURL: URL(fileURLWithPath: "/nonexistent/photo.jpg"),
                           caption: "x") { result in
            defer { done.fulfill() }
            guard case .failure(let error) = result else {
                return XCTFail("Expected failure")
            }
            XCTAssertEqual(error, .unreadablePhoto)
        }

        wait(for: [done], timeout: 1)
        XCTAssertTrue(transport.requests.isEmpty)
    }
}
