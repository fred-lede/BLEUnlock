# Telegram Notifications Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add optional, menu-configured Telegram notifications to BLEUnlock, including an optional camera photo for manual-unlock alerts.

**Architecture:** Add focused settings, Keychain, Telegram transport, camera capture, and orchestration types, then connect them to the existing `AppDelegate` event and menu paths. Keep the existing `event` script independent, use completion handlers for macOS 11 compatibility, and inject all side effects so the feature is covered by deterministic XCTest tests.

**Tech Stack:** Swift 5, AppKit, Foundation/URLSession, Security, AVFoundation, XCTest, Telegram Bot API (`sendMessage` and `sendPhoto`), macOS 11+

## Global Constraints

- Preserve `~/Library/Application Scripts/jp.sone.BLEUnlock/event` and its existing arguments unchanged.
- Telegram starts disabled for existing and new users.
- Event defaults are `away=true`, `lost=true`, `unlocked=false`, and `intruded=true`.
- `Take Photo on Manual Unlock` defaults to true and applies only to `intruded` plus the explicit test-notification action.
- Store Bot Token and Chat ID in macOS Keychain; never store or print either value in UserDefaults, logs, alerts, or error descriptions.
- Request camera access only when a photo is actually needed.
- Delete every temporary photo on success, failure, cancellation, and request-construction failure.
- Camera failure falls back to text; photo-upload failure does not send a second text notification.
- Telegram failures must never block or change BLE presence, locking, or unlocking behavior.
- Use the existing localization mechanism and add every new key to every currently supported `Localizable.strings` file.
- Do not add LINE, image hosting, photo history, third-party dependencies, or unrelated refactoring.
- Preserve the user's existing uncommitted changes in `BLEUnlock.xcodeproj/project.pbxproj` and `BLEUnlock.xcodeproj/xcshareddata/xcschemes/BLEUnlock.xcscheme`; merge additions and stage only intentional hunks.

---

## File Map

- Create `BLEUnlock/TelegramEvent.swift`: event model, context, and stable preference keys.
- Create `BLEUnlock/TelegramSettings.swift`: UserDefaults-backed switches and Keychain-backed credentials.
- Create `BLEUnlock/KeychainStore.swift`: small Security-framework adapter.
- Create `BLEUnlock/TelegramNotifier.swift`: Telegram request construction, transport, response validation, and redacted errors.
- Create `BLEUnlock/CameraCapture.swift`: AVFoundation authorization and one-shot JPEG capture.
- Create `BLEUnlock/TelegramNotificationService.swift`: event filtering, message formatting, photo fallback/cleanup, and failure reporting.
- Create `BLEUnlock/TelegramMenuController.swift`: submenu, configuration dialog, event toggles, photo toggle, and test action.
- Modify `BLEUnlock/AppDelegate.swift`: create the feature objects and forward the four existing events after running the existing script.
- Modify `BLEUnlock/Info.plist`: add `NSCameraUsageDescription`.
- Modify all `BLEUnlock/*.lproj/Localizable.strings`: localize the new menu, dialog, event, status, and error strings.
- Modify `BLEUnlock.xcodeproj/project.pbxproj`: add production files, the `BLEUnlockTests` XCTest target, Security/AVFoundation linkage where necessary, and test build settings.
- Modify `BLEUnlock.xcodeproj/xcshareddata/xcschemes/BLEUnlock.xcscheme`: include `BLEUnlockTests` in the Test action without changing the user's existing Run configuration.
- Create `BLEUnlockTests/TestDoubles.swift`: deterministic defaults, secrets, HTTP, camera, file-removal, clock, and failure-reporter doubles.
- Create `BLEUnlockTests/TelegramSettingsTests.swift`.
- Create `BLEUnlockTests/KeychainStoreTests.swift`.
- Create `BLEUnlockTests/TelegramNotifierTests.swift`.
- Create `BLEUnlockTests/TelegramNotificationServiceTests.swift`.
- Create `BLEUnlockTests/TelegramMenuControllerTests.swift`.
- Modify `README.md` and `README.ja.md`: setup, privacy, event defaults, testing, and troubleshooting.

---

### Task 1: Test Harness, Event Model, and Preference Settings

**Files:**
- Create: `BLEUnlock/TelegramEvent.swift`
- Create: `BLEUnlock/TelegramSettings.swift`
- Create: `BLEUnlockTests/TestDoubles.swift`
- Create: `BLEUnlockTests/TelegramSettingsTests.swift`
- Modify: `BLEUnlock.xcodeproj/project.pbxproj`
- Modify: `BLEUnlock.xcodeproj/xcshareddata/xcschemes/BLEUnlock.xcscheme`

**Interfaces:**
- Produces: `TelegramEvent`, `TelegramEventContext`, `TelegramCredentials`, `SecretStoring`, and `TelegramSettings`.
- Produces: a shared `BLEUnlockTests` target used by every later task.

- [ ] **Step 1: Add the XCTest target and a failing defaults test**

Add a macOS Unit Testing Bundle named `BLEUnlockTests` with:

```text
PRODUCT_BUNDLE_IDENTIFIER = jp.sone.BLEUnlockTests
MACOSX_DEPLOYMENT_TARGET = 11.0
SWIFT_VERSION = 5.0
TEST_HOST = $(BUILT_PRODUCTS_DIR)/BLEUnlock.app/Contents/MacOS/BLEUnlock
BUNDLE_LOADER = $(TEST_HOST)
```

Add it to the shared scheme's Test action. Merge these entries into the current project and scheme files; do not regenerate either file.

Create `BLEUnlockTests/TelegramSettingsTests.swift`:

```swift
import XCTest
@testable import BLEUnlock

final class TelegramSettingsTests: XCTestCase {
    private var defaults: UserDefaults!
    private var secrets: MemorySecretStore!

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: #file)!
        defaults.removePersistentDomain(forName: #file)
        secrets = MemorySecretStore()
    }

    func testDefaultsAreDisabledWithApprovedEventChoices() throws {
        let settings = TelegramSettings(defaults: defaults, secrets: secrets)

        XCTAssertFalse(settings.isEnabled)
        XCTAssertTrue(settings.isEventEnabled(.away))
        XCTAssertTrue(settings.isEventEnabled(.lost))
        XCTAssertFalse(settings.isEventEnabled(.unlocked))
        XCTAssertTrue(settings.isEventEnabled(.intruded))
        XCTAssertTrue(settings.takePhotoOnIntruded)
        XCTAssertFalse(try settings.isConfigured())
    }

    func testPersistsSwitchesAndCredentials() throws {
        let settings = TelegramSettings(defaults: defaults, secrets: secrets)
        settings.isEnabled = true
        settings.setEvent(.away, enabled: false)
        settings.takePhotoOnIntruded = false
        try settings.saveCredentials(token: "token-123", chatID: "987654")

        let reloaded = TelegramSettings(defaults: defaults, secrets: secrets)
        XCTAssertTrue(reloaded.isEnabled)
        XCTAssertFalse(reloaded.isEventEnabled(.away))
        XCTAssertFalse(reloaded.takePhotoOnIntruded)
        XCTAssertEqual(try reloaded.credentials(),
                       TelegramCredentials(token: "token-123", chatID: "987654"))
    }
}
```

Create the first shared double in `BLEUnlockTests/TestDoubles.swift`:

```swift
final class MemorySecretStore: SecretStoring {
    var values: [String: String] = [:]
    func string(for account: String) throws -> String? { values[account] }
    func set(_ value: String, for account: String) throws { values[account] = value }
    func removeValue(for account: String) throws { values.removeValue(forKey: account) }
}
```

- [ ] **Step 2: Run the focused test and verify it fails**

Run:

```bash
xcodebuild test -project BLEUnlock.xcodeproj -scheme BLEUnlock -destination 'platform=macOS' -only-testing:BLEUnlockTests/TelegramSettingsTests
```

Expected: build failure because `TelegramSettings`, `TelegramEvent`, `TelegramCredentials`, and `SecretStoring` do not exist.

- [ ] **Step 3: Add the minimal event and settings implementation**

Create `BLEUnlock/TelegramEvent.swift`:

```swift
import Foundation

enum TelegramEvent: String, CaseIterable {
    case away, lost, unlocked, intruded

    var defaultEnabled: Bool { self != .unlocked }
    var defaultsKey: String { "telegram.event.\(rawValue)" }
}

struct TelegramEventContext: Equatable {
    let event: TelegramEvent
    let hostName: String
    let timestamp: Date
    let rssi: Int?
}

struct TelegramCredentials: Equatable {
    let token: String
    let chatID: String
}
```

Create `BLEUnlock/TelegramSettings.swift`:

```swift
import Foundation

protocol SecretStoring {
    func string(for account: String) throws -> String?
    func set(_ value: String, for account: String) throws
    func removeValue(for account: String) throws
}

final class TelegramSettings {
    private enum Key {
        static let enabled = "telegram.enabled"
        static let takePhoto = "telegram.takePhotoOnIntruded"
        static let token = "botToken"
        static let chatID = "chatID"
    }

    private let defaults: UserDefaults
    private let secrets: SecretStoring

    init(defaults: UserDefaults = .standard, secrets: SecretStoring) {
        self.defaults = defaults
        self.secrets = secrets
    }

    var isEnabled: Bool {
        get { defaults.bool(forKey: Key.enabled) }
        set { defaults.set(newValue, forKey: Key.enabled) }
    }

    var takePhotoOnIntruded: Bool {
        get { defaults.object(forKey: Key.takePhoto) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Key.takePhoto) }
    }

    func isEventEnabled(_ event: TelegramEvent) -> Bool {
        defaults.object(forKey: event.defaultsKey) as? Bool ?? event.defaultEnabled
    }

    func setEvent(_ event: TelegramEvent, enabled: Bool) {
        defaults.set(enabled, forKey: event.defaultsKey)
    }

    func credentials() throws -> TelegramCredentials? {
        guard let token = try secrets.string(for: Key.token), !token.isEmpty,
              let chatID = try secrets.string(for: Key.chatID), !chatID.isEmpty else { return nil }
        return TelegramCredentials(token: token, chatID: chatID)
    }

    func isConfigured() throws -> Bool { try credentials() != nil }

    func saveCredentials(token: String, chatID: String) throws {
        try secrets.set(token.trimmingCharacters(in: .whitespacesAndNewlines), for: Key.token)
        try secrets.set(chatID.trimmingCharacters(in: .whitespacesAndNewlines), for: Key.chatID)
    }
}
```

- [ ] **Step 4: Run the focused test and verify it passes**

Run the Step 2 command.

Expected: `TelegramSettingsTests` passes.

- [ ] **Step 5: Commit the test harness and settings model**

```bash
git add BLEUnlock/TelegramEvent.swift BLEUnlock/TelegramSettings.swift BLEUnlockTests/TestDoubles.swift BLEUnlockTests/TelegramSettingsTests.swift
git add -p BLEUnlock.xcodeproj/project.pbxproj BLEUnlock.xcodeproj/xcshareddata/xcschemes/BLEUnlock.xcscheme
git commit -m "Add Telegram settings model and test target"
```

---

### Task 2: Keychain Credential Storage

**Files:**
- Create: `BLEUnlock/KeychainStore.swift`
- Create: `BLEUnlockTests/KeychainStoreTests.swift`
- Modify: `BLEUnlock.xcodeproj/project.pbxproj`

**Interfaces:**
- Consumes: `SecretStoring` from Task 1.
- Produces: `KeychainStore(service:accessGroup:)` implementing `SecretStoring`.

- [ ] **Step 1: Write failing Keychain lifecycle tests**

```swift
import XCTest
@testable import BLEUnlock

final class KeychainStoreTests: XCTestCase {
    private let account = "test-credential"
    private lazy var store = KeychainStore(service: "jp.sone.BLEUnlockTests.\(UUID().uuidString)")

    override func tearDown() {
        try? store.removeValue(for: account)
        super.tearDown()
    }

    func testSaveReadReplaceAndDelete() throws {
        try store.set("first", for: account)
        XCTAssertEqual(try store.string(for: account), "first")
        try store.set("second", for: account)
        XCTAssertEqual(try store.string(for: account), "second")
        try store.removeValue(for: account)
        XCTAssertNil(try store.string(for: account))
    }
}
```

- [ ] **Step 2: Run the test and verify it fails**

Run:

```bash
xcodebuild test -project BLEUnlock.xcodeproj -scheme BLEUnlock -destination 'platform=macOS' -only-testing:BLEUnlockTests/KeychainStoreTests
```

Expected: build failure because `KeychainStore` does not exist.

- [ ] **Step 3: Implement the Security adapter**

