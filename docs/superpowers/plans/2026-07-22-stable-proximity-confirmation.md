# Stable Proximity Confirmation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Confirm that a monitored phone is genuinely close using two qualifying RSSI samples out of three, then unlock exactly once within 1–2 seconds in normal mode.

**Architecture:** Add a pure `ProximityConfirmation` state machine that evaluates timestamped RSSI samples, plus a `ProximityMonitor` that owns the 1.5-second timeout and temporary 0.4-second burst timer through an injectable scheduler. `BLE` remains the CoreBluetooth owner and forwards samples to the monitor; the existing away/lost, wake, password, Telegram, camera, and location paths remain unchanged.

**Tech Stack:** Swift 5, CoreBluetooth, Foundation `Timer`/`RunLoop`, XCTest, Xcode 26.

## Global Constraints

- Normal-mode close confirmation must finish within 1–2 seconds after the first candidate sample.
- The candidate threshold is exactly 5 dB below the configured unlock threshold.
- The confirmation window is exactly 1.5 seconds.
- Collect at most three fresh samples and confirm when at least two meet the configured unlock threshold.
- Burst RSSI requests run approximately every 0.4 seconds and only while a normal-mode confirmation is active.
- Passive mode uses duplicate advertisements only and must not connect or start burst RSSI requests.
- A single qualifying RSSI spike must never confirm proximity.
- Existing moving-average away detection and lock delay remain unchanged.
- Do not change or migrate the user's configured unlock or lock RSSI values; use `-55 dBm` only for the final manual validation.
- Do not change Telegram, photo capture, location, password entry, or screen wake behaviour.
- Preserve the untracked `.codegraph/` directory and stage only task-owned files.

## File Map

- Create `BLEUnlock/ProximityConfirmation.swift`: pure timestamped three-sample/two-success decision state machine.
- Create `BLEUnlock/ProximityMonitor.swift`: timeout and burst scheduling around the pure state machine; no CoreBluetooth dependency.
- Modify `BLEUnlock/BLE.swift`: feed monitored RSSI samples into `ProximityMonitor`, request fresh RSSI during bursts, confirm presence once, and reset lifecycle state.
- Create `BLEUnlockTests/ProximityConfirmationTests.swift`: deterministic state-machine boundary tests.
- Create `BLEUnlockTests/ProximityMonitorTests.swift`: scheduler, timeout, burst, reset, passive-mode, and callback tests.
- Modify `BLEUnlock.xcodeproj/project.pbxproj`: register the two production files and two test files without regenerating the project.

---

### Task 1: Implement the pure three-sample confirmation state machine

**Files:**
- Create: `BLEUnlock/ProximityConfirmation.swift`
- Create: `BLEUnlockTests/ProximityConfirmationTests.swift`
- Modify: `BLEUnlock.xcodeproj/project.pbxproj`

**Interfaces:**
- Consumes: timestamped integer RSSI values and the current integer unlock threshold.
- Produces: `ProximityConfirmationDecision`, `ProximityConfirmationRejection`, and `ProximityConfirmation.record(rssi:at:unlockThreshold:)`, `expire(at:)`, and `reset()`.

- [ ] **Step 1: Register and write the failing state-machine tests**

Create `BLEUnlockTests/ProximityConfirmationTests.swift`:

