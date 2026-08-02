# Notification Settings (Telegram + Synology Chat) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Turn the existing Telegram Notifications submenu into a channel-aware Notification Settings submenu that lets the user choose Telegram or Synology Chat, keeping all existing Telegram behavior, stored keys, and credentials intact.

**Architecture:** One `NotificationSettings` class owns a selected channel plus per-channel enabled/photo/location preferences. Telegram reuses its existing UserDefaults keys and Keychain service (zero migration); Synology gets new keys and a new Keychain service. A renamed `NotificationService` routes each event to a `TelegramSending` or a new `SynologySending` sender. `SynologyNotifier` posts text through the incoming webhook (`SYNO.Chat.External`) and photos through the undocumented `SYNO.Chat.Post` API (login → multipart upload → post). The menu controller gains a radio-style channel submenu and per-channel dialogs.

**Tech Stack:** Swift 5, AppKit, Foundation, URLSession, XCTest, Xcode 14+ (`xcodeproj`), `xcodebuild` CLI.

**Build/Test command used throughout:** `xcodebuild test -scheme BLEUnlock -destination 'platform=macOS'`

---

## File Inventory

**Renamed files (type + path + PBXFileReference `path` change; PBXBuildFile entries keep their IDs):**
- `BLEUnlock/TelegramEvent.swift` → `BLEUnlock/NotificationEvent.swift` (contains `NotificationEvent`, `NotificationEventContext`, `TelegramCredentials`)
- `BLEUnlock/TelegramSettings.swift` → `BLEUnlock/NotificationSettings.swift` (contains `SecretStoring` and later `NotificationChannel`)
- `BLEUnlock/TelegramNotificationService.swift` → `BLEUnlock/NotificationService.swift`
- `BLEUnlock/TelegramMenuController.swift` → `BLEUnlock/NotificationMenuController.swift`
- `BLEUnlockTests/TelegramSettingsTests.swift` → `BLEUnlockTests/NotificationSettingsTests.swift`
- `BLEUnlockTests/TelegramNotificationServiceTests.swift` → `BLEUnlockTests/NotificationServiceTests.swift`
- `BLEUnlockTests/TelegramMenuControllerTests.swift` → `BLEUnlockTests/NotificationMenuControllerTests.swift`

**New files:**
- `BLEUnlock/SynologyNotifier.swift` (`SynologyCredentials`, `SynologyError`, `SynologySending`, `SynologyNotifier`)
- `BLEUnlockTests/SynologyNotifierTests.swift`

**Modified files:**
- `BLEUnlock/AppDelegate.swift` (wiring, `t("notifications")`, two Keychain services)
- `BLEUnlock/TelegramNotifier.swift` (make `Data` multipart helpers `internal` so SynologyNotifier can reuse them)
- `BLEUnlockTests/TestDoubles.swift` (add `QueuedHTTPTransport`, `RecordingSynologySender`)
- `BLEUnlockTests/LocalizationTests.swift` (key sets, source scan, privacy tests, forbidden strings)
- `BLEUnlock.xcodeproj/project.pbxproj` (7 `path` renames + 2 new files)
- 9 localization files: `BLEUnlock/<Base|da|de|ja|nb|sv|tr|zh-Hans|zh-Hant>.lproj/Localizable.strings`
- `README.md`, `README.ja.md`, `README_CHT.md`

**Unchanged (shared components):** `TelegramNotifier.swift` (types), `CameraCapture.swift`, `MacLocationProvider.swift`, `PhotoLocationCoordinator.swift`, `KeychainStore.swift`, `Info.plist`, all `InfoPlist.strings`.

---

## Design Decisions Locked In