Create `BLEUnlock/KeychainStore.swift` with `import Security`, generic-password queries using `kSecClassGenericPassword`, `kSecAttrService`, and `kSecAttrAccount`, and these exact public behaviors:

```swift
enum KeychainStoreError: LocalizedError {
    case status(OSStatus)
    var errorDescription: String? { "Keychain operation failed (\(statusCode))." }
    private var statusCode: OSStatus {
        switch self { case .status(let status): return status }
    }
}

final class KeychainStore: SecretStoring {
    let service: String
    let accessGroup: String?

    init(service: String, accessGroup: String? = nil) {
        self.service = service
        self.accessGroup = accessGroup
    }

    private func query(for account: String) -> [CFString: Any] {
        var result: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account
        ]
        if let accessGroup = accessGroup { result[kSecAttrAccessGroup] = accessGroup }
        return result
    }

    func string(for account: String) throws -> String? {
        var query = query(for: account)
        query[kSecReturnData] = true
        query[kSecMatchLimit] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess,
              let data = item as? Data,
              let value = String(data: data, encoding: .utf8) else {
            throw KeychainStoreError.status(status)
        }
        return value
    }

    func set(_ value: String, for account: String) throws {
        let data = Data(value.utf8)
        let status = SecItemUpdate(query(for: account) as CFDictionary,
                                   [kSecValueData: data] as CFDictionary)
        if status == errSecSuccess { return }
        guard status == errSecItemNotFound else { throw KeychainStoreError.status(status) }
        var attributes = query(for: account)
        attributes[kSecValueData] = data
        let addStatus = SecItemAdd(attributes as CFDictionary, nil)
        guard addStatus == errSecSuccess else { throw KeychainStoreError.status(addStatus) }
    }

    func removeValue(for account: String) throws {
        let status = SecItemDelete(query(for: account) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainStoreError.status(status)
        }
    }
}
```

The method bodies must never include the secret value in thrown errors. Add `KeychainStore.swift` to the app target and link `Security.framework` if the target does not already resolve it automatically.

- [ ] **Step 4: Run the Keychain and settings tests**

```bash
xcodebuild test -project BLEUnlock.xcodeproj -scheme BLEUnlock -destination 'platform=macOS' -only-testing:BLEUnlockTests/KeychainStoreTests -only-testing:BLEUnlockTests/TelegramSettingsTests
```

Expected: both suites pass.

- [ ] **Step 5: Commit**

```bash
git add BLEUnlock/KeychainStore.swift BLEUnlockTests/KeychainStoreTests.swift
git add -p BLEUnlock.xcodeproj/project.pbxproj
git commit -m "Store Telegram credentials in Keychain"
```

---

### Task 3: Telegram HTTP Client

**Files:**
- Create: `BLEUnlock/TelegramNotifier.swift`
- Create: `BLEUnlockTests/TelegramNotifierTests.swift`
- Modify: `BLEUnlockTests/TestDoubles.swift`
- Modify: `BLEUnlock.xcodeproj/project.pbxproj`

**Interfaces:**
- Consumes: `TelegramCredentials`.
- Produces: `HTTPTransport`, `URLSessionTransport`, `TelegramSending`, `TelegramNotifier`, and sanitized `TelegramError`.

- [ ] **Step 1: Add a recording transport and failing request tests**

Add to `TestDoubles.swift`:

```swift
final class RecordingHTTPTransport: HTTPTransport {
    var requests: [URLRequest] = []
    var result: Result<(Data, HTTPURLResponse), Error>!
    func perform(_ request: URLRequest,
                 completion: @escaping (Result<(Data, HTTPURLResponse), Error>) -> Void) {
        requests.append(request)
        completion(result)
    }
}
```

Create tests that assert:

```swift
func testSendTextBuildsFormRequestAndAcceptsOKResponse()
func testSendPhotoBuildsMultipartWithJPEGAndCaption()
func testTelegramOKFalseReturnsSanitizedDescription()
func testTransportErrorDoesNotExposeTokenOrRequestURL()
func testMalformedResponseFails()
```

The first test must assert method `POST`, endpoint suffix `/sendMessage`, content type `application/x-www-form-urlencoded`, and decoded fields `chat_id` and `text`. The photo test must assert `/sendPhoto`, a multipart boundary, `chat_id`, `caption`, `photo`, filename, and exact JPEG bytes. Every error test must assert that neither `token-SECRET` nor `bot token-SECRET` appears in `String(describing: error)`.

Implement the tests using this concrete pattern, repeating it for each named case with the response/body variation described above:

```swift
func testSendTextBuildsFormRequestAndAcceptsOKResponse() throws {
    transport.result = .success((Data(#"{"ok":true}"#.utf8), response(status: 200)))
    let done = expectation(description: "completion")
    notifier.sendText(credentials: .init(token: "token-SECRET", chatID: "987654"),
                      text: "Fred & Mac") { result in
        XCTAssertNoThrow(try result.get())
        done.fulfill()
    }
    wait(for: [done], timeout: 1)
    let request = try XCTUnwrap(transport.requests.first)
    XCTAssertEqual(request.httpMethod, "POST")
    XCTAssertEqual(request.url?.path, "/bottoken-SECRET/sendMessage")
    XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"),
                   "application/x-www-form-urlencoded")
    let body = String(decoding: try XCTUnwrap(request.httpBody), as: UTF8.self)
    XCTAssertTrue(body.contains("chat_id=987654"))
    XCTAssertTrue(body.contains("text=Fred%20%26%20Mac"))
}

func testTelegramOKFalseReturnsSanitizedDescription() {
    transport.result = .success((Data(#"{"ok":false,"description":"Forbidden"}"#.utf8),
                                 response(status: 200)))
    let done = expectation(description: "completion")
    notifier.sendText(credentials: .init(token: "token-SECRET", chatID: "987654"), text: "x") {
        guard case .failure(let error) = $0 else { return XCTFail("Expected failure") }
        XCTAssertEqual(error, .rejected("Forbidden"))
        XCTAssertFalse(String(describing: error).contains("token-SECRET"))
        done.fulfill()
    }
    wait(for: [done], timeout: 1)
}
```

Define `response(status:)` in the test class with a token-free dummy URL:

```swift
private func response(status: Int) -> HTTPURLResponse {
    HTTPURLResponse(url: URL(string: "https://api.telegram.org")!,
                    statusCode: status, httpVersion: nil, headerFields: nil)!
}
```

