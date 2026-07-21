# Traditional Chinese Localization Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add complete Taiwan Traditional Chinese (`zh-Hant`) localization for the BLEUnlock interface, Telegram functionality, and camera permission prompt.

**Architecture:** Add one standard macOS localization directory containing the same keys as Base English, register both strings resources as new children of the existing Xcode variant groups, and extend the existing localization test matrix. BLEUnlock continues to use `NSLocalizedString`; no runtime language selector or production behavior changes are introduced.

**Tech Stack:** Swift 5, XCTest, macOS bundle localization, Xcode `.pbxproj`, property-list `.strings` files.

## Global Constraints

- Use Taiwan Traditional Chinese terminology and the locale identifier `zh-Hant`.
- Translate the complete BLEUnlock menu and every Telegram string, not only newly added Telegram labels.
- Keep language selection controlled by macOS and do not add an in-app language setting.
- Preserve all existing locales and Telegram behavior.
- Preserve the user's uncommitted `project.pbxproj`, shared scheme, and `.codegraph/` changes; stage only the localization implementation.
- Keep the current macOS 11 deployment target and add no dependencies.

---

### Task 1: Add and verify Taiwan Traditional Chinese resources

**Files:**
- Create: `BLEUnlock/zh-Hant.lproj/Localizable.strings`
- Create: `BLEUnlock/zh-Hant.lproj/InfoPlist.strings`
- Modify: `BLEUnlockTests/LocalizationTests.swift`
- Modify: `BLEUnlock.xcodeproj/project.pbxproj`

**Interfaces:**
- Consumes: `NSLocalizedString`, the existing `Localizable.strings` and `InfoPlist.strings` variant groups, and `LocalizationTests.localizationDirectories`.
- Produces: a `zh-Hant` bundle localization selected automatically by macOS.

- [ ] **Step 1: Extend the locale matrix before adding resources**

Change the test locale list to include `zh-Hant`:

```swift
private let localizationDirectories = [
    "Base", "da", "de", "ja", "nb", "sv", "tr", "zh-Hans", "zh-Hant"
]
```

Do not create either `zh-Hant` resource yet.

- [ ] **Step 2: Run the focused tests and verify RED**

Run:

```bash
xcodebuild test \
  -project BLEUnlock.xcodeproj \
  -scheme BLEUnlock \
  -destination 'platform=macOS' \
  -only-testing:BLEUnlockTests/LocalizationTests \
  -derivedDataPath /private/tmp/BLEUnlockZhHantDerivedData \
  CODE_SIGNING_ALLOWED=NO
```

Expected: `TEST FAILED`; the localization tests report missing `BLEUnlock/zh-Hant.lproj/Localizable.strings` and/or `InfoPlist.strings`.

- [ ] **Step 3: Create the complete Traditional Chinese UI localization**

Create `BLEUnlock/zh-Hant.lproj/Localizable.strings` with exactly this content:

```text
"about" = "關於 BLEUnlock";
"bluetooth_power_warn" = "藍牙已關閉。若要使用 BLEUnlock，請開啟藍牙。";
"cancel" = "取消";
"closer" = "⬆靠近";
"device" = "裝置";
"device_not_set" = "尚未選擇裝置";
"disabled" = "停用";
"enter_password" = "輸入密碼以解鎖螢幕。";
"enter_rssi_threshold" = "輸入最低 RSSI";
"enter_rssi_threshold_info" = "掃描時會忽略 RSSI 低於此值的裝置。";
"farther" = "⬇遠離";
"launch_at_login" = "登入時啟動";
"lock_delay" = "延遲鎖定";
"lock_now" = "立即鎖定螢幕";
"lock_rssi" = "鎖定 RSSI";
"minute" = "分鐘";
"minutes" = "分鐘";
"not_detected" = "未偵測到訊號";
"notification_device_away" = "裝置已遠離";
"notification_locked" = "此電腦已由 BLEUnlock 鎖定";
"notification_lost_signal" = "訊號已中斷";
"notification_update_available" = "有可用的更新。";
"ok" = "確定";
"passive_mode" = "被動模式";
"password_info" = "密碼將安全地儲存在鑰匙圈中。";
"password_not_set" = "尚未設定密碼。";
"pause_now_playing" = "鎖定時暫停「播放中」";
"quit" = "結束 BLEUnlock";
"scanning" = "正在掃描…";
"seconds" = "秒";
"set_password" = "設定密碼…";
"set_rssi_threshold" = "設定最低 RSSI…";
"sleep_display" = "鎖定時關閉螢幕";
"timeout" = "無訊號逾時";
"unlock_rssi" = "解鎖 RSSI";
"use_screensaver_to_lock" = "使用螢幕保護程式鎖定";
"wake_on_proximity" = "接近時喚醒";
"wake_without_unlocking" = "喚醒但不解鎖";

"telegram" = "Telegram 通知";
"telegram_enable" = "啟用 Telegram";
"telegram_configure" = "設定…";
"telegram_test" = "傳送測試通知";
"telegram_events" = "事件";
"telegram_event_away" = "裝置已遠離";
"telegram_event_lost" = "訊號已中斷";
"telegram_event_unlocked" = "已由 BLEUnlock 解鎖";
"telegram_event_intruded" = "已手動解鎖";
"telegram_take_photo" = "手動解鎖時附加照片";
"telegram_status_not_configured" = "尚未設定";
"telegram_status_enabled" = "已啟用";
"telegram_status_disabled" = "已停用";
"telegram_bot_token" = "Bot Token";
"telegram_chat_id" = "Chat ID";
"telegram_save" = "儲存";
"telegram_setup_help" = "使用 @BotFather 建立 Bot 並複製 Token。先傳送訊息給 Bot，再開啟 Telegram Bot API 的 getUpdates，從回應中複製數字 Chat ID。";
"telegram_test_success" = "測試通知已傳送。";
"telegram_test_failed" = "無法傳送測試通知。";
"telegram_camera_privacy" = "BLEUnlock 會使用系統預設相機拍攝一張照片並上傳至 Telegram。嘗試傳送後會刪除暫存照片；若拍攝失敗，BLEUnlock 會改傳送文字。";
"telegram_error_not_configured" = "請先設定 Bot Token 與 Chat ID。";
"telegram_camera_error_denied" = "相機存取權限遭拒。";
"telegram_camera_error_restricted" = "相機存取受到限制。";
"telegram_camera_error_no_camera" = "找不到可用的相機。";
"telegram_camera_error_setup_failed" = "無法設定相機。";
"telegram_camera_error_capture_failed" = "相機無法拍攝照片。";
"telegram_camera_error_timeout" = "相機拍攝逾時。";
"telegram_camera_error_file_write_failed" = "無法儲存拍攝的照片。";
"telegram_error_invalid_request" = "無法建立 Telegram 請求。";
"telegram_error_unreadable_photo" = "無法讀取拍攝的照片。";
"telegram_error_transport" = "無法連線至 Telegram。";
"telegram_error_http_status" = "Telegram 傳回 HTTP 狀態碼 %d。";
"telegram_error_rejected" = "Telegram 拒絕了此請求。";
"telegram_error_invalid_response" = "Telegram 傳回無效的回應。";
"telegram_error_settings_unavailable" = "無法讀取 Telegram 設定。";
"telegram_error_file_cleanup" = "無法刪除拍攝的照片。";
"telegram_error_keychain_status" = "鑰匙圈操作失敗（%d）。";
"telegram_failure_notification_subtitle" = "Telegram 通知失敗";
"telegram_message_time" = "時間";
"telegram_message_rssi" = "RSSI";
```

- [ ] **Step 4: Add the localized camera permission description**

Create `BLEUnlock/zh-Hant.lproj/InfoPlist.strings`:

```text
"NSCameraUsageDescription" = "BLEUnlock 使用系統預設相機拍攝手動解鎖的照片，並將警示上傳至 Telegram。";
```

- [ ] **Step 5: Register `zh-Hant` in the Xcode variant groups**

In `BLEUnlock.xcodeproj/project.pbxproj`, add two unique `PBXFileReference` entries:

```text
7E10003F3000000000000001 /* zh-Hant */ = {isa = PBXFileReference; lastKnownFileType = text.plist.strings; name = "zh-Hant"; path = "zh-Hant.lproj/InfoPlist.strings"; sourceTree = "<group>"; };
7E1000403000000000000001 /* zh-Hant */ = {isa = PBXFileReference; lastKnownFileType = text.plist.strings; name = "zh-Hant"; path = "zh-Hant.lproj/Localizable.strings"; sourceTree = "<group>"; };
```

Add `"zh-Hant",` to `knownRegions`. Add `7E10003F3000000000000001` to the `InfoPlist.strings` variant group's children and `7E1000403000000000000001` to the `Localizable.strings` variant group's children. Do not add a second Resources build-phase entry: both variant groups already have exactly one.

- [ ] **Step 6: Run focused localization tests and verify GREEN**

Run the Step 2 command again.

Expected: all `LocalizationTests` pass, including localization completeness, production reference coverage, camera privacy wording, camera usage descriptions, and the hard-coded-English guard.

- [ ] **Step 7: Validate resources and project syntax**

Run:

```bash
plutil -lint \
  BLEUnlock/zh-Hant.lproj/Localizable.strings \
  BLEUnlock/zh-Hant.lproj/InfoPlist.strings \
  BLEUnlock.xcodeproj/project.pbxproj
git diff --check
```

Expected: every file reports `OK`; `git diff --check` produces no output.

- [ ] **Step 8: Run the complete test suite**

Run:

```bash
xcodebuild test \
  -project BLEUnlock.xcodeproj \
  -scheme BLEUnlock \
  -destination 'platform=macOS' \
  -derivedDataPath /private/tmp/BLEUnlockZhHantDerivedData \
  CODE_SIGNING_ALLOWED=NO
```

Expected: all existing tests plus the expanded localization tests pass with `** TEST SUCCEEDED **`.

- [ ] **Step 9: Build Debug and Release and inspect bundled resources**

Run:

```bash
xcodebuild build -project BLEUnlock.xcodeproj -scheme BLEUnlock \
  -configuration Debug -derivedDataPath /private/tmp/BLEUnlockZhHantDebugDerivedData \
  CODE_SIGNING_ALLOWED=NO
xcodebuild build -project BLEUnlock.xcodeproj -scheme BLEUnlock \
  -configuration Release -derivedDataPath /private/tmp/BLEUnlockZhHantReleaseDerivedData \
  CODE_SIGNING_ALLOWED=NO
test -f build/Release/BLEUnlock.app/Contents/Resources/zh-Hant.lproj/Localizable.strings
test -f build/Release/BLEUnlock.app/Contents/Resources/zh-Hant.lproj/InfoPlist.strings
```

Expected: both builds end with `** BUILD SUCCEEDED **`; both Traditional Chinese resource files exist in the Release app.

- [ ] **Step 10: Review scope and commit only the localization implementation**

Run:

```bash
git status --short
git diff -- BLEUnlockTests/LocalizationTests.swift \
  BLEUnlock/zh-Hant.lproj/Localizable.strings \
  BLEUnlock/zh-Hant.lproj/InfoPlist.strings \
  BLEUnlock.xcodeproj/project.pbxproj
```

Confirm the user's pre-existing shared-scheme change and unrelated `.codegraph/` remain unstaged. Stage the two new resources and test normally, then use patch staging for only the `zh-Hant` Xcode-project hunks if working in the dirty main checkout:

```bash
git add BLEUnlock/zh-Hant.lproj/Localizable.strings \
  BLEUnlock/zh-Hant.lproj/InfoPlist.strings \
  BLEUnlockTests/LocalizationTests.swift
git add -p BLEUnlock.xcodeproj/project.pbxproj
git diff --cached --check
git commit -m "Add Traditional Chinese localization"
```

Expected: the commit contains only the two `zh-Hant` resource files, localization test update, and Xcode resource wiring. User-local Xcode settings and `.codegraph/` remain outside the commit.