- **Telegram keeps its old UserDefaults keys** (`telegram.enabled`, `telegram.takePhotoOnIntruded`, `telegram.attachMacLocation`) and its old Keychain service (`jp.sone.BLEUnlock.telegram`, accounts `botToken`/`chatID`). **No migration.**
- **Synology gets new keys**: `notification.channel`, `notification.enabled.synologyChat`, `notification.takePhoto.synologyChat`, `notification.attachLocation.synologyChat`; a new Keychain service `jp.sone.BLEUnlock.synology` with accounts `webhookURL`, `username`, `password`, `channelID`.
- **Event switches stay shared** under `telegram.event.<rawValue>`; the `telegram_event_*` localization keys are reused by both channels.
- **`SYNO.Chat.External`** (incoming webhook, `version=2`, `method=incoming`) sends text: `POST <webhookURL>` with form body `payload={"text": "..."}`. Success = `{"success": true}`.
- **`SYNO.Chat.Post`** (`method=create`, `version=5`) sends photos: (1) login `SYNO.API.Auth` `version=6` with `enable_syno_token=yes`, `format=sid`, `session=Chat` at `https://<host>/webapi/auth.cgi` → `sid` + `synotoken`; (2) multipart upload to `entry.cgi` with query params `api/method/version/channel_id/_sid`, header `X-SYNO-TOKEN`, cookie `id=<sid>`, multipart fields `type=file`, `message=""`, `conn_id=""`, and the photo as the `file` part — this immediately creates the photo post (response carries `post_id`/`file_props`, **no `file_id`**; the multipart `message` field is ignored); (3) send the caption as a **separate text post** via form POST `message=<caption>` to the same `entry.cgi` URL with `X-SYNO-TOKEN` → `{"success": true}`. (Reference: N4S4/synology-api `post_file_upload`; **deviation from this plan's original 3-step `file_id` flow** — live-verified on DSM 7.3.2 VirtualDSM, `SYNO.Chat.Post` maxVersion 8, commit "fix: post Synology photo caption as separate text post".)
- **Synology location** = coordinates + accuracy + Apple Maps link appended to the caption text (no native map message). Telegram keeps its separate native `sendLocation` message.
- **No photo→text retry on upload failure**; a **failed capture** falls back to text. Temporary photo is deleted after every attempt.
- **`InfoPlist.strings` and `Info.plist` are NOT changed** — camera/location permission prompts stay as-is (out of scope).
- **`telegram_camera_error_*`, `telegram_message_*`, `telegram_location_*`, `telegram_error_*` (TelegramNotifier), `telegram_bot_token`, `telegram_chat_id`, `telegram_setup_help`, `telegram_camera_privacy` localization keys are kept unchanged.** Only the shared-menu/flow keys are renamed to `notification_*`, and new `synology_*` keys are added.

### Localization key changes (applied in Task 1)

Renamed (17) — remove old key, add new key:
| Old key | New key | Base value |
|---|---|---|
| `telegram` | `notifications` | `Notification Settings` |
| `telegram_enable` | `notification_enable` | `Enable Notification` |
| `telegram_configure` | `notification_configure` | `Configure…` |
| `telegram_test` | `notification_test` | `Send Test Notification` |
| `telegram_events` | `notification_events` | `Events` |
| `telegram_take_photo` | `notification_take_photo` | `Attach a photo for manual unlock` |
| `telegram_attach_mac_location` | `notification_attach_mac_location` | `Attach Mac Location` |
| `telegram_status_not_configured` | `notification_status_not_configured` | `Not configured` |
| `telegram_status_enabled` | `notification_status_enabled` | `Enabled` |
| `telegram_status_disabled` | `notification_status_disabled` | `Disabled` |
| `telegram_save` | `notification_save` | `Save` |
| `telegram_test_success` | `notification_test_success` | `Test notification sent.` |
| `telegram_test_failed` | `notification_test_failed` | `Could not send the test notification.` |
| `telegram_error_not_configured` | `notification_error_not_configured` | `Configure the selected notification channel first.` |
| `telegram_error_settings_unavailable` | `notification_error_settings_unavailable` | `Notification settings could not be read.` |
| `telegram_error_file_cleanup` | `notification_error_file_cleanup` | `The captured photo could not be deleted.` |
| `telegram_failure_notification_subtitle` | `notification_failure_notification_subtitle` | `Notification failed` |

Added (21):
| Key | Base value |
|---|---|
| `notification_channel` | `Notification Channel` |
| `notification_channel_telegram` | `Telegram` |
| `notification_channel_synology_chat` | `Synology Chat` |
| `notification_camera_privacy_synology` | `BLEUnlock uses the system default camera and uploads one photo to Synology Chat. The temporary photo is deleted after the attempt; if capture fails, BLEUnlock sends text instead.` |
| `synology_webhook_url` | `Webhook URL` |
| `synology_username` | `DSM Username` |
| `synology_password` | `DSM Password / API Token` |
| `synology_channel_id` | `Chat Channel ID` |
| `synology_setup_help` | `In Synology Chat, open Settings > Integration, create an incoming webhook, and copy its URL. Enter a DSM account that can post to the channel, or a personal API token when the account uses two-factor authentication. Enter the numeric ID of the channel that should receive notifications.` |
| `synology_error_invalid_request` | `The Synology Chat request could not be created.` |
| `synology_error_transport` | `The Synology Chat server could not be reached.` |
| `synology_error_http_status` | `The Synology Chat server returned HTTP status %d.` |
| `synology_error_invalid_response` | `The Synology Chat server returned an invalid response.` |
| `synology_error_login` | `Synology Chat login failed. Check the DSM username and password or API token.` |
| `synology_error_upload` | `The photo could not be uploaded to Synology Chat.` |
| `synology_error_post` | `The message could not be posted to Synology Chat.` |
| `synology_error_settings_unavailable` | `Synology Chat settings could not be read.` |

Kept unchanged (30): `telegram_event_away`, `telegram_event_lost`, `telegram_event_unlocked`, `telegram_event_intruded`, `telegram_bot_token`, `telegram_chat_id`, `telegram_setup_help`, `telegram_camera_privacy`, `telegram_camera_error_denied`, `telegram_camera_error_restricted`, `telegram_camera_error_no_camera`, `telegram_camera_error_setup_failed`, `telegram_camera_error_capture_failed`, `telegram_camera_error_timeout`, `telegram_camera_error_file_write_failed`, `telegram_error_invalid_request`, `telegram_error_unreadable_photo`, `telegram_error_transport`, `telegram_error_http_status`, `telegram_error_rejected`, `telegram_error_invalid_response`, `telegram_error_keychain_status`, `telegram_message_time`, `telegram_message_rssi`, `telegram_message_coordinates`, `telegram_message_accuracy`, `telegram_message_map`, `telegram_location_unavailable`, `telegram_location_error`, `telegram_location_send_error`.

---

## Task 1: Rename Telegram → Notification (zero behavior change)

**Files:**
- Modify: `BLEUnlock/TelegramEvent.swift`, `BLEUnlock/TelegramSettings.swift`, `BLEUnlock/TelegramNotificationService.swift`, `BLEUnlock/TelegramMenuController.swift` (rename types, then `git mv` files)
- Modify: `BLEUnlockTests/TelegramSettingsTests.swift`, `BLEUnlockTests/TelegramNotificationServiceTests.swift`, `BLEUnlockTests/TelegramMenuControllerTests.swift` (rename test classes + source-path references, then `git mv`)
- Modify: `BLEUnlock/AppDelegate.swift`, `BLEUnlockTests/LocalizationTests.swift`, `BLEUnlockTests/TestDoubles.swift`
- Modify: `BLEUnlock.xcodeproj/project.pbxproj` (7 `path` renames + comment text)
- Modify: all 9 `Localizable.strings` files (apply the localization key changes table)
- Test: `xcodebuild test -scheme BLEUnlock -destination 'platform=macOS'`

This task is a pure mechanical rename. The build will be broken between individual steps; the task is verified only at the end when the full suite is green. Do the renames in the order below.

- [ ] **Step 1: Rename types in `TelegramEvent.swift`, then `git mv` the file**

Apply these renames inside `BLEUnlock/TelegramEvent.swift` (keep `TelegramCredentials` exactly as-is):
- `enum TelegramEvent` → `enum NotificationEvent`
- `TelegramEventContext` → `NotificationEventContext`
- Inside `NotificationEventContext`, field type `let event: TelegramEvent` → `let event: NotificationEvent`

Final file content:
```swift
import Foundation

enum NotificationEvent: String, CaseIterable {
    case away, lost, unlocked, intruded

    var defaultEnabled: Bool { self != .unlocked }
    var defaultsKey: String { "telegram.event.\(rawValue)" }
}

struct NotificationEventContext: Equatable {
    let event: NotificationEvent
    let hostName: String
    let timestamp: Date
    let rssi: Int?
}

struct TelegramCredentials: Equatable {
    let token: String
    let chatID: String
}
```

```bash
git mv BLEUnlock/TelegramEvent.swift BLEUnlock/NotificationEvent.swift
```

- [ ] **Step 2: Rename types in `TelegramSettings.swift`, then `git mv`**

- `final class TelegramSettings` → `final class NotificationSettings`
- `TelegramEvent` → `NotificationEvent` (two occurrences)
- Keep `SecretStoring`, the `Key` enum, all stored keys, properties, and method bodies unchanged.

```bash
git mv BLEUnlock/TelegramSettings.swift BLEUnlock/NotificationSettings.swift
```

- [ ] **Step 3: Rename types in `TelegramNotificationService.swift`, then `git mv`**

- `protocol TelegramNotificationHandling` → `protocol NotificationHandling`
- `protocol TelegramMessageFormatting` → `protocol NotificationMessageFormatting`
- `final class TelegramMessageFormatter: TelegramMessageFormatting` → `final class NotificationMessageFormatter: NotificationMessageFormatting`
- `TelegramEventContext` → `NotificationEventContext` (all occurrences)
- `TelegramEvent` → `NotificationEvent` (in `localizedDescription(for:)` and the switch cases — the switch is unchanged)
- `private enum TelegramNotificationServiceError` → `private enum NotificationServiceError`
- `final class TelegramNotificationService: TelegramNotificationHandling` → `final class NotificationService: NotificationHandling`
- `private let settings: TelegramSettings` → `private let settings: NotificationSettings`
- `private let formatter: TelegramMessageFormatting` → `private let formatter: NotificationMessageFormatting`
- Init parameter `formatter: TelegramMessageFormatting = TelegramMessageFormatter()` → `formatter: NotificationMessageFormatting = NotificationMessageFormatter()`
- Inside `UserNotificationFailureDelivery.deliver`, `t("telegram_failure_notification_subtitle")` → `t("notification_failure_notification_subtitle")`
- Inside `NotificationServiceError.errorDescription`: `t("telegram_error_not_configured")` → `t("notification_error_not_configured")`, `t("telegram_error_settings_unavailable")` → `t("notification_error_settings_unavailable")`
- Inside `RateLimitedFailureReporter.report` and `NotificationService` methods: the `t("telegram_error_settings_unavailable")` calls → `t("notification_error_settings_unavailable")`; `t("telegram_error_file_cleanup")` → `t("notification_error_file_cleanup")`. The `NSLog("BLEUnlock Telegram notification failure category: %@", ...)` string and `category: "telegram"` / `"telegram-location"` reporter arguments are NOT user-visible and stay unchanged.

Leave every protocol in this file (`FailureReporting`, `FailureNotificationDelivering`, `UserNotificationCenterDelivering`, `MainThreadScheduling`) and all of `RateLimitedFailureReporter`, `UserNotificationFailureDelivery`, `DispatchMainThreadScheduler`, and the four Telegram-flow private methods (`sendLocatedPhotoOrFallback`, `deliver`, `sendPhotoOrFallback`, `sendText`) unchanged apart from the renames above.

```bash
git mv BLEUnlock/TelegramNotificationService.swift BLEUnlock/NotificationService.swift
```

- [ ] **Step 4: Rename types in `TelegramMenuController.swift`, then `git mv`**

- `protocol TelegramDialogPresenting` → `protocol NotificationDialogPresenting`
- `final class TelegramMenuController` → `final class NotificationMenuController`
- `TelegramEvent` → `NotificationEvent` (the `eventItems` dictionary type and `TelegramEvent.allCases`)
- `private let settings: TelegramSettings` → `private let settings: NotificationSettings`
- `private let service: TelegramNotificationHandling` → `private let service: NotificationHandling`
- `private let dialogs: TelegramDialogPresenting` → `private let dialogs: NotificationDialogPresenting`
- Init signature: `init(settings: TelegramSettings, service: TelegramNotificationHandling, dialogs: TelegramDialogPresenting, ...)` → `init(settings: NotificationSettings, service: NotificationHandling, dialogs: NotificationDialogPresenting, ...)`
- Dispatch queue label `"jp.sone.BLEUnlock.telegram.menu"` → `"jp.sone.BLEUnlock.notification.menu"`
- Localization calls: `t("telegram_enable")` → `t("notification_enable")`, `t("telegram_configure")` → `t("notification_configure")`, `t("telegram_test")` → `t("notification_test")`, `t("telegram_events")` → `t("notification_events")`, `t("telegram_take_photo")` → `t("notification_take_photo")`, `t("telegram_attach_mac_location")` → `t("notification_attach_mac_location")`, `t("telegram_status_not_configured")` → `t("notification_status_not_configured")`, `t("telegram_status_enabled")` → `t("notification_status_enabled")`, `t("telegram_status_disabled")` → `t("notification_status_disabled")`, `t("telegram_test_success")` → `t("notification_test_success")`, `t("telegram_test_failed")` → `t("notification_test_failed")`, `t("telegram_error_settings_unavailable")` → `t("notification_error_settings_unavailable")`, `t("telegram_error_not_configured")` → `t("notification_error_not_configured")`
- Keep `t("telegram_event_\(event.rawValue)")`, `t("telegram_camera_privacy")`, `t("telegram_bot_token")`, `t("telegram_chat_id")`, `t("telegram_save")` → **note:** `t("telegram_save")` DOES change → `t("notification_save")` (it appears in the presenter, Step 4b). The menu controller itself does not use `telegram_save`.
- `final class AppKitTelegramDialogPresenter: TelegramDialogPresenting` → `final class AppKitNotificationDialogPresenter: NotificationDialogPresenting`
- In `AppKitNotificationDialogPresenter.requestCredentials`: `t("telegram_configure")` → `t("notification_configure")`, `t("telegram_save")` → `t("notification_save")`; keep `t("telegram_setup_help")`, `t("telegram_camera_privacy")`, `t("telegram_bot_token")`, `t("telegram_chat_id")`.
- In `showResult` inside `NotificationMenuController` and the presenter, the `ok` key stays `t("ok")`.

```bash
git mv BLEUnlock/TelegramMenuController.swift BLEUnlock/NotificationMenuController.swift
```

- [ ] **Step 5: Rename test classes and source-path references, then `git mv` the three test files**

In `BLEUnlockTests/TelegramSettingsTests.swift`:
- `final class TelegramSettingsTests` → `final class NotificationSettingsTests`
- `TelegramSettings(defaults:secrets:)` → `NotificationSettings(defaults:secrets:)` (all occurrences)

In `BLEUnlockTests/TelegramNotificationServiceTests.swift`:
- `final class TelegramNotificationServiceTests` → `final class NotificationServiceTests`
- `TelegramSettings` → `NotificationSettings` (all occurrences)
- `TelegramNotificationService(` → `NotificationService(`
- `TelegramEvent` → `NotificationEvent` (the `context(event:rssi:)` helper signature and `TelegramNotificationService` test file name references)
- `TelegramMessageFormatter()` → `NotificationMessageFormatter()` (one occurrence)
- `TelegramEventContext(` → `NotificationEventContext(`
- In `testProductionAppWiresCoreLocationIntoTelegramMenuAndService`, the assertions check `AppDelegate.swift` contains `"location: macLocationProvider"` and `"locationAuthorization: macLocationProvider"` — these remain valid because Task 1 keeps the `TelegramMenuController`/`NotificationMenuController` init parameter names (`locationAuthorization:`). No change needed here.

In `BLEUnlockTests/TelegramMenuControllerTests.swift`:
- `final class TelegramMenuControllerTests` → `final class NotificationMenuControllerTests`
- `TelegramSettings` → `NotificationSettings`
- `TelegramMenuController(` → `NotificationMenuController(`
- `RecordingTelegramNotificationService` → `RecordingNotificationService`, and its conformance `NotificationHandling` (was `TelegramNotificationHandling`); `handle(_ context: NotificationEventContext)` signature updated; `TelegramEventContext` → `NotificationEventContext`
- `RecordingTelegramDialogPresenter: TelegramDialogPresenting` → `RecordingNotificationDialogPresenter: NotificationDialogPresenting`
- `t("telegram_status_not_configured")` → `t("notification_status_not_configured")`, `t("telegram_test_success")` → `t("notification_test_success")`, `t("telegram_camera_privacy")` stays
- In `testControllerDoesNotReadOrRetainTelegramCredentials`, the source path `"BLEUnlock/TelegramMenuController.swift"` → `"BLEUnlock/NotificationMenuController.swift"`; the assertions (no `settings.credentials()`, no `TelegramCredentials`, contains `saveCredentials(replacementToken:`) stay valid.
- In `testCameraPrivacyExplanationIsVisibleAdjacentToPhotoToggle` and `testLocationItemIsBelowPrivacyTextAndDisabledWhenPhotoIsOff`, no changes needed.

```bash
git mv BLEUnlockTests/TelegramSettingsTests.swift BLEUnlockTests/NotificationSettingsTests.swift
git mv BLEUnlockTests/TelegramNotificationServiceTests.swift BLEUnlockTests/NotificationServiceTests.swift
git mv BLEUnlockTests/TelegramMenuControllerTests.swift BLEUnlockTests/NotificationMenuControllerTests.swift
```

- [ ] **Step 6: Update `BLEUnlock/AppDelegate.swift`**

- `let telegramSettings = TelegramSettings(secrets: KeychainStore(service: "jp.sone.BLEUnlock.telegram"))` → `let notificationSettings = NotificationSettings(secrets: KeychainStore(service: "jp.sone.BLEUnlock.telegram"))`
- `lazy var telegramService: TelegramNotificationHandling = TelegramNotificationService(` → `lazy var notificationService: NotificationHandling = NotificationService(`; body unchanged
- `lazy var telegramMenuController = TelegramMenuController(` → `lazy var notificationMenuController = NotificationMenuController(`; body unchanged
- `private let telegramEventQueue` → `private let notificationEventQueue`; label `"jp.sone.BLEUnlock.telegram.events"` → `"jp.sone.BLEUnlock.notification.events"`
- In `dispatchEvent`: `TelegramEvent(rawValue: rawValue)` → `NotificationEvent(rawValue: rawValue)`; `TelegramEventContext(` → `NotificationEventContext(`; `telegramEventQueue.async { [weak self] in self?.telegramService.handle(context) }` → `notificationEventQueue.async { [weak self] in self?.notificationService.handle(context) }`
- In `constructMenu`: `item = mainMenu.addItem(withTitle: t("telegram"), ...)` → `t("notifications")`; `item.submenu = telegramMenuController.menu` → `item.submenu = notificationMenuController.menu`

- [ ] **Step 7: Update `BLEUnlockTests/TestDoubles.swift`**

No type changes are needed for the existing doubles. Add a `NotificationCallKind` alias note: leave `TelegramCallKind` and `RecordingTelegramSender` untouched (the Telegram channel still uses them). No edit required in this task.

- [ ] **Step 8: Apply the localization key changes to all 9 `Localizable.strings` files**

For `BLEUnlock/Base.lproj/Localizable.strings`, replace the current `telegram` block (lines 40-86) with this block:

```text
"notifications" = "Notification Settings";
"notification_channel" = "Notification Channel";
"notification_channel_telegram" = "Telegram";
"notification_channel_synology_chat" = "Synology Chat";
"notification_enable" = "Enable Notification";
"notification_configure" = "Configure…";
"notification_test" = "Send Test Notification";
"notification_events" = "Events";
"notification_take_photo" = "Attach a photo for manual unlock";
"notification_attach_mac_location" = "Attach Mac Location";
"notification_status_not_configured" = "Not configured";
"notification_status_enabled" = "Enabled";
"notification_status_disabled" = "Disabled";
"notification_save" = "Save";
"notification_test_success" = "Test notification sent.";
"notification_test_failed" = "Could not send the test notification.";
"notification_error_not_configured" = "Configure the selected notification channel first.";
"notification_error_settings_unavailable" = "Notification settings could not be read.";
"notification_error_file_cleanup" = "The captured photo could not be deleted.";
"notification_failure_notification_subtitle" = "Notification failed";
"notification_camera_privacy_synology" = "BLEUnlock uses the system default camera and uploads one photo to Synology Chat. The temporary photo is deleted after the attempt; if capture fails, BLEUnlock sends text instead.";
"synology_webhook_url" = "Webhook URL";
"synology_username" = "DSM Username";
"synology_password" = "DSM Password / API Token";
"synology_channel_id" = "Chat Channel ID";
"synology_setup_help" = "In Synology Chat, open Settings > Integration, create an incoming webhook, and copy its URL. Enter a DSM account that can post to the channel, or a personal API token when the account uses two-factor authentication. Enter the numeric ID of the channel that should receive notifications.";
"synology_error_invalid_request" = "The Synology Chat request could not be created.";
"synology_error_transport" = "The Synology Chat server could not be reached.";
"synology_error_http_status" = "The Synology Chat server returned HTTP status %d.";
"synology_error_invalid_response" = "The Synology Chat server returned an invalid response.";
"synology_error_login" = "Synology Chat login failed. Check the DSM username and password or API token.";
"synology_error_upload" = "The photo could not be uploaded to Synology Chat.";
"synology_error_post" = "The message could not be posted to Synology Chat.";
"synology_error_settings_unavailable" = "Synology Chat settings could not be read.";

"telegram_event_away" = "Device is away";
"telegram_event_lost" = "Signal is lost";
"telegram_event_unlocked" = "Unlocked by BLEUnlock";
"telegram_event_intruded" = "Unlocked manually";
"telegram_bot_token" = "Bot token";
"telegram_chat_id" = "Chat ID";
"telegram_setup_help" = "Create a bot with @BotFather and copy its token. Send the bot a message, then open getUpdates in the Telegram Bot API and copy the numeric Chat ID from the response.";
"telegram_camera_privacy" = "BLEUnlock uses the system default camera and uploads one photo to Telegram. The temporary photo is deleted after the attempt; if capture fails, BLEUnlock sends text instead.";
"telegram_camera_error_denied" = "Camera access was denied.";
"telegram_camera_error_restricted" = "Camera access is restricted.";
"telegram_camera_error_no_camera" = "No camera is available.";
"telegram_camera_error_setup_failed" = "The camera could not be configured.";
"telegram_camera_error_capture_failed" = "The camera could not capture a photo.";
"telegram_camera_error_timeout" = "The camera capture timed out.";
"telegram_camera_error_file_write_failed" = "The captured photo could not be saved.";
"telegram_error_invalid_request" = "The Telegram request could not be created.";
"telegram_error_unreadable_photo" = "The captured photo could not be read.";
"telegram_error_transport" = "Telegram could not be reached.";
"telegram_error_http_status" = "Telegram returned HTTP status %d.";
"telegram_error_rejected" = "Telegram rejected the request.";
"telegram_error_invalid_response" = "Telegram returned an invalid response.";
"telegram_error_keychain_status" = "Keychain operation failed (%d).";
"telegram_message_time" = "Time";
"telegram_message_rssi" = "RSSI";
"telegram_message_coordinates" = "GPS Coordinates";
"telegram_message_accuracy" = "Location Accuracy";
"telegram_message_map" = "Map";
"telegram_location_unavailable" = "The location at capture time is unavailable.";
"telegram_location_error" = "The Mac location could not be obtained.";
"telegram_location_send_error" = "The photo was sent, but the Telegram map location could not be sent.";
```

For each of the other 8 files (`da`, `de`, `ja`, `nb`, `sv`, `tr`, `zh-Hans`, `zh-Hant`):

1. **Remove** the 17 old keys: `telegram`, `telegram_enable`, `telegram_configure`, `telegram_test`, `telegram_events`, `telegram_take_photo`, `telegram_attach_mac_location`, `telegram_status_not_configured`, `telegram_status_enabled`, `telegram_status_disabled`, `telegram_save`, `telegram_test_success`, `telegram_test_failed`, `telegram_error_not_configured`, `telegram_error_settings_unavailable`, `telegram_error_file_cleanup`, `telegram_failure_notification_subtitle`.
2. **Add** the corresponding new key with the translated value from that file's old value. Where the semantics changed, translate the new Base English value: `notifications`, `notification_enable`, `notification_error_not_configured` ("Configure the selected notification channel first."), `notification_error_settings_unavailable` ("Notification settings could not be read."), `notification_failure_notification_subtitle` ("Notification failed"). The remaining renamed keys reuse the existing translated value verbatim (`notification_configure`, `notification_test`, `notification_events`, `notification_take_photo`, `notification_attach_mac_location`, `notification_status_not_configured`, `notification_status_enabled`, `notification_status_disabled`, `notification_save`, `notification_test_success`, `notification_test_failed`, `notification_error_file_cleanup`).
3. **Add** the 21 new keys (`notification_channel`, `notification_channel_telegram`, `notification_channel_synology_chat`, `notification_camera_privacy_synology`, `synology_webhook_url`, `synology_username`, `synology_password`, `synology_channel_id`, `synology_setup_help`, and the 8 `synology_error_*` keys) translated into that language following the style of its existing `telegram_*` entries (e.g. Japanese uses polite 〜します/〜できません phrasing; keep the same terminology used for "Telegram" entries, substituting "Synology Chat" / "Synology Chat通知" as appropriate). The `%d` format specifiers must be preserved.
4. Keep all 30 unchanged `telegram_*` keys exactly as they are.

- [ ] **Step 9: Rewrite `BLEUnlockTests/LocalizationTests.swift`**

Replace the `telegramKeys` set (lines 6-28) and the related tests with this version:

```swift
import Foundation
import XCTest
@testable import BLEUnlock

final class LocalizationTests: XCTestCase {
    private let telegramKeys: Set<String> = [
        "telegram_event_away", "telegram_event_lost",
        "telegram_event_unlocked", "telegram_event_intruded",
        "telegram_bot_token", "telegram_chat_id", "telegram_setup_help",
        "telegram_camera_privacy",
        "telegram_camera_error_denied", "telegram_camera_error_restricted",
        "telegram_camera_error_no_camera", "telegram_camera_error_setup_failed",
        "telegram_camera_error_capture_failed", "telegram_camera_error_timeout",
        "telegram_camera_error_file_write_failed",
        "telegram_error_invalid_request", "telegram_error_unreadable_photo",
        "telegram_error_transport", "telegram_error_http_status",
        "telegram_error_rejected", "telegram_error_invalid_response",
        "telegram_error_keychain_status",
        "telegram_message_time", "telegram_message_rssi",
        "telegram_message_coordinates", "telegram_message_accuracy",
        "telegram_message_map", "telegram_location_unavailable",
        "telegram_location_error", "telegram_location_send_error"
    ]

    private let notificationKeys: Set<String> = [
        "notifications", "notification_channel",
        "notification_channel_telegram", "notification_channel_synology_chat",
        "notification_enable", "notification_configure", "notification_test",
        "notification_events", "notification_take_photo",
        "notification_attach_mac_location", "notification_status_not_configured",
        "notification_status_enabled", "notification_status_disabled",
        "notification_save", "notification_test_success", "notification_test_failed",
        "notification_error_not_configured", "notification_error_settings_unavailable",
        "notification_error_file_cleanup", "notification_failure_notification_subtitle",
        "notification_camera_privacy_synology"
    ]

    private let synologyKeys: Set<String> = [
        "synology_webhook_url", "synology_username", "synology_password",
        "synology_channel_id", "synology_setup_help",
        "synology_error_invalid_request", "synology_error_transport",
        "synology_error_http_status", "synology_error_invalid_response",
        "synology_error_login", "synology_error_upload", "synology_error_post",
        "synology_error_settings_unavailable"
    ]

    private var allKeys: Set<String> {
        telegramKeys.union(notificationKeys).union(synologyKeys)
    }

    private let localizationDirectories = [
        "Base", "da", "de", "ja", "nb", "sv", "tr", "zh-Hans", "zh-Hant"
    ]
    private let concreteTelegramEventKeys: Set<String> = [
        "telegram_event_away", "telegram_event_lost",
        "telegram_event_unlocked", "telegram_event_intruded"
    ]
    private let dynamicTelegramEventReference = #"telegram_event_\(event.rawValue)"#

    private var repository: URL {
        URL(fileURLWithPath: #file)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    func testEveryLocalizationContainsAllKeys() throws {
        for name in localizationDirectories {
            let url = repository.appendingPathComponent("BLEUnlock/\(name).lproj/Localizable.strings")
            let values = try strings(at: url)
            XCTAssertTrue(allKeys.subtracting(values.keys).isEmpty, "Missing keys in \(name)")
            for key in allKeys {
                let value = try XCTUnwrap(values[key], "Missing \(key) in \(name)")
                XCTAssertFalse(value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                               "Empty \(key) in \(name)")
                XCTAssertNotEqual(value, key, "Raw localization key in \(name)")
            }
        }
    }

    func testEveryNonBaseLocalizationContainsAllAboutBoxTitles() throws {
        let expectedKeys: Set<String> = [
            "VLW-23-BX0.title", "WIg-Gy-UeI.title",
            "fPY-L3-Edh.title", "hgX-Z1-8qq.title"
        ]

        for name in localizationDirectories where name != "Base" {
            let url = repository.appendingPathComponent("BLEUnlock/\(name).lproj/AboutBox.strings")
            let values = try strings(at: url)
            XCTAssertTrue(expectedKeys.subtracting(values.keys).isEmpty,
                          "Missing AboutBox keys in \(name)")
        }
    }

    func testCameraPrivacyTextStatesTheCompleteDataFlow() throws {
        let values = try strings(at: repository.appendingPathComponent(
            "BLEUnlock/Base.lproj/Localizable.strings"
        ))
        let privacy = try XCTUnwrap(values["telegram_camera_privacy"]).lowercased()

        for phrase in ["system default camera", "upload", "telegram", "deleted", "text"] {
            XCTAssertTrue(privacy.contains(phrase),
                          "Camera privacy text must mention \(phrase)")
        }
    }

    func testSynologyCameraPrivacyTextStatesTheCompleteDataFlow() throws {
        let values = try strings(at: repository.appendingPathComponent(
            "BLEUnlock/Base.lproj/Localizable.strings"
        ))
        let privacy = try XCTUnwrap(values["notification_camera_privacy_synology"]).lowercased()

        for phrase in ["system default camera", "upload", "synology chat", "deleted", "text"] {
            XCTAssertTrue(privacy.contains(phrase),
                          "Synology camera privacy text must mention \(phrase)")
        }
    }

    func testEveryLocalizationContainsCameraUsageDescription() throws {
        for name in localizationDirectories {
            let url = repository.appendingPathComponent("BLEUnlock/\(name).lproj/InfoPlist.strings")
            let values = try strings(at: url)
            let description = try XCTUnwrap(values["NSCameraUsageDescription"],
                                            "Missing NSCameraUsageDescription in \(name)")
            XCTAssertFalse(description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            XCTAssertNotEqual(description, "NSCameraUsageDescription")
        }
    }

    func testEveryLocalizationContainsExactLocationUsageDescription() throws {
        let expectedDescriptions = [
            "Base": "BLEUnlock gets this Mac's location at capture time and attaches the coordinates and map to the Telegram security notification.",
            "da": "BLEUnlock henter denne Macs placering på optagelsestidspunktet og vedhæfter koordinater og kort til Telegram-sikkerhedsmeddelelsen.",
            "de": "BLEUnlock ermittelt den Standort dieses Macs zum Aufnahmezeitpunkt und fügt Koordinaten und Karte der Telegram-Sicherheitsmeldung hinzu.",
            "ja": "BLEUnlockは撮影時のこのMacの位置情報を取得し、座標と地図をTelegramのセキュリティ通知に添付します。",
            "nb": "BLEUnlock henter posisjonen til denne Macen på opptakstidspunktet og legger ved koordinater og kart i Telegram-sikkerhetsvarslet.",
            "sv": "BLEUnlock hämtar den här Mac-datorns plats när fotot tas och bifogar koordinater och karta till Telegram-säkerhetsnotisen.",
            "tr": "BLEUnlock fotoğraf çekildiğinde bu Mac'in konumunu alır ve koordinatlarla haritayı Telegram güvenlik bildirimine ekler.",
            "zh-Hans": "BLEUnlock 获取这台 Mac 拍照时的位置，并将坐标和地图附加到 Telegram 安全通知。",
            "zh-Hant": "BLEUnlock 取得這部 Mac 拍照當時的位置，並將座標與地圖附加到 Telegram 安全通知。"
        ]

        for name in localizationDirectories {
            let url = repository.appendingPathComponent("BLEUnlock/\(name).lproj/InfoPlist.strings")
            let values = try strings(at: url)
            let description = try XCTUnwrap(values["NSLocationUsageDescription"],
                                            "Missing NSLocationUsageDescription in \(name)")
            XCTAssertFalse(description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            XCTAssertEqual(description, expectedDescriptions[name])
        }
    }

    func testBaseInfoPlistContainsMacLocationUsageDescriptionOnly() throws {
        let url = repository.appendingPathComponent("BLEUnlock/Info.plist")
        let values = try XCTUnwrap(
            PropertyListSerialization.propertyList(from: Data(contentsOf: url),
                                                   options: [],
                                                   format: nil) as? [String: Any]
        )

        XCTAssertEqual(values["NSLocationUsageDescription"] as? String,
                       "BLEUnlock gets this Mac's location at capture time and attaches the coordinates and map to the Telegram security notification.")
        XCTAssertNil(values["NSLocationAlwaysUsageDescription"])
        XCTAssertNil(values["NSLocationAlwaysAndWhenInUseUsageDescription"])
        XCTAssertNil(values["NSLocationWhenInUseUsageDescription"])
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

    func testOnlyAppBuildConfigurationsEnableLocationResourceAccess() throws {
        let source = try String(contentsOf: repository.appendingPathComponent(
            "BLEUnlock.xcodeproj/project.pbxproj"
        ))
        let appConfigurations = ["3DD4B65F226C1C3400451B7B", "3DD4B660226C1C3400451B7B"]
        let otherTargetConfigurations = [
            "3D600A4C22701A5C0068FB7B", "3D600A4D22701A5C0068FB7B",
            "7E1000193000000000000001", "7E1000203000000000000001"
        ]

        XCTAssertEqual(source.components(separatedBy: "ENABLE_RESOURCE_ACCESS_LOCATION = YES;").count - 1,
                       2)
        for identifier in appConfigurations {
            XCTAssertTrue(try buildConfiguration(identifier, in: source)
                .contains("ENABLE_RESOURCE_ACCESS_LOCATION = YES;"))
        }
        for identifier in otherTargetConfigurations {
            XCTAssertFalse(try buildConfiguration(identifier, in: source)
                .contains("ENABLE_RESOURCE_ACCESS_LOCATION"))
        }
    }

    func testProductionNotificationLocalizationReferencesAreCovered() throws {
        let generatedEventKeys = Set(NotificationEvent.allCases.map {
            "telegram_event_\($0.rawValue)"
        })
        XCTAssertEqual(generatedEventKeys, concreteTelegramEventKeys,
                       "Every finite NotificationEvent value must have an explicit localization key")
        XCTAssertTrue(generatedEventKeys.isSubset(of: telegramKeys))

        let sourceFiles = [
            "CameraCapture.swift", "KeychainStore.swift", "NotificationMenuController.swift",
            "NotificationService.swift", "TelegramNotifier.swift"
        ]
        let expression = try NSRegularExpression(
            pattern: #"(?:t|NSLocalizedString)\("((?:telegram|notification|synology)_[^\"]+)"#
        )
        var referencedKeys: Set<String> = []

        for name in sourceFiles {
            let source = try String(contentsOf: repository.appendingPathComponent("BLEUnlock/\(name)"))
            let range = NSRange(source.startIndex..., in: source)
            for match in expression.matches(in: source, range: range) {
                guard let keyRange = Range(match.range(at: 1), in: source) else { continue }
                let key = String(source[keyRange])
                if key == dynamicTelegramEventReference {
                    referencedKeys.formUnion(generatedEventKeys)
                } else {
                    XCTAssertFalse(key.contains(#"\("#),
                                   "Unrecognized dynamic localization reference: \(key)")
                    referencedKeys.insert(key)
                }
            }
        }

        XCTAssertTrue(referencedKeys.isSubset(of: allKeys),
                      "Production keys missing from completeness set: \(referencedKeys.subtracting(allKeys))")
    }

    func testNotificationSourcesDoNotContainHardCodedEnglishErrorsOrLabels() throws {
        let files = ["CameraCapture.swift", "KeychainStore.swift",
                     "NotificationService.swift", "TelegramNotifier.swift"]
        let source = try files.map {
            try String(contentsOf: repository.appendingPathComponent("BLEUnlock/\($0)"))
        }.joined(separator: "\n")
        let forbidden = [
            "Camera access was denied.", "Camera access is restricted.",
            "No camera is available.", "The camera could not be configured.",
            "The camera could not capture a photo.", "The camera capture timed out.",
            "The captured photo could not be saved.",
            "The Telegram request could not be created.",
            "The captured photo could not be read.", "Telegram could not be reached.",
            "Telegram returned HTTP status", "Telegram returned an invalid response.",
            "Telegram notification failed", "Telegram settings could not be read.",
            "The captured photo could not be deleted.", "Keychain operation failed",
            "The Synology Chat request could not be created.",
            "The Synology Chat server could not be reached.",
            "The Synology Chat server returned HTTP status",
            "The Synology Chat server returned an invalid response.",
            "Synology Chat login failed.", "The photo could not be uploaded to Synology Chat.",
            "The message could not be posted to Synology Chat.",
            "Synology Chat settings could not be read.",
            "Notification settings could not be read.", "Notification failed"
        ]

        for text in forbidden {
            XCTAssertFalse(source.contains(text), "Hard-coded user-visible text: \(text)")
        }
    }

    private func strings(at url: URL) throws -> [String: String] {
        let data = try Data(contentsOf: url)
        let plist = try PropertyListSerialization.propertyList(from: data,
                                                               options: [],
                                                               format: nil)
        return try XCTUnwrap(plist as? [String: String])
    }

    private func buildConfiguration(_ identifier: String, in source: String) throws -> Substring {
        let start = try XCTUnwrap(source.range(of: "\(identifier) /*"))
        let suffix = source[start.lowerBound...]
        let end = try XCTUnwrap(suffix.range(of: "\n\t\t};"))
        return suffix[..<end.upperBound]
    }
}
```

- [ ] **Step 10: Update `BLEUnlock.xcodeproj/project.pbxproj` for the 7 file renames**

For each `PBXFileReference` below, change only its `path` value (and the matching comment text, which is cosmetic) to the new file name. The `PBXBuildFile` entries keep their IDs — update only their `/* ... */` comment text:

| PBXFileReference ID | old path → new path |
|---|---|
| `7E1000213000000000000001` | `TelegramEvent.swift` → `NotificationEvent.swift` |
| `7E1000223000000000000001` | `TelegramSettings.swift` → `NotificationSettings.swift` |
| `7E10002C3000000000000001` | `TelegramNotificationService.swift` → `NotificationService.swift` |
| `7E1000313000000000000001` | `TelegramMenuController.swift` → `NotificationMenuController.swift` |
| `7E1000113000000000000001` | `TelegramSettingsTests.swift` → `NotificationSettingsTests.swift` |
| `7E10002E3000000000000001` | `TelegramNotificationServiceTests.swift` → `NotificationServiceTests.swift` |
| `7E10002F3000000000000001` | `TelegramMenuControllerTests.swift` → `NotificationMenuControllerTests.swift` |

- [ ] **Step 11: Run the full test suite**

Run: `xcodebuild test -scheme BLEUnlock -destination 'platform=macOS'`
Expected: all tests PASS (behavior unchanged — this task only renames).

- [ ] **Step 12: Commit**

```bash
git add -A
git commit -m "refactor: rename Telegram notification types to Notification
```

---

## Task 2: SynologyNotifier (webhook text + SYNO.Chat.Post photo flow)

**Files:**
- Create: `BLEUnlock/SynologyNotifier.swift`
- Modify: `BLEUnlock/TelegramNotifier.swift` (make `Data` multipart helpers `internal`)
- Create: `BLEUnlockTests/SynologyNotifierTests.swift`
- Modify: `BLEUnlockTests/TestDoubles.swift` (add `QueuedHTTPTransport`)
- Modify: `BLEUnlockTests/LocalizationTests.swift` (add `SynologyNotifier.swift` to the source scan + forbidden-files lists)
- Modify: `BLEUnlock.xcodeproj/project.pbxproj` (add the two new files)

- [ ] **Step 1: Write the failing test file `BLEUnlockTests/SynologyNotifierTests.swift`**

```swift
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
            .success((Data(#"{"success":true,"data":{"file_id":"file-123"}}"#.utf8), response())),
            .success((Data(#"{"success":true,"data":{"post_id":"post-1"}}"#.utf8), response()))
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
        var query = try XCTUnwrap(URLComponents(url: try XCTUnwrap(login.url), resolvingAgainstBaseURL: false).queryItems)
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
        query = try XCTUnwrap(URLComponents(url: try XCTUnwrap(upload.url), resolvingAgainstBaseURL: false).queryItems)
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
        XCTAssertTrue(body.contains(photoBytes))

        let post = transport.requests[2]
        XCTAssertEqual(post.url?.path, "/webapi/entry.cgi")
        query = try XCTUnwrap(URLComponents(url: try XCTUnwrap(post.url), resolvingAgainstBaseURL: false).queryItems)
        XCTAssertEqual(query.first(where: { $0.name == "_sid" })?.value, "sid-SECRET")
        XCTAssertEqual(post.value(forHTTPHeaderField: "X-SYNO-TOKEN"), "token-SECRET")
        let postBody = String(decoding: try XCTUnwrap(post.httpBody), as: UTF8.self)
        XCTAssertTrue(postBody.contains("file_id=file-123"))
        XCTAssertTrue(postBody.contains("message=Door%20opened"))
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

    func testSendPhotoPostFailureMapsToPostFailed() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let photoURL = directory.appendingPathComponent("capture.jpg")
        try Data([0xFF, 0xD8, 0xFF, 0xD9]).write(to: photoURL)

        transport.results = [
            .success((Data(#"{"success":true,"data":{"sid":"sid-SECRET","synotoken":"token-SECRET"}}"#.utf8), response())),
            .success((Data(#"{"success":true,"data":{"file_id":"file-123"}}"#.utf8), response())),
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
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `xcodebuild test -scheme BLEUnlock -destination 'platform=macOS'`
Expected: the build FAILS (or `SynologyNotifierTests` errors) because `SynologyNotifier`, `SynologySending`, `SynologyCredentials`, `SynologyError`, and `QueuedHTTPTransport` do not exist yet.

- [ ] **Step 3: Add `QueuedHTTPTransport` to `BLEUnlockTests/TestDoubles.swift`**

Append to `TestDoubles.swift`:

```swift
final class QueuedHTTPTransport: HTTPTransport {
    var requests: [URLRequest] = []
    var results: [Result<(Data, HTTPURLResponse), Error>] = []

    func perform(_ request: URLRequest,
                 completion: @escaping (Result<(Data, HTTPURLResponse), Error>) -> Void) {
        requests.append(request)
        if results.isEmpty {
            completion(.failure(NSError(domain: "QueuedHTTPTransport", code: -1)))
        } else {
            completion(results.removeFirst())
        }
    }
}
```

- [ ] **Step 4: Make the multipart helpers reusable in `BLEUnlock/TelegramNotifier.swift`**

Change `private extension Data {` to `extension Data {` (line 202). The two methods `appendMultipartField(name:value:boundary:)` and `appendMultipartFile(name:filename:mimeType:bytes:boundary:)` then become internal.

- [ ] **Step 5: Write the minimal `BLEUnlock/SynologyNotifier.swift`**

```swift
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
    let file_id: String?
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
                guard let decoded = try? JSONDecoder().decode(SynologySuccessResponse.self, from: data),
                      decoded.success else {
                    completion(.failure(.invalidResponse))
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
                              let fileID = decoded.data?.file_id, !fileID.isEmpty else {
                            completion(.failure(.uploadFailed))
                            return
                        }
                        guard let postRequest = self.makePostRequest(baseURL: baseURL,
                                                                     session: session,
                                                                     credentials: credentials,
                                                                     caption: caption,
                                                                     fileID: fileID) else {
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
                                 caption: String,
                                 fileID: String) -> URLRequest? {
        guard let url = entryURL(baseURL: baseURL,
                                 session: session,
                                 channelID: credentials.channelID) else { return nil }
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue(session.synoToken, forHTTPHeaderField: "X-SYNO-TOKEN")
        request.httpBody = formEncoded([
            ("message", caption),
            ("file_id", fileID)
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
```

Note: `SynologyError` never propagates raw server text, so credentials, the sid, and the token can never appear in error descriptions or `String(describing:)` output.

- [ ] **Step 6: Add `SynologyNotifier.swift` to `BLEUnlock.xcodeproj/project.pbxproj`**

Add these entries using unused PBX IDs (verify no collision first with `grep -c "7E1000543000000000000001" BLEUnlock.xcodeproj/project.pbxproj`):

1. `PBXFileReference` (add near the other app source file references, ~line 141):
```
7E1000543000000000000001 /* SynologyNotifier.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = SynologyNotifier.swift; sourceTree = "<group>"; };
```
2. `PBXBuildFile` (add near the other app source build files, ~line 51):
```
7E1000553000000000000001 /* SynologyNotifier.swift in Sources */ = {isa = PBXBuildFile; fileRef = 7E1000543000000000000001 /* SynologyNotifier.swift */; };
```
3. Add `7E1000543000000000000001 /* SynologyNotifier.swift */,` to the app source group (after the `TelegramNotifier.swift` group entry, ~line 238).
4. Add `7E1000553000000000000001 /* SynologyNotifier.swift in Sources */,` to the App `Sources` build phase (after the `TelegramNotifier.swift in Sources` entry, ~line 467).
5. Add `BLEUnlockTests/SynologyNotifierTests.swift` the same way with IDs `7E1000563000000000000001` (PBXFileReference) and `7E1000573000000000000001` (PBXBuildFile): add the file reference near line 141, the build file near line 51, the group entry after `TelegramNotifierTests.swift` (~line 286), and the `Sources` phase entry after `TelegramNotifierTests.swift in Sources` (~line 495).

- [ ] **Step 7: Update `BLEUnlockTests/LocalizationTests.swift` to scan `SynologyNotifier.swift`**

In `testProductionNotificationLocalizationReferencesAreCovered`, change the `sourceFiles` array to include `"SynologyNotifier.swift"` after `"NotificationService.swift"`. In `testNotificationSourcesDoNotContainHardCodedEnglishErrorsOrLabels`, add `"SynologyNotifier.swift"` to the `files` array.

- [ ] **Step 8: Run the tests**

Run: `xcodebuild test -scheme BLEUnlock -destination 'platform=macOS'`
Expected: `SynologyNotifierTests` PASS; all other tests PASS.

- [ ] **Step 9: Commit**

```bash
git add -A
git commit -m "feat: add Synology Chat notifier (webhook text + SYNO.Chat.Post photo flow)"
```

---

## Task 3: Per-channel NotificationSettings (selected channel + per-channel preferences + Synology storage)

**Files:**
- Modify: `BLEUnlock/NotificationSettings.swift` (add `NotificationChannel`, selected-channel view, per-channel methods, Synology credential methods)
- Modify: `BLEUnlock/AppDelegate.swift` (construct `NotificationSettings` with two Keychain services)
- Modify: `BLEUnlockTests/NotificationSettingsTests.swift` (rewrite for the per-channel API)
- Test: full suite

- [ ] **Step 1: Write the failing tests — replace `BLEUnlockTests/NotificationSettingsTests.swift`**

```swift
import XCTest
@testable import BLEUnlock

final class NotificationSettingsTests: XCTestCase {
    private var defaultsSuiteName: String!
    private var defaults: UserDefaults!
    private var telegramSecrets: MemorySecretStore!
    private var synologySecrets: MemorySecretStore!

    override func setUp() {
        super.setUp()
        defaultsSuiteName = "jp.sone.BLEUnlockTests.NotificationSettings.\(UUID())"
        defaults = UserDefaults(suiteName: defaultsSuiteName)!
        defaults.removePersistentDomain(forName: defaultsSuiteName)
        telegramSecrets = MemorySecretStore()
        synologySecrets = MemorySecretStore()
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: defaultsSuiteName)
        defaultsSuiteName = nil
        defaults = nil
        telegramSecrets = nil
        synologySecrets = nil
        super.tearDown()
    }

    private func makeSettings() -> NotificationSettings {
        NotificationSettings(defaults: defaults,
                             telegramSecrets: telegramSecrets,
                             synologySecrets: synologySecrets)
    }

    func testDefaultsSelectTelegramWithApprovedEventChoices() throws {
        let settings = makeSettings()

        XCTAssertEqual(settings.selectedChannel, .telegram)
        XCTAssertFalse(settings.isEnabled(.telegram))
        XCTAssertTrue(settings.isEventEnabled(.away))
        XCTAssertTrue(settings.isEventEnabled(.lost))
        XCTAssertFalse(settings.isEventEnabled(.unlocked))
        XCTAssertTrue(settings.isEventEnabled(.intruded))
        XCTAssertTrue(settings.takePhotoOnIntruded(.telegram))
        XCTAssertFalse(try settings.isConfigured(.telegram))
        XCTAssertFalse(try settings.isConfigured(.synologyChat))
    }

    func testChannelSelectionPersists() {
        let settings = makeSettings()
        settings.selectedChannel = .synologyChat

        XCTAssertEqual(makeSettings().selectedChannel, .synologyChat)
    }

    func testPerChannelPreferencesAreIndependent() throws {
        let settings = makeSettings()
        settings.setEnabled(true, for: .telegram)
        settings.setTakePhotoOnIntruded(false, for: .telegram)
        settings.setAttachMacLocation(true, for: .telegram)
        settings.setEnabled(true, for: .synologyChat)
        settings.setTakePhotoOnIntruded(false, for: .synologyChat)
        settings.setAttachMacLocation(true, for: .synologyChat)

        let reloaded = makeSettings()
        XCTAssertTrue(reloaded.isEnabled(.telegram))
        XCTAssertFalse(reloaded.takePhotoOnIntruded(.telegram))
        XCTAssertTrue(reloaded.attachMacLocation(.telegram))
        XCTAssertTrue(reloaded.isEnabled(.synologyChat))
        XCTAssertFalse(reloaded.takePhotoOnIntruded(.synologyChat))
        XCTAssertTrue(reloaded.attachMacLocation(.synologyChat))
    }

    func testSynologyDefaultsMatchTelegram() {
        let settings = makeSettings()

        XCTAssertFalse(settings.isEnabled(.synologyChat))
        XCTAssertTrue(settings.takePhotoOnIntruded(.synologyChat))
        XCTAssertFalse(settings.attachMacLocation(.synologyChat))
    }

    func testEventsAreSharedAcrossChannels() throws {
        let settings = makeSettings()
        settings.setEvent(.away, enabled: false)

        XCTAssertFalse(makeSettings().isEventEnabled(.away))
        XCTAssertTrue(settings.isEventEnabled(.lost))
    }

    func testTelegramReusesLegacyUserDefaultsKeysForNoMigration() throws {
        defaults.set(true, forKey: "telegram.enabled")
        defaults.set(false, forKey: "telegram.takePhotoOnIntruded")
        defaults.set(true, forKey: "telegram.attachMacLocation")

        let settings = makeSettings()
        XCTAssertTrue(settings.isEnabled(.telegram))
        XCTAssertFalse(settings.takePhotoOnIntruded(.telegram))
        XCTAssertTrue(settings.attachMacLocation(.telegram))
    }

    func testSynologyUsesNewKeysInDefaults() throws {
        let settings = makeSettings()
        settings.setEnabled(true, for: .synologyChat)
        settings.setTakePhotoOnIntruded(false, for: .synologyChat)

        XCTAssertTrue(defaults.bool(forKey: "notification.enabled.synologyChat"))
        XCTAssertFalse(defaults.bool(forKey: "notification.takePhoto.synologyChat"))
        XCTAssertNil(defaults.object(forKey: "telegram.enabled") as? Bool)
        XCTAssertNil(defaults.object(forKey: "telegram.takePhotoOnIntruded") as? Bool)
    }

    func testPersistsTelegramSwitchesAndCredentials() throws {
        let settings = makeSettings()
        settings.setEnabled(true, for: .telegram)
        settings.setEvent(.away, enabled: false)
        settings.setTakePhotoOnIntruded(false, for: .telegram)
        try settings.saveTelegramCredentials(replacementToken: "token-123", chatID: "987654")

        let reloaded = makeSettings()
        XCTAssertTrue(reloaded.isEnabled(.telegram))
        XCTAssertFalse(reloaded.isEventEnabled(.away))
        XCTAssertFalse(reloaded.takePhotoOnIntruded(.telegram))
        XCTAssertEqual(try reloaded.telegramCredentials(),
                       TelegramCredentials(token: "token-123", chatID: "987654"))
    }

    func testTelegramCredentialsUseLegacyKeychainAccounts() throws {
        telegramSecrets.values = ["botToken": "token-123", "chatID": "987654"]
        XCTAssertEqual(try makeSettings().telegramCredentials(),
                       TelegramCredentials(token: "token-123", chatID: "987654"))
    }

    func testBlankOrNilReplacementPreservesStoredTelegramToken() throws {
        let settings = makeSettings()
        try settings.saveTelegramCredentials(replacementToken: "original", chatID: "old-chat")

        try settings.saveTelegramCredentials(replacementToken: "  \n", chatID: "new-chat")
        XCTAssertEqual(try settings.telegramCredentials(),
                       TelegramCredentials(token: "original", chatID: "new-chat"))

        try settings.saveTelegramCredentials(replacementToken: nil, chatID: "newest-chat")
        XCTAssertEqual(try settings.telegramCredentials(),
                       TelegramCredentials(token: "original", chatID: "newest-chat"))
    }

    func testSynologyCredentialsRoundTrip() throws {
        let settings = makeSettings()
        try settings.saveSynologyCredentials(webhookURL: "https://nas.local/webapi/entry.cgi?token=w",
                                             username: "admin",
                                             password: "pw",
                                             channelID: "42")

        XCTAssertEqual(try makeSettings().synologyCredentials(),
                       SynologyCredentials(webhookURL: "https://nas.local/webapi/entry.cgi?token=w",
                                           username: "admin",
                                           password: "pw",
                                           channelID: "42"))
    }

    func testBlankSynologyPasswordPreservesStoredPassword() throws {
        let settings = makeSettings()
        try settings.saveSynologyCredentials(webhookURL: "https://nas.local",
                                             username: "admin",
                                             password: "secret",
                                             channelID: "1")
        try settings.saveSynologyCredentials(webhookURL: "https://nas.local",
                                             username: "admin",
                                             password: "   ",
                                             channelID: "2")

        let credentials = try settings.synologyCredentials()
        XCTAssertEqual(credentials?.password, "secret")
        XCTAssertEqual(credentials?.channelID, "2")
    }

    func testSynologyIsConfiguredOnlyWhenAllCredentialsPresent() throws {
        let settings = makeSettings()
        XCTAssertFalse(try settings.isConfigured(.synologyChat))

        try settings.saveSynologyCredentials(webhookURL: "https://nas.local",
                                             username: "u",
                                             password: "p",
                                             channelID: "1")
        XCTAssertTrue(try settings.isConfigured(.synologyChat))
    }

    func testTelegramConfiguredOnlyWhenBothCredentialsPresent() throws {
        let settings = makeSettings()
        XCTAssertFalse(try settings.isConfigured(.telegram))

        try settings.saveTelegramCredentials(replacementToken: "t", chatID: "c")
        XCTAssertTrue(try settings.isConfigured(.telegram))
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `xcodebuild test -scheme BLEUnlock -destination 'platform=macOS'`
Expected: build FAILS — `NotificationSettings` has no `NotificationChannel`, no `selectedChannel`, and the init still takes a single `secrets:` parameter.

- [ ] **Step 3: Replace the contents of `BLEUnlock/NotificationSettings.swift`**

```swift
import Foundation

protocol SecretStoring {
    func string(for account: String) throws -> String?
    func set(_ value: String, for account: String) throws
    func removeValue(for account: String) throws
}

enum NotificationChannel: String, CaseIterable {
    case telegram
    case synologyChat
}

final class NotificationSettings {
    private enum Key {
        static let channel = "notification.channel"

        static let telegramEnabled = "telegram.enabled"
        static let telegramTakePhoto = "telegram.takePhotoOnIntruded"
        static let telegramAttachMacLocation = "telegram.attachMacLocation"

        static let synologyEnabled = "notification.enabled.synologyChat"
        static let synologyTakePhoto = "notification.takePhoto.synologyChat"
        static let synologyAttachMacLocation = "notification.attachLocation.synologyChat"

        static let telegramToken = "botToken"
        static let telegramChatID = "chatID"

        static let synologyWebhookURL = "webhookURL"
        static let synologyUsername = "username"
        static let synologyPassword = "password"
        static let synologyChannelID = "channelID"
    }

    private let defaults: UserDefaults
    private let telegramSecrets: SecretStoring
    private let synologySecrets: SecretStoring

    init(defaults: UserDefaults = .standard,
         telegramSecrets: SecretStoring,
         synologySecrets: SecretStoring) {
        self.defaults = defaults
        self.telegramSecrets = telegramSecrets
        self.synologySecrets = synologySecrets
    }

    var selectedChannel: NotificationChannel {
        get {
            NotificationChannel(rawValue: defaults.string(forKey: Key.channel) ?? "")
                ?? .telegram
        }
        set { defaults.set(newValue.rawValue, forKey: Key.channel) }
    }

    func isEnabled(_ channel: NotificationChannel) -> Bool {
        defaults.bool(forKey: channel == .telegram ? Key.telegramEnabled : Key.synologyEnabled)
    }

    func setEnabled(_ enabled: Bool, for channel: NotificationChannel) {
        defaults.set(enabled,
                     forKey: channel == .telegram ? Key.telegramEnabled : Key.synologyEnabled)
    }

    func takePhotoOnIntruded(_ channel: NotificationChannel) -> Bool {
        let key = channel == .telegram ? Key.telegramTakePhoto : Key.synologyTakePhoto
        return defaults.object(forKey: key) as? Bool ?? true
    }

    func setTakePhotoOnIntruded(_ enabled: Bool, for channel: NotificationChannel) {
        defaults.set(enabled,
                     forKey: channel == .telegram ? Key.telegramTakePhoto : Key.synologyTakePhoto)
    }

    func attachMacLocation(_ channel: NotificationChannel) -> Bool {
        let key = channel == .telegram ? Key.telegramAttachMacLocation : Key.synologyAttachMacLocation
        return defaults.object(forKey: key) as? Bool ?? false
    }

    func setAttachMacLocation(_ enabled: Bool, for channel: NotificationChannel) {
        defaults.set(enabled,
                     forKey: channel == .telegram ? Key.telegramAttachMacLocation : Key.synologyAttachMacLocation)
    }

    func isEventEnabled(_ event: NotificationEvent) -> Bool {
        defaults.object(forKey: event.defaultsKey) as? Bool ?? event.defaultEnabled
    }

    func setEvent(_ event: NotificationEvent, enabled: Bool) {
        defaults.set(enabled, forKey: event.defaultsKey)
    }

    func isConfigured(_ channel: NotificationChannel) throws -> Bool {
        switch channel {
        case .telegram: return try telegramCredentials() != nil
        case .synologyChat: return try synologyCredentials() != nil
        }
    }

    func telegramCredentials() throws -> TelegramCredentials? {
        guard let token = try telegramSecrets.string(for: Key.telegramToken), !token.isEmpty,
              let chatID = try telegramSecrets.string(for: Key.telegramChatID), !chatID.isEmpty else { return nil }
        return TelegramCredentials(token: token, chatID: chatID)
    }

    func saveTelegramCredentials(replacementToken: String?, chatID: String) throws {
        let replacement = replacementToken?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let replacement = replacement, !replacement.isEmpty {
            try telegramSecrets.set(replacement, for: Key.telegramToken)
        }
        try telegramSecrets.set(chatID.trimmingCharacters(in: .whitespacesAndNewlines),
                                for: Key.telegramChatID)
    }

    func synologyCredentials() throws -> SynologyCredentials? {
        guard let webhookURL = try synologySecrets.string(for: Key.synologyWebhookURL),
              !webhookURL.isEmpty,
              let username = try synologySecrets.string(for: Key.synologyUsername),
              !username.isEmpty,
              let password = try synologySecrets.string(for: Key.synologyPassword),
              !password.isEmpty,
              let channelID = try synologySecrets.string(for: Key.synologyChannelID),
              !channelID.isEmpty else { return nil }
        return SynologyCredentials(webhookURL: webhookURL,
                                   username: username,
                                   password: password,
                                   channelID: channelID)
    }

    func saveSynologyCredentials(webhookURL: String,
                                 username: String,
                                 password: String?,
                                 channelID: String) throws {
        try synologySecrets.set(webhookURL.trimmingCharacters(in: .whitespacesAndNewlines),
                                for: Key.synologyWebhookURL)
        try synologySecrets.set(username.trimmingCharacters(in: .whitespacesAndNewlines),
                                for: Key.synologyUsername)
        if let password = password?.trimmingCharacters(in: .whitespacesAndNewlines),
           !password.isEmpty {
            try synologySecrets.set(password, for: Key.synologyPassword)
        }
        try synologySecrets.set(channelID.trimmingCharacters(in: .whitespacesAndNewlines),
                                for: Key.synologyChannelID)
    }
}
```

- [ ] **Step 4: Update `BLEUnlock/AppDelegate.swift` construction**

Replace:
```swift
let notificationSettings = NotificationSettings(
    secrets: KeychainStore(service: "jp.sone.BLEUnlock.telegram")
)
```
with:
```swift
let notificationSettings = NotificationSettings(
    defaults: .standard,
    telegramSecrets: KeychainStore(service: "jp.sone.BLEUnlock.telegram"),
    synologySecrets: KeychainStore(service: "jp.sone.BLEUnlock.synology")
)
```

The `notificationService` and `notificationMenuController` still construct with the renamed-but-single-channel API; they compile unchanged because `NotificationService` and `NotificationMenuController` still use `settings.isEnabled` (selected-channel view), `settings.takePhotoOnIntruded`, `settings.attachMacLocation`, `settings.credentials()`, `settings.isConfigured()`, and `settings.saveCredentials(replacementToken:chatID:)`. **Note:** those consumers will be migrated to the per-channel API in Tasks 4 and 5; until then they keep working because `selectedChannel` defaults to `.telegram`.

- [ ] **Step 5: Run the tests**

Run: `xcodebuild test -scheme BLEUnlock -destination 'platform=macOS'`
Expected: `NotificationSettingsTests` PASS; all other tests PASS (behavior unchanged; default channel is Telegram).

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "feat: add per-channel NotificationSettings with Synology credential storage"
```

---

## Task 4: NotificationService channel routing + Synology flow

**Files:**
- Modify: `BLEUnlock/NotificationService.swift` (routing, Synology text/photo/located-photo flow, per-channel sendTest)
- Modify: `BLEUnlock/AppDelegate.swift` (pass `synologySender:` to `NotificationService`)
- Modify: `BLEUnlockTests/NotificationServiceTests.swift` (add routing + Synology tests)
- Modify: `BLEUnlockTests/TestDoubles.swift` (add `RecordingSynologySender`)
- Test: full suite

- [ ] **Step 1: Add `RecordingSynologySender` to `BLEUnlockTests/TestDoubles.swift`**

Append:

```swift
final class RecordingSynologySender: SynologySending {
    struct TextCall {
        let credentials: SynologyCredentials
        let text: String
    }

    struct PhotoCall {
        let credentials: SynologyCredentials
        let photoURL: URL
        let caption: String
    }

    var textResult: Result<Void, SynologyError> = .success(())
    var photoResult: Result<Void, SynologyError> = .success(())
    private(set) var textCalls: [TextCall] = []
    private(set) var photoCalls: [PhotoCall] = []

    func sendText(credentials: SynologyCredentials,
                  text: String,
                  completion: @escaping (Result<Void, SynologyError>) -> Void) {
        textCalls.append(.init(credentials: credentials, text: text))
        completion(textResult)
    }

    func sendPhoto(credentials: SynologyCredentials,
                   photoURL: URL,
                   caption: String,
                   completion: @escaping (Result<Void, SynologyError>) -> Void) {
        photoCalls.append(.init(credentials: credentials,
                                photoURL: photoURL,
                                caption: caption))
        completion(photoResult)
    }
}
```

- [ ] **Step 2: Write the failing routing tests — append to `BLEUnlockTests/NotificationServiceTests.swift`**

Add these test methods (and update the existing `setUp` to construct the service with both senders — see Step 5). The existing tests currently construct `TelegramNotificationService(settings:sender:camera:...)`; they must switch to `NotificationService(settings:telegramSender:synologySender:camera:...)` and the per-channel settings API (`settings.isEnabled(.telegram)` instead of `settings.isEnabled`, etc.).

New test methods:

```swift
func testSynologyChannelSendsTextForAwayEvent() throws {
    settings.selectedChannel = .synologyChat
    try configureSynology()

    service.handle(context(event: .away, rssi: -47))

    XCTAssertEqual(camera.captureCalls, 0)
    XCTAssertEqual(synologySender.photoCalls.count, 0)
    XCTAssertEqual(synologySender.textCalls.count, 1)
    let call = try XCTUnwrap(synologySender.textCalls.first)
    XCTAssertEqual(call.credentials,
                   SynologyCredentials(webhookURL: "https://nas.local",
                                       username: "user",
                                       password: "pass",
                                       channelID: "42"))
    XCTAssertTrue(call.text.contains(t("telegram_event_away")))
}

func testSynologyIntrudedWithPhotoSendsPhotoAndDeletesFile() throws {
    settings.selectedChannel = .synologyChat
    try configureSynology()
    camera.result = .success(photoURL)

    service.handle(context(event: .intruded))

    XCTAssertEqual(camera.captureCalls, 1)
    XCTAssertEqual(synologySender.photoCalls.count, 1)
    XCTAssertEqual(synologySender.photoCalls.first?.photoURL, photoURL)
    XCTAssertEqual(synologySender.textCalls.count, 0)
    XCTAssertEqual(remover.calls, [photoURL])
    XCTAssertTrue(reporter.categories.isEmpty)
}

func testSynologyPhotoUploadFailureDeletesFileWithoutTextRetry() throws {
    settings.selectedChannel = .synologyChat
    try configureSynology()
    camera.result = .success(photoURL)
    synologySender.photoResult = .failure(.uploadFailed)

    service.handle(context(event: .intruded))

    XCTAssertEqual(synologySender.photoCalls.count, 1)
    XCTAssertEqual(synologySender.textCalls.count, 0)
    XCTAssertEqual(remover.calls, [photoURL])
    XCTAssertEqual(reporter.categories, ["synology"])
}

func testSynologyCaptureFailureFallsBackToText() throws {
    settings.selectedChannel = .synologyChat
    try configureSynology()
    camera.result = .failure(.denied)

    service.handle(context(event: .intruded))

    XCTAssertEqual(synologySender.photoCalls.count, 0)
    XCTAssertEqual(synologySender.textCalls.count, 1)
    XCTAssertEqual(reporter.categories, ["camera"])
}

func testSynologyLocationEnabledIncludesMapLinkInCaptionWithoutNativeMap() throws {
    settings.selectedChannel = .synologyChat
    try configureSynology()
    settings.setAttachMacLocation(true, for: .synologyChat)
    camera.result = .success(photoURL)
    location.result = .success(.init(latitude: 25.033,
                                     longitude: 121.5654,
                                     horizontalAccuracy: 18,
                                     timestamp: Date(timeIntervalSince1970: 100)))

    service.handle(context(event: .intruded))

    XCTAssertEqual(synologySender.photoCalls.count, 1)
    XCTAssertTrue(synologySender.photoCalls[0].caption.contains("25.033000, 121.565400"))
    XCTAssertTrue(synologySender.photoCalls[0].caption.contains("maps.apple.com"))
    XCTAssertTrue(location.requestedDates.count == 1)
    XCTAssertEqual(telegramSender.locationCalls.count, 0,
                   "Synology has no native map message")
}

func testSynologyDisabledOrUnconfiguredDoesNothing() throws {
    settings.selectedChannel = .synologyChat

    service.handle(context(event: .intruded))
    assertNoCameraOrNetworkCalls()

    settings.setEnabled(true, for: .synologyChat)
    service.handle(context(event: .intruded))
    assertNoCameraOrNetworkCalls()
}

func testSelectedChannelRoutesToTelegramWhenTelegramIsSelected() throws {
    settings.selectedChannel = .telegram
    try settings.saveTelegramCredentials(replacementToken: "token", chatID: "chat")
    settings.setEnabled(true, for: .telegram)
    camera.result = .success(photoURL)

    service.handle(context(event: .intruded))

    XCTAssertEqual(telegramSender.photoCalls.count, 1)
    XCTAssertEqual(synologySender.photoCalls.count, 0)
}

func testSynologyTestNotificationUsesSynologyPhotoPreference() throws {
    settings.selectedChannel = .synologyChat
    try configureSynology()
    camera.result = .success(photoURL)
    var result: Result<Void, Error>?

    service.sendTest(hostName: "Fred-Mac") { result = $0 }

    assertSuccess(result)
    XCTAssertEqual(synologySender.photoCalls.count, 1)
    XCTAssertEqual(camera.captureCalls, 1)
}
```

And helper methods:

```swift
private func configureSynology() throws {
    try settings.saveSynologyCredentials(webhookURL: "https://nas.local",
                                         username: "user",
                                         password: "pass",
                                         channelID: "42")
    settings.setEnabled(true, for: .synologyChat)
}
```

- [ ] **Step 3: Run the test to verify it fails**

Run: `xcodebuild test -scheme BLEUnlock -destination 'platform=macOS'`
Expected: build FAILS — `NotificationService` still uses `sender:` and has no Synology flow.

- [ ] **Step 4: Update `BLEUnlock/NotificationService.swift`**

Rename the service's Telegram-only sender parameter and add the Synology sender:

```swift
final class NotificationService: NotificationHandling {
    private let settings: NotificationSettings
    private let telegramSender: TelegramSending
    private let synologySender: SynologySending
    private let camera: PhotoCapturing
    private let location: MacLocationProviding
    private let removeFile: (URL) throws -> Void
    private let reporter: FailureReporting
    private let formatter: NotificationMessageFormatting

    init(settings: NotificationSettings,
         telegramSender: TelegramSending,
         synologySender: SynologySending,
         camera: PhotoCapturing,
         location: MacLocationProviding = CoreMacLocationProvider(),
         removeFile: @escaping (URL) throws -> Void = {
             try FileManager.default.removeItem(at: $0)
         },
         reporter: FailureReporting,
         formatter: NotificationMessageFormatting = NotificationMessageFormatter()) {
        self.settings = settings
        self.telegramSender = telegramSender
        self.synologySender = synologySender
        self.camera = camera
        self.location = location
        self.removeFile = removeFile
        self.reporter = reporter
        self.formatter = formatter
    }

    func handle(_ context: NotificationEventContext) {
        let channel = settings.selectedChannel
        guard settings.isEnabled(channel), settings.isEventEnabled(context.event) else {
            return
        }
        do {
            guard try settings.isConfigured(channel) else { return }
        } catch {
            reporter.report(category: "settings",
                            message: t("notification_error_settings_unavailable"))
            return
        }

        switch channel {
        case .telegram:
            handleTelegram(context)
        case .synologyChat:
            handleSynology(context)
        }
    }

    func sendTest(hostName: String,
                  completion: @escaping (Result<Void, Error>) -> Void) {
        switch settings.selectedChannel {
        case .telegram:
            sendTelegramTest(hostName: hostName, completion: completion)
        case .synologyChat:
            sendSynologyTest(hostName: hostName, completion: completion)
        }
    }
    ...
}
```

Replace the old `handle`, `sendTest`, and the private Telegram flow methods with the following. Keep `NotificationServiceError` (rename error string keys were already applied in Task 1):

```swift
    private func handleTelegram(_ context: NotificationEventContext) {
        let credentials: TelegramCredentials
        do {
            guard let storedCredentials = try settings.telegramCredentials() else { return }
            credentials = storedCredentials
        } catch {
            reporter.report(category: "settings",
                            message: t("notification_error_settings_unavailable"))
            return
        }

        if context.event == .intruded && settings.takePhotoOnIntruded(.telegram) {
            if settings.attachMacLocation(.telegram) {
                sendLocatedPhotoOrFallback(credentials: credentials,
                                           context: context,
                                           completion: nil)
            } else {
                sendPhotoOrFallback(credentials: credentials,
                                    message: formatter.message(for: context),
                                    completion: nil)
            }
        } else {
            sendText(credentials: credentials,
                     message: formatter.message(for: context),
                     completion: nil)
        }
    }

    private func sendTelegramTest(hostName: String,
                                  completion: @escaping (Result<Void, Error>) -> Void) {
        let credentials: TelegramCredentials
        do {
            guard let storedCredentials = try settings.telegramCredentials() else {
                completion(.failure(NotificationServiceError.notConfigured))
                return
            }
            credentials = storedCredentials
        } catch {
            completion(.failure(NotificationServiceError.settingsUnavailable))
            return
        }

        let context = NotificationEventContext(event: .intruded,
                                               hostName: hostName,
                                               timestamp: Date(),
                                               rssi: nil)
        if settings.takePhotoOnIntruded(.telegram) {
            if settings.attachMacLocation(.telegram) {
                sendLocatedPhotoOrFallback(credentials: credentials,
                                           context: context,
                                           completion: completion)
            } else {
                sendPhotoOrFallback(credentials: credentials,
                                    message: formatter.message(for: context),
                                    completion: completion)
            }
        } else {
            sendText(credentials: credentials,
                     message: formatter.message(for: context),
                     completion: completion)
        }
    }

    private func handleSynology(_ context: NotificationEventContext) {
        let credentials: SynologyCredentials
        do {
            guard let storedCredentials = try settings.synologyCredentials() else { return }
            credentials = storedCredentials
        } catch {
            reporter.report(category: "settings",
                            message: t("notification_error_settings_unavailable"))
            return
        }

        if context.event == .intruded && settings.takePhotoOnIntruded(.synologyChat) {
            if settings.attachMacLocation(.synologyChat) {
                sendLocatedSynologyPhotoOrFallback(credentials: credentials,
                                                   context: context,
                                                   completion: nil)
            } else {
                sendSynologyPhotoOrFallback(credentials: credentials,
                                            context: context,
                                            completion: nil)
            }
        } else {
            sendSynologyText(credentials: credentials,
                             message: formatter.message(for: context),
                             completion: nil)
        }
    }

    private func sendSynologyTest(hostName: String,
                                  completion: @escaping (Result<Void, Error>) -> Void) {
        let credentials: SynologyCredentials
        do {
            guard let storedCredentials = try settings.synologyCredentials() else {
                completion(.failure(NotificationServiceError.notConfigured))
                return
            }
            credentials = storedCredentials
        } catch {
            completion(.failure(NotificationServiceError.settingsUnavailable))
            return
        }

        let context = NotificationEventContext(event: .intruded,
                                               hostName: hostName,
                                               timestamp: Date(),
                                               rssi: nil)
        if settings.takePhotoOnIntruded(.synologyChat) {
            if settings.attachMacLocation(.synologyChat) {
                sendLocatedSynologyPhotoOrFallback(credentials: credentials,
                                                   context: context,
                                                   completion: completion)
            } else {
                sendSynologyPhotoOrFallback(credentials: credentials,
                                            context: context,
                                            completion: completion)
            }
        } else {
            sendSynologyText(credentials: credentials,
                             message: formatter.message(for: context),
                             completion: completion)
        }
    }

    private func sendLocatedSynologyPhotoOrFallback(
        credentials: SynologyCredentials,
        context: NotificationEventContext,
        completion: ((Result<Void, Error>) -> Void)?
    ) {
        let coordinator = PhotoLocationCoordinator(camera: camera, location: location)
        coordinator.capture(capturedAt: context.timestamp) { [coordinator] outcome in
            _ = coordinator
            self.deliverSynology(outcome,
                                 credentials: credentials,
                                 context: context,
                                 completion: completion)
        }
    }

    private func deliverSynology(
        _ outcome: PhotoLocationOutcome,
        credentials: SynologyCredentials,
        context: NotificationEventContext,
        completion: ((Result<Void, Error>) -> Void)?
    ) {
        switch outcome {
        case .cameraFailure(let error):
            reporter.report(category: "camera", message: error.localizedDescription)
            completion?(.failure(error))
            sendSynologyText(credentials: credentials,
                             message: formatter.message(for: context),
                             completion: nil)
        case .photo(let photoURL, let positionResult):
            let position = try? positionResult.get()
            if case .failure = positionResult {
                reporter.report(category: "location", message: t("telegram_location_error"))
            }
            let caption = formatter.photoCaption(for: context, location: position)
            sendSynologyPhoto(credentials: credentials,
                              photoURL: photoURL,
                              caption: caption,
                              completion: completion)
        }
    }

    private func sendSynologyPhotoOrFallback(
        credentials: SynologyCredentials,
        context: NotificationEventContext,
        completion: ((Result<Void, Error>) -> Void)?
    ) {
        camera.capture { [weak self] captureResult in
            guard let self = self else { return }
            switch captureResult {
            case .failure(let error):
                self.reporter.report(category: "camera", message: error.localizedDescription)
                completion?(.failure(error))
                self.sendSynologyText(credentials: credentials,
                                      message: self.formatter.message(for: context),
                                      completion: nil)
            case .success(let photoURL):
                self.sendSynologyPhoto(credentials: credentials,
                                       photoURL: photoURL,
                                       caption: self.formatter.message(for: context),
                                       completion: completion)
            }
        }
    }

    private func sendSynologyPhoto(credentials: SynologyCredentials,
                                   photoURL: URL,
                                   caption: String,
                                   completion: ((Result<Void, Error>) -> Void)?) {
        synologySender.sendPhoto(credentials: credentials,
                                 photoURL: photoURL,
                                 caption: caption) { [removeFile, reporter] result in
            do {
                try removeFile(photoURL)
            } catch {
                reporter.report(category: "file",
                                message: t("notification_error_file_cleanup"))
            }
            switch result {
            case .success:
                completion?(.success(()))
            case .failure(let error):
                reporter.report(category: "synology",
                                message: error.localizedDescription)
                completion?(.failure(error))
            }
        }
    }

    private func sendSynologyText(credentials: SynologyCredentials,
                                  message: String,
                                  completion: ((Result<Void, Error>) -> Void)?) {
        synologySender.sendText(credentials: credentials,
                                text: message) { [reporter] result in
            if case .failure(let error) = result {
                reporter.report(category: "synology", message: error.localizedDescription)
            }
            completion?(result.mapError { $0 as Error })
        }
    }
```

Keep the existing `sendLocatedPhotoOrFallback`, `deliver`, `sendPhotoOrFallback`, and `sendText` methods (the Telegram versions) exactly as they were after Task 1, except:
- `settings.credentials()` → `settings.telegramCredentials()`
- `settings.isEnabled` → `settings.isEnabled(.telegram)`
- `settings.takePhotoOnIntruded` → `settings.takePhotoOnIntruded(.telegram)`
- `settings.attachMacLocation` → `settings.attachMacLocation(.telegram)`
- `t("telegram_error_settings_unavailable")` → `t("notification_error_settings_unavailable")` (already done in Task 1)
- `t("telegram_error_file_cleanup")` → `t("notification_error_file_cleanup")` (already done in Task 1)

Remove the old `handle` and `sendTest` bodies (replaced by the new routing `handle`/`sendTest` + `handleTelegram`/`sendTelegramTest`/`handleSynology`/`sendSynologyTest`).

- [ ] **Step 5: Update the existing `BLEUnlockTests/NotificationServiceTests.swift` construction**

Change `setUp`:
```swift
service = NotificationService(
    settings: settings,
    telegramSender: sender,
    synologySender: synologySender,
    camera: camera,
    location: location,
    removeFile: remover.remove,
    reporter: reporter
)
```
Add `private var synologySender: RecordingSynologySender!` and initialize it. Update every `sender.*` reference in the existing Telegram tests to `telegramSender.*` where it now refers to the Telegram sender, and every `settings.isEnabled` → `settings.isEnabled(.telegram)`, `settings.takePhotoOnIntruded` → `settings.takePhotoOnIntruded(.telegram)`, `settings.attachMacLocation` → `settings.attachMacLocation(.telegram)`. The `callOrder`/`TelegramCallKind` machinery stays on `RecordingTelegramSender`. In `testProductionAppWiresCoreLocationIntoTelegramMenuAndService`, the `AppDelegate.swift` assertions (`"location: macLocationProvider"`, `"locationAuthorization: macLocationProvider"`) remain valid.

- [ ] **Step 6: Update `BLEUnlock/AppDelegate.swift` service construction**

Replace:
```swift
lazy var notificationService: NotificationHandling = NotificationService(
    settings: notificationSettings,
    sender: TelegramNotifier(transport: URLSessionTransport()),
    camera: CameraCapture(),
    location: macLocationProvider,
    reporter: RateLimitedFailureReporter()
)
```
with:
```swift
lazy var notificationService: NotificationHandling = NotificationService(
    settings: notificationSettings,
    telegramSender: TelegramNotifier(transport: URLSessionTransport()),
    synologySender: SynologyNotifier(transport: URLSessionTransport()),
    camera: CameraCapture(),
    location: macLocationProvider,
    reporter: RateLimitedFailureReporter()
)
```

- [ ] **Step 7: Run the tests**

Run: `xcodebuild test -scheme BLEUnlock -destination 'platform=macOS'`
Expected: all tests PASS, including the new Synology routing tests.

- [ ] **Step 8: Commit**

```bash
git add -A
git commit -m "feat: route notifications to selected channel with Synology text/photo flow"
```

---

## Task 5: NotificationMenuController channel submenu + per-channel dialogs

**Files:**
- Modify: `BLEUnlock/NotificationMenuController.swift` (channel submenu, per-channel toggles, channel-aware configure/test, Synology dialog)
- Modify: `BLEUnlock/NotificationSettings.swift` (remove the now-unused selected-channel convenience aliases — optional cleanup; see Step 6)
- Modify: `BLEUnlock/AppDelegate.swift` (dialogs presenter name; no signature change beyond Task 1)
- Modify: `BLEUnlockTests/NotificationMenuControllerTests.swift` (channel radio tests, per-channel enable, configure routing)
- Test: full suite

- [ ] **Step 1: Write the failing tests — rewrite `BLEUnlockTests/NotificationMenuControllerTests.swift`**

```swift
import AppKit
import XCTest
@testable import BLEUnlock

final class NotificationMenuControllerTests: XCTestCase {
    private var defaultsSuiteName: String!
    private var defaults: UserDefaults!
    private var settings: NotificationSettings!
    private var service: RecordingNotificationService!
    private var dialogs: RecordingNotificationDialogPresenter!
    private var locationAuthorization: RecordingLocationAuthorizationRequester!
    private var controller: NotificationMenuController!

    override func setUp() {
        super.setUp()
        defaultsSuiteName = "jp.sone.BLEUnlockTests.NotificationMenuController.\(UUID())"
        defaults = UserDefaults(suiteName: defaultsSuiteName)!
        defaults.removePersistentDomain(forName: defaultsSuiteName)
        settings = NotificationSettings(defaults: defaults,
                                        telegramSecrets: MemorySecretStore(),
                                        synologySecrets: MemorySecretStore())
        service = RecordingNotificationService()
        dialogs = RecordingNotificationDialogPresenter()
        locationAuthorization = RecordingLocationAuthorizationRequester()
        controller = NotificationMenuController(settings: settings,
                                                service: service,
                                                dialogs: dialogs,
                                                locationAuthorization: locationAuthorization,
                                                hostName: { "Fred-Mac" })
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: defaultsSuiteName)
        defaultsSuiteName = nil
        defaults = nil
        settings = nil
        service = nil
        dialogs = nil
        locationAuthorization = nil
        controller = nil
        super.tearDown()
    }

    func testUnconfiguredMenuDisablesEnableAndTestAndShowsNotConfigured() {
        controller.menuWillOpen(controller.menu)

        XCTAssertFalse(controller.enableItem.isEnabled)
        XCTAssertFalse(controller.testItem.isEnabled)
        XCTAssertEqual(controller.statusItem.title, t("notification_status_not_configured"))
    }

    func testChannelRadioReflectsSelectionAndSwitchingPersists() throws {
        controller.menuWillOpen(controller.menu)

        XCTAssertEqual(controller.channelItems[.telegram]?.state, .on)
        XCTAssertEqual(controller.channelItems[.synologyChat]?.state, .off)

        controller.selectChannel(controller.channelItems[.synologyChat]!)

        XCTAssertEqual(settings.selectedChannel, .synologyChat)
        XCTAssertEqual(controller.channelItems[.telegram]?.state, .off)
        XCTAssertEqual(controller.channelItems[.synologyChat]?.state, .on)
    }

    func testConfiguredMenuCanEnableSelectedChannel() throws {
        try settings.saveTelegramCredentials(replacementToken: "token", chatID: "chat")
        controller.menuWillOpen(controller.menu)

        XCTAssertTrue(controller.enableItem.isEnabled)
        XCTAssertEqual(controller.enableItem.state, .off)

        controller.toggleEnabled(controller.enableItem)

        XCTAssertTrue(settings.isEnabled(.telegram))
        XCTAssertEqual(controller.enableItem.state, .on)
    }

    func testEnableStateReflectsSynologyChannelWhenSelected() throws {
        try settings.saveSynologyCredentials(webhookURL: "https://nas.local",
                                             username: "u",
                                             password: "p",
                                             channelID: "1")
        settings.setEnabled(true, for: .synologyChat)
        controller.selectChannel(controller.channelItems[.synologyChat]!)

        XCTAssertTrue(controller.enableItem.isEnabled)
        XCTAssertEqual(controller.enableItem.state, .on)
    }

    func testPerChannelTogglesWriteOnlyToSelectedChannel() throws {
        try settings.saveTelegramCredentials(replacementToken: "token", chatID: "chat")
        try settings.saveSynologyCredentials(webhookURL: "https://nas.local",
                                             username: "u",
                                             password: "p",
                                             channelID: "1")
        controller.selectChannel(controller.channelItems[.synologyChat]!)

        controller.togglePhoto(controller.photoItem)
        controller.toggleLocation(controller.locationItem)

        XCTAssertFalse(settings.takePhotoOnIntruded(.synologyChat))
        XCTAssertTrue(settings.attachMacLocation(.synologyChat))
        XCTAssertTrue(settings.takePhotoOnIntruded(.telegram),
                      "Telegram photo preference must not change")
    }

    func testEventAndPhotoItemsReflectSettings() throws {
        try settings.saveTelegramCredentials(replacementToken: "token", chatID: "chat")
        controller.menuWillOpen(controller.menu)

        XCTAssertEqual(controller.eventItems[.away]?.state, .on)
        XCTAssertEqual(controller.eventItems[.unlocked]?.state, .off)
        XCTAssertEqual(controller.photoItem.state, .on)

        controller.toggleEvent(controller.eventItems[.unlocked]!)
        controller.togglePhoto(controller.photoItem)

        XCTAssertTrue(settings.isEventEnabled(.unlocked))
        XCTAssertFalse(settings.takePhotoOnIntruded(.telegram))
    }

    func testConfigureLeavesExistingTelegramTokenWhenTokenFieldIsBlank() throws {
        try settings.saveTelegramCredentials(replacementToken: "original", chatID: "old-chat")
        dialogs.telegramInput = .init(replacementToken: nil, chatID: "new-chat")

        controller.configure()

        XCTAssertTrue(dialogs.requestWasOnMainThread)
        XCTAssertEqual(dialogs.hasStoredTokenValues, [true])
        XCTAssertEqual(try settings.telegramCredentials(),
                       .init(token: "original", chatID: "new-chat"))
    }

    func testConfigureReplacesTelegramTokenWhenNewValueIsEntered() throws {
        try settings.saveTelegramCredentials(replacementToken: "original", chatID: "old-chat")
        dialogs.telegramInput = .init(replacementToken: " replacement ", chatID: "new-chat")

        controller.configure()

        XCTAssertEqual(try settings.telegramCredentials(),
                       .init(token: "replacement", chatID: "new-chat"))
    }

    func testConfigureRoutesToSynologyDialogWhenSynologySelected() throws {
        controller.selectChannel(controller.channelItems[.synologyChat]!)
        dialogs.synologyInput = .init(webhookURL: "https://nas.local",
                                      username: "user",
                                      password: "pass",
                                      channelID: "42")

        controller.configure()

        XCTAssertEqual(dialogs.synologyRequests, 1)
        XCTAssertEqual(try settings.synologyCredentials(),
                       SynologyCredentials(webhookURL: "https://nas.local",
                                           username: "user",
                                           password: "pass",
                                           channelID: "42"))
        XCTAssertEqual(dialogs.telegramRequests, 0)
    }

    func testSendTestCallsServiceAndPresentsResult() throws {
        try settings.saveTelegramCredentials(replacementToken: "token", chatID: "chat")
        let presented = expectation(description: "Result presented")
        dialogs.onShowResult = { presented.fulfill() }

        controller.sendTest()

        wait(for: [presented], timeout: 2)
        XCTAssertEqual(service.hostNames, ["Fred-Mac"])
        XCTAssertEqual(dialogs.results.count, 1)
        XCTAssertEqual(dialogs.results.first?.title, t("notification_test_success"))
        XCTAssertTrue(dialogs.showResultWasOnMainThread)
    }

    func testCameraPrivacyExplanationIsVisibleAdjacentToPhotoToggle() throws {
        try settings.saveTelegramCredentials(replacementToken: "token", chatID: "chat")
        let photoIndex = controller.menu.index(of: controller.photoItem)
        let privacyIndex = controller.menu.index(of: controller.privacyItem)

        XCTAssertEqual(privacyIndex, photoIndex + 1)
        XCTAssertEqual(controller.privacyItem.title, t("telegram_camera_privacy"))
        XCTAssertFalse(controller.privacyItem.isEnabled)
    }

    func testSynologyPrivacyLineShowsWhenSynologySelected() throws {
        try settings.saveSynologyCredentials(webhookURL: "https://nas.local",
                                             username: "u",
                                             password: "p",
                                             channelID: "1")
        controller.selectChannel(controller.channelItems[.synologyChat]!)
        controller.menuWillOpen(controller.menu)

        XCTAssertEqual(controller.privacyItem.title,
                       t("notification_camera_privacy_synology"))
    }

    func testLocationItemIsBelowPrivacyTextAndDisabledWhenPhotoIsOff() throws {
        try settings.saveTelegramCredentials(replacementToken: "token", chatID: "chat")
        settings.setTakePhotoOnIntruded(false, for: .telegram)
        controller.menuWillOpen(controller.menu)

        XCTAssertEqual(controller.menu.index(of: controller.locationItem),
                       controller.menu.index(of: controller.privacyItem) + 1)
        XCTAssertFalse(controller.locationItem.isEnabled)
        XCTAssertEqual(controller.locationItem.state, .off)
    }

    func testTurningPhotoOffDisablesLocationItem() {
        controller.menuWillOpen(controller.menu)

        controller.togglePhoto(controller.photoItem)

        XCTAssertFalse(controller.locationItem.isEnabled)
    }

    func testEnablingLocationPersistsAndRequestsAuthorizationOnce() {
        controller.toggleLocation(controller.locationItem)

        XCTAssertTrue(settings.attachMacLocation(.telegram))
        XCTAssertEqual(locationAuthorization.requestCalls, 1)
        XCTAssertEqual(controller.locationItem.state, .on)

        controller.toggleLocation(controller.locationItem)

        XCTAssertFalse(settings.attachMacLocation(.telegram))
        XCTAssertEqual(locationAuthorization.requestCalls, 1)
    }

    func testControllerDoesNotReadOrRetainCredentials() throws {
        let repository = URL(fileURLWithPath: #file)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(contentsOf: repository.appendingPathComponent(
            "BLEUnlock/NotificationMenuController.swift"
        ))

        XCTAssertFalse(source.contains("settings.credentials()"))
        XCTAssertFalse(source.contains("settings.synologyCredentials()"))
        XCTAssertFalse(source.contains("settings.telegramCredentials()"))
        XCTAssertFalse(source.contains("TelegramCredentials"))
        XCTAssertFalse(source.contains("SynologyCredentials"))
        XCTAssertTrue(source.contains("saveTelegramCredentials(replacementToken:"))
        XCTAssertTrue(source.contains("saveSynologyCredentials(webhookURL:"))
    }
}

private final class RecordingLocationAuthorizationRequester: LocationAuthorizationRequesting {
    private(set) var requestCalls = 0

    func requestAuthorization() {
        requestCalls += 1
    }
}

private final class RecordingNotificationService: NotificationHandling {
    private let lock = NSLock()
    private var recordedHostNames: [String] = []
    var result: Result<Void, Error> = .success(())

    var hostNames: [String] {
        lock.lock()
        defer { lock.unlock() }
        return recordedHostNames
    }

    func handle(_ context: NotificationEventContext) {}

    func sendTest(hostName: String,
                  completion: @escaping (Result<Void, Error>) -> Void) {
        lock.lock()
        recordedHostNames.append(hostName)
        lock.unlock()
        completion(result)
    }
}

private final class RecordingNotificationDialogPresenter: NotificationDialogPresenting {
    struct PresentedResult {
        let title: String
        let message: String
    }

    var telegramInput: TelegramCredentialInput?
    var synologyInput: SynologyCredentialInput?
    private(set) var hasStoredTokenValues: [Bool] = []
    private(set) var telegramRequests = 0
    private(set) var synologyRequests = 0
    private(set) var results: [PresentedResult] = []
    private(set) var requestWasOnMainThread = false
    private(set) var showResultWasOnMainThread = false
    var onShowResult: (() -> Void)?

    func requestTelegramCredentials(hasStoredToken: Bool,
                                    completion: (TelegramCredentialInput?) -> Void) {
        requestWasOnMainThread = Thread.isMainThread
        hasStoredTokenValues.append(hasStoredToken)
        telegramRequests += 1
        completion(telegramInput)
    }

    func requestSynologyCredentials(hasStoredPassword: Bool,
                                    completion: (SynologyCredentialInput?) -> Void) {
        requestWasOnMainThread = Thread.isMainThread
        synologyRequests += 1
        completion(synologyInput)
    }

    func showResult(title: String, message: String) {
        showResultWasOnMainThread = Thread.isMainThread
        results.append(.init(title: title, message: message))
        onShowResult?()
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `xcodebuild test -scheme BLEUnlock -destination 'platform=macOS'`
Expected: build FAILS — no `channelItems`, no `selectChannel`, no `NotificationDialogPresenting` split, no `SynologyCredentialInput`.

- [ ] **Step 3: Update `BLEUnlock/NotificationMenuController.swift`**

Add the `SynologyCredentialInput` struct and change the dialog protocol:

```swift
struct TelegramCredentialInput {
    let replacementToken: String?
    let chatID: String
}

struct SynologyCredentialInput {
    let webhookURL: String
    let username: String
    let password: String?
    let channelID: String
}

protocol NotificationDialogPresenting {
    func requestTelegramCredentials(hasStoredToken: Bool,
                                    completion: (TelegramCredentialInput?) -> Void)
    func requestSynologyCredentials(hasStoredPassword: Bool,
                                    completion: (SynologyCredentialInput?) -> Void)
    func showResult(title: String, message: String)
}
```

Change the controller class:

```swift
final class NotificationMenuController: NSObject, NSMenuDelegate {
    let menu = NSMenu()
    let channelItems: [NotificationChannel: NSMenuItem]
    let enableItem: NSMenuItem
    let testItem: NSMenuItem
    let statusItem: NSMenuItem
    let eventItems: [NotificationEvent: NSMenuItem]
    let photoItem: NSMenuItem
    let privacyItem: NSMenuItem
    let locationItem: NSMenuItem

    private let settings: NotificationSettings
    private let service: NotificationHandling
    private let dialogs: NotificationDialogPresenting
    private let locationAuthorization: LocationAuthorizationRequesting
    private let hostName: () -> String
    private let serviceQueue = DispatchQueue(label: "jp.sone.BLEUnlock.notification.menu",
                                             qos: .utility)

    init(settings: NotificationSettings,
         service: NotificationHandling,
         dialogs: NotificationDialogPresenting,
         locationAuthorization: LocationAuthorizationRequesting = CoreMacLocationProvider(),
         hostName: @escaping () -> String = { Host.current().localizedName ?? "Mac" }) {
        self.settings = settings
        self.service = service
        self.dialogs = dialogs
        self.locationAuthorization = locationAuthorization
        self.hostName = hostName

        let channelMenu = NSMenu()
        channelMenu.autoenablesItems = false
        var channelItems: [NotificationChannel: NSMenuItem] = [:]
        for channel in NotificationChannel.allCases {
            let key = channel == .telegram
                ? "notification_channel_telegram"
                : "notification_channel_synology_chat"
            let item = NSMenuItem(title: t(key),
                                  action: #selector(selectChannel(_:)),
                                  keyEquivalent: "")
            item.target = self
            channelItems[channel] = item
            channelMenu.addItem(item)
        }
        self.channelItems = channelItems

        let channelItem = NSMenuItem(title: t("notification_channel"),
                                     action: nil,
                                     keyEquivalent: "")
        channelItem.submenu = channelMenu

        enableItem = NSMenuItem(title: t("notification_enable"),
                                action: #selector(toggleEnabled(_:)),
                                keyEquivalent: "")
        let configureItem = NSMenuItem(title: t("notification_configure"),
                                       action: #selector(configure),
                                       keyEquivalent: "")
        testItem = NSMenuItem(title: t("notification_test"),
                              action: #selector(sendTest),
                              keyEquivalent: "")

        let eventsMenu = NSMenu()
        eventsMenu.autoenablesItems = false
        var items: [NotificationEvent: NSMenuItem] = [:]
        for event in NotificationEvent.allCases {
            let item = NSMenuItem(title: t("telegram_event_\(event.rawValue)"),
                                  action: #selector(toggleEvent(_:)),
                                  keyEquivalent: "")
            items[event] = item
            eventsMenu.addItem(item)
        }
        eventItems = items

        let eventsItem = NSMenuItem(title: t("notification_events"),
                                    action: nil,
                                    keyEquivalent: "")
        eventsItem.submenu = eventsMenu
        photoItem = NSMenuItem(title: t("notification_take_photo"),
                               action: #selector(togglePhoto(_:)),
                               keyEquivalent: "")
        privacyItem = NSMenuItem(title: t("telegram_camera_privacy"),
                                 action: nil,
                                 keyEquivalent: "")
        privacyItem.isEnabled = false
        locationItem = NSMenuItem(title: t("notification_attach_mac_location"),
                                  action: #selector(toggleLocation(_:)),
                                  keyEquivalent: "")
        statusItem = NSMenuItem(title: t("notification_status_not_configured"),
                                action: nil,
                                keyEquivalent: "")
        statusItem.isEnabled = false

        super.init()

        enableItem.target = self
        configureItem.target = self
        testItem.target = self
        eventItems.values.forEach { $0.target = self }
        photoItem.target = self
        locationItem.target = self

        menu.autoenablesItems = false
        menu.delegate = self
        menu.addItem(channelItem)
        menu.addItem(enableItem)
        menu.addItem(configureItem)
        menu.addItem(testItem)
        menu.addItem(.separator())
        menu.addItem(eventsItem)
        menu.addItem(photoItem)
        menu.addItem(privacyItem)
        menu.addItem(locationItem)
        menu.addItem(.separator())
        menu.addItem(statusItem)
    }

    func menuWillOpen(_ menu: NSMenu) {
        let channel = settings.selectedChannel
        for (candidate, item) in channelItems {
            item.state = candidate == channel ? .on : .off
        }
        let configured = (try? settings.isConfigured(channel)) == true
        enableItem.isEnabled = configured
        testItem.isEnabled = configured
        enableItem.state = configured && settings.isEnabled(channel) ? .on : .off
        for (event, item) in eventItems {
            item.state = settings.isEventEnabled(event) ? .on : .off
        }
        photoItem.state = settings.takePhotoOnIntruded(channel) ? .on : .off
        privacyItem.title = channel == .telegram
            ? t("telegram_camera_privacy")
            : t("notification_camera_privacy_synology")
        locationItem.state = settings.attachMacLocation(channel) ? .on : .off
        locationItem.isEnabled = settings.takePhotoOnIntruded(channel)

        if !configured {
            statusItem.title = t("notification_status_not_configured")
        } else if settings.isEnabled(channel) {
            statusItem.title = t("notification_status_enabled")
        } else {
            statusItem.title = t("notification_status_disabled")
        }
    }

    @objc internal func selectChannel(_ item: NSMenuItem) {
        guard let channel = channelItems.first(where: { $0.value === item })?.key else { return }
        settings.selectedChannel = channel
        menuWillOpen(menu)
    }

    @objc internal func toggleEnabled(_ item: NSMenuItem) {
        let channel = settings.selectedChannel
        guard (try? settings.isConfigured(channel)) == true else {
            menuWillOpen(menu)
            return
        }
        settings.setEnabled(!settings.isEnabled(channel), for: channel)
        menuWillOpen(menu)
    }

    @objc internal func toggleEvent(_ item: NSMenuItem) {
        guard let event = eventItems.first(where: { $0.value === item })?.key else { return }
        settings.setEvent(event, enabled: !settings.isEventEnabled(event))
        item.state = settings.isEventEnabled(event) ? .on : .off
    }

    @objc internal func togglePhoto(_ item: NSMenuItem) {
        let channel = settings.selectedChannel
        settings.setTakePhotoOnIntruded(!settings.takePhotoOnIntruded(channel), for: channel)
        menuWillOpen(menu)
    }

    @objc internal func toggleLocation(_ item: NSMenuItem) {
        let channel = settings.selectedChannel
        guard settings.takePhotoOnIntruded(channel) else {
            menuWillOpen(menu)
            return
        }
        settings.setAttachMacLocation(!settings.attachMacLocation(channel), for: channel)
        if settings.attachMacLocation(channel) {
            locationAuthorization.requestAuthorization()
        }
        menuWillOpen(menu)
    }

    @objc internal func configure() {
        switch settings.selectedChannel {
        case .telegram:
            configureTelegram()
        case .synologyChat:
            configureSynology()
        }
    }

    private func configureTelegram() {
        let configured: Bool
        do {
            configured = try settings.isConfigured(.telegram)
        } catch {
            dialogs.showResult(title: t("notification_configure"),
                               message: t("notification_error_settings_unavailable"))
            return
        }

        dialogs.requestTelegramCredentials(hasStoredToken: configured) { input in
            guard let input = input else { return }
            do {
                try self.settings.saveTelegramCredentials(replacementToken: input.replacementToken,
                                                          chatID: input.chatID)
                guard try self.settings.isConfigured(.telegram) else {
                    self.dialogs.showResult(
                        title: t("notification_configure"),
                        message: t("notification_error_not_configured")
                    )
                    return
                }
                self.menuWillOpen(self.menu)
            } catch {
                self.dialogs.showResult(title: t("notification_configure"),
                                        message: error.localizedDescription)
            }
        }
    }

    private func configureSynology() {
        let configured: Bool
        do {
            configured = try settings.isConfigured(.synologyChat)
        } catch {
            dialogs.showResult(title: t("notification_configure"),
                               message: t("notification_error_settings_unavailable"))
            return
        }

        dialogs.requestSynologyCredentials(hasStoredPassword: configured) { input in
            guard let input = input else { return }
            do {
                try self.settings.saveSynologyCredentials(webhookURL: input.webhookURL,
                                                          username: input.username,
                                                          password: input.password,
                                                          channelID: input.channelID)
                guard try self.settings.isConfigured(.synologyChat) else {
                    self.dialogs.showResult(
                        title: t("notification_configure"),
                        message: t("notification_error_not_configured")
                    )
                    return
                }
                self.menuWillOpen(self.menu)
            } catch {
                self.dialogs.showResult(title: t("notification_configure"),
                                        message: error.localizedDescription)
            }
        }
    }

    @objc internal func sendTest() {
        let service = self.service
        let resolvedHostName = hostName()
        serviceQueue.async { [weak self] in
            service.sendTest(hostName: resolvedHostName) { result in
                self?.showTestResult(result)
            }
        }
    }

    private func showTestResult(_ result: Result<Void, Error>) {
        onMain { [weak self] in
            guard let self = self else { return }
            switch result {
            case .success:
                self.dialogs.showResult(title: t("notification_test_success"), message: "")
            case .failure(let error):
                self.dialogs.showResult(title: t("notification_test_failed"),
                                        message: error.localizedDescription)
            }
        }
    }

    private func onMain(_ action: @escaping () -> Void) {
        if Thread.isMainThread {
            action()
        } else {
            DispatchQueue.main.async(execute: action)
        }
    }
}
```

Replace `AppKitNotificationDialogPresenter` with this version (keeps the Telegram dialog; adds the Synology dialog):

```swift
final class AppKitNotificationDialogPresenter: NotificationDialogPresenting {
    func requestTelegramCredentials(hasStoredToken: Bool,
                                    completion: (TelegramCredentialInput?) -> Void) {
        precondition(Thread.isMainThread)

        let alert = NSAlert()
        alert.window.title = "BLEUnlock"
        alert.messageText = t("notification_configure")
        alert.addButton(withTitle: t("notification_save"))
        alert.addButton(withTitle: t("cancel"))

        let explanation = NSTextField(wrappingLabelWithString: t("telegram_setup_help"))
        explanation.preferredMaxLayoutWidth = 360
        let privacy = NSTextField(wrappingLabelWithString: t("telegram_camera_privacy"))
        privacy.preferredMaxLayoutWidth = 360

        let tokenLabel = NSTextField(labelWithString: t("telegram_bot_token"))
        let tokenField = NSSecureTextField()
        tokenField.stringValue = ""
        tokenField.placeholderString = hasStoredToken ? nil : t("telegram_bot_token")

        let chatIDLabel = NSTextField(labelWithString: t("telegram_chat_id"))
        let chatIDField = NSTextField()

        let stack = NSStackView(views: [explanation,
                                        privacy,
                                        tokenLabel,
                                        tokenField,
                                        chatIDLabel,
                                        chatIDField])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.edgeInsets = NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
        stack.frame = NSRect(x: 0, y: 0, width: 360, height: 190)
        tokenField.widthAnchor.constraint(equalToConstant: 360).isActive = true
        chatIDField.widthAnchor.constraint(equalToConstant: 360).isActive = true
        alert.accessoryView = stack

        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else {
            completion(nil)
            return
        }

        let token = tokenField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        completion(.init(replacementToken: token.isEmpty ? nil : token,
                         chatID: chatIDField.stringValue))
    }

    func requestSynologyCredentials(hasStoredPassword: Bool,
                                    completion: (SynologyCredentialInput?) -> Void) {
        precondition(Thread.isMainThread)

        let alert = NSAlert()
        alert.window.title = "BLEUnlock"
        alert.messageText = t("notification_configure")
        alert.addButton(withTitle: t("notification_save"))
        alert.addButton(withTitle: t("cancel"))

        let explanation = NSTextField(wrappingLabelWithString: t("synology_setup_help"))
        explanation.preferredMaxLayoutWidth = 360
        let privacy = NSTextField(wrappingLabelWithString: t("notification_camera_privacy_synology"))
        privacy.preferredMaxLayoutWidth = 360

        let urlLabel = NSTextField(labelWithString: t("synology_webhook_url"))
        let urlField = NSTextField()
        let usernameLabel = NSTextField(labelWithString: t("synology_username"))
        let usernameField = NSTextField()
        let passwordLabel = NSTextField(labelWithString: t("synology_password"))
        let passwordField = NSSecureTextField()
        passwordField.stringValue = ""
        passwordField.placeholderString = hasStoredPassword ? nil : t("synology_password")
        let channelIDLabel = NSTextField(labelWithString: t("synology_channel_id"))
        let channelIDField = NSTextField()

        let stack = NSStackView(views: [explanation,
                                        privacy,
                                        urlLabel,
                                        urlField,
                                        usernameLabel,
                                        usernameField,
                                        passwordLabel,
                                        passwordField,
                                        channelIDLabel,
                                        channelIDField])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.edgeInsets = NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
        stack.frame = NSRect(x: 0, y: 0, width: 360, height: 330)
        for field in [urlField, usernameField, passwordField, channelIDField] {
            field.widthAnchor.constraint(equalToConstant: 360).isActive = true
        }
        alert.accessoryView = stack

        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else {
            completion(nil)
            return
        }

        let password = passwordField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        completion(.init(webhookURL: urlField.stringValue,
                         username: usernameField.stringValue,
                         password: password.isEmpty ? nil : password,
                         channelID: channelIDField.stringValue))
    }

    func showResult(title: String, message: String) {
        precondition(Thread.isMainThread)
        let alert = NSAlert()
        alert.window.title = "BLEUnlock"
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: t("ok"))
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }
}
```

- [ ] **Step 4: Update `BLEUnlock/AppDelegate.swift` dialogs reference**

The `notificationMenuController` already passes `dialogs: AppKitNotificationDialogPresenter()` (renamed in Task 1). No change needed. Verify the line reads `dialogs: AppKitNotificationDialogPresenter()`.

- [ ] **Step 5: Optional cleanup — remove the unused selected-channel convenience aliases in `BLEUnlock/NotificationSettings.swift`**

After this task, no consumer uses `isEnabled`, `takePhotoOnIntruded`, `attachMacLocation` (properties) or `credentials()`, `saveCredentials(...)`, `isConfigured()` (aliases) anymore. The `NotificationSettings` final API is the per-channel one from Task 3. If the grep `rg "settings\.(isEnabled|takePhotoOnIntruded|attachMacLocation|credentials|saveCredentials|isConfigured)\b" BLEUnlock BLEUnlockTests` returns no matches (besides the method definitions), leave Task 3's implementation as the final version — no aliases were added, so nothing to remove. (Task 3 introduced no alias properties, so this step is a no-op.)

- [ ] **Step 6: Run the tests**

Run: `xcodebuild test -scheme BLEUnlock -destination 'platform=macOS'`
Expected: all tests PASS.

- [ ] **Step 7: Commit**

```bash
git add -A
git commit -m "feat: add channel submenu and per-channel configure dialog to notification menu"
```

---

## Task 6: Update README documentation

**Files:**
- Modify: `README.md` (lines 64-76 Telegram section)
- Modify: `README.ja.md` (lines 57-69)
- Modify: `README_CHT.md` (lines 73-87)

- [ ] **Step 1: Update `README.md`**

Replace the `## Telegram notifications` section (lines 64-76) with a `## Notification Settings` section that: renames the menu path to *BLEUnlock > Notification Settings*; explains the channel selector (Telegram or Synology Chat, radio selection, default Telegram); documents that Telegram keeps its existing setup (BotFather token + Chat ID) and that choosing Synology requires an incoming webhook (from *Synology Chat > Settings > Integration*), a DSM username and password or personal API token (for 2FA accounts), and the numeric channel ID; notes that a channel can be enabled only after it is configured; keeps the existing paragraphs about event defaults, photo capture for `intruded`, text fallback, photo deletion, and the legacy `event` script (adjusting "Telegram" wording to "the selected channel" where the behavior is channel-independent). Update the trailing LINE Notify historical note (line 171) only if it references the Telegram-only flow in a way that is now inaccurate.

- [ ] **Step 2: Update `README.ja.md`**

Apply the equivalent changes to the `## Telegram通知` section (lines 57-69), keeping Japanese style and terminology consistent with the existing file.

- [ ] **Step 3: Update `README_CHT.md`**

Apply the equivalent changes to the `## Telegram 通知` section (lines 73-87), keeping Traditional Chinese style and terminology consistent with the existing file.

- [ ] **Step 4: Verify and commit**

Run: `xcodebuild test -scheme BLEUnlock -destination 'platform=macOS'` (should be unaffected).
```bash
git add -A
git commit -m "docs: document Notification Settings with Synology Chat channel"
```

---

## Task 7: Final verification

- [ ] **Step 1: Run the full suite**

Run: `xcodebuild test -scheme BLEUnlock -destination 'platform=macOS'`
Expected: all tests PASS with no failures or warnings introduced.

- [ ] **Step 2: Grep for stale identifiers**

Run:
```bash
rg -n "TelegramSettings|TelegramNotificationService|TelegramMenuController|TelegramEvent\b|TelegramEventContext|TelegramNotificationHandling|TelegramMessageFormatt" BLEUnlock BLEUnlockTests README.md README.ja.md README_CHT.md
```
Expected: only `TelegramNotifier`, `TelegramCredentials`, `TelegramError`, `TelegramLocation`, and the `telegram_*` localization keys remain. No stale type names.

- [ ] **Step 3: Manual verification checklist (requires a Mac with camera + a real NAS)**

- [ ] Build and run the app; the top-level menu reads "Notification Settings".
- [ ] The channel submenu shows Telegram and Synology Chat; switching updates Enable/Configure/status/privacy line.
- [ ] With Telegram selected and configured: send test text and test photo.
- [ ] With Synology selected and configured: send test text; send test photo against a DSM 7.3.2+ NAS. If the NAS rejects `SYNO.API.Auth` version 6 (code 117 or similar), or `SYNO.Chat.Post` fails, note it — `SYNO.Chat.Post` is undocumented and compatibility is confirmed only on DSM 7.3.2+. Text via the webhook must still work.
- [ ] For a 2FA account, use a personal DSM API token in the password field and confirm login works.
- [ ] Confirm the legacy `event` script still receives all four event arguments.
- [ ] Confirm temporary intrusion photos are deleted after each send attempt.

- [ ] **Step 4: Finish**

All tasks complete. No further commit required unless Step 2 finds stale identifiers.

---

## Self-Review Notes

- **Spec coverage:** channel selector (Task 5), per-channel enabled/photo/location (Task 3), shared event switches (Tasks 3/4), Synology webhook text + `SYNO.Chat.Post` photo (Tasks 2/4), no-migration Telegram keys (Task 3 `testTelegramReusesLegacyUserDefaultsKeysForNoMigration`), privacy line per channel (Task 5), sendTest per channel (Tasks 4/5), localization completeness (Task 1), README (Task 6). Non-goals (dual-send, LINE, `file_url`, cloud hosting, event-script changes) are not implemented.
- **Verification plan for the undocumented API:** `SYNO.Chat.Post` behavior is pinned by `SynologyNotifierTests` at the request level; end-to-end correctness against a live NAS is covered by Task 7 Step 3 and intentionally cannot be automated.
- **Placeholders:** no TODOs; every code step carries the actual code or a precise mechanical instruction. The only deliberately open content is the 8 non-Base translations in Task 1 Step 8, which are specified as exact key/value mappings plus source English strings and are machine-enforced by `LocalizationTests`.
- **Type consistency:** `NotificationChannel` cases are `telegram` / `synologyChat` everywhere (keys `notification.enabled.synologyChat` etc.). `SynologyError` cases match the localization keys. `NotificationService` init parameter `synologySender:` matches `AppDelegate`. `SynologyCredentials` field order (`webhookURL, username, password, channelID`) is consistent in `NotificationSettings`, `SynologyNotifier`, and the tests.
