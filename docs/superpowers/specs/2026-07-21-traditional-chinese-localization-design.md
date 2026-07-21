# Traditional Chinese Localization Design

## Goal

Add complete Taiwan Traditional Chinese localization to BLEUnlock while preserving the existing macOS-driven language selection behavior.

## Scope

- Add `zh-Hant.lproj/Localizable.strings` containing every existing BLEUnlock and Telegram localization key.
- Add `zh-Hant.lproj/InfoPlist.strings` with the localized camera usage description.
- Use natural Taiwan terminology, including 「裝置」、「訊號」、「設定」、「螢幕」、「通知」 and 「解鎖」.
- Register Traditional Chinese resources in the Xcode project.
- Extend localization tests so `zh-Hant` is subject to the same completeness, production-reference, and Info.plist checks as every existing locale.

## Language Selection

BLEUnlock will continue using `NSLocalizedString` and macOS bundle localization. It will not add an in-app language selector. Users can select Traditional Chinese through the macOS language order or per-application language setting.

## Compatibility

Existing Base English, Simplified Chinese, Japanese, Danish, German, Norwegian, Swedish, and Turkish resources remain unchanged except where project resource registration requires an Xcode project update. Existing Telegram defaults and behavior are unchanged.

## Verification

Implementation will follow test-driven development:

1. Add `zh-Hant` to localization expectations and observe the focused localization test fail because resources are missing.
2. Add both Traditional Chinese resource files and Xcode project wiring.
3. Run focused localization tests, the complete XCTest suite, and Debug and Release builds.
4. Verify plist syntax, built bundle resources, whitespace, and that no unrelated user-local Xcode settings are staged.

## Success Criteria

- A Traditional Chinese macOS environment displays the complete BLEUnlock interface and Telegram feature in Taiwan Traditional Chinese.
- The camera permission prompt is localized.
- All automated localization and regression tests pass.
- Debug and Release builds succeed.