```swift
import Foundation
import XCTest
@testable import BLEUnlock

final class ProximityConfirmationTests: XCTestCase {
    func testIgnoresSamplesBelowCandidateThreshold() {
        var confirmation = ProximityConfirmation()

        let decision = confirmation.record(rssi: -61,
                                           at: 0,
                                           unlockThreshold: -55)

        XCTAssertEqual(decision, .ignored)
        XCTAssertFalse(confirmation.isConfirming)
    }

    func testCandidateBoundaryStartsConfirmationWithoutQualifying() {
        var confirmation = ProximityConfirmation()

        let decision = confirmation.record(rssi: -60,
                                           at: 0,
                                           unlockThreshold: -55)

        XCTAssertEqual(decision, .started(sampleCount: 1,
                                          qualifyingCount: 0))
        XCTAssertTrue(confirmation.isConfirming)
    }

    func testTwoQualifyingSamplesOutOfThreeConfirm() {
        var confirmation = ProximityConfirmation()
        XCTAssertEqual(confirmation.record(rssi: -58, at: 0,
                                           unlockThreshold: -55),
                       .started(sampleCount: 1, qualifyingCount: 0))
        XCTAssertEqual(confirmation.record(rssi: -54, at: 0.4,
                                           unlockThreshold: -55),
                       .collecting(sampleCount: 2, qualifyingCount: 1))

        let decision = confirmation.record(rssi: -55, at: 0.8,
                                           unlockThreshold: -55)

        XCTAssertEqual(decision, .confirmed(sampleCount: 3,
                                            elapsed: 0.8))
        XCTAssertFalse(confirmation.isConfirming)
    }

    func testOneQualifyingSampleOutOfThreeRejects() {
        var confirmation = ProximityConfirmation()
        _ = confirmation.record(rssi: -60, at: 0,
                                unlockThreshold: -55)
        _ = confirmation.record(rssi: -54, at: 0.4,
                                unlockThreshold: -55)

        let decision = confirmation.record(rssi: -57, at: 0.8,
                                           unlockThreshold: -55)

        XCTAssertEqual(decision,
                       .rejected(reason: .sampleLimit,
                                 sampleCount: 3,
                                 elapsed: 0.8))
        XCTAssertFalse(confirmation.isConfirming)
    }

    func testStrongSpikeFollowedByTwoWeakSamplesRejects() {
        var confirmation = ProximityConfirmation()
        _ = confirmation.record(rssi: -35, at: 0,
                                unlockThreshold: -55)
        _ = confirmation.record(rssi: -58, at: 0.4,
                                unlockThreshold: -55)

        let decision = confirmation.record(rssi: -59, at: 0.8,
                                           unlockThreshold: -55)

        XCTAssertEqual(decision,
                       .rejected(reason: .sampleLimit,
                                 sampleCount: 3,
                                 elapsed: 0.8))
    }

    func testSingleStrongSpikeTimesOutWithoutConfirming() {
        var confirmation = ProximityConfirmation()
        _ = confirmation.record(rssi: -40, at: 0,
                                unlockThreshold: -55)

        let decision = confirmation.expire(at: 1.5)

        XCTAssertEqual(decision,
                       .rejected(reason: .timeout,
                                 sampleCount: 1,
                                 elapsed: 1.5))
        XCTAssertFalse(confirmation.isConfirming)
    }

    func testSampleAtTimeoutBoundaryIsRejectedAsTimeout() {
        var confirmation = ProximityConfirmation()
        _ = confirmation.record(rssi: -54, at: 0,
                                unlockThreshold: -55)

        let decision = confirmation.record(rssi: -54, at: 1.5,
                                           unlockThreshold: -55)

        XCTAssertEqual(decision,
                       .rejected(reason: .timeout,
                                 sampleCount: 1,
                                 elapsed: 1.5))
    }

    func testResetClearsSamplesBeforeNextAttempt() {
        var confirmation = ProximityConfirmation()
        _ = confirmation.record(rssi: -54, at: 0,
                                unlockThreshold: -55)
        confirmation.reset()

        let decision = confirmation.record(rssi: -54, at: 0.4,
                                           unlockThreshold: -55)

        XCTAssertEqual(decision, .started(sampleCount: 1,
                                          qualifyingCount: 1))
    }

    func testChangingThresholdStartsFreshAttempt() {
        var confirmation = ProximityConfirmation()
        _ = confirmation.record(rssi: -54, at: 0,
                                unlockThreshold: -55)

        let decision = confirmation.record(rssi: -59, at: 0.4,
                                           unlockThreshold: -60)

        XCTAssertEqual(decision, .started(sampleCount: 1,
                                          qualifyingCount: 1))
    }
}
```

