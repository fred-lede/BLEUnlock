import Foundation
import XCTest
@testable import BLEUnlock

final class ProximityMonitorTests: XCTestCase {
    func testCandidateStartsTimeoutAndNormalModeBurst() {
        let fixture = Fixture()

        fixture.monitor.receive(rssi: -60,
                                unlockThreshold: -55,
                                allowsBurst: true)

        XCTAssertEqual(fixture.scheduler.entries.map(\.interval), [1.5, 0.4])
        XCTAssertEqual(fixture.scheduler.entries.map(\.repeats), [false, true])
    }

    func testPassiveModeStartsTimeoutWithoutBurstRequests() {
        let fixture = Fixture()

        fixture.monitor.receive(rssi: -60,
                                unlockThreshold: -55,
                                allowsBurst: false)

        XCTAssertEqual(fixture.scheduler.entries.map(\.interval), [1.5])
        XCTAssertEqual(fixture.sampleRequests, 0)
    }

    func testBurstTickRequestsFreshRSSI() throws {
        let fixture = Fixture()
        fixture.monitor.receive(rssi: -60,
                                unlockThreshold: -55,
                                allowsBurst: true)

        try XCTUnwrap(fixture.scheduler.entries.first { $0.repeats }).action()

        XCTAssertEqual(fixture.sampleRequests, 1)
    }

    func testSecondQualifyingSampleConfirmsOnceAndCancelsTimers() {
        let fixture = Fixture()
        fixture.monitor.receive(rssi: -54,
                                unlockThreshold: -55,
                                allowsBurst: true)
        fixture.now = 0.4

        fixture.monitor.receive(rssi: -55,
                                unlockThreshold: -55,
                                allowsBurst: true)

        XCTAssertEqual(fixture.confirmations, 1)
        XCTAssertTrue(fixture.scheduler.entries.allSatisfy(\.cancellation.isCancelled))
    }

    func testTimeoutRejectsAndStopsBurst() throws {
        let fixture = Fixture()
        fixture.monitor.receive(rssi: -54,
                                unlockThreshold: -55,
                                allowsBurst: true)
        fixture.now = 1.5

        try XCTUnwrap(fixture.scheduler.entries.first { !$0.repeats }).action()

        XCTAssertEqual(fixture.confirmations, 0)
        XCTAssertTrue(fixture.scheduler.entries.allSatisfy(\.cancellation.isCancelled))
        XCTAssertTrue(fixture.messages.contains { $0.contains("timeout") })
    }

    func testResetCancelsAttemptAndPreventsStaleTimeoutConfirmation() throws {
        let fixture = Fixture()
        fixture.monitor.receive(rssi: -54,
                                unlockThreshold: -55,
                                allowsBurst: true)
        let timeout = try XCTUnwrap(fixture.scheduler.entries.first { !$0.repeats })

        fixture.monitor.reset(reason: "device changed")
        fixture.now = 1.5
        timeout.action()

        XCTAssertEqual(fixture.confirmations, 0)
        XCTAssertTrue(timeout.cancellation.isCancelled)
    }
}

private final class Fixture {
    var now: TimeInterval = 0
    var sampleRequests = 0
    var confirmations = 0
    var messages: [String] = []
    let scheduler = ManualProximityScheduler()
    lazy var monitor = ProximityMonitor(
        scheduler: scheduler,
        now: { self.now },
        requestSample: { self.sampleRequests += 1 },
        onConfirmed: { self.confirmations += 1 },
        logger: { self.messages.append($0) }
    )
}

private final class ManualProximityCancellation: ProximityScheduledCancellation {
    private(set) var isCancelled = false
    func cancel() { isCancelled = true }
}

private final class ManualProximityScheduler: ProximityScheduling {
    struct Entry {
        let interval: TimeInterval
        let repeats: Bool
        let cancellation: ManualProximityCancellation
        let action: () -> Void
    }

    private(set) var entries: [Entry] = []

    func schedule(after interval: TimeInterval,
                  repeats: Bool,
                  _ action: @escaping () -> Void) -> ProximityScheduledCancellation {
        let cancellation = ManualProximityCancellation()
        entries.append(Entry(interval: interval,
                             repeats: repeats,
                             cancellation: cancellation,
                             action: action))
        return cancellation
    }
}
