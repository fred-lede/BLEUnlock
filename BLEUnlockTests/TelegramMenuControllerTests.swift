import AppKit
import XCTest
@testable import BLEUnlock

final class TelegramMenuControllerTests: XCTestCase {
    private var defaultsSuiteName: String!
    private var defaults: UserDefaults!
    private var settings: TelegramSettings!
    private var service: RecordingTelegramNotificationService!
    private var dialogs: RecordingTelegramDialogPresenter!
    private var controller: TelegramMenuController!

    override func setUp() {
        super.setUp()
        defaultsSuiteName = "jp.sone.BLEUnlockTests.TelegramMenuController.\(UUID())"
        defaults = UserDefaults(suiteName: defaultsSuiteName)!
        defaults.removePersistentDomain(forName: defaultsSuiteName)
        settings = TelegramSettings(defaults: defaults, secrets: MemorySecretStore())
        service = RecordingTelegramNotificationService()
        dialogs = RecordingTelegramDialogPresenter()
        controller = TelegramMenuController(settings: settings,
                                            service: service,
                                            dialogs: dialogs,
                                            hostName: { "Fred-Mac" })
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: defaultsSuiteName)
        defaultsSuiteName = nil
        defaults = nil
        settings = nil
        service = nil
        dialogs = nil
        controller = nil
        super.tearDown()
    }

    func testUnconfiguredMenuDisablesEnableAndTestAndShowsNotConfigured() {
        controller.menuWillOpen(controller.menu)

        XCTAssertFalse(controller.enableItem.isEnabled)
        XCTAssertFalse(controller.testItem.isEnabled)
        XCTAssertEqual(controller.statusItem.title, t("telegram_status_not_configured"))
    }

    func testConfiguredMenuCanEnableTelegram() throws {
        try settings.saveCredentials(token: "token", chatID: "chat")
        controller.menuWillOpen(controller.menu)

        XCTAssertTrue(controller.enableItem.isEnabled)
        XCTAssertEqual(controller.enableItem.state, .off)

        controller.toggleEnabled(controller.enableItem)

        XCTAssertTrue(settings.isEnabled)
        XCTAssertEqual(controller.enableItem.state, .on)
    }

    func testEventAndPhotoItemsReflectAndPersistSettings() throws {
        try settings.saveCredentials(token: "token", chatID: "chat")
        controller.menuWillOpen(controller.menu)

        XCTAssertEqual(controller.eventItems[.away]?.state, .on)
        XCTAssertEqual(controller.eventItems[.unlocked]?.state, .off)
        XCTAssertEqual(controller.photoItem.state, .on)

        controller.toggleEvent(controller.eventItems[.unlocked]!)
        controller.togglePhoto(controller.photoItem)

        XCTAssertTrue(settings.isEventEnabled(.unlocked))
        XCTAssertFalse(settings.takePhotoOnIntruded)
    }

    func testConfigureLeavesExistingTokenWhenTokenFieldIsBlank() throws {
        try settings.saveCredentials(token: "original", chatID: "old-chat")
        dialogs.credentialInput = .init(replacementToken: nil, chatID: "new-chat")

        controller.configure()

        XCTAssertTrue(dialogs.requestWasOnMainThread)
        XCTAssertEqual(dialogs.hasStoredTokenValues, [true])
        XCTAssertEqual(try settings.credentials(),
                       .init(token: "original", chatID: "new-chat"))
    }

    func testConfigureReplacesTokenWhenNewValueIsEntered() throws {
        try settings.saveCredentials(token: "original", chatID: "old-chat")
        dialogs.credentialInput = .init(replacementToken: " replacement ",
                                        chatID: "new-chat")

        controller.configure()

        XCTAssertEqual(try settings.credentials(),
                       .init(token: "replacement", chatID: "new-chat"))
    }

    func testSendTestCallsServiceAndPresentsResult() throws {
        try settings.saveCredentials(token: "token", chatID: "chat")
        let presented = expectation(description: "Result presented")
        dialogs.onShowResult = { presented.fulfill() }

        controller.sendTest()

        wait(for: [presented], timeout: 2)
        XCTAssertEqual(service.hostNames, ["Fred-Mac"])
        XCTAssertEqual(dialogs.results.count, 1)
        XCTAssertEqual(dialogs.results.first?.title, t("telegram_test_success"))
        XCTAssertTrue(dialogs.showResultWasOnMainThread)
    }
}

private final class RecordingTelegramNotificationService: TelegramNotificationHandling {
    private let lock = NSLock()
    private var recordedHostNames: [String] = []
    var result: Result<Void, Error> = .success(())

    var hostNames: [String] {
        lock.lock()
        defer { lock.unlock() }
        return recordedHostNames
    }

    func handle(_ context: TelegramEventContext) {}

    func sendTest(hostName: String,
                  completion: @escaping (Result<Void, Error>) -> Void) {
        lock.lock()
        recordedHostNames.append(hostName)
        lock.unlock()
        completion(result)
    }
}

private final class RecordingTelegramDialogPresenter: TelegramDialogPresenting {
    struct PresentedResult {
        let title: String
        let message: String
    }

    var credentialInput: TelegramCredentialInput?
    private(set) var hasStoredTokenValues: [Bool] = []
    private(set) var results: [PresentedResult] = []
    private(set) var requestWasOnMainThread = false
    private(set) var showResultWasOnMainThread = false
    var onShowResult: (() -> Void)?

    func requestCredentials(hasStoredToken: Bool,
                            completion: (TelegramCredentialInput?) -> Void) {
        requestWasOnMainThread = Thread.isMainThread
        hasStoredTokenValues.append(hasStoredToken)
        completion(credentialInput)
    }

    func showResult(title: String, message: String) {
        showResultWasOnMainThread = Thread.isMainThread
        results.append(.init(title: title, message: message))
        onShowResult?()
    }
}
