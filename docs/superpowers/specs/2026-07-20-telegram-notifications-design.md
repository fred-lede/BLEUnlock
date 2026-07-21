# Telegram Notifications Design

## Summary

Add an optional, native Telegram notification channel to BLEUnlock. Users configure it from the status-item menu without editing the existing `event` shell script. The existing script integration remains unchanged and continues to run independently.

This version supports Telegram only. LINE integration and the image-hosting infrastructure it would require are explicitly deferred.

## Goals

- Let users enable and configure Telegram from the BLEUnlock menu.
- Support independent notification switches for `away`, `lost`, `unlocked`, and `intruded` events.
- Capture and attach a photo when a manual unlock (`intruded`) is detected, when enabled.
- Store credentials securely and avoid exposing them in logs or errors.
- Keep notification and camera failures from affecting BLE monitoring, locking, or unlocking.
- Preserve the existing `~/Library/Application Scripts/jp.sone.BLEUnlock/event` interface.

## Non-goals

- LINE Messaging API support.
- LINE Notify support, because LINE Notify was terminated on March 31, 2025.
- Cloud image hosting or an image archive.
- Changing the meaning or arguments of existing BLEUnlock events.
- Replacing the existing user-provided event script.

## User Interface

Add a **Telegram Notifications** submenu to the status-item menu with:

- **Enable Telegram**, a checkable item.
- **Configure…**, which opens the Telegram settings dialog.
- **Send Test Notification**, enabled only when both credentials are present.
- An **Events** submenu containing:
  - Device Away (`away`), enabled by default.
  - Signal Lost (`lost`), enabled by default.
  - Unlocked by BLEUnlock (`unlocked`), disabled by default.
  - Manually Unlocked (`intruded`), enabled by default.
- **Take Photo on Manual Unlock**, enabled by default. This setting applies only to `intruded`.
- A non-interactive status item showing Not Configured, Enabled, or Disabled.

The Telegram settings dialog contains:

- A secure Bot Token field. An existing token is never displayed; entering a new value replaces it.
- A Chat ID field.
- Save and Cancel buttons.
- Concise instructions for creating a bot with BotFather and obtaining a Chat ID.

Telegram can be enabled only when a Bot Token and Chat ID have been saved. The test action follows the current photo setting: it sends a test photo when photo capture is enabled and otherwise sends a text message.

All new UI strings use the project's existing localization mechanism. Keys must be present in every currently supported localization so users never see raw localization keys.

## Architecture

### TelegramSettings

`TelegramSettings` owns notification configuration.

- Store the enabled state, four event switches, and manual-unlock photo switch in `UserDefaults`.
- Store the Bot Token and Chat ID in macOS Keychain.
- Expose whether configuration is complete without exposing credential values to menu code.
- Never put credentials into `UserDefaults`, console output, alert text, or error descriptions.

Default event behavior is fixed as follows:

| Event | Default | Photo eligible |
|---|---:|---:|
| `away` | On | No |
| `lost` | On | No |
| `unlocked` | Off | No |
| `intruded` | On | Yes |

### TelegramNotifier

`TelegramNotifier` uses `URLSession` and the Telegram Bot API.

- Use `sendMessage` for text-only notifications.
- Use multipart `sendPhoto` for a manual-unlock notification with a captured JPEG.
- Include the Mac's host name, a human-readable event description, timestamp, and RSSI when available.
- Validate the HTTP status and Telegram response fields, including `ok` and `description`.
- Apply a finite request timeout.
- Perform work asynchronously so no network request blocks BLE processing or screen locking/unlocking.
- Return structured, sanitized errors that never include the Bot Token or full request URL.

The notifier is independent of the existing `runScript` path. An event may therefore run the user's script and send Telegram notification concurrently; either may fail without suppressing the other.

### CameraCapture

`CameraCapture` uses AVFoundation and the system default video camera.

- Request camera access only when a photo is first required, either by an `intruded` event or a photo-enabled test.
- Add a clear `NSCameraUsageDescription` explaining that BLEUnlock photographs a manual unlock for Telegram alerts.
- Capture one JPEG to a uniquely named file in the system temporary directory.
- Return a specific error for denied/restricted permission, no available camera, setup failure, timeout, or capture failure.
- Clean up capture resources after each request.

Only `intruded` may capture an event photo. If photo capture fails for any reason, BLEUnlock sends the same notification as text so the security alert is not lost.

## Event Flow

1. BLEUnlock produces an existing event: `away`, `lost`, `unlocked`, or `intruded`.
2. Existing event-script behavior runs unchanged.
3. If Telegram is disabled, incomplete, or the event switch is off, Telegram processing stops.
4. Text-only events are formatted and submitted to `TelegramNotifier` asynchronously.
5. For `intruded` with photo capture enabled:
   1. `CameraCapture` requests permission when necessary and captures one JPEG.
   2. `TelegramNotifier` sends it with the event text as the caption.
   3. The temporary JPEG is deleted after the send completes, whether it succeeds or fails.
6. If capture fails, send a text-only `intruded` notification and record the sanitized camera error.

The temporary file must also be deleted on request construction errors and cancellation paths, not only on successful network completion.

## Error Handling

- The Configure and Test actions display actionable errors in a dialog.
- Background event failures are written to system logging with credentials redacted.
- A background failure produces a local notification, rate-limited so repeated network or Telegram failures do not flood Notification Center.
- Telegram, Keychain, and camera failures never change BLE presence state or interrupt lock/unlock behavior.
- A failed photo capture falls back to text; a failed photo upload does not retry as text because Telegram may already have accepted the upload before the client observed the failure.

## Security and Privacy

- Bot Token and Chat ID reside in Keychain and are never placed in preferences or source-controlled files.
- The application asks for camera permission only if the photo feature is actually exercised.
- The UI explains that enabling manual-unlock photography captures an image from the system default camera and uploads it to Telegram.
- Captured files exist only in the system temporary directory and are deleted after the attempt completes.
- No photo history is maintained by BLEUnlock.
- Network requests use Telegram's HTTPS Bot API endpoints only.

## Test Strategy

Add a test target and use dependency injection around networking, settings, Keychain access, and camera capture.

Automated tests cover:

- Default and persisted values for all event and photo switches.
- Menu enablement and state synchronization for missing, disabled, and enabled configurations.
- Keychain save, replace, read, and delete behavior through a test double.
- Event filtering for all four event types.
- Text request formatting and escaping.
- Multipart photo request structure and caption content.
- HTTP errors, Telegram `ok: false` responses, malformed responses, and timeouts.
- Credential redaction from surfaced errors and logs.
- Camera denial, missing-camera, capture-failure, and timeout behavior.
- Text fallback after capture failure.
- Temporary-file deletion on success, failure, cancellation, and request-construction errors.
- Existing script dispatch remaining independent from Telegram success or failure.

Manual verification covers:

- First-use camera permission and denied-permission behavior on macOS.
- Configure, enable, event toggles, and test actions in the status-item menu.
- A real Telegram text notification and photo notification.
- A real manual-unlock event with the captured temporary file removed afterward.
- Existing `event` scripts still receiving the same arguments.

## Compatibility and Rollout

- Existing users start with Telegram disabled, so updating BLEUnlock causes no new network or camera activity.
- Users who enable Telegram receive the documented event defaults.
- Existing preferences and event scripts remain valid.
- README documentation will describe Telegram bot setup, Chat ID discovery, menu configuration, camera permission, event defaults, and troubleshooting.
