# Telegram Photo Location Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Optionally attach the Mac's fresh Core Location coordinates and an Apple Maps link to Telegram intrusion photos, then send a Telegram native location message without ever blocking the security notification on location failure.

**Architecture:** Add a one-shot Core Location adapter that returns an app-owned `TelegramLocation`, then coordinate it in parallel with the existing camera capture. Extend the existing Telegram sender and formatter through small protocols, keep the feature opt-in through `TelegramSettings`, and wire authorization from the Telegram menu without continuous tracking or persisted coordinates.

**Tech Stack:** Swift 5, AppKit, Core Location, Foundation networking, Telegram Bot API, XCTest, Xcode 26, macOS 11 deployment target.

## Global Constraints

- Use the Mac's location, not the monitored Bluetooth device's location.
- The `attachMacLocation` setting is opt-in and defaults to `false`.
- Use one-shot Core Location with a five-second timeout; do not continuously track.
- Accept only valid coordinates with nonnegative horizontal accuracy whose measurement timestamp is within 60 seconds of the snapshot timestamp.
- Start photo capture and location acquisition concurrently; never delay the actual shutter for location.
- Location denial, restriction, error, invalid data, or timeout must still send the photo with a localized unavailable note.
- Send Telegram `sendLocation` only after the photo upload succeeds; camera or photo-upload failure must not send a map.
- Coordinates remain in memory and must not be written to settings, Keychain, files, or error logs.
- Add no third-party dependency and keep the current macOS 11 deployment target.
- Preserve the user's unrelated uncommitted Xcode project, shared scheme, and `.codegraph` changes. Perform implementation in an isolated worktree and stage only task-owned files.

---

### Task 1: One-shot Mac location boundary

**Files:**
- Create: `BLEUnlock/MacLocationProvider.swift`
- Create: `BLEUnlockTests/MacLocationProviderTests.swift`
- Modify: `BLEUnlock.xcodeproj/project.pbxproj`

**Interfaces:**
- Consumes: `CLLocationManager`, `CLLocationManagerDelegate`, `CLLocationCoordinate2DIsValid`, and the main run loop.
- Produces: `TelegramLocation`, `MacLocationError`, `LocationRequestCancelling`, `LocationAuthorizationRequesting`, `MacLocationProviding.requestLocation(capturedAt:completion:)`, and `CoreMacLocationProvider`.

- [ ] **Step 1: Add the location value and deterministic provider tests**

Register both new files in the application and test targets, then add tests with a recording `CoreLocationClient` and controlled timeout scheduler:

```swift
private var client: RecordingCoreLocationClient!
private var scheduler: ControlledLocationTimeoutScheduler!

override func setUp() {
    super.setUp()
    client = RecordingCoreLocationClient()
    scheduler = ControlledLocationTimeoutScheduler()
}

func testFreshValidLocationCompletesOnce() {
    let capturedAt = Date(timeIntervalSince1970: 1_000)
    let provider = makeProvider()
    var results: [Result<TelegramLocation, MacLocationError>] = []

    let token = provider.requestLocation(capturedAt: capturedAt) { results.append($0) }
    client.sendAuthorization(.authorizedWhenInUse)
    client.sendLocations([
        CLLocation(coordinate: .init(latitude: 25.0330, longitude: 121.5654),
                   altitude: 0,
                   horizontalAccuracy: 18,
                   verticalAccuracy: -1,
                   timestamp: capturedAt.addingTimeInterval(2))
    ])
    client.sendLocations([])

    XCTAssertNotNil(token)
    XCTAssertEqual(results, [.success(.init(latitude: 25.0330,
                                            longitude: 121.5654,
                                            horizontalAccuracy: 18,
                                            timestamp: capturedAt.addingTimeInterval(2)))])
    XCTAssertEqual(client.requestLocationCalls, 1)
    XCTAssertEqual(client.stopCalls, 1)
}

func testRejectsStaleAndInvalidLocations() {
    let capturedAt = Date(timeIntervalSince1970: 1_000)
    let provider = makeProvider()
    var result: Result<TelegramLocation, MacLocationError>?

    _ = provider.requestLocation(capturedAt: capturedAt) { result = $0 }
    client.sendAuthorization(.authorizedWhenInUse)
    client.sendLocations([
        CLLocation(coordinate: .init(latitude: 25, longitude: 121),
                   altitude: 0,
                   horizontalAccuracy: 10,
                   verticalAccuracy: -1,
                   timestamp: capturedAt.addingTimeInterval(-61))
    ])

    XCTAssertEqual(result, .failure(.invalidLocation))
}

func testTimesOutAfterFiveSecondsAndIgnoresLateCallback() {
    let provider = makeProvider()
    var results: [Result<TelegramLocation, MacLocationError>] = []

    _ = provider.requestLocation(capturedAt: Date()) { results.append($0) }
    XCTAssertEqual(scheduler.intervals, [5])
    scheduler.fireFirst()
    client.sendLocations([freshLocation])

    XCTAssertEqual(results, [.failure(.timeout)])
    XCTAssertEqual(client.stopCalls, 1)
}

func testDeniedRestrictedAndCancelledRequestsCompleteWithoutCoordinates() {
    assertAuthorization(.denied, produces: .denied)
    assertAuthorization(.restricted, produces: .restricted)

    let provider = makeProvider()
    var result: Result<TelegramLocation, MacLocationError>?
    let token = provider.requestLocation(capturedAt: Date()) { result = $0 }
    token.cancel()
    XCTAssertEqual(result, .failure(.cancelled))
}
```

The recording client exposes closures matching the production adapter:

```swift
final class RecordingCoreLocationClient: CoreLocationClient {
    var authorizationStatus: CLAuthorizationStatus = .notDetermined
    var onAuthorizationChange: ((CLAuthorizationStatus) -> Void)?
    var onLocations: (([CLLocation]) -> Void)?
    var onError: ((Error) -> Void)?
    private(set) var authorizationCalls = 0
    private(set) var requestLocationCalls = 0
    private(set) var stopCalls = 0

    func requestWhenInUseAuthorization() { authorizationCalls += 1 }
    func requestLocation() { requestLocationCalls += 1 }
    func stop() { stopCalls += 1 }
    func sendAuthorization(_ status: CLAuthorizationStatus) {
        authorizationStatus = status
        onAuthorizationChange?(status)
    }
    func sendLocations(_ locations: [CLLocation]) { onLocations?(locations) }
    func send(error: Error) { onError?(error) }
}

final class ControlledLocationTimeoutScheduler {
    private(set) var intervals: [TimeInterval] = []
    private var actions: [() -> Void] = []

    func schedule(after interval: TimeInterval,
                  action: @escaping () -> Void) -> () -> Void {
        intervals.append(interval)
        actions.append(action)
        let index = actions.count - 1
        return { [weak self] in self?.actions[index] = {} }
    }

    func fireFirst() { actions[0]() }
}

private func makeProvider() -> CoreMacLocationProvider {
    CoreMacLocationProvider(makeClient: { client },
                            servicesEnabled: { true },
                            scheduleTimeout: scheduler.schedule)
}

private var freshLocation: CLLocation {
    CLLocation(coordinate: .init(latitude: 25.033, longitude: 121.5654),
               altitude: 0,
               horizontalAccuracy: 18,
               verticalAccuracy: -1,
               timestamp: Date())
}

private func assertAuthorization(_ status: CLAuthorizationStatus,
                                 produces expected: MacLocationError) {
    client.authorizationStatus = .notDetermined
    let provider = makeProvider()
    var result: Result<TelegramLocation, MacLocationError>?
    _ = provider.requestLocation(capturedAt: Date()) { result = $0 }
    client.sendAuthorization(status)
    XCTAssertEqual(result, .failure(expected))
}
```