Register only the test file first so RED is caused by missing production types. Add these exact entries to `BLEUnlock.xcodeproj/project.pbxproj`:

```text
7E10004E3000000000000001 /* ProximityConfirmationTests.swift in Sources */ = {isa = PBXBuildFile; fileRef = 7E10004F3000000000000001 /* ProximityConfirmationTests.swift */; };
7E10004F3000000000000001 /* ProximityConfirmationTests.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = ProximityConfirmationTests.swift; sourceTree = "<group>"; };
```

Add the file reference to the `BLEUnlockTests` group and the build file to the `BLEUnlockTests` Sources phase.

- [ ] **Step 2: Run the focused test target and verify RED**

Run:

```bash
xcodebuild test -project BLEUnlock.xcodeproj -scheme BLEUnlock \
  -destination 'platform=macOS' -derivedDataPath build/DerivedData \
  -only-testing:BLEUnlockTests/ProximityConfirmationTests \
  CODE_SIGNING_ALLOWED=NO
```

Expected: build fails with `cannot find 'ProximityConfirmation' in scope`.

- [ ] **Step 3: Implement the minimal pure state machine**

Create `BLEUnlock/ProximityConfirmation.swift`:

```swift
import Foundation

enum ProximityConfirmationRejection: Equatable {
    case sampleLimit
    case timeout
}

enum ProximityConfirmationDecision: Equatable {
    case ignored
    case started(sampleCount: Int, qualifyingCount: Int)
    case collecting(sampleCount: Int, qualifyingCount: Int)
    case confirmed(sampleCount: Int, elapsed: TimeInterval)
    case rejected(reason: ProximityConfirmationRejection,
                  sampleCount: Int,
                  elapsed: TimeInterval)
}

struct ProximityConfirmation {
    let candidateMargin = 5
    let timeout: TimeInterval = 1.5
    let maximumSamples = 3
    let requiredQualifyingSamples = 2

    private var startedAt: TimeInterval?
    private var activeThreshold: Int?
    private var samples: [Int] = []

    var isConfirming: Bool { startedAt != nil }

    mutating func record(rssi: Int,
                         at timestamp: TimeInterval,
                         unlockThreshold: Int) -> ProximityConfirmationDecision {
        if let activeThreshold = activeThreshold,
           activeThreshold != unlockThreshold {
            reset()
        }

        if let startedAt = startedAt,
           timestamp - startedAt >= timeout {
            let sampleCount = samples.count
            let elapsed = timestamp - startedAt
            reset()
            return .rejected(reason: .timeout,
                             sampleCount: sampleCount,
                             elapsed: elapsed)
        }

        if startedAt == nil {
            guard rssi >= unlockThreshold - candidateMargin else {
                return .ignored
            }
            startedAt = timestamp
            activeThreshold = unlockThreshold
        }

        samples.append(rssi)
        let qualifyingCount = samples.filter { $0 >= unlockThreshold }.count
        let sampleCount = samples.count
        let elapsed = timestamp - (startedAt ?? timestamp)

        if qualifyingCount >= requiredQualifyingSamples {
            reset()
            return .confirmed(sampleCount: sampleCount, elapsed: elapsed)
        }
        if sampleCount >= maximumSamples {
            reset()
            return .rejected(reason: .sampleLimit,
                             sampleCount: sampleCount,
                             elapsed: elapsed)
        }
        return sampleCount == 1
            ? .started(sampleCount: sampleCount,
                       qualifyingCount: qualifyingCount)
            : .collecting(sampleCount: sampleCount,
                          qualifyingCount: qualifyingCount)
    }

    mutating func expire(at timestamp: TimeInterval) -> ProximityConfirmationDecision {
        guard let startedAt = startedAt,
              timestamp - startedAt >= timeout else {
            return .ignored
        }
        let sampleCount = samples.count
        let elapsed = timestamp - startedAt
        reset()
        return .rejected(reason: .timeout,
                         sampleCount: sampleCount,
                         elapsed: elapsed)
    }

    mutating func reset() {
        startedAt = nil
        activeThreshold = nil
        samples.removeAll()
    }
}
```

