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