- [ ] **Step 2: Run the focused test and verify RED**

Run:

```bash
xcodebuild test -project BLEUnlock.xcodeproj -scheme BLEUnlock \
  -destination 'platform=macOS' -derivedDataPath build/DerivedData \
  -only-testing:BLEUnlockTests/MacLocationProviderTests \
  CODE_SIGNING_ALLOWED=NO
```

Expected: compilation fails because `TelegramLocation`, `CoreLocationClient`, and `CoreMacLocationProvider` do not exist.

- [ ] **Step 3: Implement the app-owned location types and protocols**

Create `BLEUnlock/MacLocationProvider.swift` beginning with:

```swift
import CoreLocation
import Foundation

struct TelegramLocation: Equatable {
    let latitude: Double
    let longitude: Double
    let horizontalAccuracy: CLLocationAccuracy
    let timestamp: Date
}

enum MacLocationError: Error, Equatable {
    case servicesDisabled
    case denied
    case restricted
    case unavailable
    case invalidLocation
    case timeout
    case cancelled
}

protocol LocationRequestCancelling: AnyObject {
    func cancel()
}

protocol LocationAuthorizationRequesting {
    func requestAuthorization()
}

protocol MacLocationProviding {
    @discardableResult
    func requestLocation(
        capturedAt: Date,
        completion: @escaping (Result<TelegramLocation, MacLocationError>) -> Void
    ) -> LocationRequestCancelling
}

protocol CoreLocationClient: AnyObject {
    var authorizationStatus: CLAuthorizationStatus { get }
    var onAuthorizationChange: ((CLAuthorizationStatus) -> Void)? { get set }
    var onLocations: (([CLLocation]) -> Void)? { get set }
    var onError: ((Error) -> Void)? { get set }
    func requestWhenInUseAuthorization()
    func requestLocation()
    func stop()
}
```

Implement `CLLocationClient` as the only type that imports delegate callbacks into closures. Initialize and use its `CLLocationManager` on the main run loop:

```swift
final class CLLocationClient: NSObject, CoreLocationClient, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    var onAuthorizationChange: ((CLAuthorizationStatus) -> Void)?
    var onLocations: (([CLLocation]) -> Void)?
    var onError: ((Error) -> Void)?
    var authorizationStatus: CLAuthorizationStatus { manager.authorizationStatus }

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    func requestWhenInUseAuthorization() { manager.requestWhenInUseAuthorization() }
    func requestLocation() { manager.requestLocation() }
    func stop() { manager.stopUpdatingLocation() }
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        onAuthorizationChange?(manager.authorizationStatus)
    }
    func locationManager(_ manager: CLLocationManager,
                         didUpdateLocations locations: [CLLocation]) {
        onLocations?(locations)
    }
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        onError?(error)
    }
}
```

- [ ] **Step 4: Implement the five-second, exactly-once request lifecycle**

Use a request object retained by the returned cancellation token. All state transitions run on the main queue:

```swift
final class CoreMacLocationProvider: MacLocationProviding, LocationAuthorizationRequesting {
    typealias ClientFactory = () -> CoreLocationClient
    typealias TimeoutScheduler = (TimeInterval, @escaping () -> Void) -> () -> Void

    private let makeClient: ClientFactory
    private let servicesEnabled: () -> Bool
    private let scheduleTimeout: TimeoutScheduler
    private var authorizationClient: CoreLocationClient?

    init(makeClient: @escaping ClientFactory = CLLocationClient.init,
         servicesEnabled: @escaping () -> Bool = CLLocationManager.locationServicesEnabled,
         scheduleTimeout: @escaping TimeoutScheduler = CoreMacLocationProvider.dispatchTimeout) {
        self.makeClient = makeClient
        self.servicesEnabled = servicesEnabled
        self.scheduleTimeout = scheduleTimeout
    }

    func requestAuthorization() {
        DispatchQueue.main.async {
            guard self.servicesEnabled() else { return }
            let client = self.makeClient()
            self.authorizationClient = client
            if client.authorizationStatus == .notDetermined {
                client.requestWhenInUseAuthorization()
            }
        }
    }

    @discardableResult
    func requestLocation(
        capturedAt: Date,
        completion: @escaping (Result<TelegramLocation, MacLocationError>) -> Void
    ) -> LocationRequestCancelling {
        let request = CoreMacLocationRequest(makeClient: makeClient,
                                             servicesEnabled: servicesEnabled,
                                             scheduleTimeout: scheduleTimeout,
                                             capturedAt: capturedAt,
                                             completion: completion)
        request.start()
        return request
    }

    static func dispatchTimeout(after interval: TimeInterval,
                                action: @escaping () -> Void) -> () -> Void {
        let item = DispatchWorkItem(block: action)
        DispatchQueue.main.asyncAfter(deadline: .now() + interval, execute: item)
        return { item.cancel() }
    }
}
```

Add the complete request object. It creates the Core Location client only after reaching the main thread, schedules exactly `5`, requests authorization once for `.notDetermined`, and requests one location for an authorized state:

```swift
private final class CoreMacLocationRequest: LocationRequestCancelling {
    private let makeClient: () -> CoreLocationClient
    private let servicesEnabled: () -> Bool
    private let scheduleTimeout: CoreMacLocationProvider.TimeoutScheduler
    private let capturedAt: Date
    private var completion: ((Result<TelegramLocation, MacLocationError>) -> Void)?
    private var client: CoreLocationClient?
    private var cancelTimeout: (() -> Void)?
    private var didRequestAuthorization = false
    private var didRequestLocation = false
    private var didFinish = false

    init(makeClient: @escaping () -> CoreLocationClient,
         servicesEnabled: @escaping () -> Bool,
         scheduleTimeout: @escaping CoreMacLocationProvider.TimeoutScheduler,
         capturedAt: Date,
         completion: @escaping (Result<TelegramLocation, MacLocationError>) -> Void) {
        self.makeClient = makeClient
        self.servicesEnabled = servicesEnabled
        self.scheduleTimeout = scheduleTimeout
        self.capturedAt = capturedAt
        self.completion = completion
    }

    func start() {
        if Thread.isMainThread { startOnMain() }
        else { DispatchQueue.main.async { self.startOnMain() } }
    }

    func cancel() {
        if Thread.isMainThread { finish(.failure(.cancelled)) }
        else { DispatchQueue.main.async { self.finish(.failure(.cancelled)) } }
    }

    private func startOnMain() {
        dispatchPrecondition(condition: .onQueue(.main))
        guard !didFinish else { return }
        guard servicesEnabled() else {
            finish(.failure(.servicesDisabled))
            return
        }
        let client = makeClient()
        self.client = client
        client.onAuthorizationChange = { [weak self] in self?.handleAuthorization($0) }
        client.onLocations = { [weak self] in self?.accept($0) }
        client.onError = { [weak self] _ in self?.finish(.failure(.unavailable)) }
        cancelTimeout = scheduleTimeout(5) { [weak self] in
            self?.finish(.failure(.timeout))
        }
        handleAuthorization(client.authorizationStatus)
    }

    private func handleAuthorization(_ status: CLAuthorizationStatus) {
        guard !didFinish, let client = client else { return }
        switch status {
        case .authorizedAlways, .authorizedWhenInUse:
            guard !didRequestLocation else { return }
            didRequestLocation = true
            client.requestLocation()
        case .denied:
            finish(.failure(.denied))
        case .restricted:
            finish(.failure(.restricted))
        case .notDetermined:
            guard !didRequestAuthorization else { return }
            didRequestAuthorization = true
            client.requestWhenInUseAuthorization()
        @unknown default:
            finish(.failure(.unavailable))
        }
    }

    private func accept(_ locations: [CLLocation]) {
        guard !didFinish else { return }
        guard let value = locations.reversed().first(where: { location in
            CLLocationCoordinate2DIsValid(location.coordinate) &&
                location.horizontalAccuracy >= 0 &&
                abs(location.timestamp.timeIntervalSince(capturedAt)) <= 60
        }) else {
            finish(.failure(.invalidLocation))
            return
        }
        finish(.success(.init(latitude: value.coordinate.latitude,
                              longitude: value.coordinate.longitude,
                              horizontalAccuracy: value.horizontalAccuracy,
                              timestamp: value.timestamp)))
    }

    private func finish(_ result: Result<TelegramLocation, MacLocationError>) {
        dispatchPrecondition(condition: .onQueue(.main))
        guard !didFinish, let completion = completion else { return }
        didFinish = true
        self.completion = nil
        cancelTimeout?()
        cancelTimeout = nil
        client?.stop()
        client?.onAuthorizationChange = nil
        client?.onLocations = nil
        client?.onError = nil
        client = nil
        completion(result)
    }
}
```