Register the production file with these exact project entries:

```text
7E10004C3000000000000001 /* ProximityConfirmation.swift in Sources */ = {isa = PBXBuildFile; fileRef = 7E10004D3000000000000001 /* ProximityConfirmation.swift */; };
7E10004D3000000000000001 /* ProximityConfirmation.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = ProximityConfirmation.swift; sourceTree = "<group>"; };
```

Add the file reference to the `BLEUnlock` group and the build file to the application Sources phase.

- [ ] **Step 4: Run focused tests and verify GREEN**

Run the command from Step 2 again.

Expected: all nine `ProximityConfirmationTests` pass with zero failures.

- [ ] **Step 5: Commit the pure decision engine**

```bash
git diff --check
git add BLEUnlock/ProximityConfirmation.swift \
  BLEUnlockTests/ProximityConfirmationTests.swift \
  BLEUnlock.xcodeproj/project.pbxproj
git commit -m "Add stable proximity confirmation engine"
```

---

### Task 2: Add deterministic timeout and temporary burst orchestration

**Files:**
- Create: `BLEUnlock/ProximityMonitor.swift`
- Create: `BLEUnlockTests/ProximityMonitorTests.swift`
- Modify: `BLEUnlock.xcodeproj/project.pbxproj`

**Interfaces:**
- Consumes: `ProximityConfirmation.record(rssi:at:unlockThreshold:)`, `expire(at:)`, and `reset()`.
- Produces: `ProximityScheduling.schedule(after:repeats:_:)`, `RunLoopProximityScheduler`, and `ProximityMonitor.receive(rssi:unlockThreshold:allowsBurst:)`/`reset(reason:)`.

- [ ] **Step 1: Register and write failing monitor tests with a manual scheduler**

Create `BLEUnlockTests/ProximityMonitorTests.swift`:

```swift
import Foundation
import XCTest
@testable import BLEUnlock

final class ProximityMonitorTests: XCTestCase {
    func testCandidateStartsTimeoutAndNormalModeBurst() {
        let fixture = Fixture()

        fixture.monitor.receive(rssi: -60,
                                unlockThreshold: -55,
                                allowsBurst: true)

        XCTAssertEqual(fixture.scheduler.entries.map(\.interval), [1.5, 0.4])
        XCTAssertEqual(fixture.scheduler.entries.map(\.repeats), [false, true])
    }

    func testPassiveModeStartsTimeoutWithoutBurstRequests() {
        let fixture = Fixture()

        fixture.monitor.receive(rssi: -60,
                                unlockThreshold: -55,
                                allowsBurst: false)

        XCTAssertEqual(fixture.scheduler.entries.map(\.interval), [1.5])
        XCTAssertEqual(fixture.sampleRequests, 0)
    }

    func testBurstTickRequestsFreshRSSI() throws {
        let fixture = Fixture()
        fixture.monitor.receive(rssi: -60,
                                unlockThreshold: -55,
                                allowsBurst: true)

        try XCTUnwrap(fixture.scheduler.entries.first { $0.repeats }).action()

        XCTAssertEqual(fixture.sampleRequests, 1)
    }

    func testSecondQualifyingSampleConfirmsOnceAndCancelsTimers() {
        let fixture = Fixture()
        fixture.monitor.receive(rssi: -54,
                                unlockThreshold: -55,
                                allowsBurst: true)
        fixture.now = 0.4

        fixture.monitor.receive(rssi: -55,
                                unlockThreshold: -55,
                                allowsBurst: true)

        XCTAssertEqual(fixture.confirmations, 1)
        XCTAssertTrue(fixture.scheduler.entries.allSatisfy(\.cancellation.isCancelled))
    }

    func testTimeoutRejectsAndStopsBurst() throws {
        let fixture = Fixture()
        fixture.monitor.receive(rssi: -54,
                                unlockThreshold: -55,
                                allowsBurst: true)
        fixture.now = 1.5

        try XCTUnwrap(fixture.scheduler.entries.first { !$0.repeats }).action()

        XCTAssertEqual(fixture.confirmations, 0)
        XCTAssertTrue(fixture.scheduler.entries.allSatisfy(\.cancellation.isCancelled))
        XCTAssertTrue(fixture.messages.contains { $0.contains("timeout") })
    }

    func testResetCancelsAttemptAndPreventsStaleTimeoutConfirmation() throws {
        let fixture = Fixture()
        fixture.monitor.receive(rssi: -54,
                                unlockThreshold: -55,
                                allowsBurst: true)
        let timeout = try XCTUnwrap(fixture.scheduler.entries.first { !$0.repeats })

        fixture.monitor.reset(reason: "device changed")
        fixture.now = 1.5
        timeout.action()

        XCTAssertEqual(fixture.confirmations, 0)
        XCTAssertTrue(timeout.cancellation.isCancelled)
    }
}

private final class Fixture {
    var now: TimeInterval = 0
    var sampleRequests = 0
    var confirmations = 0
    var messages: [String] = []
    let scheduler = ManualProximityScheduler()
    lazy var monitor = ProximityMonitor(
        scheduler: scheduler,
        now: { self.now },
        requestSample: { self.sampleRequests += 1 },
        onConfirmed: { self.confirmations += 1 },
        logger: { self.messages.append($0) }
    )
}

private final class ManualProximityCancellation: ProximityScheduledCancellation {
    private(set) var isCancelled = false
    func cancel() { isCancelled = true }
}

private final class ManualProximityScheduler: ProximityScheduling {
    struct Entry {
        let interval: TimeInterval
        let repeats: Bool
        let cancellation: ManualProximityCancellation
        let action: () -> Void
    }

    private(set) var entries: [Entry] = []

    func schedule(after interval: TimeInterval,
                  repeats: Bool,
                  _ action: @escaping () -> Void) -> ProximityScheduledCancellation {
        let cancellation = ManualProximityCancellation()
        entries.append(Entry(interval: interval,
                             repeats: repeats,
                             cancellation: cancellation,
                             action: action))
        return cancellation
    }
}
```

Register only the test file first:

```text
7E1000523000000000000001 /* ProximityMonitorTests.swift in Sources */ = {isa = PBXBuildFile; fileRef = 7E1000533000000000000001 /* ProximityMonitorTests.swift */; };
7E1000533000000000000001 /* ProximityMonitorTests.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = ProximityMonitorTests.swift; sourceTree = "<group>"; };
```

Add the reference to the test group and build file to the test Sources phase.

- [ ] **Step 2: Run monitor tests and verify RED**

Run:

```bash
xcodebuild test -project BLEUnlock.xcodeproj -scheme BLEUnlock \
  -destination 'platform=macOS' -derivedDataPath build/DerivedData \
  -only-testing:BLEUnlockTests/ProximityMonitorTests \
  CODE_SIGNING_ALLOWED=NO
```

Expected: build fails with missing `ProximityMonitor`, `ProximityScheduling`, and `ProximityScheduledCancellation` types.

- [ ] **Step 3: Implement the scheduler and monitor**

Create `BLEUnlock/ProximityMonitor.swift`:

```swift
import Foundation

protocol ProximityScheduledCancellation: AnyObject {
    func cancel()
}

protocol ProximityScheduling {
    @discardableResult
    func schedule(after interval: TimeInterval,
                  repeats: Bool,
                  _ action: @escaping () -> Void) -> ProximityScheduledCancellation
}

private final class TimerProximityCancellation: ProximityScheduledCancellation {
    private let timer: Timer
    init(timer: Timer) { self.timer = timer }
    func cancel() { timer.invalidate() }
}

final class RunLoopProximityScheduler: ProximityScheduling {
    func schedule(after interval: TimeInterval,
                  repeats: Bool,
                  _ action: @escaping () -> Void) -> ProximityScheduledCancellation {
        let timer = Timer(timeInterval: interval, repeats: repeats) { _ in action() }
        RunLoop.main.add(timer, forMode: .common)
        return TimerProximityCancellation(timer: timer)
    }
}

final class ProximityMonitor {
    private let scheduler: ProximityScheduling
    private let now: () -> TimeInterval
    private let requestSample: () -> Void
    private let onConfirmed: () -> Void
    private let logger: (String) -> Void
    private var confirmation = ProximityConfirmation()
    private var timeoutCancellation: ProximityScheduledCancellation?
    private var burstCancellation: ProximityScheduledCancellation?

    init(scheduler: ProximityScheduling = RunLoopProximityScheduler(),
         now: @escaping () -> TimeInterval = { Date().timeIntervalSince1970 },
         requestSample: @escaping () -> Void,
         onConfirmed: @escaping () -> Void,
         logger: @escaping (String) -> Void = { print($0) }) {
        self.scheduler = scheduler
        self.now = now
        self.requestSample = requestSample
        self.onConfirmed = onConfirmed
        self.logger = logger
    }

    func receive(rssi: Int, unlockThreshold: Int, allowsBurst: Bool) {
        handle(confirmation.record(rssi: rssi,
                                   at: now(),
                                   unlockThreshold: unlockThreshold),
               allowsBurst: allowsBurst,
               rssi: rssi)
    }

    func reset(reason: String) {
        let wasConfirming = confirmation.isConfirming
        confirmation.reset()
        stopTimers()
        if wasConfirming {
            logger("Proximity confirmation reset: \(reason)")
        }
    }

    private func handle(_ decision: ProximityConfirmationDecision,
                        allowsBurst: Bool,
                        rssi: Int?) {
        switch decision {
        case .ignored:
            return
        case .started(let sampleCount, let qualifyingCount):
            logger("Proximity confirmation started: sample \(sampleCount), RSSI \(rssi ?? 0), qualifying \(qualifyingCount)")
            startTimers(allowsBurst: allowsBurst)
        case .collecting(let sampleCount, let qualifyingCount):
            logger("Proximity confirmation sample \(sampleCount), RSSI \(rssi ?? 0), qualifying \(qualifyingCount)")
        case .confirmed(let sampleCount, let elapsed):
            stopTimers()
            logger("Proximity confirmed with \(sampleCount) samples in \(elapsed)s")
            onConfirmed()
        case .rejected(let reason, let sampleCount, let elapsed):
            stopTimers()
            logger("Proximity confirmation rejected: \(reason), \(sampleCount) samples in \(elapsed)s")
        }
    }

    private func startTimers(allowsBurst: Bool) {
        stopTimers()
        timeoutCancellation = scheduler.schedule(after: confirmation.timeout,
                                                   repeats: false) { [weak self] in
            guard let self = self else { return }
            self.handle(self.confirmation.expire(at: self.now()),
                        allowsBurst: false,
                        rssi: nil)
        }
        if allowsBurst {
            burstCancellation = scheduler.schedule(after: 0.4,
                                                    repeats: true) { [weak self] in
                self?.requestSample()
            }
            logger("Proximity burst sampling started")
        }
    }

    private func stopTimers() {
        timeoutCancellation?.cancel()
        timeoutCancellation = nil
        if burstCancellation != nil {
            logger("Proximity burst sampling stopped")
        }
        burstCancellation?.cancel()
        burstCancellation = nil
    }
}
```

Register the production file:

```text
7E1000503000000000000001 /* ProximityMonitor.swift in Sources */ = {isa = PBXBuildFile; fileRef = 7E1000513000000000000001 /* ProximityMonitor.swift */; };
7E1000513000000000000001 /* ProximityMonitor.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = ProximityMonitor.swift; sourceTree = "<group>"; };
```

Add the reference to the application group and build file to the application Sources phase.

- [ ] **Step 4: Run monitor and engine tests and verify GREEN**

