import AppKit
import Foundation
import XCTest
@testable import BLEUnlock

final class NotificationServiceTests: XCTestCase {
    private var defaultsSuiteName: String!
    private var defaults: UserDefaults!
    private var settings: NotificationSettings!
    private var telegramSender: RecordingTelegramSender!
    private var synologySender: RecordingSynologySender!
    private var camera: StubPhotoCapturer!
    private var location: StubMacLocationProvider!
    private var reporter: RecordingFailureReporter!
    private var remover: RecordingFileRemover!
    private var service: NotificationService!
    private let photoURL = URL(fileURLWithPath: "/private/tmp/BLEUnlock-test-photo.jpg")

    override func setUp() {
        super.setUp()
        defaultsSuiteName = "jp.sone.BLEUnlockTests.NotificationService.\(UUID())"
        defaults = UserDefaults(suiteName: defaultsSuiteName)
        defaults.removePersistentDomain(forName: defaultsSuiteName)
        settings = NotificationSettings(defaults: defaults,
                                       telegramSecrets: MemorySecretStore(),
                                       synologySecrets: MemorySecretStore())
        telegramSender = RecordingTelegramSender()
        synologySender = RecordingSynologySender()
        camera = StubPhotoCapturer()
        location = StubMacLocationProvider()
        reporter = RecordingFailureReporter()
        remover = RecordingFileRemover()
        service = NotificationService(
            settings: settings,
            telegramSender: telegramSender,
            synologySender: synologySender,
            camera: camera,
            location: location,
            removeFile: remover.remove,
            reporter: reporter
        )
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: defaultsSuiteName)
        defaultsSuiteName = nil
        defaults = nil
        settings = nil
        telegramSender = nil
        synologySender = nil
        camera = nil
        location = nil
        reporter = nil
        remover = nil
        service = nil
        super.tearDown()
    }

    func testDisabledTelegramDoesNothing() throws {
        try settings.saveTelegramCredentials(replacementToken: "token", chatID: "chat")

        service.handle(context(event: .intruded))

        assertNoCameraOrNetworkCalls()
    }

    func testUnconfiguredTelegramDoesNothing() {
        settings.setEnabled(true, for: .telegram)

        service.handle(context(event: .intruded))

        assertNoCameraOrNetworkCalls()
    }

    func testKeychainReadFailureIsReportedWithoutLeakingUnderlyingError() {
        let secret = "token-SECRET"
        let failure = NSError(domain: secret,
                              code: 17,
                              userInfo: [NSLocalizedDescriptionKey: "Could not read \(secret)"])
        settings = NotificationSettings(defaults: defaults,
                                        telegramSecrets: ThrowingSecretStore(error: failure),
                                        synologySecrets: MemorySecretStore())
        settings.setEnabled(true, for: .telegram)
        service = NotificationService(
            settings: settings,
            telegramSender: telegramSender,
            synologySender: synologySender,
            camera: camera,
            location: location,
            removeFile: remover.remove,
            reporter: reporter
        )

        service.handle(context(event: .intruded))

        assertNoCameraOrNetworkCalls()
        XCTAssertEqual(reporter.categories, ["settings"])
        XCTAssertEqual(reporter.messages, [t("notification_error_settings_unavailable")])
        XCTAssertFalse(reporter.messages.joined().contains(secret))
    }

    func testDisabledEventDoesNothing() throws {
        try configure()
        settings.setEvent(.intruded, enabled: false)

        service.handle(context(event: .intruded))

        assertNoCameraOrNetworkCalls()
    }

    func testAwaySendsHostTimeEventAndRSSIAsText() throws {
        try configure()

        service.handle(context(event: .away, rssi: -47))

        XCTAssertEqual(camera.captureCalls, 0)
        XCTAssertEqual(telegramSender.photoCalls.count, 0)
        XCTAssertEqual(telegramSender.textCalls.count, 1)
        let call = try XCTUnwrap(telegramSender.textCalls.first)
        XCTAssertEqual(call.credentials, .init(token: "token", chatID: "chat"))
        let lines = call.text.components(separatedBy: "\n")
        XCTAssertEqual(lines.count, 3)
        let eventDescription = NSLocalizedString("telegram_event_away",
                                                 value: "Device Away",
                                                 comment: "")
        XCTAssertEqual(lines[0], "Fred-Mac — \(eventDescription)")
        XCTAssertTrue(lines[1].hasPrefix("\(t("telegram_message_time")): "))
        XCTAssertEqual(lines[2], "\(t("telegram_message_rssi")): -47 dBm")
    }

    func testIntrudedWithPhotoSendsPhotoAndDeletesFileOnSuccess() throws {
        try configure()
        camera.result = .success(photoURL)

        service.handle(context(event: .intruded))

        XCTAssertEqual(camera.captureCalls, 1)
        XCTAssertEqual(telegramSender.photoCalls.count, 1)
        XCTAssertEqual(telegramSender.photoCalls.first?.photoURL, photoURL)
        XCTAssertEqual(telegramSender.textCalls.count, 0)
        XCTAssertEqual(remover.calls, [photoURL])
        XCTAssertTrue(reporter.categories.isEmpty)
    }

    func testIntrudedDeletesPhotoWhenUploadFailsWithoutTextRetry() throws {
        try configure()
        camera.result = .success(photoURL)
        telegramSender.photoResult = .failure(.transport)

        service.handle(context(event: .intruded))

        XCTAssertEqual(telegramSender.photoCalls.count, 1)
        XCTAssertEqual(telegramSender.textCalls.count, 0)
        XCTAssertEqual(remover.calls, [photoURL])
        XCTAssertEqual(reporter.categories, ["telegram"])
    }

    func testCancelledPhotoUploadDeletesPhotoWithoutTextRetry() throws {
        try configure()
        camera.result = .success(photoURL)
        telegramSender.photoResult = .failure(.transport)

        service.handle(context(event: .intruded))

        XCTAssertEqual(telegramSender.photoCalls.count, 1)
        XCTAssertEqual(telegramSender.textCalls.count, 0)
        XCTAssertEqual(remover.calls, [photoURL])
        XCTAssertEqual(reporter.categories, ["telegram"])
    }

    func testCaptureFailureFallsBackToTextAndReportsFailure() throws {
        try configure()
        camera.result = .failure(.denied)

        service.handle(context(event: .intruded, rssi: -47))

        XCTAssertEqual(telegramSender.photoCalls.count, 0)
        XCTAssertEqual(telegramSender.textCalls.count, 1)
        XCTAssertEqual(reporter.categories, ["camera"])
    }

    func testRequestConstructionFailureDeletesPhoto() throws {
        try configure()
        camera.result = .success(photoURL)
        telegramSender.photoResult = .failure(.invalidRequest)

        service.handle(context(event: .intruded))

        XCTAssertEqual(telegramSender.photoCalls.count, 1)
        XCTAssertEqual(telegramSender.textCalls.count, 0)
        XCTAssertEqual(remover.calls, [photoURL])
        XCTAssertEqual(reporter.categories, ["telegram"])
    }

    func testLocationEnabledSendsCaptionedPhotoThenNativeMap() throws {
        try configure()
        settings.setAttachMacLocation(true, for: .telegram)
        camera.result = .success(photoURL)
        let validLocation = TelegramLocation(latitude: 25.033,
                                             longitude: 121.5654,
                                             horizontalAccuracy: 18,
                                             timestamp: Date(timeIntervalSince1970: 100))
        location.result = .success(validLocation)

        service.handle(context(event: .intruded))

        XCTAssertEqual(telegramSender.photoCalls.count, 1)
        XCTAssertTrue(telegramSender.photoCalls[0].caption.contains("25.033000, 121.565400"))
        XCTAssertEqual(telegramSender.locationCalls.map(\.location), [validLocation])
        XCTAssertEqual(telegramSender.callOrder, [.photo, .location])
    }

    func testLocationDisabledNeverCallsProviderOrSendsMap() throws {
        try configure()
        settings.setAttachMacLocation(false, for: .telegram)
        camera.result = .success(photoURL)

        service.handle(context(event: .intruded))

        XCTAssertTrue(location.requestedDates.isEmpty)
        XCTAssertTrue(telegramSender.locationCalls.isEmpty)
        XCTAssertEqual(telegramSender.callOrder, [.photo])
    }

    func testLocationFailureSendsPhotoWithUnavailableCaptionAndNoMap() throws {
        try configure()
        settings.setAttachMacLocation(true, for: .telegram)
        camera.result = .success(photoURL)
        location.result = .failure(.timeout)

        service.handle(context(event: .intruded))

        XCTAssertTrue(telegramSender.photoCalls[0].caption.contains(t("telegram_location_unavailable")))
        XCTAssertTrue(telegramSender.locationCalls.isEmpty)
        XCTAssertEqual(reporter.categories, ["location"])
        XCTAssertEqual(reporter.messages, [t("telegram_location_error")])
    }

    func testLocatedCameraFailureCancelsLocationAndUsesTextFallbackWithoutCoordinates() throws {
        try configure()
        settings.setAttachMacLocation(true, for: .telegram)
        camera.result = .failure(.denied)
        location.result = .success(.init(latitude: 25.033,
                                         longitude: 121.5654,
                                         horizontalAccuracy: 18,
                                         timestamp: Date(timeIntervalSince1970: 100)))

        service.handle(context(event: .intruded))

        XCTAssertEqual(location.token.cancelCalls, 1)
        XCTAssertEqual(telegramSender.textCalls.count, 1)
        XCTAssertFalse(telegramSender.textCalls[0].text.contains("25.033000"))
        XCTAssertTrue(telegramSender.photoCalls.isEmpty)
        XCTAssertTrue(telegramSender.locationCalls.isEmpty)
        XCTAssertEqual(telegramSender.callOrder, [.text])
    }

    func testPhotoUploadFailureDoesNotSendNativeMapAndCleansFile() throws {
        try configure()
        settings.setAttachMacLocation(true, for: .telegram)
        camera.result = .success(photoURL)
        location.result = .success(.init(latitude: 25.033,
                                         longitude: 121.5654,
                                         horizontalAccuracy: 18,
                                         timestamp: Date(timeIntervalSince1970: 100)))
        telegramSender.photoResult = .failure(.transport)

        service.handle(context(event: .intruded))

        XCTAssertTrue(telegramSender.locationCalls.isEmpty)
        XCTAssertEqual(telegramSender.callOrder, [.photo])
        XCTAssertEqual(remover.calls, [photoURL])
    }

    func testNativeMapFailureReportsWithoutResendingPhoto() throws {
        try configure()
        settings.setAttachMacLocation(true, for: .telegram)
        camera.result = .success(photoURL)
        location.result = .success(.init(latitude: 25.033,
                                         longitude: 121.5654,
                                         horizontalAccuracy: 18,
                                         timestamp: Date(timeIntervalSince1970: 100)))
        telegramSender.locationResult = .failure(.transport)

        service.handle(context(event: .intruded))

        XCTAssertEqual(telegramSender.photoCalls.count, 1)
        XCTAssertEqual(telegramSender.locationCalls.count, 1)
        XCTAssertEqual(telegramSender.callOrder, [.photo, .location])
        XCTAssertEqual(reporter.categories.last, "telegram-location")
        XCTAssertEqual(reporter.messages.last, t("telegram_location_send_error"))
    }

    func testLocatedTestNotificationUsesOneTimestampForCaptionAndLocation() throws {
        try settings.saveTelegramCredentials(replacementToken: "token", chatID: "chat")
        settings.setAttachMacLocation(true, for: .telegram)
        camera.result = .success(photoURL)
        location.result = .success(.init(latitude: 25.033,
                                         longitude: 121.5654,
                                         horizontalAccuracy: 18,
                                         timestamp: Date()))
        let formatter = RecordingNotificationMessageFormatter()
        service = NotificationService(
            settings: settings,
            telegramSender: telegramSender,
            synologySender: synologySender,
            camera: camera,
            location: location,
            removeFile: remover.remove,
            reporter: reporter,
            formatter: formatter
        )
        var result: Result<Void, Error>?

        service.sendTest(hostName: "Fred-Mac") { result = $0 }

        assertSuccess(result)
        XCTAssertEqual(formatter.photoCaptionContexts.count, 1)
        XCTAssertEqual(location.requestedDates, [formatter.photoCaptionContexts[0].timestamp])
    }

    func testTestNotificationUsesPhotoSetting() throws {
        try settings.saveTelegramCredentials(replacementToken: "token", chatID: "chat")
        camera.result = .success(photoURL)
        var photoResult: Result<Void, Error>?

        service.sendTest(hostName: "Fred-Mac") { photoResult = $0 }

        assertSuccess(photoResult)
        XCTAssertEqual(camera.captureCalls, 1)
        XCTAssertEqual(telegramSender.photoCalls.count, 1)
        XCTAssertEqual(telegramSender.textCalls.count, 0)
        XCTAssertEqual(remover.calls, [photoURL])

        settings.setTakePhotoOnIntruded(false, for: .telegram)
        var textResult: Result<Void, Error>?
        service.sendTest(hostName: "Fred-Mac") { textResult = $0 }

        assertSuccess(textResult)
        XCTAssertEqual(camera.captureCalls, 1)
        XCTAssertEqual(telegramSender.photoCalls.count, 1)
        XCTAssertEqual(telegramSender.textCalls.count, 1)
    }

    func testPhotoEnabledTestSurfacesCaptureFailureAfterTextFallback() throws {
        try settings.saveTelegramCredentials(replacementToken: "token", chatID: "chat")
        camera.result = .failure(.denied)
        var result: Result<Void, Error>?

        service.sendTest(hostName: "Fred-Mac") { result = $0 }

        guard case .failure(let error)? = result else {
            return XCTFail("Expected camera failure, got \(String(describing: result))")
        }
        XCTAssertEqual(error as? CameraCaptureError, .denied)
        XCTAssertEqual(telegramSender.textCalls.count, 1,
                       "The test alert may still fall back to text")
        XCTAssertEqual(telegramSender.photoCalls.count, 0)
        XCTAssertEqual(reporter.categories, ["camera"])
    }

    func testUserNotificationDeliveryCreatesAndDeliversOnMainThread() {
        let delivered = expectation(description: "notification delivered")
        let center = RecordingUserNotificationCenter()
        center.onDeliver = { delivered.fulfill() }
        var factoryWasOnMainThread = false
        let delivery = UserNotificationFailureDelivery(
            notificationCenter: center,
            notificationFactory: {
                factoryWasOnMainThread = Thread.isMainThread
                return NSUserNotification()
            }
        )

        DispatchQueue.global(qos: .utility).async {
            delivery.deliver(message: "Offline")
        }

        wait(for: [delivered], timeout: 1)
        XCTAssertTrue(factoryWasOnMainThread)
        XCTAssertTrue(center.deliveryWasOnMainThread)
        XCTAssertEqual(center.notifications.first?.subtitle,
                       t("notification_failure_notification_subtitle"))
        XCTAssertEqual(center.notifications.first?.informativeText, "Offline")
    }

    func testFailureReporterRateLimitsSameFailureForFiveMinutes() {
        var now = Date(timeIntervalSince1970: 100)
        let delivery = RecordingFailureNotificationDelivery()
        let rateLimitedReporter = RateLimitedFailureReporter(
            now: { now },
            interval: 300,
            notificationDelivery: delivery
        )

        rateLimitedReporter.report(category: "camera", message: "Denied")
        rateLimitedReporter.report(category: "camera", message: "Denied again")
        rateLimitedReporter.report(category: "telegram", message: "Offline")
        now.addTimeInterval(299)
        rateLimitedReporter.report(category: "camera", message: "Still denied")

        XCTAssertEqual(delivery.messages, ["Denied", "Offline"])

        now.addTimeInterval(1)
        rateLimitedReporter.report(category: "camera", message: "Denied after interval")

        XCTAssertEqual(delivery.messages, ["Denied", "Offline", "Denied after interval"])
    }

    func testProductionAppWiresCoreLocationIntoTelegramMenuAndService() throws {
        let repository = URL(fileURLWithPath: #file)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(contentsOf: repository.appendingPathComponent(
            "BLEUnlock/AppDelegate.swift"
        ))
        XCTAssertTrue(source.contains("CoreMacLocationProvider"))
        XCTAssertTrue(source.contains("location: macLocationProvider"))
        XCTAssertTrue(source.contains("locationAuthorization: macLocationProvider"))
    }

    func testPhotoCaptionIncludesCoordinatesAccuracyAndEscapedAppleMapsLink() {
        let formatter = NotificationMessageFormatter()
        let context = NotificationEventContext(event: .intruded,
                                               hostName: "Fred-Mac",
                                               timestamp: Date(timeIntervalSince1970: 1_000),
                                               rssi: nil)
        let location = TelegramLocation(latitude: 25.033,
                                        longitude: 121.5654,
                                        horizontalAccuracy: 18.4,
                                        timestamp: context.timestamp)

        let caption = formatter.photoCaption(for: context, location: location)

        XCTAssertTrue(caption.contains("25.033000, 121.565400"))
        XCTAssertTrue(caption.contains("±18 m"))
        XCTAssertTrue(caption.contains("https://maps.apple.com/?ll=25.033000,121.565400"))
    }

    func testPhotoCaptionMarksLocationUnavailableWithoutCoordinates() {
        let formatter = NotificationMessageFormatter()
        let context = NotificationEventContext(event: .intruded,
                                               hostName: "Fred-Mac",
                                               timestamp: Date(timeIntervalSince1970: 1_000),
                                               rssi: nil)

        let caption = formatter.photoCaption(for: context, location: nil)

        XCTAssertTrue(caption.contains(t("telegram_location_unavailable")))
        XCTAssertFalse(caption.contains("maps.apple.com"))
    }

    private func configure() throws {
        try settings.saveTelegramCredentials(replacementToken: "token", chatID: "chat")
        settings.setEnabled(true, for: .telegram)
    }

    private func configureSynology() throws {
        try settings.saveSynologyCredentials(webhookURL: "https://nas.local",
                                             username: "user",
                                             password: "pass",
                                             channelID: "42")
        settings.setEnabled(true, for: .synologyChat)
    }

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

    private func context(event: NotificationEvent, rssi: Int? = nil) -> NotificationEventContext {
        .init(event: event,
              hostName: "Fred-Mac",
              timestamp: Date(timeIntervalSince1970: 100),
              rssi: rssi)
    }

    private func assertNoCameraOrNetworkCalls(file: StaticString = #filePath,
                                              line: UInt = #line) {
        XCTAssertEqual(camera.captureCalls, 0, file: file, line: line)
        XCTAssertTrue(location.requestedDates.isEmpty, file: file, line: line)
        XCTAssertEqual(telegramSender.textCalls.count, 0, file: file, line: line)
        XCTAssertEqual(telegramSender.photoCalls.count, 0, file: file, line: line)
        XCTAssertEqual(telegramSender.locationCalls.count, 0, file: file, line: line)
        XCTAssertEqual(synologySender.textCalls.count, 0, file: file, line: line)
        XCTAssertEqual(synologySender.photoCalls.count, 0, file: file, line: line)
    }

    private func assertSuccess(_ result: Result<Void, Error>?,
                               file: StaticString = #filePath,
                               line: UInt = #line) {
        guard case .success? = result else {
            return XCTFail("Expected success, got \(String(describing: result))",
                           file: file,
                           line: line)
        }
    }
}

private final class RecordingNotificationMessageFormatter: NotificationMessageFormatting {
    private(set) var messageContexts: [NotificationEventContext] = []
    private(set) var photoCaptionContexts: [NotificationEventContext] = []

    func message(for context: NotificationEventContext) -> String {
        messageContexts.append(context)
        return "message"
    }

    func photoCaption(for context: NotificationEventContext,
                      location: TelegramLocation?) -> String {
        photoCaptionContexts.append(context)
        return "caption"
    }
}

private final class RecordingUserNotificationCenter: UserNotificationCenterDelivering {
    private(set) var notifications: [NSUserNotification] = []
    private(set) var deliveryWasOnMainThread = false
    var onDeliver: (() -> Void)?

    func deliver(_ notification: NSUserNotification) {
        deliveryWasOnMainThread = Thread.isMainThread
        notifications.append(notification)
        onDeliver?()
    }
}