- [ ] **Step 5: Run focused tests and verify GREEN**

Run the command from Step 2 again.

Expected: all `MacLocationProviderTests` pass with zero failures.

- [ ] **Step 6: Commit the location boundary**

```bash
git diff --check
git add BLEUnlock/MacLocationProvider.swift \
  BLEUnlockTests/MacLocationProviderTests.swift \
  BLEUnlock.xcodeproj/project.pbxproj
git commit -m "Add one-shot Mac location provider"
```

---

### Task 2: Opt-in Telegram location setting and menu

**Files:**
- Modify: `BLEUnlock/TelegramSettings.swift:10-33`
- Modify: `BLEUnlock/TelegramMenuController.swift:15-136`
- Modify: `BLEUnlockTests/TelegramSettingsTests.swift`
- Modify: `BLEUnlockTests/TelegramMenuControllerTests.swift:5-118`

**Interfaces:**
- Consumes: `LocationAuthorizationRequesting.requestAuthorization()` from Task 1.
- Produces: `TelegramSettings.attachMacLocation`, `TelegramMenuController.locationItem`, and `toggleLocation(_:)`.

- [ ] **Step 1: Write failing setting and menu tests**

Add tests that establish default-off privacy, persistence, enablement, and permission timing:

```swift
func testAttachMacLocationDefaultsOffAndPersists() {
    XCTAssertFalse(settings.attachMacLocation)
    settings.attachMacLocation = true
    XCTAssertTrue(settings.attachMacLocation)
}

func testLocationItemIsBelowPrivacyTextAndDisabledWhenPhotoIsOff() throws {
    try settings.saveCredentials(replacementToken: "token", chatID: "chat")
    settings.takePhotoOnIntruded = false
    controller.menuWillOpen(controller.menu)

    XCTAssertEqual(controller.menu.index(of: controller.locationItem),
                   controller.menu.index(of: controller.privacyItem) + 1)
    XCTAssertFalse(controller.locationItem.isEnabled)
    XCTAssertEqual(controller.locationItem.state, .off)
}

func testEnablingLocationPersistsAndRequestsAuthorizationOnce() {
    controller.toggleLocation(controller.locationItem)

    XCTAssertTrue(settings.attachMacLocation)
    XCTAssertEqual(locationAuthorization.requestCalls, 1)
    XCTAssertEqual(controller.locationItem.state, .on)

    controller.toggleLocation(controller.locationItem)
    XCTAssertFalse(settings.attachMacLocation)
    XCTAssertEqual(locationAuthorization.requestCalls, 1)
}
```

Inject this test double in `setUp`:

```swift
final class RecordingLocationAuthorizationRequester: LocationAuthorizationRequesting {
    private(set) var requestCalls = 0
    func requestAuthorization() { requestCalls += 1 }
}

// In setUp:
locationAuthorization = RecordingLocationAuthorizationRequester()
controller = TelegramMenuController(settings: settings,
                                    service: service,
                                    dialogs: dialogs,
                                    locationAuthorization: locationAuthorization,
                                    hostName: { "Fred-Mac" })
```

- [ ] **Step 2: Run focused tests and verify RED**

```bash
xcodebuild test -project BLEUnlock.xcodeproj -scheme BLEUnlock \
  -destination 'platform=macOS' -derivedDataPath build/DerivedData \
  -only-testing:BLEUnlockTests/TelegramSettingsTests \
  -only-testing:BLEUnlockTests/TelegramMenuControllerTests \
  CODE_SIGNING_ALLOWED=NO
```

Expected: compilation fails because `attachMacLocation`, `locationItem`, and the new controller dependency do not exist.

- [ ] **Step 3: Add the default-off setting**

Add the key and property:

```swift
private enum Key {
    static let enabled = "telegram.enabled"
    static let takePhoto = "telegram.takePhotoOnIntruded"
    static let attachMacLocation = "telegram.attachMacLocation"
    static let token = "botToken"
    static let chatID = "chatID"
}

var attachMacLocation: Bool {
    get { defaults.object(forKey: Key.attachMacLocation) as? Bool ?? false }
    set { defaults.set(newValue, forKey: Key.attachMacLocation) }
}
```

- [ ] **Step 4: Add and synchronize the location menu item**

Extend the initializer with `locationAuthorization: LocationAuthorizationRequesting`, create `locationItem` with `t("telegram_attach_mac_location")`, and insert it immediately after `privacyItem`. Update `menuWillOpen` and actions:

```swift
locationItem.state = settings.attachMacLocation ? .on : .off
locationItem.isEnabled = settings.takePhotoOnIntruded

@objc internal func togglePhoto(_ item: NSMenuItem) {
    settings.takePhotoOnIntruded.toggle()
    menuWillOpen(menu)
}

@objc internal func toggleLocation(_ item: NSMenuItem) {
    guard settings.takePhotoOnIntruded else {
        menuWillOpen(menu)
        return
    }
    settings.attachMacLocation.toggle()
    if settings.attachMacLocation {
        locationAuthorization.requestAuthorization()
    }
    menuWillOpen(menu)
}
```

Do not cancel an already-dispatched notification when the setting is turned off.

- [ ] **Step 5: Run focused tests and commit**

Run the Step 2 command; expected: both suites pass.

```bash
git diff --check
git add BLEUnlock/TelegramSettings.swift BLEUnlock/TelegramMenuController.swift \
  BLEUnlockTests/TelegramSettingsTests.swift \
  BLEUnlockTests/TelegramMenuControllerTests.swift
git commit -m "Add opt-in Telegram location setting"
```

---

### Task 3: Telegram native location transport

**Files:**
- Modify: `BLEUnlock/TelegramNotifier.swift:8-174`
- Modify: `BLEUnlockTests/TelegramNotifierTests.swift`
- Modify: `BLEUnlockTests/TestDoubles.swift:34-67`

**Interfaces:**
- Consumes: `TelegramCredentials`, `HTTPTransport`, `formEncoded(_:)`, and the existing sanitized response path.
- Produces: `TelegramSending.sendLocation(credentials:location:completion:)`.

