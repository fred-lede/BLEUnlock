import XCTest

final class LocalizationTests: XCTestCase {
    private let telegramKeys: Set<String> = [
        "telegram", "telegram_enable", "telegram_configure", "telegram_test",
        "telegram_events", "telegram_event_away", "telegram_event_lost",
        "telegram_event_unlocked", "telegram_event_intruded",
        "telegram_take_photo", "telegram_status_not_configured",
        "telegram_status_enabled", "telegram_status_disabled",
        "telegram_bot_token", "telegram_chat_id", "telegram_save",
        "telegram_setup_help", "telegram_test_success", "telegram_test_failed",
        "telegram_camera_privacy", "telegram_error_not_configured"
    ]

    func testEveryLocalizationContainsAllTelegramKeys() throws {
        let repository = URL(fileURLWithPath: #file)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let localizationDirectories = ["Base", "da", "de", "ja", "nb", "sv", "tr", "zh-Hans"]

        for name in localizationDirectories {
            let url = repository.appendingPathComponent("BLEUnlock/\(name).lproj/Localizable.strings")
            let data = try Data(contentsOf: url)
            let plist = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
            let values = try XCTUnwrap(plist as? [String: String])
            XCTAssertTrue(telegramKeys.subtracting(values.keys).isEmpty, "Missing keys in \(name)")
        }
    }
}
