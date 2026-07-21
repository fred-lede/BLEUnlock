# Camera Warm-Up Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Delay the first AVFoundation photo request by one second so automatic exposure and white balance can stabilize before a Telegram snapshot.

**Architecture:** Add a small `CameraWarmup` scheduling unit that delays an action and checks the existing `PhotoSessionLifecycle` before executing it. `AVPhotoSession` will use a scheduler backed by its existing serial camera queue, preserving cancellation, teardown, and the outer ten-second timeout.

**Tech Stack:** Swift 5, AVFoundation, Grand Central Dispatch, XCTest, Xcode 26.

## Global Constraints

- Use a fixed one-second warm-up interval.
- Keep the existing ten-second end-to-end capture timeout unchanged.
- A capture cancelled during warm-up must not request a photo.
- Do not change authorization, Telegram text fallback, file cleanup, localization, or add a user setting.
- Preserve the user's unrelated Xcode project, scheme, and `.codegraph` working-tree changes.

---

### Task 1: Delay the AVFoundation photo request

**Files:**
- Modify: `BLEUnlock/CameraCapture.swift:61-205`
- Modify: `BLEUnlock/CameraCapture.swift:408-466`
- Test: `BLEUnlockTests/CameraCaptureTests.swift:150-180`

**Interfaces:**
- Consumes: `CameraScheduling.schedule(after:_:)`, `PhotoSessionLifecycle.performIfActive(_:)`, and `DispatchCameraScheduler.init(queue:)`.
- Produces: `CameraWarmup.init(scheduler:interval:)` and `CameraWarmup.schedule(lifecycle:_:) -> ScheduledCancellation`.

- [ ] **Step 1: Write failing warm-up timing and cancellation tests**

Add these methods to `CameraCaptureTests`:

```swift
func testCameraWarmupWaitsOneSecondBeforeCaptureAction() throws {
    let lifecycle = PhotoSessionLifecycle()
    XCTAssertTrue(lifecycle.prepare { _ in })
    var captureActions = 0
    let warmup = CameraWarmup(scheduler: scheduler, interval: 1)

    warmup.schedule(lifecycle: lifecycle) {
        captureActions += 1
    }

    XCTAssertEqual(captureActions, 0)
    XCTAssertEqual(scheduler.scheduledIntervals, [1])

    try XCTUnwrap(scheduler.blocks.first)()

    XCTAssertEqual(captureActions, 1)
}

func testCameraWarmupSkipsCaptureActionAfterCancellation() throws {
    let lifecycle = PhotoSessionLifecycle()
    XCTAssertTrue(lifecycle.prepare { _ in })
    var captureActions = 0
    let warmup = CameraWarmup(scheduler: scheduler, interval: 1)

    warmup.schedule(lifecycle: lifecycle) {
        captureActions += 1
    }
    lifecycle.cancel()

    try XCTUnwrap(scheduler.blocks.first)()

    XCTAssertEqual(captureActions, 0)
}
```

- [ ] **Step 2: Run the focused tests and verify RED**

Run:

```bash
xcodebuild test -project BLEUnlock.xcodeproj -scheme BLEUnlock \
  -destination 'platform=macOS' -derivedDataPath build/DerivedData \
  -only-testing:BLEUnlockTests/CameraCaptureTests/testCameraWarmupWaitsOneSecondBeforeCaptureAction \
  -only-testing:BLEUnlockTests/CameraCaptureTests/testCameraWarmupSkipsCaptureActionAfterCancellation \
  CODE_SIGNING_ALLOWED=NO
```

Expected: build fails with `cannot find 'CameraWarmup' in scope`, proving the new behavior does not yet exist.

- [ ] **Step 3: Implement the minimal lifecycle-aware warm-up unit**

Add after `PhotoSessionLifecycle`:

```swift
struct CameraWarmup {
    let scheduler: CameraScheduling
    let interval: TimeInterval

    @discardableResult
    func schedule(lifecycle: PhotoSessionLifecycle,
                  _ action: @escaping () -> Void) -> ScheduledCancellation {
        scheduler.schedule(after: interval) {
            _ = lifecycle.performIfActive(action)
        }
    }
}
```

- [ ] **Step 4: Wire the warm-up to the serial AVFoundation queue**

Change `AVPhotoSession` construction so the queue and warm-up scheduler share the same serial queue:

```swift
private let queue: DispatchQueue
private let warmup: CameraWarmup

private init(session: AVCaptureSession,
             output: AVCapturePhotoOutput,
             queue: DispatchQueue = DispatchQueue(
                label: "jp.sone.BLEUnlock.camera-capture"
             ),
             warmupScheduler: CameraScheduling? = nil,
             warmupInterval: TimeInterval = 1) {
    self.session = session
    self.output = output
    self.queue = queue
    self.warmup = CameraWarmup(
        scheduler: warmupScheduler ?? DispatchCameraScheduler(queue: queue),
        interval: warmupInterval
    )
}
```

In `captureJPEG`, keep `session.startRunning()` on `queue`, then replace the immediate completion/delegate/photo block with:

```swift
warmup.schedule(lifecycle: lifecycle) { [output, lifecycle] in
    guard let completion = lifecycle.takePreparedCompletion() else { return }
    let proxy = AVPhotoCaptureDelegateProxy(completion: completion) { [weak lifecycle] proxy in
        lifecycle?.didFinishCallback(for: proxy)
    }
    guard lifecycle.install(delegate: proxy) else {
        proxy.abandon()
        return
    }
    guard lifecycle.performIfActive({
        output.capturePhoto(with: AVCapturePhotoSettings(), delegate: proxy)
    }) else {
        proxy.abandon()
        lifecycle.didFinishCallback(for: proxy)
        return
    }
}
```

- [ ] **Step 5: Run focused tests and verify GREEN**

Run the command from Step 2 again.

Expected: both selected tests pass with zero failures.

- [ ] **Step 6: Run the complete regression suite**

Run:

```bash
xcodebuild test -project BLEUnlock.xcodeproj -scheme BLEUnlock \
  -destination 'platform=macOS' -derivedDataPath build/DerivedData \
  CODE_SIGNING_ALLOWED=NO
```

Expected: all tests pass, including the existing timeout, cancellation, delegate-retention, Telegram fallback, localization, and BLE scan tests.

- [ ] **Step 7: Build Release**

Run:

```bash
xcodebuild build -project BLEUnlock.xcodeproj -scheme BLEUnlock \
  -configuration Release -derivedDataPath build/DerivedData \
  SYMROOT=build CODE_SIGNING_ALLOWED=NO
```

Expected: `** BUILD SUCCEEDED **` and `build/Release/BLEUnlock.app` exists.

- [ ] **Step 8: Commit only the warm-up implementation**

```bash
git diff --check
git add BLEUnlock/CameraCapture.swift BLEUnlockTests/CameraCaptureTests.swift
git commit -m "Warm up camera before Telegram snapshots"
```