- [ ] **Step 1: Write failing `sendLocation` request tests**

```swift
func testSendLocationUsesTelegramEndpointAndFormFields() throws {
    transport.result = .success((Data(#"{"ok":true}"#.utf8), response(status: 200)))
    let credentials = TelegramCredentials(token: "token-SECRET", chatID: "987654")
    let location = TelegramLocation(latitude: 25.0330,
                                    longitude: 121.5654,
                                    horizontalAccuracy: 18,
                                    timestamp: Date())
    let done = expectation(description: "completion")

    notifier.sendLocation(credentials: credentials, location: location) { result in
        guard case .success = result else {
            return XCTFail("Expected success, got \(result)")
        }
        done.fulfill()
    }

    wait(for: [done], timeout: 1)
    let request = try XCTUnwrap(transport.requests.first)
    XCTAssertEqual(request.url?.path, "/bottoken-SECRET/sendLocation")
    XCTAssertEqual(request.httpMethod, "POST")
    let body = String(decoding: try XCTUnwrap(request.httpBody), as: UTF8.self)
    XCTAssertTrue(body.contains("chat_id=987654"))
    XCTAssertTrue(body.contains("latitude=25.033"))
    XCTAssertTrue(body.contains("longitude=121.5654"))
}

func testSendLocationRedactsCredentialsFromRejectedResponse() {
    let payload = #"{"ok":false,"description":"token-SECRET 987654 rejected"}"#
    transport.result = .success((Data(payload.utf8), response(status: 200)))
    let done = expectation(description: "completion")
    let location = TelegramLocation(latitude: 25.033,
                                    longitude: 121.5654,
                                    horizontalAccuracy: 18,
                                    timestamp: Date())

    notifier.sendLocation(credentials: .init(token: "token-SECRET", chatID: "987654"),
                          location: location) { result in
        XCTAssertEqual(result,
                       .failure(.rejected("[redacted] [redacted] rejected")))
        done.fulfill()
    }

    wait(for: [done], timeout: 1)
}
```

Reuse the file's existing `response(status:)` helper; do not add a second HTTP-response factory.

- [ ] **Step 2: Run focused tests and verify RED**

```bash
xcodebuild test -project BLEUnlock.xcodeproj -scheme BLEUnlock \
  -destination 'platform=macOS' -derivedDataPath build/DerivedData \
  -only-testing:BLEUnlockTests/TelegramNotifierTests \
  CODE_SIGNING_ALLOWED=NO
```

Expected: compilation fails because `TelegramSending.sendLocation` is missing.

- [ ] **Step 3: Extend the sender protocol and production notifier**

Add this exact interface and implementation:

```swift
func sendLocation(credentials: TelegramCredentials,
                  location: TelegramLocation,
                  completion: @escaping (Result<Void, TelegramError>) -> Void)

func sendLocation(credentials: TelegramCredentials,
                  location: TelegramLocation,
                  completion: @escaping (Result<Void, TelegramError>) -> Void) {
    guard let url = endpointURL(token: credentials.token, method: "sendLocation") else {
        completion(.failure(.invalidRequest))
        return
    }
    var request = URLRequest(url: url, timeoutInterval: 15)
    request.httpMethod = "POST"
    request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
    request.httpBody = formEncoded([
        ("chat_id", credentials.chatID),
        ("latitude", String(location.latitude)),
        ("longitude", String(location.longitude))
    ])
    perform(request, credentials: credentials, completion: completion)
}
```

Extend `RecordingTelegramSender` with a `LocationCall`, `locationResult`, and `locationCalls` so later service tests can assert order and coordinates.

- [ ] **Step 4: Run focused tests and commit**

Run the Step 2 command; expected: all notifier tests pass.

```bash
git diff --check
git add BLEUnlock/TelegramNotifier.swift BLEUnlockTests/TelegramNotifierTests.swift \
  BLEUnlockTests/TestDoubles.swift
git commit -m "Send Telegram native location messages"
```

---

### Task 4: Localized photo location caption

**Files:**
- Modify: `BLEUnlock/TelegramNotificationService.swift:10-102`
- Modify: `BLEUnlockTests/TelegramNotificationServiceTests.swift`

**Interfaces:**
- Consumes: `TelegramEventContext`, `TelegramLocation`, `t(_:)`, and current-locale date formatting.
- Produces: `TelegramMessageFormatting.photoCaption(for:location:) -> String`.

- [ ] **Step 1: Write failing caption tests with a fixed locale and date**

```swift
func testPhotoCaptionIncludesCoordinatesAccuracyAndEscapedAppleMapsLink() {
    let formatter = TelegramMessageFormatter()
    let context = TelegramEventContext(event: .intruded,
                                       hostName: "Fred-Mac",
                                       timestamp: Date(timeIntervalSince1970: 1_000),
                                       rssi: nil)
    let location = TelegramLocation(latitude: 25.033,
                                    longitude: 121.5654,
                                    horizontalAccuracy: 18.4,
                                    timestamp: context.timestamp)

    let caption = formatter.photoCaption(for: context, location: location)

    XCTAssertTrue(caption.contains("25.033000, 121.565400"))
    XCTAssertTrue(caption.contains("±18 m"))
    XCTAssertTrue(caption.contains("https://maps.apple.com/?ll=25.033000,121.565400"))
}

func testPhotoCaptionMarksLocationUnavailableWithoutCoordinates() {
    let formatter = TelegramMessageFormatter()
    let context = TelegramEventContext(event: .intruded,
                                       hostName: "Fred-Mac",
                                       timestamp: Date(timeIntervalSince1970: 1_000),
                                       rssi: nil)
    let caption = formatter.photoCaption(for: context, location: nil)
    XCTAssertTrue(caption.contains(t("telegram_location_unavailable")))
    XCTAssertFalse(caption.contains("maps.apple.com"))
}
```

- [ ] **Step 2: Run focused formatter tests and verify RED**

```bash
xcodebuild test -project BLEUnlock.xcodeproj -scheme BLEUnlock \
  -destination 'platform=macOS' -derivedDataPath build/DerivedData \
  -only-testing:BLEUnlockTests/TelegramNotificationServiceTests \
  CODE_SIGNING_ALLOWED=NO
```

Expected: compilation fails because `photoCaption(for:location:)` is absent.

- [ ] **Step 3: Implement deterministic coordinate and map formatting**

Extend the protocol and formatter:

```swift
protocol TelegramMessageFormatting {
    func message(for context: TelegramEventContext) -> String
    func photoCaption(for context: TelegramEventContext,
                      location: TelegramLocation?) -> String
}

func photoCaption(for context: TelegramEventContext,
                  location: TelegramLocation?) -> String {
    var lines = [message(for: context)]
    guard let location = location else {
        lines.append(t("telegram_location_unavailable"))
        return lines.joined(separator: "\n")
    }
    let latitude = posixDecimal(location.latitude)
    let longitude = posixDecimal(location.longitude)
    lines.append("\(t("telegram_message_coordinates")): \(latitude), \(longitude)")
    lines.append(String(format: "%@: ±%.0f m",
                        t("telegram_message_accuracy"),
                        location.horizontalAccuracy))
    lines.append("\(t("telegram_message_map")): https://maps.apple.com/?ll=\(latitude),\(longitude)")
    return lines.joined(separator: "\n")
}

private func posixDecimal(_ value: Double) -> String {
    String(format: "%.6f", locale: Locale(identifier: "en_US_POSIX"), value)
}
```

The existing `message(for:)` remains unchanged so notifications without the opt-in setting do not gain an unavailable line.