```bash
xcodebuild test -project BLEUnlock.xcodeproj -scheme BLEUnlock \
  -destination 'platform=macOS' -derivedDataPath build/DerivedData \
  -only-testing:BLEUnlockTests/ProximityConfirmationTests \
  -only-testing:BLEUnlockTests/ProximityMonitorTests \
  CODE_SIGNING_ALLOWED=NO
```

Expected: all proximity engine and monitor tests pass with zero failures.

- [ ] **Step 5: Commit scheduling orchestration**

```bash
git diff --check
git add BLEUnlock/ProximityMonitor.swift \
  BLEUnlockTests/ProximityMonitorTests.swift \
  BLEUnlock.xcodeproj/project.pbxproj
git commit -m "Add burst sampling for proximity confirmation"
```

---

### Task 3: Integrate stable confirmation into CoreBluetooth monitoring

**Files:**
- Modify: `BLEUnlock/BLE.swift:146-292`
- Modify: `BLEUnlock/BLE.swift:308-435`
- Test: `BLEUnlockTests/ProximityMonitorTests.swift`

**Interfaces:**
- Consumes: `ProximityMonitor.receive(rssi:unlockThreshold:allowsBurst:)` and `reset(reason:)`.
- Produces: the existing `BLEDelegate.updatePresence(presence:reason:)` call with `presence == true` and reason `close`, emitted only after confirmation.

- [ ] **Step 1: Add a failing regression test for identical decisions with unrelated photo state**

Add to `ProximityMonitorTests`:

```swift
func testUnrelatedPhotoSettingDoesNotChangeConfirmationSequence() {
    func run(photoEnabled: Bool) -> Int {
        let defaults = UserDefaults.standard
        let key = "telegram.takePhotoOnIntruded"
        let previous = defaults.object(forKey: key)
        defer {
            if let previous = previous {
                defaults.set(previous, forKey: key)
            } else {
                defaults.removeObject(forKey: key)
            }
        }
        defaults.set(photoEnabled, forKey: key)

        let fixture = Fixture()
        fixture.monitor.receive(rssi: -54,
                                unlockThreshold: -55,
                                allowsBurst: true)
        fixture.now = 0.4
        fixture.monitor.receive(rssi: -55,
                                unlockThreshold: -55,
                                allowsBurst: true)
        return fixture.confirmations
    }

    XCTAssertEqual(run(photoEnabled: false), 1)
    XCTAssertEqual(run(photoEnabled: true), 1)
}
```

This documents the intentional interface boundary: the proximity path accepts no Telegram or photo setting.

- [ ] **Step 2: Run the proximity tests before integration**

Run the focused command from Task 2, Step 4.

Expected: all tests, including the photo-independence regression, pass. This is a characterization test rather than a RED test because it protects the already-approved subsystem boundary before `BLE.swift` is changed.

- [ ] **Step 3: Construct the monitor inside `BLE`**

Add this lazy property after the existing timer properties:

```swift
private lazy var proximityMonitor = ProximityMonitor(
    requestSample: { [weak self] in
        self?.requestBurstRSSI()
    },
    onConfirmed: { [weak self] in
        self?.confirmMonitoredDeviceClose()
    }
)
```

Add these helpers before `updateMonitoredPeripheral(_:)`:

```swift
private func requestBurstRSSI() {
    guard !passiveMode, let peripheral = monitoredPeripheral else { return }
    if peripheral.state == .connected {
        peripheral.readRSSI()
    } else {
        connectMonitoredPeripheral()
    }
}

private func confirmMonitoredDeviceClose() {
    guard !presence else { return }
    print("Device is close")
    presence = true
    delegate?.updatePresence(presence: true, reason: "close")
    latestRSSIs.removeAll()
}
```

- [ ] **Step 4: Replace single-sample close detection**

Replace the raw one-sample block at the start of `updateMonitoredPeripheral(_:)` with:

```swift
if !presence {
    let effectiveUnlockRSSI = unlockRSSI == UNLOCK_DISABLED
        ? lockRSSI
        : unlockRSSI
    proximityMonitor.receive(rssi: rssi,
                             unlockThreshold: effectiveUnlockRSSI,
                             allowsBurst: !passiveMode)
}
```

Keep the existing moving-average calculation, RSSI UI update, away timer, and signal timer below it unchanged.

- [ ] **Step 5: Reset confirmation at every monitoring lifecycle boundary**

Add `proximityMonitor.reset(reason:)` at these exact boundaries:

```swift
func setPassiveMode(_ mode: Bool) {
    proximityMonitor.reset(reason: "passive mode changed")
    // existing body follows
}

func startMonitor(uuid: UUID) {
    proximityMonitor.reset(reason: "monitored device changed")
    // existing body follows
}
```

In the signal timeout closure, reset before publishing `lost`:

```swift
self.proximityMonitor.reset(reason: "signal lost")
if self.presence {
    self.presence = false
    self.delegate?.updatePresence(presence: false, reason: "lost")
}
```

In `.poweredOff`, reset before clearing presence:

```swift
proximityMonitor.reset(reason: "Bluetooth powered off")
presence = false
```

In the away timer closure, reset before setting `presence = false`:

```swift
self.proximityMonitor.reset(reason: "device away")
self.presence = false
self.delegate?.updatePresence(presence: false, reason: "away")
```

Do not add a reset to `stopScanning()`: that method closes the temporary device-list scan and is not a monitoring lifecycle boundary.

- [ ] **Step 6: Run focused proximity tests and the existing BLE scan tests**

```bash
xcodebuild test -project BLEUnlock.xcodeproj -scheme BLEUnlock \
  -destination 'platform=macOS' -derivedDataPath build/DerivedData \
  -only-testing:BLEUnlockTests/ProximityConfirmationTests \
  -only-testing:BLEUnlockTests/ProximityMonitorTests \
  -only-testing:BLEUnlockTests/BLEScanTests \
  CODE_SIGNING_ALLOWED=NO
```

Expected: all selected tests pass and `BLE.swift` compiles without changing its public delegate interface.

- [ ] **Step 7: Run the complete regression suite**

```bash
xcodebuild test -project BLEUnlock.xcodeproj -scheme BLEUnlock \
  -destination 'platform=macOS' -derivedDataPath build/DerivedData \
  CODE_SIGNING_ALLOWED=NO
```

Expected: all tests pass, including Telegram, camera, location, localization, keychain, notification, and BLE scan tests.

- [ ] **Step 8: Build the unsigned Release product in the project directory**

```bash
xcodebuild build -project BLEUnlock.xcodeproj -scheme BLEUnlock \
  -configuration Release -derivedDataPath build/DerivedData \
  SYMROOT=build CODE_SIGNING_ALLOWED=NO
```

Expected: `** BUILD SUCCEEDED **` and `build/Release/BLEUnlock.app` exists.

- [ ] **Step 9: Perform the manual normal-mode acceptance check**

Use a fixed signed copy of the app, leave passive mode off, set unlock RSSI to `-55 dBm`, and leave lock RSSI at `-70 dBm`. Move the monitored phone from clearly away to approximately 0.5–1 metre from the Mac.

Expected diagnostic sequence:

```text
Proximity confirmation started: ...
Proximity burst sampling started
Proximity confirmation sample ...
Proximity burst sampling stopped
Proximity confirmed with 2 samples in ...s
Device is close
```

Expected behaviour: exactly one unlock occurs within 1–2 seconds after the candidate begins. Repeat with one isolated strong sample followed by weak samples; no unlock should occur.

- [ ] **Step 10: Commit BLE integration only**

```bash
git diff --check
git status --short
git add BLEUnlock/BLE.swift BLEUnlockTests/ProximityMonitorTests.swift
git commit -m "Confirm proximity before automatic unlock"
```

Confirm that `.codegraph/` remains untracked and is not included in any commit.
