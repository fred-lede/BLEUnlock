# Stable Proximity Confirmation Design

## Goal

Make proximity unlock reliable despite normal Bluetooth RSSI fluctuations. A monitored phone approximately 0.5–1 metre from the Mac should trigger exactly one unlock within 1–2 seconds when the signal is consistently strong enough. A single RSSI spike must not trigger an unlock.

This work changes only the close-device decision. Existing away/lost locking, Telegram notifications, camera capture, location attachment, password entry, and screen wake behaviour remain unchanged.

## Current Behaviour and Root Cause

`BLE.updateMonitoredPeripheral(_:)` currently marks an absent device present as soon as one raw RSSI sample reaches `unlockRSSI`. The away path is more conservative: it evaluates a moving average against `lockRSSI` and then waits for `proximityTimeout` before locking.

The asymmetric filtering explains why approaching can feel inconsistent and why lowering the unlock threshold alone would increase false-unlock risk. The current user settings (`unlockRSSI = -50 dBm`, `lockRSSI = -70 dBm`) also require a much stronger signal to unlock than to remain present. Telegram photo capture is not on the approach path and is not a cause of RSSI detection latency.

## Chosen Approach

Use a three-sample, two-success confirmation window with temporary burst sampling.

Alternatives considered:

- Two consecutive qualifying samples: simple and fast, but one normal low outlier restarts confirmation.
- Moving average sustained for a fixed duration: smooth, but difficult to meet the 1–2 second response target.
- Two qualifying samples out of three: tolerates one high spike or one low dip while retaining fast response. This is the selected approach.

## Proximity Confirmation State Machine

Introduce a small, independent proximity confirmation component. It accepts timestamped RSSI samples and emits decisions without owning CoreBluetooth objects or application actions.

The component has two states:

1. `absent`: no confirmation is active.
2. `confirming`: a bounded set of fresh samples is being evaluated.

Given a configured unlock threshold `U`:

- The candidate threshold is `U - 5 dB`. For example, `U = -55 dBm` produces a candidate threshold of `-60 dBm`.
- While absent, samples below the candidate threshold do nothing.
- A sample at or above the candidate threshold starts a 1.5-second confirmation window and is retained as the first sample.
- Confirmation accepts at most three samples, including the candidate sample.
- A sample qualifies when its RSSI is at or above `U`.
- As soon as two samples qualify, confirmation succeeds and emits exactly one close decision.
- If three samples arrive without two qualifying samples, confirmation fails and returns to `absent`.
- If 1.5 seconds elapse first, confirmation fails and returns to `absent`.
- Samples from an earlier or completed window are never reused.

A candidate sample between `U - 5 dB` and `U` starts verification but does not count as a qualifying sample. A single arbitrarily strong sample can count only once and cannot complete confirmation by itself.

## BLE Integration and Sampling

`BLE` continues to own CoreBluetooth connections, scanning, timers, and delegate calls. The confirmation component owns only decision state.

When the confirmation component enters `confirming` in normal mode:

- If the monitored peripheral is connected, request fresh RSSI readings approximately every 0.4 seconds.
- If it is disconnected, retain the existing connection attempt and continue accepting duplicate advertisement samples.
- Stop burst sampling immediately after success, failure, or timeout.
- Restore the existing approximately two-second active RSSI interval after burst sampling.

In passive mode, never connect or increase the sampling frequency. Confirmation uses duplicate advertisement samples only. Consequently, the 1–2 second response target applies to normal mode and is not guaranteed in passive mode.

On confirmation success, `BLE` sets `presence = true`, clears the existing smoothing history as it does today, and invokes `updatePresence(presence: true, reason: "close")` once. Existing screen wake and unlock handling then proceeds unchanged.

The away path continues to use the existing moving average, `lockRSSI`, and lock delay. It does not share confirmation samples with the close path.

## Reset and Lifecycle Rules

Clear any confirmation state, pending timeout, and burst timer when:

- confirmation succeeds, fails, or expires;
- Bluetooth becomes unavailable;
- the monitored device is lost or changed;
- monitoring restarts;
- the application stops scanning or terminates.

Timer callbacks must verify that they still belong to the active confirmation attempt before requesting RSSI or changing state. This prevents a callback from an expired attempt affecting a later one.

## Diagnostics

Add concise diagnostic output for:

- confirmation start and candidate RSSI;
- each sample number and RSSI;
- confirmation success, sample count, and elapsed time;
- failure reason: insufficient samples, three-sample rejection, reset, or timeout;
- burst sampling start and stop.

Diagnostics must not include Telegram credentials, passwords, or unrelated device data.

## Testing

Unit-test the confirmation component independently with a controllable clock:

- one strong sample never confirms;
- two qualifying samples among three confirm;
- one qualifying sample among three rejects;
- a low outlier does not prevent two other samples from confirming;
- a high spike followed by two low samples rejects;
- the exact candidate, unlock, and timeout boundaries behave consistently;
- timeout clears all retained samples;
- reset clears samples and prevents stale callbacks from confirming;
- success is emitted only once per attempt.

Test BLE integration with fakes or existing scan doubles:

- entering confirmation starts burst reads only in normal mode;
- success, rejection, timeout, device change, and Bluetooth loss stop burst reads;
- normal active sampling resumes after a burst;
- passive mode never initiates burst reads or a connection;
- exactly one `presence = true` delegate event is emitted on success;
- enabling or disabling Telegram photo capture produces identical proximity decisions.

## Acceptance Criteria

- In normal mode, with the phone approximately 0.5–1 metre away and at least two of three fresh samples meeting the unlock threshold, BLEUnlock triggers one unlock within 1–2 seconds.
- A single qualifying RSSI spike never triggers unlock.
- One low outlier among three samples does not block unlock when the other two qualify.
- Failed or expired attempts do not affect later attempts.
- Away/lost locking behaviour and its timing are unchanged.
- Telegram photo, camera, and location behaviour are unchanged.
- The full automated test suite passes.