- [ ] **Step 4: Run focused tests and commit**

Run Step 2 again; expected: all service and formatter tests pass.

```bash
git diff --check
git add BLEUnlock/TelegramNotificationService.swift \
  BLEUnlockTests/TelegramNotificationServiceTests.swift
git commit -m "Format Telegram photo location captions"
```

---

### Task 5: Coordinate camera and location notification delivery

**Files:**
- Create: `BLEUnlock/PhotoLocationCoordinator.swift`
- Create: `BLEUnlockTests/PhotoLocationCoordinatorTests.swift`
- Modify: `BLEUnlock/TelegramNotificationService.swift:169-283`
- Modify: `BLEUnlockTests/TelegramNotificationServiceTests.swift`
- Modify: `BLEUnlockTests/TestDoubles.swift`
- Modify: `BLEUnlock.xcodeproj/project.pbxproj`

**Interfaces:**
- Consumes: `PhotoCapturing.capture`, `MacLocationProviding.requestLocation`, `TelegramMessageFormatting.photoCaption`, and all three `TelegramSending` methods.
- Produces: `PhotoLocationCoordinator.capture(capturedAt:completion:)` and service delivery ordering of photo then native map.

- [ ] **Step 1: Write failing coordinator concurrency and race tests**

Use controllable camera and location doubles whose completions do not fire automatically:

```swift
private var camera: ControlledPhotoCapturer!
private var location: ControlledMacLocationProvider!
private var coordinator: PhotoLocationCoordinator!
private let capturedAt = Date(timeIntervalSince1970: 100)
private let photoURL = URL(fileURLWithPath: "/private/tmp/location-test.jpg")
private let validLocation = TelegramLocation(latitude: 25.033,
                                             longitude: 121.5654,
                                             horizontalAccuracy: 18,
                                             timestamp: Date(timeIntervalSince1970: 100))

override func setUp() {
    super.setUp()
    camera = ControlledPhotoCapturer()
    location = ControlledMacLocationProvider()
    coordinator = PhotoLocationCoordinator(camera: camera, location: location)
}

func testStartsPhotoAndLocationImmediatelyAndWaitsForBoth() {
    var outputs: [PhotoLocationOutcome] = []
    coordinator.capture(capturedAt: capturedAt) { outputs.append($0) }

    XCTAssertEqual(camera.captureCalls, 1)
    XCTAssertEqual(location.requestedDates, [capturedAt])
    camera.complete(.success(photoURL))
    XCTAssertTrue(outputs.isEmpty)
    location.complete(.success(validLocation))
    XCTAssertEqual(outputs, [.photo(photoURL, .success(validLocation))])
}

func testLocationFailureStillReturnsPhotoWithoutLocation() {
    var outcome: PhotoLocationOutcome?
    coordinator.capture(capturedAt: capturedAt) { outcome = $0 }
    location.complete(.failure(.timeout))
    camera.complete(.success(photoURL))
    XCTAssertEqual(outcome, .photo(photoURL, .failure(.timeout)))
}

func testCameraFailureCancelsLocationAndCompletesImmediatelyOnce() {
    var outcomes: [PhotoLocationOutcome] = []
    coordinator.capture(capturedAt: capturedAt) { outcomes.append($0) }
    camera.complete(.failure(.captureFailed))
    location.complete(.success(validLocation))

    XCTAssertEqual(location.token.cancelCalls, 1)
    XCTAssertEqual(outcomes, [.cameraFailure(.captureFailed)])
}

private final class ControlledPhotoCapturer: PhotoCapturing {
    private(set) var captureCalls = 0
    private var completion: ((Result<URL, CameraCaptureError>) -> Void)?
    func capture(completion: @escaping (Result<URL, CameraCaptureError>) -> Void) {
        captureCalls += 1
        self.completion = completion
    }
    func complete(_ result: Result<URL, CameraCaptureError>) {
        completion?(result)
    }
}

private final class RecordingLocationToken: LocationRequestCancelling {
    private(set) var cancelCalls = 0
    func cancel() { cancelCalls += 1 }
}

private final class ControlledMacLocationProvider: MacLocationProviding {
    let token = RecordingLocationToken()
    private(set) var requestedDates: [Date] = []
    private var completion: ((Result<TelegramLocation, MacLocationError>) -> Void)?
    @discardableResult
    func requestLocation(
        capturedAt: Date,
        completion: @escaping (Result<TelegramLocation, MacLocationError>) -> Void
    ) -> LocationRequestCancelling {
        requestedDates.append(capturedAt)
        self.completion = completion
        return token
    }
    func complete(_ result: Result<TelegramLocation, MacLocationError>) {
        completion?(result)
    }
}
```

- [ ] **Step 2: Run focused coordinator tests and verify RED**

```bash
xcodebuild test -project BLEUnlock.xcodeproj -scheme BLEUnlock \
  -destination 'platform=macOS' -derivedDataPath build/DerivedData \
  -only-testing:BLEUnlockTests/PhotoLocationCoordinatorTests \
  CODE_SIGNING_ALLOWED=NO
```

Expected: compilation fails because `PhotoLocationCoordinator` and `PhotoLocationOutcome` do not exist.

- [ ] **Step 3: Implement an exactly-once coordinator**

Create a per-notification coordinator. Protect mutable state with `NSLock`; do not share a cancellation token across notifications:

```swift
enum PhotoLocationOutcome: Equatable {
    case photo(URL, Result<TelegramLocation, MacLocationError>)
    case cameraFailure(CameraCaptureError)
}

final class PhotoLocationCoordinator {
    private let camera: PhotoCapturing
    private let location: MacLocationProviding
    private let lock = NSLock()
    private var photo: Result<URL, CameraCaptureError>?
    private var position: Result<TelegramLocation, MacLocationError>?
    private var locationToken: LocationRequestCancelling?
    private var didComplete = false

    init(camera: PhotoCapturing, location: MacLocationProviding) {
        self.camera = camera
        self.location = location
    }

    func capture(capturedAt: Date,
                 completion: @escaping (PhotoLocationOutcome) -> Void) {
        let token = location.requestLocation(capturedAt: capturedAt) { [weak self] result in
            self?.record(location: result, completion: completion)
        }
        lock.lock()
        locationToken = token
        let cancelImmediately = didComplete
        lock.unlock()
        if cancelImmediately { token.cancel() }
        camera.capture { [weak self] result in
            self?.record(photo: result, completion: completion)
        }
    }

    private func record(photo result: Result<URL, CameraCaptureError>,
                        completion: @escaping (PhotoLocationOutcome) -> Void) {
        var action: (() -> Void)?
        lock.lock()
        if !didComplete {
            photo = result
            switch result {
            case .failure(let error):
                didComplete = true
                let token = locationToken
                locationToken = nil
                action = {
                    token?.cancel()
                    completion(.cameraFailure(error))
                }
            case .success:
                action = finishPhotoIfReady(completion: completion)
            }
        }
        lock.unlock()
        action?()
    }

    private func record(location result: Result<TelegramLocation, MacLocationError>,
                         completion: @escaping (PhotoLocationOutcome) -> Void) {
        lock.lock()
        var action: (() -> Void)?
        if !didComplete {
            position = result
            action = finishPhotoIfReady(completion: completion)
        }
        lock.unlock()
        action?()
    }

    private func finishPhotoIfReady(
        completion: @escaping (PhotoLocationOutcome) -> Void
    ) -> (() -> Void)? {
        guard case .success(let url)? = photo, let position = position else { return nil }
        didComplete = true
        locationToken = nil
        return { completion(.photo(url, position)) }
    }
}
```

