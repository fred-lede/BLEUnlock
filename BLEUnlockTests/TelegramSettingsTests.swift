import XCTest
@testable import BLEUnlock

final class TelegramSettingsTests: XCTestCase {
    private var defaults: UserDefaults!
    private var secrets: MemorySecretStore!

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: #file)!
        defaults.removePersistentDomain(forName: #file)
        secrets = MemorySecretStore()
    }

    func testDefaultsAreDisabledWithApprovedEventChoices() throws {
        let settings = TelegramSettings(defaults: defaults, secrets: secrets)

        XCTAssertFalse(settings.isEnabled)
        XCTAssertTrue(settings.isEventEnabled(.away))
        XCTAssertTrue(settings.isEventEnabled(.lost))
        XCTAssertFalse(settings.isEventEnabled(.unlocked))
        XCTAssertTrue(settings.isEventEnabled(.intruded))
        XCTAssertTrue(settings.takePhotoOnIntruded)
        XCTAssertFalse(try settings.isConfigured())
    }

    func testPersistsSwitchesAndCredentials() throws {
        let settings = TelegramSettings(defaults: defaults, secrets: secrets)
        settings.isEnabled = true
        settings.setEvent(.away, enabled: false)
        settings.takePhotoOnIntruded = false
        try settings.saveCredentials(token: "token-123", chatID: "987654")

        let reloaded = TelegramSettings(defaults: defaults, secrets: secrets)
        XCTAssertTrue(reloaded.isEnabled)
        XCTAssertFalse(reloaded.isEventEnabled(.away))
        XCTAssertFalse(reloaded.takePhotoOnIntruded)
        XCTAssertEqual(try reloaded.credentials(),
                       TelegramCredentials(token: "token-123", chatID: "987654"))
    }
}
