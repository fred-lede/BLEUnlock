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

        controller.toggleLocation(controller.locationItem)
        controller.togglePhoto(controller.photoItem)

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
        XCTAssertNil(source.range(of: #"\bTelegramCredentials\b"#, options: .regularExpression))
        XCTAssertNil(source.range(of: #"\bSynologyCredentials\b"#, options: .regularExpression))
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