The completion action always runs after unlocking. It preserves a location
failure for generic local reporting while every late callback observes
`didComplete` and returns.

- [ ] **Step 4: Write failing notification ordering and fallback tests**

Extend `TestDoubles.swift` with an immediately completing provider and sender order recording:

```swift
final class StubLocationRequestToken: LocationRequestCancelling {
    private(set) var cancelCalls = 0
    func cancel() { cancelCalls += 1 }
}

final class StubMacLocationProvider: MacLocationProviding {
    var result: Result<TelegramLocation, MacLocationError> = .failure(.unavailable)
    private(set) var requestedDates: [Date] = []
    let token = StubLocationRequestToken()

    @discardableResult
    func requestLocation(
        capturedAt: Date,
        completion: @escaping (Result<TelegramLocation, MacLocationError>) -> Void
    ) -> LocationRequestCancelling {
        requestedDates.append(capturedAt)
        completion(result)
        return token
    }
}

enum TelegramCallKind: Equatable { case text, photo, location }
```

Add `private(set) var callOrder: [TelegramCallKind] = []` to
`RecordingTelegramSender`, append the matching value in each send method, and
record `LocationCall(credentials:location:)` in its new `sendLocation` method.
In `TelegramNotificationServiceTests.setUp`, create
`location = StubMacLocationProvider()` and pass `location: location` to the
service initializer. Do the same in the test that reconstructs the service
after a Keychain error.

```swift
func testLocationEnabledSendsCaptionedPhotoThenNativeMap() throws {
    try configure()
    settings.attachMacLocation = true
    camera.result = .success(photoURL)
    let validLocation = TelegramLocation(latitude: 25.033,
                                         longitude: 121.5654,
                                         horizontalAccuracy: 18,
                                         timestamp: Date(timeIntervalSince1970: 100))
    location.result = .success(validLocation)

    service.handle(context(event: .intruded))

    XCTAssertEqual(sender.photoCalls.count, 1)
    XCTAssertTrue(sender.photoCalls[0].caption.contains("25.033000, 121.565400"))
    XCTAssertEqual(sender.locationCalls.map(\.location), [validLocation])
    XCTAssertEqual(sender.callOrder, [.photo, .location])
}

func testLocationFailureSendsPhotoWithUnavailableCaptionAndNoMap() throws {
    try configure()
    settings.attachMacLocation = true
    camera.result = .success(photoURL)
    location.result = .failure(.timeout)

    service.handle(context(event: .intruded))

    XCTAssertTrue(sender.photoCalls[0].caption.contains(t("telegram_location_unavailable")))
    XCTAssertTrue(sender.locationCalls.isEmpty)
    XCTAssertEqual(reporter.categories, ["location"])
    XCTAssertEqual(reporter.messages, [t("telegram_location_error")])
}

func testPhotoUploadFailureDoesNotSendNativeMapAndCleansFile() throws {
    try configure()
    settings.attachMacLocation = true
    camera.result = .success(photoURL)
    location.result = .success(.init(latitude: 25.033,
                                     longitude: 121.5654,
                                     horizontalAccuracy: 18,
                                     timestamp: Date(timeIntervalSince1970: 100)))
    sender.photoResult = .failure(.transport)

    service.handle(context(event: .intruded))

    XCTAssertTrue(sender.locationCalls.isEmpty)
    XCTAssertEqual(remover.calls, [photoURL])
}

func testNativeMapFailureReportsWithoutResendingPhoto() throws {
    try configure()
    settings.attachMacLocation = true
    camera.result = .success(photoURL)
    location.result = .success(.init(latitude: 25.033,
                                     longitude: 121.5654,
                                     horizontalAccuracy: 18,
                                     timestamp: Date(timeIntervalSince1970: 100)))
    sender.locationResult = .failure(.transport)
    service.handle(context(event: .intruded))
    XCTAssertEqual(sender.photoCalls.count, 1)
    XCTAssertEqual(reporter.categories.last, "telegram-location")
    XCTAssertEqual(reporter.messages.last, t("telegram_location_send_error"))
}
```

Also preserve tests proving disabled location never calls the provider and camera failure uses the existing text fallback without coordinates.

- [ ] **Step 5: Integrate the coordinator into the notification service**

Add `location: MacLocationProviding` to the service initializer. When photo capture is enabled:

```swift
if settings.attachMacLocation {
    sendLocatedPhotoOrFallback(credentials: credentials,
                               context: context,
                               completion: completion)
} else {
    sendPhotoOrFallback(credentials: credentials,
                        message: formatter.message(for: context),
                        completion: completion)
}
```

Keep each coordinator alive through its completion by capturing it explicitly in the completion closure:

```swift
let coordinator = PhotoLocationCoordinator(camera: camera, location: location)
coordinator.capture(capturedAt: context.timestamp) { [coordinator] outcome in
    _ = coordinator
    self.deliver(outcome,
                 credentials: credentials,
                 context: context,
                 completion: completion)
}
```

Handle the outcome in `deliver` as follows:

```swift
case .cameraFailure(let error):
    reporter.report(category: "camera", message: error.localizedDescription)
    completion?(.failure(error))
    sendText(credentials: credentials,
             message: formatter.message(for: context),
             completion: nil)

case .photo(let photoURL, let positionResult):
    let position = try? positionResult.get()
    if case .failure = positionResult {
        reporter.report(category: "location", message: t("telegram_location_error"))
    }
    let caption = formatter.photoCaption(for: context, location: position)
    sender.sendPhoto(credentials: credentials, photoURL: photoURL, caption: caption) { result in
        do {
            try self.removeFile(photoURL)
        } catch {
            reporter.report(category: "file", message: t("telegram_error_file_cleanup"))
        }
        switch (result, position) {
        case (.success, .some(let position)):
            sender.sendLocation(credentials: credentials, location: position) { mapResult in
                if case .failure = mapResult {
                    reporter.report(category: "telegram-location",
                                    message: t("telegram_location_send_error"))
                }
                completion?(mapResult.mapError { $0 as Error })
            }
        default:
            if case .failure(let error) = result {
                reporter.report(category: "telegram", message: error.localizedDescription)
            }
            completion?(result.mapError { $0 as Error })
        }
    }
```

For test notifications, construct one `TelegramEventContext` and pass its same timestamp to both the formatter and location provider.

- [ ] **Step 6: Run focused tests and commit**

Run:

```bash
xcodebuild test -project BLEUnlock.xcodeproj -scheme BLEUnlock \
  -destination 'platform=macOS' -derivedDataPath build/DerivedData \
  -only-testing:BLEUnlockTests/PhotoLocationCoordinatorTests \
  -only-testing:BLEUnlockTests/TelegramNotificationServiceTests \
  CODE_SIGNING_ALLOWED=NO
```

Expected: all coordinator and service tests pass, including existing photo cleanup and text fallback cases.

```bash
git diff --check
git add BLEUnlock/PhotoLocationCoordinator.swift \
  BLEUnlock/TelegramNotificationService.swift \
  BLEUnlockTests/PhotoLocationCoordinatorTests.swift \
  BLEUnlockTests/TelegramNotificationServiceTests.swift \
  BLEUnlockTests/TestDoubles.swift BLEUnlock.xcodeproj/project.pbxproj
git commit -m "Attach Mac location to Telegram photos"
```

---

### Task 6: Production wiring, permissions, localization, and verification

