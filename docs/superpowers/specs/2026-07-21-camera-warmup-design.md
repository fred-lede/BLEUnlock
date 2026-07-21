# Camera Warm-Up Design

## Problem

BLEUnlock starts `AVCaptureSession` and immediately requests a still photo. The
camera has no time to converge automatic exposure and white balance, so the
first Telegram snapshot can be substantially underexposed.

## Chosen approach

Wait one second after the capture session starts before requesting the photo.
The delay applies only to the AVFoundation production session; authorization,
Telegram delivery, text fallback, file cleanup, and the existing ten-second
capture timeout remain unchanged.

Alternatives considered:

- Observe `adjustingExposure` until it becomes false. This adapts to the camera,
  but adds KVO lifetime and hardware-specific edge cases for little benefit.
- Capture and discard a first frame. This warms exposure but performs two photo
  captures and increases latency and resource use.

## Design

`AVPhotoSession` receives a camera scheduler and a warm-up interval, defaulting
to one second. After `session.startRunning()` succeeds, it schedules the existing
photo request rather than issuing it immediately. The scheduled block reuses the
existing lifecycle guards so cancellation during warm-up cannot capture a photo
or retain a delegate.

The existing outer ten-second timeout continues to bound the complete operation,
including warm-up. No new user setting is added.

## Error and cancellation behavior

- If capture is cancelled during warm-up, the scheduled photo request becomes a
  no-op through the lifecycle guard.
- If the overall ten-second timeout expires, the existing timeout and teardown
  path stops the session.
- Camera and Telegram failures retain the existing localized error and text-only
  fallback behavior.

## Testing

Add a deterministic unit test with a recording session/output boundary and a
controllable scheduler. It must prove that starting capture does not request a
photo immediately and that advancing the one-second warm-up requests exactly one
photo. Existing cancellation and timeout tests must continue to pass, followed
by the complete test suite and a Release build.
