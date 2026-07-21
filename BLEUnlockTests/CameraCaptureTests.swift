import AVFoundation
import Foundation
import XCTest
@testable import BLEUnlock

final class StubCameraAuthorization: CameraAuthorizationProviding {
    var authorizationStatus: AVAuthorizationStatus = .authorized
    var requestResult = true
    private(set) var requestAccessCalls = 0

    func requestAccess(completion: @escaping (Bool) -> Void) {
        requestAccessCalls += 1
        completion(requestResult)
    }
}

final class StubPhotoSession: PhotoSessionProviding {
    var result: Result<Data, CameraCaptureError>?
    private(set) var stopped = false
    private(set) var captureCalls = 0
    private var completion: ((Result<Data, CameraCaptureError>) -> Void)?

    func captureJPEG(completion: @escaping (Result<Data, CameraCaptureError>) -> Void) {
        captureCalls += 1
        self.completion = completion
        if let result = result {
            completion(result)
        }
    }

    func complete(with result: Result<Data, CameraCaptureError>) {
        completion?(result)
    }

    func stop() {
        stopped = true
    }
}

final class StubScheduledCancellation: ScheduledCancellation {
    private(set) var cancelCalls = 0

    func cancel() {
        cancelCalls += 1
    }
}

final class StubCameraScheduler: CameraScheduling {
    private(set) var scheduledIntervals: [TimeInterval] = []
    private(set) var blocks: [() -> Void] = []
    private(set) var cancellations: [StubScheduledCancellation] = []

    @discardableResult
    func schedule(after interval: TimeInterval,
                  _ block: @escaping () -> Void) -> ScheduledCancellation {
        let cancellation = StubScheduledCancellation()
        scheduledIntervals.append(interval)
        blocks.append(block)
        cancellations.append(cancellation)
        return cancellation
    }
}

final class CameraCaptureTests: XCTestCase {
    private var temporaryDirectory: URL!
    private var scheduler: StubCameraScheduler!

