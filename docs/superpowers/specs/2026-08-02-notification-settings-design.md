# Notification Settings Design

## Summary

Rename the existing **Telegram Notifications** submenu to **Notification Settings** (通知設定). Inside Notification Settings, keep all existing Telegram functionality and add a Synology Chat channel. Users pick exactly one channel (Telegram or Synology Chat); all channel-specific settings shown in the menu adapt to the selection.

Telegram keeps its current behavior, stored keys, and Keychain accounts so existing users are unaffected. Synology Chat sends text through its incoming webhook and uploads photos through the full `SYNO.Chat.Post` API.

## Goals

- Rename the status-item submenu to Notification Settings.
- Let users choose the notification channel: Telegram or Synology Chat.
- Preserve every existing Telegram setting and credential without migration.
- Add Synology Chat configuration: incoming webhook for text, `SYNO.Chat.Post` for photo upload.
- Share the event switches (`away`, `lost`, `unlocked`, `intruded`) across channels.
- Keep per-channel enabled, photo, and location preferences.
- Keep all existing security, error-handling, and localization behavior.

## Non-goals

- Sending to both channels simultaneously; only one channel is active at a time.
- LINE integration.
- Synology Chat `file_url` uploads or a temporary local HTTP file server.
- Cloud image hosting or an image archive.
- Changing the meaning or arguments of existing BLEUnlock events.
- Replacing the existing user-provided event script.

## User Interface

Rename the top-level menu item from `t("telegram")` to `t("notifications")` (通知設定). The submenu becomes:

- **Notification Channel**, a submenu with two radio-style checkable items:
  - Telegram
  - Synology Chat
- **Enable Notification**, a checkable item reflecting the selected channel's enabled state.
- **Configure…**, which opens the selected channel's settings dialog.
- **Send Test Notification**, enabled only when the selected channel is configured.
- An **Events** submenu shared by both channels:
  - Device Away (`away`), enabled by default.
  - Signal Lost (`lost`), enabled by default.
  - Unlocked by BLEUnlock (`unlocked`), disabled by default.
  - Manually Unlocked (`intruded`), enabled by default.
- **Take Photo on Manual Unlock**, reflecting the selected channel's preference, enabled by default. Applies only to `intruded`.
- A non-interactive privacy explanation line specific to the selected channel.
- **Attach Mac Location**, reflecting the selected channel's preference, disabled by default.
- A non-interactive status item showing Not Configured, Enabled, or Disabled for the selected channel.

The Telegram dialog is unchanged (Bot Token + Chat ID). The Synology Chat dialog contains:

- **Webhook URL** — the full incoming-webhook URL from Synology Chat Integration.
- **DSM Username** — an account able to post to the target channel.
- **DSM Password / API Token** — the account password, or a DSM personal API token for accounts with 2FA. Never displayed after saving.
- **Chat Channel ID** — the numeric channel ID to receive messages.
- Save and Cancel buttons, plus concise setup instructions.

A channel can be enabled only when it is configured. The test action follows the selected channel's photo preference: it sends a test photo when photo capture is enabled and otherwise sends a text message.

All new UI strings use the project's existing localization mechanism. Keys must be present in every currently supported localization so users never see raw localization keys.

## Architecture

### NotificationChannel

```swift
enum NotificationChannel: String, CaseIterable {
    case telegram
    case synologyChat
}
```

### NotificationEvent

Rename `TelegramEvent` to `NotificationEvent` (same raw values: `away`, `lost`, `unlocked`, `intruded`) and `TelegramEventContext` to `NotificationEventContext`. Storage keys stay `telegram.event.<rawValue>` so existing event preferences survive unchanged.

### NotificationSettings

A new `NotificationSettings` class replaces `TelegramSettings` in the app wiring. It owns both channels' configuration.

UserDefaults keys:

- `notification.channel` — selected channel (default `.telegram`).
- Telegram reuses its existing keys so existing users keep their preferences with no migration: `telegram.enabled`, `telegram.takePhotoOnIntruded`, `telegram.attachMacLocation`.
- `notification.enabled.synologyChat` / `notification.takePhoto.synologyChat` (default true) / `notification.attachLocation.synologyChat` (default false) — Synology-only per-channel preferences.
- `telegram.event.<rawValue>` — shared event switches, unchanged from today (defaults: all on except `unlocked`).

Keychain accounts (via existing `SecretStoring`):

- Telegram: `botToken`, `chatID` — unchanged; existing users keep their configuration.
- Synology: `synology.webhookURL`, `synology.username`, `synology.password`, `synology.channelID`.

`NotificationSettings` exposes per-channel helpers (`isEnabled`, `takePhotoOnIntruded`, `attachMacLocation`, `isConfigured`, credential save/read) and never exposes credential values to menu code.

### NotificationService

Rename `TelegramNotificationService` to `NotificationService`, implementing `NotificationHandling`:

1. Read the selected channel and the shared event switch.
2. If the channel is disabled, not configured, or the event switch is off, stop.
3. For `.telegram`, run the existing flow: `TelegramNotifier` text/photo, `sendLocation` for map location.
4. For `.synologyChat`, run the Synology flow:
   - text events → `SynologyNotifier.sendText` (webhook).
   - `intruded` with photo enabled → capture via `CameraCapture` → `SynologyNotifier.sendPhoto` (full API); on capture failure, fall back to text.
   - when location is attached, append the coordinates and Apple Maps link as text (Synology has no native map location).