- [ ] **Step 2: Run the notifier tests and verify they fail**

```bash
xcodebuild test -project BLEUnlock.xcodeproj -scheme BLEUnlock -destination 'platform=macOS' -only-testing:BLEUnlockTests/TelegramNotifierTests
```

Expected: build failure because the notifier interfaces do not exist.

- [ ] **Step 3: Implement request creation and response validation**

Use these interfaces in `BLEUnlock/TelegramNotifier.swift`:

```swift
protocol HTTPTransport {
    func perform(_ request: URLRequest,
                 completion: @escaping (Result<(Data, HTTPURLResponse), Error>) -> Void)
}

protocol TelegramSending {
    func sendText(credentials: TelegramCredentials, text: String,
                  completion: @escaping (Result<Void, TelegramError>) -> Void)
    func sendPhoto(credentials: TelegramCredentials, photoURL: URL, caption: String,
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
        case .invalidRequest: return "The Telegram request could not be created."
        case .unreadablePhoto: return "The captured photo could not be read."
        case .transport: return "Telegram could not be reached."
        case .httpStatus(let code): return "Telegram returned HTTP status \(code)."
        case .rejected(let description): return description
        case .invalidResponse: return "Telegram returned an invalid response."
        }
    }
}

final class TelegramNotifier: TelegramSending {
    private let transport: HTTPTransport
    init(transport: HTTPTransport) { self.transport = transport }

    func sendText(credentials: TelegramCredentials, text: String,
                  completion: @escaping (Result<Void, TelegramError>) -> Void) {
        guard let request = makeTextRequest(credentials: credentials, text: text) else {
            completion(.failure(.invalidRequest)); return
        }
        perform(request, completion: completion)
    }

    func sendPhoto(credentials: TelegramCredentials, photoURL: URL, caption: String,
                   completion: @escaping (Result<Void, TelegramError>) -> Void) {
        guard let request = try? makePhotoRequest(credentials: credentials,
                                                  photoURL: photoURL,
                                                  caption: caption) else {
            completion(.failure(.unreadablePhoto)); return
        }
        perform(request, completion: completion)
    }

    private func makeTextRequest(credentials: TelegramCredentials, text: String) -> URLRequest? {
        guard let url = URL(string: "https://api.telegram.org/bot\(credentials.token)/sendMessage") else { return nil }
        var components = URLComponents()
        components.queryItems = [URLQueryItem(name: "chat_id", value: credentials.chatID),
                                 URLQueryItem(name: "text", value: text)]
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
        body.appendMultipartFile(name: "photo", filename: photoURL.lastPathComponent,
                                 mimeType: "image/jpeg", bytes: data, boundary: boundary)
        body.append(Data("--\(boundary)--\r\n".utf8))
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
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
                    completion(.failure(.httpStatus(response.statusCode))); return
                }
                guard let decoded = try? JSONDecoder().decode(TelegramResponse.self, from: data) else {
                    completion(.failure(.invalidResponse)); return
                }
                decoded.ok
                    ? completion(.success(()))
                    : completion(.failure(.rejected(decoded.description ?? "Telegram rejected the request.")))
            }
        }
    }
}

private extension Data {
    mutating func appendMultipartField(name: String, value: String, boundary: String) {
        append(Data("--\(boundary)\r\n".utf8))
        append(Data("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".utf8))
        append(Data("\(value)\r\n".utf8))
    }

    mutating func appendMultipartFile(name: String, filename: String,
                                      mimeType: String, bytes: Data, boundary: String) {
        append(Data("--\(boundary)\r\n".utf8))
        append(Data("Content-Disposition: form-data; name=\"\(name)\"; filename=\"\(filename)\"\r\n".utf8))
        append(Data("Content-Type: \(mimeType)\r\n\r\n".utf8))
        append(bytes)
        append(Data("\r\n".utf8))
    }
}

final class URLSessionTransport: HTTPTransport {
    private let session: URLSession
    init(session: URLSession = .shared) { self.session = session }
    func perform(_ request: URLRequest,
                 completion: @escaping (Result<(Data, HTTPURLResponse), Error>) -> Void) {
        session.dataTask(with: request) { data, response, error in
            if error != nil { completion(.failure(TelegramError.transport)); return }
            guard let data = data, let response = response as? HTTPURLResponse else {
                completion(.failure(TelegramError.invalidResponse)); return
            }
            completion(.success((data, response)))
        }.resume()
    }
}
```

Decode only this response shape:

```swift
private struct TelegramResponse: Decodable {
    let ok: Bool
    let description: String?
}
```

Map a non-2xx response to `.httpStatus(code)`, `ok: false` to `.rejected(description ?? "Telegram rejected the request.")`, and transport failures to `.transport`. Never propagate `URLError`, `URLRequest`, or a token-bearing URL to callers.

- [ ] **Step 4: Run the notifier tests**

Run the Step 2 command.

Expected: all notifier tests pass.

- [ ] **Step 5: Commit**

```bash
git add BLEUnlock/TelegramNotifier.swift BLEUnlockTests/TelegramNotifierTests.swift BLEUnlockTests/TestDoubles.swift
git add -p BLEUnlock.xcodeproj/project.pbxproj
git commit -m "Add Telegram Bot API client"
```

---

### Task 4: One-shot Camera Capture

**Files:**
- Create: `BLEUnlock/CameraCapture.swift`
- Create: `BLEUnlockTests/CameraCaptureTests.swift`
- Modify: `BLEUnlock/Info.plist`
- Modify: `BLEUnlock.xcodeproj/project.pbxproj`

**Interfaces:**
- Produces: `PhotoCapturing`, `CameraAuthorizationProviding`, `PhotoSessionProviding`, `CameraCapture`, and `CameraCaptureError`.

- [ ] **Step 1: Write failing authorization and temporary-file tests**

Use injected authorization and session providers; tests must cover:

```swift
func testAuthorizedCaptureWritesReturnedJPEGToUniqueTemporaryURL()
func testNotDeterminedRequestsAccessBeforeCapture()
func testDeniedPermissionReturnsDeniedWithoutStartingSession()
func testMissingCameraReturnsNoCamera()
func testCaptureTimeoutStopsSessionAndReturnsTimeout()
func testCaptureFailureStopsSessionAndReturnsCaptureFailed()
```