**Files:**
- Modify: `BLEUnlock/AppDelegate.swift:33-46`
- Modify: `BLEUnlock/Info.plist`
- Modify: `BLEUnlock/BLEUnlock.entitlements`
- Modify: `BLEUnlock.xcodeproj/project.pbxproj`
- Modify: `BLEUnlock/Base.lproj/Localizable.strings`
- Modify: `BLEUnlock/da.lproj/Localizable.strings`
- Modify: `BLEUnlock/de.lproj/Localizable.strings`
- Modify: `BLEUnlock/ja.lproj/Localizable.strings`
- Modify: `BLEUnlock/nb.lproj/Localizable.strings`
- Modify: `BLEUnlock/sv.lproj/Localizable.strings`
- Modify: `BLEUnlock/tr.lproj/Localizable.strings`
- Modify: `BLEUnlock/zh-Hans.lproj/Localizable.strings`
- Modify: `BLEUnlock/zh-Hant.lproj/Localizable.strings`
- Modify: the matching `InfoPlist.strings` file in each locale above
- Modify: `BLEUnlockTests/LocalizationTests.swift`
- Modify: `BLEUnlockTests/TelegramNotificationServiceTests.swift`

**Interfaces:**
- Consumes: `CoreMacLocationProvider`, `TelegramNotificationService`, and `TelegramMenuController` dependencies from Tasks 1-5.
- Produces: the shipping menu, macOS location permission prompt, complete localized copy, and a verified Release app.

- [ ] **Step 1: Add failing production-wiring and localization tests**

Append these exact values to the existing `telegramKeys` set:

```swift
"telegram_attach_mac_location", "telegram_message_coordinates",
"telegram_message_accuracy", "telegram_message_map",
"telegram_location_unavailable", "telegram_location_error",
"telegram_location_send_error"
```

For every locale, assert `NSLocationUsageDescription` exists and is nonempty in `InfoPlist.strings`. Add a source-wiring regression test:

```swift
func testProductionAppWiresCoreLocationIntoTelegramMenuAndService() throws {
    let source = try String(contentsOf: repository.appendingPathComponent(
        "BLEUnlock/AppDelegate.swift"
    ))
    XCTAssertTrue(source.contains("CoreMacLocationProvider"))
    XCTAssertTrue(source.contains("location: macLocationProvider"))
    XCTAssertTrue(source.contains("locationAuthorization: macLocationProvider"))
}

func testProductionEntitlementsAllowMacLocation() throws {
    let url = repository.appendingPathComponent("BLEUnlock/BLEUnlock.entitlements")
    let values = try XCTUnwrap(
        PropertyListSerialization.propertyList(from: Data(contentsOf: url),
                                               options: [],
                                               format: nil) as? [String: Any]
    )
    XCTAssertEqual(values["com.apple.security.personal-information.location"] as? Bool,
                   true)
}
```

- [ ] **Step 2: Run focused tests and verify RED**

```bash
xcodebuild test -project BLEUnlock.xcodeproj -scheme BLEUnlock \
  -destination 'platform=macOS' -derivedDataPath build/DerivedData \
  -only-testing:BLEUnlockTests/LocalizationTests \
  -only-testing:BLEUnlockTests/TelegramNotificationServiceTests \
  CODE_SIGNING_ALLOWED=NO
```

Expected: failures report missing location strings, missing purpose descriptions, and missing AppDelegate wiring.

- [ ] **Step 3: Wire one production provider to the service and menu**

Update `AppDelegate`:

```swift
let macLocationProvider = CoreMacLocationProvider()

lazy var telegramService: TelegramNotificationHandling = TelegramNotificationService(
    settings: telegramSettings,
    sender: TelegramNotifier(transport: URLSessionTransport()),
    camera: CameraCapture(),
    location: macLocationProvider,
    reporter: RateLimitedFailureReporter()
)

lazy var telegramMenuController = TelegramMenuController(
    settings: telegramSettings,
    service: telegramService,
    dialogs: AppKitTelegramDialogPresenter(),
    locationAuthorization: macLocationProvider
)
```

Add `NSLocationUsageDescription` to the base `Info.plist` with an English
fallback. Add this Boolean to `BLEUnlock/BLEUnlock.entitlements`:

```xml
<key>com.apple.security.personal-information.location</key>
<true/>
```

Set `ENABLE_RESOURCE_ACCESS_LOCATION = YES;` in both BLEUnlock app-target
build configurations in `project.pbxproj`; do not change the Launcher or test
target. Do not request Always authorization or enable background location.

- [ ] **Step 4: Add complete localized UI and permission copy**

Add these exact blocks to each `Localizable.strings`.

Base English:

```text
"telegram_attach_mac_location" = "Attach Mac Location";
"telegram_message_coordinates" = "GPS Coordinates";
"telegram_message_accuracy" = "Location Accuracy";
"telegram_message_map" = "Map";
"telegram_location_unavailable" = "The location at capture time is unavailable.";
"telegram_location_error" = "The Mac location could not be obtained.";
"telegram_location_send_error" = "The photo was sent, but the Telegram map location could not be sent.";
```

Danish:

```text
"telegram_attach_mac_location" = "Vedhæft Mac-placering";
"telegram_message_coordinates" = "GPS-koordinater";
"telegram_message_accuracy" = "Placeringens nøjagtighed";
"telegram_message_map" = "Kort";
"telegram_location_unavailable" = "Placeringen på optagelsestidspunktet kunne ikke hentes.";
"telegram_location_error" = "Mac-computerens placering kunne ikke hentes.";
"telegram_location_send_error" = "Billedet blev sendt, men Telegram-kortplaceringen kunne ikke sendes.";
```

German:

```text
"telegram_attach_mac_location" = "Mac-Standort anhängen";
"telegram_message_coordinates" = "GPS-Koordinaten";
"telegram_message_accuracy" = "Standortgenauigkeit";
"telegram_message_map" = "Karte";
"telegram_location_unavailable" = "Der Standort zum Aufnahmezeitpunkt ist nicht verfügbar.";
"telegram_location_error" = "Der Mac-Standort konnte nicht ermittelt werden.";
"telegram_location_send_error" = "Das Foto wurde gesendet, aber der Telegram-Kartenstandort konnte nicht gesendet werden.";
```

Japanese:

```text
"telegram_attach_mac_location" = "Macの位置情報を添付";
"telegram_message_coordinates" = "GPS座標";
"telegram_message_accuracy" = "位置情報の精度";
"telegram_message_map" = "地図";
"telegram_location_unavailable" = "撮影時の位置情報を取得できませんでした。";
"telegram_location_error" = "Macの位置情報を取得できませんでした。";
"telegram_location_send_error" = "写真は送信されましたが、Telegramの地図位置情報を送信できませんでした。";
```

Norwegian Bokmål:

```text
"telegram_attach_mac_location" = "Legg ved Mac-posisjon";
"telegram_message_coordinates" = "GPS-koordinater";
"telegram_message_accuracy" = "Posisjonsnøyaktighet";
"telegram_message_map" = "Kart";
"telegram_location_unavailable" = "Posisjonen på opptakstidspunktet er ikke tilgjengelig.";
"telegram_location_error" = "Kunne ikke hente Mac-posisjonen.";
"telegram_location_send_error" = "Bildet ble sendt, men kartposisjonen kunne ikke sendes til Telegram.";
```

Swedish:

```text
"telegram_attach_mac_location" = "Bifoga Mac-plats";
"telegram_message_coordinates" = "GPS-koordinater";
"telegram_message_accuracy" = "Platsnoggrannhet";
"telegram_message_map" = "Karta";
"telegram_location_unavailable" = "Platsen vid fotograferingstillfället är inte tillgänglig.";
"telegram_location_error" = "Det gick inte att hämta Mac-datorns plats.";
"telegram_location_send_error" = "Fotot skickades, men kartplatsen kunde inte skickas till Telegram.";
```

Turkish:

```text
"telegram_attach_mac_location" = "Mac Konumunu Ekle";
"telegram_message_coordinates" = "GPS Koordinatları";
"telegram_message_accuracy" = "Konum Doğruluğu";
"telegram_message_map" = "Harita";
"telegram_location_unavailable" = "Fotoğraf çekildiği andaki konum alınamadı.";
"telegram_location_error" = "Mac konumu alınamadı.";
"telegram_location_send_error" = "Fotoğraf gönderildi ancak Telegram harita konumu gönderilemedi.";
```

Simplified Chinese:

```text
"telegram_attach_mac_location" = "附加 Mac 位置";
"telegram_message_coordinates" = "GPS 坐标";
"telegram_message_accuracy" = "定位精度";
"telegram_message_map" = "地图";
"telegram_location_unavailable" = "无法获取拍照时的位置。";
"telegram_location_error" = "无法获取 Mac 位置。";
"telegram_location_send_error" = "照片已发送，但无法发送 Telegram 地图位置。";
```

Traditional Chinese:

```text
"telegram_attach_mac_location" = "附加 Mac 位置";
"telegram_message_coordinates" = "GPS 座標";
"telegram_message_accuracy" = "定位精確度";
"telegram_message_map" = "地圖";
"telegram_location_unavailable" = "無法取得拍照當時的位置。";
"telegram_location_error" = "無法取得 Mac 位置。";
"telegram_location_send_error" = "照片已傳送，但無法傳送 Telegram 地圖位置。";
```

Add these exact purpose descriptions to the matching `InfoPlist.strings`:

```text
// Base
"NSLocationUsageDescription" = "BLEUnlock gets this Mac's location at capture time and attaches the coordinates and map to the Telegram security notification.";
// da
"NSLocationUsageDescription" = "BLEUnlock henter denne Macs placering på optagelsestidspunktet og vedhæfter koordinater og kort til Telegram-sikkerhedsmeddelelsen.";
// de
"NSLocationUsageDescription" = "BLEUnlock ermittelt den Standort dieses Macs zum Aufnahmezeitpunkt und fügt Koordinaten und Karte der Telegram-Sicherheitsmeldung hinzu.";
// ja
"NSLocationUsageDescription" = "BLEUnlockは撮影時のこのMacの位置情報を取得し、座標と地図をTelegramのセキュリティ通知に添付します。";
// nb
"NSLocationUsageDescription" = "BLEUnlock henter posisjonen til denne Macen på opptakstidspunktet og legger ved koordinater og kart i Telegram-sikkerhetsvarslet.";
// sv
"NSLocationUsageDescription" = "BLEUnlock hämtar den här Mac-datorns plats när fotot tas och bifogar koordinater och karta till Telegram-säkerhetsnotisen.";
// tr
"NSLocationUsageDescription" = "BLEUnlock fotoğraf çekildiğinde bu Mac'in konumunu alır ve koordinatlarla haritayı Telegram güvenlik bildirimine ekler.";
// zh-Hans
"NSLocationUsageDescription" = "BLEUnlock 获取这台 Mac 拍照时的位置，并将坐标和地图附加到 Telegram 安全通知。";
```

Traditional Chinese `InfoPlist.strings`:

```text
"NSLocationUsageDescription" = "BLEUnlock 取得這部 Mac 拍照當時的位置，並將座標與地圖附加到 Telegram 安全通知。";
```

- [ ] **Step 5: Validate every strings file and run focused tests**

```bash
find BLEUnlock \( -path '*.lproj/Localizable.strings' -o \
  -path '*.lproj/InfoPlist.strings' \) -print0 | xargs -0 -n1 plutil -lint
xcodebuild test -project BLEUnlock.xcodeproj -scheme BLEUnlock \
  -destination 'platform=macOS' -derivedDataPath build/DerivedData \
  -only-testing:BLEUnlockTests/LocalizationTests \
  -only-testing:BLEUnlockTests/TelegramNotificationServiceTests \
  CODE_SIGNING_ALLOWED=NO
```

Expected: every property-list strings file reports `OK`; both focused suites pass.

- [ ] **Step 6: Run the complete regression suite**

```bash
xcodebuild test -project BLEUnlock.xcodeproj -scheme BLEUnlock \
  -destination 'platform=macOS' -derivedDataPath build/DerivedData \
  CODE_SIGNING_ALLOWED=NO
```

Expected: `** TEST SUCCEEDED **`; all existing camera, Telegram, localization, BLE scan, settings, and Keychain tests plus the new location tests pass.

- [ ] **Step 7: Build Release and inspect the bundle**

```bash
xcodebuild build -project BLEUnlock.xcodeproj -scheme BLEUnlock \
  -configuration Release -derivedDataPath build/DerivedData \
  SYMROOT=build CODE_SIGNING_ALLOWED=NO
plutil -p build/Release/BLEUnlock.app/Contents/Info.plist | rg NSLocationUsageDescription
plutil -p BLEUnlock/BLEUnlock.entitlements | rg personal-information.location
test -f build/Release/BLEUnlock.app/Contents/Resources/zh-Hant.lproj/InfoPlist.strings
```

Expected: `** BUILD SUCCEEDED **`, `build/Release/BLEUnlock.app` exists, the
base purpose key and source entitlement are present, and the Traditional
Chinese purpose resource is bundled.

- [ ] **Step 8: Review privacy and scope mechanically**

```bash
rg -n 'startUpdatingLocation|requestAlwaysAuthorization|allowsBackgroundLocationUpdates' BLEUnlock
rg -n 'latitude|longitude|TelegramLocation' BLEUnlock | rg 'UserDefaults|Keychain|write|print|report'
git diff --check
git status --short
```

Expected: no continuous/background/Always location API appears; no coordinate persistence or logging match appears; diff check is clean; only task-owned files are staged or modified in the isolated worktree.

- [ ] **Step 9: Commit production wiring and localization**

```bash
git add BLEUnlock/AppDelegate.swift BLEUnlock/Info.plist \
  BLEUnlock/BLEUnlock.entitlements BLEUnlock.xcodeproj/project.pbxproj \
  BLEUnlock/*.lproj/Localizable.strings BLEUnlock/*.lproj/InfoPlist.strings \
  BLEUnlockTests/LocalizationTests.swift \
  BLEUnlockTests/TelegramNotificationServiceTests.swift
git commit -m "Wire localized Telegram photo locations"
```

- [ ] **Step 10: Perform the signed hardware smoke test after integration**

Build and install the production-signed app at a fixed path, enable **Attach Mac Location**, and verify:

1. macOS asks for location permission once with the localized BLEUnlock purpose text.
2. A test notification captures the photo immediately, then sends it within five seconds with time, six-decimal coordinates, accuracy, and a working Apple Maps link.
3. Telegram shows a native location message after the photo at the same coordinates.
4. Reset or deny location permission and confirm the photo still arrives with the localized unavailable line and no native map.
5. Disable the setting and confirm another test sends the normal photo without activating Core Location.

Record the macOS version, signed app path, and observed Telegram results in the implementation handoff; do not commit credentials, coordinates, screenshots, or TCC database data.
