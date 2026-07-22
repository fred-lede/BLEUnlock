import CoreBluetooth
import XCTest
@testable import BLEUnlock

final class BLEScanTests: XCTestCase {
    func testRestartScanStopsAnExistingScanBeforeStartingAgain() {
        let scanner = RecordingBLEScanner(isScanning: true)

        restartBLEScan(using: scanner)

        XCTAssertEqual(scanner.calls, [.stop, .scan])
    }

    func testInvalidAdvertisementRSSIDoesNotStartOrCompleteConfirmation() throws {
        var confirmation = ProximityConfirmation()

        let firstSample = ProximityRSSIGate.acceptedRSSI(rawRSSI: -55,
                                                         centralState: .poweredOn,
                                                         error: nil)
        XCTAssertEqual(firstSample, -55)
        XCTAssertEqual(confirmation.record(rssi: try XCTUnwrap(firstSample),
                                           at: 0,
                                           unlockThreshold: -55),
                       .started(sampleCount: 1, qualifyingCount: 1))

        XCTAssertNil(ProximityRSSIGate.acceptedRSSI(rawRSSI: 127,
                                                     centralState: .poweredOn,
                                                     error: nil))
        XCTAssertNil(ProximityRSSIGate.acceptedRSSI(rawRSSI: 1,
                                                     centralState: .poweredOn,
                                                     error: nil))

        XCTAssertEqual(confirmation.record(rssi: -56,
                                           at: 0.4,
                                           unlockThreshold: -55),
                       .collecting(sampleCount: 2, qualifyingCount: 1))
    }

    func testRSSIReadErrorCannotCompleteConfirmation() throws {
        var confirmation = ProximityConfirmation()
        let sample = ProximityRSSIGate.acceptedRSSI(rawRSSI: -55,
                                                    centralState: .poweredOn,
                                                    error: nil)
        XCTAssertEqual(confirmation.record(rssi: try XCTUnwrap(sample),
                                           at: 0,
                                           unlockThreshold: -55),
                       .started(sampleCount: 1, qualifyingCount: 1))

        XCTAssertNil(ProximityRSSIGate.acceptedRSSI(rawRSSI: -55,
                                                     centralState: .poweredOn,
                                                     error: TestError.readFailed))
        XCTAssertEqual(confirmation.record(rssi: -56,
                                           at: 0.4,
                                           unlockThreshold: -55),
                       .collecting(sampleCount: 2, qualifyingCount: 1))
    }

    func testUnavailableCentralStatesDoNotAcceptStaleSamples() {
        let unavailableStates: [CBManagerState] = [
            .unknown, .resetting, .unsupported, .unauthorized, .poweredOff
        ]

        for state in unavailableStates {
            XCTAssertFalse(ProximityRSSIGate.isMonitoringAvailable(centralState: state))
            XCTAssertNil(ProximityRSSIGate.acceptedRSSI(rawRSSI: -55,
                                                         centralState: state,
                                                         error: nil))
        }
        XCTAssertTrue(ProximityRSSIGate.isMonitoringAvailable(centralState: .poweredOn))
    }
}

private enum TestError: Error {
    case readFailed
}

private final class RecordingBLEScanner: BLEScanning {
    enum Call: Equatable {
        case stop
        case scan
    }

    let isScanning: Bool
    private(set) var calls: [Call] = []

    init(isScanning: Bool) {
        self.isScanning = isScanning
    }

    func stopScan() {
        calls.append(.stop)
    }

    func scanForPeripherals(withServices serviceUUIDs: [CBUUID]?,
                            options: [String: Any]?) {
        calls.append(.scan)
    }
}