The authorized test supplies `[0xFF, 0xD8, 0xFF, 0xD9]`, verifies the bytes at the returned URL, then removes it. The timeout test uses an injected scheduler rather than sleeping.

Use concrete fakes and assertions in `CameraCaptureTests.swift`:

```swift
final class StubCameraAuthorization: CameraAuthorizationProviding {
    var authorizationStatus: AVAuthorizationStatus = .authorized
    var requestResult = true
    func requestAccess(completion: @escaping (Bool) -> Void) { completion(requestResult) }
}

final class StubPhotoSession: PhotoSessionProviding {
    var result: Result<Data, CameraCaptureError>?
    var stopped = false
    func captureJPEG(completion: @escaping (Result<Data, CameraCaptureError>) -> Void) {
        if let result = result { completion(result) }
    }
    func stop() { stopped = true }
}

func testAuthorizedCaptureWritesReturnedJPEGToUniqueTemporaryURL() throws {
    let session = StubPhotoSession()
    let jpeg = Data([0xFF, 0xD8, 0xFF, 0xD9])
    session.result = .success(jpeg)
    let done = expectation(description: "capture")
    CameraCapture(authorization: StubCameraAuthorization(),
                  sessionFactory: { .success(session) },
                  temporaryDirectory: temporaryDirectory,
                  scheduler: scheduler).capture { result in
        do {
            let url = try result.get()
            XCTAssertEqual(try Data(contentsOf: url), jpeg)
            XCTAssertTrue(url.lastPathComponent.hasPrefix("BLEUnlock-intruded-"))
            try FileManager.default.removeItem(at: url)
        } catch { XCTFail("\(error)") }
        done.fulfill()
    }
    wait(for: [done], timeout: 1)
    XCTAssertTrue(session.stopped)
}

func testDeniedPermissionReturnsDeniedWithoutStartingSession() {
    let authorization = StubCameraAuthorization()
    authorization.authorizationStatus = .denied
    var factoryCalls = 0
    let done = expectation(description: "capture")
    CameraCapture(authorization: authorization,
                  sessionFactory: { factoryCalls += 1; return .failure(.setupFailed) },
                  temporaryDirectory: temporaryDirectory,
                  scheduler: scheduler).capture {
        XCTAssertEqual(try? $0.get(), nil)
        if case .failure(let error) = $0 { XCTAssertEqual(error, .denied) }
        done.fulfill()
    }
    wait(for: [done], timeout: 1)
    XCTAssertEqual(factoryCalls, 0)
}
```

The fake scheduler stores blocks and returns a cancellation token; `testCaptureTimeoutStopsSessionAndReturnsTimeout` explicitly invokes the stored block, then asserts `.timeout`, `session.stopped == true`, and exactly one completion.

- [ ] **Step 2: Run the camera tests and verify they fail**

```bash
xcodebuild test -project BLEUnlock.xcodeproj -scheme BLEUnlock -destination 'platform=macOS' -only-testing:BLEUnlockTests/CameraCaptureTests
```

Expected: build failure because camera interfaces do not exist.

- [ ] **Step 3: Implement AVFoundation capture behind testable protocols**

Use these stable interfaces:

```swift
protocol PhotoCapturing {
    func capture(completion: @escaping (Result<URL, CameraCaptureError>) -> Void)
}

enum CameraCaptureError: LocalizedError, Equatable {
    case denied, restricted, noCamera, setupFailed, captureFailed, timeout, fileWriteFailed
}

protocol CameraAuthorizationProviding {
    var authorizationStatus: AVAuthorizationStatus { get }
    func requestAccess(completion: @escaping (Bool) -> Void)
}

protocol PhotoSessionProviding {
    func captureJPEG(completion: @escaping (Result<Data, CameraCaptureError>) -> Void)
    func stop()
}

protocol ScheduledCancellation { func cancel() }
protocol CameraScheduling {
    @discardableResult
    func schedule(after interval: TimeInterval,
                  _ block: @escaping () -> Void) -> ScheduledCancellation
}

final class CameraCapture: PhotoCapturing {
    init(authorization: CameraAuthorizationProviding = AVCameraAuthorization(),
         sessionFactory: @escaping () -> Result<PhotoSessionProviding, CameraCaptureError> = AVPhotoSession.make,
         temporaryDirectory: URL = FileManager.default.temporaryDirectory,
         scheduler: CameraScheduling = DispatchCameraScheduler(),
         timeout: TimeInterval = 10)

    func capture(completion: @escaping (Result<URL, CameraCaptureError>) -> Void)
}
```

Implement `capture` as a switch over `.authorized`, `.notDetermined`, `.denied`, and `.restricted`; after a successful access request, re-enter the authorized path. The authorized path creates one session, schedules a ten-second timeout, and uses a single-finish closure guarded by `NSLock` so capture and timeout cannot complete twice. The finish closure cancels the timeout, stops the session, writes successful bytes atomically, and returns the URL or `.fileWriteFailed`.

Production `AVPhotoSession.make()` must select `AVCaptureDevice.default(for: .video)`, create `AVCaptureDeviceInput`, attach `AVCapturePhotoOutput`, retain a private `AVCapturePhotoCaptureDelegate` proxy until completion, and return `.noCamera` or `.setupFailed` during construction. `captureJPEG` starts the session on a private serial queue, calls `capturePhoto(with: AVCapturePhotoSettings(), delegate:)`, converts `fileDataRepresentation()` to `Data`, and clears the retained proxy after calling its completion exactly once. `stop()` stops the session on the same queue. `CameraCapture` writes the JPEG to:

```swift
FileManager.default.temporaryDirectory
    .appendingPathComponent("BLEUnlock-intruded-\(UUID().uuidString)")
    .appendingPathExtension("jpg")
```

Add this exact key to `BLEUnlock/Info.plist`:

```xml
<key>NSCameraUsageDescription</key>
<string>BLEUnlock uses the camera to photograph a manual unlock and send the alert through Telegram.</string>
```

Link `AVFoundation.framework` if required by the project target.

- [ ] **Step 4: Run the camera tests**

Run the Step 2 command.

Expected: all camera tests pass without accessing real camera hardware.

- [ ] **Step 5: Commit**

```bash
git add BLEUnlock/CameraCapture.swift BLEUnlock/Info.plist BLEUnlockTests/CameraCaptureTests.swift
git add -p BLEUnlock.xcodeproj/project.pbxproj
git commit -m "Add one-shot camera capture"
```