    override func setUpWithError() throws {
        try super.setUpWithError()
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("BLEUnlock-CameraCaptureTests-\(UUID().uuidString)",
                                    isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory,
                                                withIntermediateDirectories: true)
        scheduler = StubCameraScheduler()
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: temporaryDirectory)
        scheduler = nil
        temporaryDirectory = nil
        try super.tearDownWithError()
    }

    func testAuthorizedCaptureWritesReturnedJPEGToUniqueTemporaryURL() throws {
        let session = StubPhotoSession()
        let jpeg = Data([0xFF, 0xD8, 0xFF, 0xD9])
        session.result = .success(jpeg)
        let done = expectation(description: "capture")

        CameraCapture(authorization: StubCameraAuthorization(),
                      sessionFactory: { .success(session) },
                      temporaryDirectory: temporaryDirectory,
                      scheduler: scheduler).capture { result in
            do {
                let url = try result.get()
                XCTAssertEqual(try Data(contentsOf: url), jpeg)
                XCTAssertEqual(url.deletingLastPathComponent(), self.temporaryDirectory)
                XCTAssertTrue(url.lastPathComponent.hasPrefix("BLEUnlock-intruded-"))
                XCTAssertEqual(url.pathExtension, "jpg")
                try FileManager.default.removeItem(at: url)
            } catch {
                XCTFail("\(error)")
            }
            done.fulfill()
        }

        wait(for: [done], timeout: 1)
        XCTAssertTrue(session.stopped)
        XCTAssertEqual(scheduler.scheduledIntervals, [10])
        XCTAssertEqual(scheduler.cancellations.first?.cancelCalls, 1)
    }

    func testNotDeterminedRequestsAccessBeforeCapture() {
        let authorization = StubCameraAuthorization()
        authorization.authorizationStatus = .notDetermined
        authorization.requestResult = true
        let session = StubPhotoSession()
        session.result = .success(Data([0xFF, 0xD8, 0xFF, 0xD9]))
        var factoryObservedAccessRequest = false
        let done = expectation(description: "capture")

        CameraCapture(authorization: authorization,
                      sessionFactory: {
                          factoryObservedAccessRequest = authorization.requestAccessCalls == 1
                          return .success(session)
                      },
                      temporaryDirectory: temporaryDirectory,
                      scheduler: scheduler).capture { result in
            if case .success(let url) = result {
                try? FileManager.default.removeItem(at: url)
            } else {
                XCTFail("Expected successful capture, got \(result)")
            }
            done.fulfill()
        }

        wait(for: [done], timeout: 1)
        XCTAssertEqual(authorization.requestAccessCalls, 1)
        XCTAssertTrue(factoryObservedAccessRequest)
        XCTAssertEqual(session.captureCalls, 1)
        XCTAssertTrue(session.stopped)
    }

    func testDeniedPermissionReturnsDeniedWithoutStartingSession() {
        let authorization = StubCameraAuthorization()
        authorization.authorizationStatus = .denied
        var factoryCalls = 0
        let done = expectation(description: "capture")

        CameraCapture(authorization: authorization,
                      sessionFactory: {
                          factoryCalls += 1
                          return .failure(.setupFailed)
                      },
                      temporaryDirectory: temporaryDirectory,
                      scheduler: scheduler).capture { result in
            XCTAssertEqual(try? result.get(), nil)
            if case .failure(let error) = result {
                XCTAssertEqual(error, .denied)
            }
            done.fulfill()
        }

        wait(for: [done], timeout: 1)
        XCTAssertEqual(factoryCalls, 0)
        XCTAssertTrue(scheduler.blocks.isEmpty)
    }

    func testMissingCameraReturnsNoCamera() {
        let done = expectation(description: "capture")

        CameraCapture(authorization: StubCameraAuthorization(),
                      sessionFactory: { .failure(.noCamera) },
                      temporaryDirectory: temporaryDirectory,
                      scheduler: scheduler).capture { result in
            guard case .failure(let error) = result else {
                return XCTFail("Expected failure, got \(result)")
            }
            XCTAssertEqual(error, .noCamera)
            done.fulfill()
        }

        wait(for: [done], timeout: 1)
        XCTAssertTrue(scheduler.blocks.isEmpty)
    }

    func testCaptureTimeoutStopsSessionAndReturnsTimeout() throws {
        let session = StubPhotoSession()
        var results: [Result<URL, CameraCaptureError>] = []

        CameraCapture(authorization: StubCameraAuthorization(),
                      sessionFactory: { .success(session) },
                      temporaryDirectory: temporaryDirectory,
                      scheduler: scheduler).capture { results.append($0) }

        XCTAssertEqual(session.captureCalls, 1)
        XCTAssertFalse(session.stopped)
        let timeout = try XCTUnwrap(scheduler.blocks.first)
        timeout()
        session.complete(with: .success(Data([0xFF, 0xD8, 0xFF, 0xD9])))

        XCTAssertEqual(results.count, 1)
        guard case .failure(let error) = results[0] else {
            return XCTFail("Expected timeout, got \(results[0])")
        }
        XCTAssertEqual(error, .timeout)
        XCTAssertTrue(session.stopped)
        XCTAssertEqual(scheduler.cancellations.first?.cancelCalls, 1)
    }

    func testCaptureFailureStopsSessionAndReturnsCaptureFailed() {
        let session = StubPhotoSession()
        session.result = .failure(.captureFailed)
        let done = expectation(description: "capture")

        CameraCapture(authorization: StubCameraAuthorization(),
                      sessionFactory: { .success(session) },
                      temporaryDirectory: temporaryDirectory,
                      scheduler: scheduler).capture { result in
            guard case .failure(let error) = result else {
                return XCTFail("Expected failure, got \(result)")
            }
            XCTAssertEqual(error, .captureFailed)
            done.fulfill()
        }

        wait(for: [done], timeout: 1)
        XCTAssertTrue(session.stopped)
        XCTAssertEqual(scheduler.cancellations.first?.cancelCalls, 1)
    }
}
