import CoreBluetooth
import XCTest
@testable import BLEUnlock

final class BLEScanTests: XCTestCase {
    func testRestartScanStopsAnExistingScanBeforeStartingAgain() {
        let scanner = RecordingBLEScanner(isScanning: true)

        restartBLEScan(using: scanner)

        XCTAssertEqual(scanner.calls, [.stop, .scan])
    }
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