---

### Task 5: Notification Orchestration, Fallback, Cleanup, and Rate Limiting

**Files:**
- Create: `BLEUnlock/TelegramNotificationService.swift`
- Create: `BLEUnlockTests/TelegramNotificationServiceTests.swift`
- Modify: `BLEUnlockTests/TestDoubles.swift`
- Modify: `BLEUnlock.xcodeproj/project.pbxproj`

**Interfaces:**
- Consumes: `TelegramSettings`, `TelegramSending`, `PhotoCapturing`, and `TelegramEventContext`.
- Produces: `TelegramNotificationHandling`, `TelegramNotificationService`, `FailureReporting`, and `RateLimitedFailureReporter`.

- [ ] **Step 1: Write failing orchestration tests**

Add recording doubles for `TelegramSending`, `PhotoCapturing`, `FailureReporting`, and file removal. Write these exact behavior tests:

```swift
func testDisabledTelegramDoesNothing()
func testDisabledEventDoesNothing()
func testAwaySendsHostTimeEventAndRSSIAsText()
func testIntrudedWithPhotoSendsPhotoAndDeletesFileOnSuccess()
func testIntrudedDeletesPhotoWhenUploadFailsWithoutTextRetry()
func testCancelledPhotoUploadDeletesPhotoWithoutTextRetry()
func testCaptureFailureFallsBackToTextAndReportsFailure()
func testRequestConstructionFailureDeletesPhoto()
func testTestNotificationUsesPhotoSetting()
func testFailureReporterRateLimitsSameFailureForFiveMinutes()
```

For each no-op test, assert zero camera and network calls. For cleanup tests, assert the exact captured URL appears once in the remover's calls. For the photo-upload failure test, assert one photo call and zero text calls.

Use this concrete arrangement for the critical fallback/cleanup cases:

```swift
func testCaptureFailureFallsBackToTextAndReportsFailure() throws {
    try settings.saveCredentials(token: "token", chatID: "chat")
    settings.isEnabled = true
    camera.result = .failure(.denied)

    service.handle(.init(event: .intruded, hostName: "Fred-Mac",
                         timestamp: Date(timeIntervalSince1970: 100), rssi: -47))

    XCTAssertEqual(sender.photoCalls.count, 0)
    XCTAssertEqual(sender.textCalls.count, 1)
    XCTAssertEqual(reporter.categories, ["camera"])
}

func testIntrudedDeletesPhotoWhenUploadFailsWithoutTextRetry() throws {
    try settings.saveCredentials(token: "token", chatID: "chat")
    settings.isEnabled = true
    camera.result = .success(photoURL)
    sender.photoResult = .failure(.transport)

    service.handle(.init(event: .intruded, hostName: "Fred-Mac",
                         timestamp: Date(timeIntervalSince1970: 100), rssi: nil))

    XCTAssertEqual(sender.photoCalls.count, 1)
    XCTAssertEqual(sender.textCalls.count, 0)
    XCTAssertEqual(removedURLs, [photoURL])
    XCTAssertEqual(reporter.categories, ["telegram"])
}
```

`RecordingTelegramSender` completes synchronously from configurable `textResult` and `photoResult`; `StubPhotoCapturer` does the same from `result`. This makes all assertions deterministic without waiting for network or camera hardware.

- [ ] **Step 2: Run the service tests and verify they fail**

```bash
xcodebuild test -project BLEUnlock.xcodeproj -scheme BLEUnlock -destination 'platform=macOS' -only-testing:BLEUnlockTests/TelegramNotificationServiceTests
```

Expected: build failure because the service interfaces do not exist.

- [ ] **Step 3: Implement the coordinator**

Use this entry point:

```swift
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

final class TelegramMessageFormatter: TelegramMessageFormatting {
    func message(for context: TelegramEventContext) -> String
}

final class RateLimitedFailureReporter: FailureReporting {
    init(now: @escaping () -> Date = Date.init,
         interval: TimeInterval = 300,
         notificationCenter: NSUserNotificationCenter = .default)
    func report(category: String, message: String)
}

final class TelegramNotificationService: TelegramNotificationHandling {
    init(settings: TelegramSettings,
         sender: TelegramSending,
         camera: PhotoCapturing,
         removeFile: @escaping (URL) throws -> Void = { try FileManager.default.removeItem(at: $0) },
         reporter: FailureReporting,
         formatter: TelegramMessageFormatting = TelegramMessageFormatter())
}
```

`handle` must return immediately unless Telegram is enabled, configured, and the event switch is on. Format messages as:

```text
<hostname> — <localized event description>
Time: <localized date/time>
RSSI: <value> dBm
```

Omit the RSSI line when nil. Use `DateFormatter` with the user's locale. For `intruded` with photos enabled, capture then call `sendPhoto`; wrap cleanup in the photo completion so it runs for both success and failure. If capture fails, report it and call `sendText`. Do not call `sendText` after `sendPhoto` failure.

Implement `RateLimitedFailureReporter` with an injected clock, a `[String: Date]` last-shown map, and a 300-second interval. It must always log a sanitized category and may post at most one local `NSUserNotification` per category per interval.

- [ ] **Step 4: Run service tests and the complete unit suite**

```bash
xcodebuild test -project BLEUnlock.xcodeproj -scheme BLEUnlock -destination 'platform=macOS'
```

Expected: all tests pass.

- [ ] **Step 5: Commit**

```bash
git add BLEUnlock/TelegramNotificationService.swift BLEUnlockTests/TelegramNotificationServiceTests.swift BLEUnlockTests/TestDoubles.swift
git add -p BLEUnlock.xcodeproj/project.pbxproj
git commit -m "Orchestrate Telegram event notifications"
```

---

### Task 6: Menu, Configuration Dialog, and AppDelegate Event Integration

**Files:**
- Create: `BLEUnlock/TelegramMenuController.swift`
- Create: `BLEUnlockTests/TelegramMenuControllerTests.swift`
- Modify: `BLEUnlock/AppDelegate.swift`
- Modify: `BLEUnlock.xcodeproj/project.pbxproj`

**Interfaces:**
- Consumes: `TelegramSettings`, `TelegramNotificationHandling`, and the Task 1 event model.
- Produces: `TelegramMenuController.menu`, configuration/test actions, and forwarding of all four existing events.

- [ ] **Step 1: Write failing menu-state tests**

Test a controller initialized with memory settings and a recording service:

```swift
func testUnconfiguredMenuDisablesEnableAndTestAndShowsNotConfigured()
func testConfiguredMenuCanEnableTelegram()
func testEventAndPhotoItemsReflectAndPersistSettings()
func testConfigureLeavesExistingTokenWhenTokenFieldIsBlank()
func testConfigureReplacesTokenWhenNewValueIsEntered()
func testSendTestCallsServiceAndPresentsResult()
```

Expose internal read-only item references under `@testable` rather than searching localized titles. Inject a `TelegramDialogPresenting` protocol so tests do not open windows.

At minimum, implement the state and persistence tests with direct item references:

```swift
func testUnconfiguredMenuDisablesEnableAndTestAndShowsNotConfigured() {
    controller.menuWillOpen(controller.menu)
    XCTAssertFalse(controller.enableItem.isEnabled)
    XCTAssertFalse(controller.testItem.isEnabled)
    XCTAssertEqual(controller.statusItem.title, t("telegram_status_not_configured"))
}

func testEventAndPhotoItemsReflectAndPersistSettings() throws {
    try settings.saveCredentials(token: "token", chatID: "chat")
    controller.menuWillOpen(controller.menu)
    XCTAssertEqual(controller.eventItems[.away]?.state, .on)
    XCTAssertEqual(controller.eventItems[.unlocked]?.state, .off)
    XCTAssertEqual(controller.photoItem.state, .on)

    controller.toggleEvent(controller.eventItems[.unlocked]!)
    controller.togglePhoto(controller.photoItem)

    XCTAssertTrue(settings.isEventEnabled(.unlocked))
    XCTAssertFalse(settings.takePhotoOnIntruded)
}

func testConfigureLeavesExistingTokenWhenTokenFieldIsBlank() throws {
    try settings.saveCredentials(token: "original", chatID: "old-chat")
    dialogs.credentialInput = .init(replacementToken: nil, chatID: "new-chat")
    controller.configure()
    XCTAssertEqual(try settings.credentials(),
                   .init(token: "original", chatID: "new-chat"))
}
```

Mark selector methods `@objc internal` so tests can call them while AppKit can still dispatch them.

- [ ] **Step 2: Run the menu tests and verify they fail**

```bash
xcodebuild test -project BLEUnlock.xcodeproj -scheme BLEUnlock -destination 'platform=macOS' -only-testing:BLEUnlockTests/TelegramMenuControllerTests
```

Expected: build failure because `TelegramMenuController` does not exist.

- [ ] **Step 3: Implement the submenu and settings dialog**

Use this controller boundary:

```swift
protocol TelegramDialogPresenting {
    func requestCredentials(hasStoredToken: Bool,
                            completion: (TelegramCredentialInput?) -> Void)
    func showResult(title: String, message: String)
}

struct TelegramCredentialInput {
    let replacementToken: String?
    let chatID: String
}

final class TelegramMenuController: NSObject, NSMenuDelegate {
    let menu = NSMenu()
    init(settings: TelegramSettings,
         service: TelegramNotificationHandling,
         dialogs: TelegramDialogPresenting,
         hostName: @escaping () -> String = { Host.current().localizedName ?? "Mac" })
}
```

Build these items in order: enabled toggle, Configure…, Send Test Notification, separator, Events submenu with all four events, photo toggle, separator, non-interactive status. In `menuWillOpen`, refresh every state and disable Enable/Test when `isConfigured()` is false. Blank token input preserves the existing token; a nonblank token replaces it. Never prefill the secure token field.

The production presenter uses `NSAlert`, `NSSecureTextField`, `NSTextField`, and a vertical `NSStackView`. Its explanatory label names BotFather and explains Chat ID without embedding external credentials or opening a browser automatically.

- [ ] **Step 4: Integrate without changing script semantics**

In `AppDelegate`, construct one settings/notifier/camera/service/menu-controller graph:

```swift
let telegramSettings = TelegramSettings(
    secrets: KeychainStore(service: "jp.sone.BLEUnlock.telegram")
)
lazy var telegramService: TelegramNotificationHandling = TelegramNotificationService(
    settings: telegramSettings,
    sender: TelegramNotifier(transport: URLSessionTransport()),
    camera: CameraCapture(),
    reporter: RateLimitedFailureReporter()
)
lazy var telegramMenuController = TelegramMenuController(
    settings: telegramSettings,
    service: telegramService,
    dialogs: AppKitTelegramDialogPresenter()
)
```

Add `Telegram Notifications` as a submenu in `constructMenu()`. Add this helper:

```swift
func dispatchEvent(_ rawValue: String) {
    runScript(rawValue)
    guard let event = TelegramEvent(rawValue: rawValue) else { return }
    telegramService.handle(TelegramEventContext(
        event: event,
        hostName: Host.current().localizedName ?? "Mac",
        timestamp: Date(),
        rssi: lastRSSI
    ))
}
```

Replace only the four existing `runScript(reason)`, `runScript("unlocked")`, and `runScript("intruded")` event call sites with `dispatchEvent(...)`. The `away` and `lost` values continue to come from `reason`; unknown values still run the script and are ignored by Telegram.

- [ ] **Step 5: Run menu tests, all tests, and a Debug build**

```bash
xcodebuild test -project BLEUnlock.xcodeproj -scheme BLEUnlock -destination 'platform=macOS'
xcodebuild build -project BLEUnlock.xcodeproj -scheme BLEUnlock -configuration Debug CODE_SIGNING_ALLOWED=NO
```

Expected: tests pass and `** BUILD SUCCEEDED **`.

- [ ] **Step 6: Commit**

```bash
git add BLEUnlock/TelegramMenuController.swift BLEUnlock/AppDelegate.swift BLEUnlockTests/TelegramMenuControllerTests.swift
git add -p BLEUnlock.xcodeproj/project.pbxproj
git commit -m "Add Telegram notification menu"
```

---

### Task 7: Localization, Documentation, and End-to-End Verification

**Files:**
- Modify: `BLEUnlock/Base.lproj/Localizable.strings`
- Modify: `BLEUnlock/da.lproj/Localizable.strings`
- Modify: `BLEUnlock/de.lproj/Localizable.strings`
- Modify: `BLEUnlock/ja.lproj/Localizable.strings`
- Modify: `BLEUnlock/nb.lproj/Localizable.strings`
- Modify: `BLEUnlock/sv.lproj/Localizable.strings`
- Modify: `BLEUnlock/tr.lproj/Localizable.strings`
- Modify: `BLEUnlock/zh-Hans.lproj/Localizable.strings`
- Modify: `README.md`
- Modify: `README.ja.md`
- Modify: `BLEUnlock.xcodeproj/project.pbxproj`