`sendTest` routes to the selected channel and reports results through the existing dialogs and failure-reporting path.

### SynologyNotifier

New `SynologyNotifier` conforming to a `SynologySending` protocol:

- `sendText(credentials, text, completion)` — POST the webhook URL with `payload={"text": "..."}` form-encoded (confirmed by the official Synology KB; the KB also accepts a raw JSON body, but the form-encoded `payload` form is the most widely tested). Success is `{"success": true}`. The official KB supports file sharing only via a public `file_url` (32 MB max), which cannot reference a local photo, so photo delivery uses the undocumented `SYNO.Chat.Post` API below.
- `sendPhoto(credentials, photoURL, caption, completion)`:
  1. Login `SYNO.API.Auth` (version 6, `method=login`, `account`, `passwd`, `session=Chat`, `format=sid`) at the host parsed from the webhook URL → `sid` + `synotoken`.
  2. Upload via `SYNO.Chat.Post` (`method=create`, version 5) multipart with `_sid`, `channel_id`, multipart fields `type=file`, `message=""`, `conn_id=""`, and the photo as the `file` part. This immediately creates the photo post in the channel; the response carries the created post (`post_id`, `file_props`), **not** a `file_id` (confirmed live on DSM 7.3.2 VirtualDSM, `SYNO.Chat.Post` maxVersion 8). The multipart `message` field is ignored, so the caption cannot ride along.
  3. Send the caption as a separate text post via `SYNO.Chat.Post` (`method=create`, version 5) form POST with `_sid`, `channel_id`, `message=caption` (no `file_id`). Success is `{"success": true}`; a non-empty caption always produces the text post after the photo.

DSM API token usage requires no special program handling: the login call is identical, and the token is simply entered in the password field.

All errors are sanitized so credentials, the sid, and the token never appear in logs, dialogs, or error descriptions. A photo upload failure does not retry as text; a failed capture falls back to text.

## Event Flow

1. BLEUnlock produces an existing event: `away`, `lost`, `unlocked`, or `intruded`.
2. The existing event-script behavior runs unchanged.
3. If the selected channel is disabled, incomplete, or the event switch is off, notification processing stops.
4. Text-only events are formatted and submitted to the selected channel's notifier asynchronously.
5. For `intruded` with photo capture enabled:
   1. `CameraCapture` requests permission when necessary and captures one JPEG.
   2. The selected channel's notifier sends it with the event text as the caption.
   3. The temporary JPEG is deleted after the send completes, whether it succeeds or fails.
6. If capture fails, send a text-only `intruded` notification and record the sanitized camera error.

## Error Handling

- The Configure and Test actions display actionable errors in a dialog.
- Background event failures are written to system logging with credentials redacted.
- A background failure produces a local notification, rate-limited so repeated failures do not flood Notification Center.
- Notification, Keychain, and camera failures never change BLE presence state or interrupt lock/unlock behavior.

## Security and Privacy

- All credentials (Telegram Bot Token/Chat ID, Synology webhook URL, DSM username/password-or-token, channel ID) reside in Keychain and are never placed in preferences or source-controlled files.
- The application asks for camera permission only if the photo feature is actually exercised.
- The privacy explanation line states where the photo is uploaded (Telegram or Synology Chat).
- Captured files exist only in the system temporary directory and are deleted after the attempt completes.
- Network requests use HTTPS for both Telegram and Synology endpoints.

## Test Strategy

Keep dependency injection around networking, settings, Keychain access, and camera capture.

Automated tests cover:

- `NotificationSettings`: channel selection, per-channel enabled/photo/location values, shared event defaults, both credential stores, no-migration event keys.
- `SynologyNotifier`: webhook text payload and response parsing; full API photo flow (login, upload, post) including error mapping; credential/sid redaction.
- `NotificationMenuController`: channel radio selection, per-channel enable state, configure/test routing per channel, menu enablement for unconfigured/configured states, privacy line adjacency.
- `NotificationService`: routing to Telegram vs Synology based on the selected channel, event filtering, text fallback on capture failure.
- `LocalizationTests`: new `notification_*` and `synology_*` keys present in every localization, and production references covered.

Existing `TelegramNotifierTests` and Telegram-specific behavior remain.

Manual verification covers:

- Selecting each channel and confirming the menu reflects its settings.
- A real Telegram text and photo notification.
- A real Synology Chat text notification.
- A real Synology Chat photo notification against a DSM 7.3.2+ NAS (including an account with 2FA using an API token).
- Existing `event` scripts still receiving the same arguments.

## Compatibility and Rollout

- Existing users keep their Telegram credentials, event preferences, and photo/location settings; the default channel is Telegram, so behavior is unchanged until the user switches.
- Synology Chat is disabled until configured.
- `SYNO.Chat.Post` is an undocumented internal API; compatibility is confirmed on DSM 7.3.2+. If it proves unavailable on a target NAS, Synology text notifications still work, and photo upload fails gracefully with a rate-limited failure notification.
- README documentation will describe the channel selector, Synology webhook creation, DSM API token setup for 2FA accounts, and channel ID discovery.