**Interfaces:**
- Consumes: every user-facing localization key introduced by Tasks 5 and 6.
- Produces: complete user setup and troubleshooting documentation.

- [ ] **Step 1: Add a failing localization completeness test**

Add `BLEUnlockTests/LocalizationTests.swift`. Parse each listed `.strings` file as a property list and assert it contains the exact shared key set:

```swift
let telegramKeys: Set<String> = [
    "telegram", "telegram_enable", "telegram_configure", "telegram_test",
    "telegram_events", "telegram_event_away", "telegram_event_lost",
    "telegram_event_unlocked", "telegram_event_intruded",
    "telegram_take_photo", "telegram_status_not_configured",
    "telegram_status_enabled", "telegram_status_disabled",
    "telegram_bot_token", "telegram_chat_id", "telegram_save",
    "telegram_setup_help", "telegram_test_success", "telegram_test_failed",
    "telegram_camera_privacy", "telegram_error_not_configured"
]
```

Use the test file location to resolve the repository without relying on the process working directory:

```swift
func testEveryLocalizationContainsAllTelegramKeys() throws {
    let repository = URL(fileURLWithPath: #file)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let localizationDirectories = ["Base", "da", "de", "ja", "nb", "sv", "tr", "zh-Hans"]
    for name in localizationDirectories {
        let url = repository.appendingPathComponent("BLEUnlock/\(name).lproj/Localizable.strings")
        let data = try Data(contentsOf: url)
        let plist = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
        let values = try XCTUnwrap(plist as? [String: String])
        XCTAssertTrue(telegramKeys.subtracting(values.keys).isEmpty, "Missing keys in \(name)")
    }
}
```

- [ ] **Step 2: Run the localization test and verify it fails**

```bash
xcodebuild test -project BLEUnlock.xcodeproj -scheme BLEUnlock -destination 'platform=macOS' -only-testing:BLEUnlockTests/LocalizationTests
```

Expected: failure listing missing Telegram keys.

- [ ] **Step 3: Add all keys to every localization**

Add natural translations for Base English, Japanese, Simplified Chinese, Danish, German, Norwegian Bokmål, Swedish, and Turkish. Keep placeholders identical across translations. Run:

```bash
plutil -lint BLEUnlock/*.lproj/Localizable.strings
```

Expected: every file reports `OK`.

- [ ] **Step 4: Update user documentation**

In `README.md` and `README.ja.md`, document:

```text
1. Create a bot with @BotFather and copy its token.
2. Send the bot a message, then obtain the numeric Chat ID from getUpdates.
3. Open BLEUnlock > Telegram Notifications > Configure… and save both values.
4. Send a test notification, choose event switches, and enable Telegram.
5. If photo alerts are enabled, approve Camera access when macOS asks.
```

State the approved defaults, that only `intruded` can capture an event photo, that temporary photos are deleted after each attempt, and that the legacy `event` script remains available. Replace the obsolete LINE Notify example with a historical note or mark it unsupported; do not present its terminated endpoint as functional.

- [ ] **Step 5: Run automated verification**

```bash
plutil -lint BLEUnlock/Info.plist BLEUnlock/*.lproj/Localizable.strings
xcodebuild test -project BLEUnlock.xcodeproj -scheme BLEUnlock -destination 'platform=macOS'
xcodebuild build -project BLEUnlock.xcodeproj -scheme BLEUnlock -configuration Release CODE_SIGNING_ALLOWED=NO
```

Expected: all plist/string files report `OK`, all tests pass, and Release reports `** BUILD SUCCEEDED **`.

- [ ] **Step 6: Perform manual verification with real credentials**

From `/Users/fred/ai/my_codex/BLEUnlock/build/Release/BLEUnlock.app`, verify:

```text
- Unconfigured state disables Enable and Test.
- Saving credentials never displays the stored token afterward.
- Test text reaches the configured Chat ID.
- Photo-enabled test prompts once for Camera access and reaches Telegram with an image.
- away/lost/intruded follow defaults; unlocked remains off until selected.
- Denied camera access produces a text-only intruded alert.
- No BLEUnlock-intruded-*.jpg remains in the temporary directory after completion.
- The existing event script still receives away, lost, unlocked, and intruded unchanged.
- Repeated offline errors do not flood Notification Center within five minutes.
```

- [ ] **Step 7: Review staged scope and commit**

```bash
git diff --check
git status --short
git add BLEUnlock/*.lproj/Localizable.strings BLEUnlockTests/LocalizationTests.swift README.md README.ja.md
git add -p BLEUnlock.xcodeproj/project.pbxproj
git commit -m "Document and localize Telegram notifications"
```

Before committing, confirm that unrelated user-local Xcode signing, Team ID, or Run-configuration changes are not staged.

---

## Final Verification Gate

- [ ] Run the complete test/build set from a clean shell:

```bash
plutil -lint BLEUnlock/Info.plist BLEUnlock/*.lproj/Localizable.strings
xcodebuild test -project BLEUnlock.xcodeproj -scheme BLEUnlock -destination 'platform=macOS'
xcodebuild build -project BLEUnlock.xcodeproj -scheme BLEUnlock -configuration Debug CODE_SIGNING_ALLOWED=NO
xcodebuild build -project BLEUnlock.xcodeproj -scheme BLEUnlock -configuration Release CODE_SIGNING_ALLOWED=NO
git diff --check
git status --short
```

Expected: plist checks are `OK`, all tests pass, both builds succeed, no whitespace errors exist, and only intentionally preserved user-local files remain modified/untracked.

- [ ] Inspect the final commit range and verify no credential or temporary image was committed:

```bash
git log --oneline 2f97965..HEAD
git diff --stat 2f97965..HEAD
git grep -nE 'bot[0-9]+:|telegram\.org/bot[^<]' -- ':!docs/superpowers/plans/*'
git ls-files | rg 'BLEUnlock-intruded-.*\.jpg$'
```

Expected: the feature commits are coherent, the secret scan and tracked-photo scan produce no matches, and the implementation matches `docs/superpowers/specs/2026-07-20-telegram-notifications-design.md`.
