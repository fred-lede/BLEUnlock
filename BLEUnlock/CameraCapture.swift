import AVFoundation
import Foundation

protocol PhotoCapturing {
    func capture(completion: @escaping (Result<URL, CameraCaptureError>) -> Void)
}

enum CameraCaptureError: LocalizedError, Equatable {
    case denied
    case restricted
    case noCamera
    case setupFailed
    case captureFailed
    case timeout
    case fileWriteFailed

    var errorDescription: String? {
        switch self {
        case .denied:
            return "Camera access was denied."
        case .restricted:
            return "Camera access is restricted."
        case .noCamera:
            return "No camera is available."
        case .setupFailed:
            return "The camera could not be configured."
        case .captureFailed:
            return "The camera could not capture a photo."
        case .timeout:
            return "The camera capture timed out."
        case .fileWriteFailed:
            return "The captured photo could not be saved."
        }
    }
}

protocol CameraAuthorizationProviding {
    var authorizationStatus: AVAuthorizationStatus { get }
    func requestAccess(completion: @escaping (Bool) -> Void)
}

protocol PhotoSessionProviding {
    func captureJPEG(completion: @escaping (Result<Data, CameraCaptureError>) -> Void)
    func stop()
}

protocol ScheduledCancellation {
    func cancel()
}

protocol CameraScheduling {
    @discardableResult
    func schedule(after interval: TimeInterval,
                  _ block: @escaping () -> Void) -> ScheduledCancellation
}

protocol AbandonablePhotoCaptureDelegate: AnyObject {
    func abandon()
}

final class PhotoSessionLifecycle {
    private let stateLock = NSLock()
    private let actionGate = NSRecursiveLock()
    private var cancelled = false
    private var activeDelegates: [ObjectIdentifier: AbandonablePhotoCaptureDelegate] = [:]
    private var abandonedDelegates: [ObjectIdentifier: AbandonablePhotoCaptureDelegate] = [:]

    func install(delegate: AbandonablePhotoCaptureDelegate) -> Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        guard !cancelled else { return false }
        activeDelegates[ObjectIdentifier(delegate)] = delegate
        return true
    }

    @discardableResult
    func performIfActive(_ action: () -> Void) -> Bool {
        actionGate.lock()
        defer { actionGate.unlock() }

        stateLock.lock()
        let isActive = !cancelled
        stateLock.unlock()
        guard isActive else { return false }

        action()
        return true
    }

    func cancel() {
        stateLock.lock()
        guard !cancelled else {
            stateLock.unlock()
            return
        }
        cancelled = true
        let delegates = Array(activeDelegates.values)
        for delegate in delegates {
            let identifier = ObjectIdentifier(delegate)
            abandonedDelegates[identifier] = delegate
            activeDelegates[identifier] = nil
        }
        stateLock.unlock()

        delegates.forEach { $0.abandon() }

        actionGate.lock()
        actionGate.unlock()
    }

    func didFinishCallback(for delegate: AbandonablePhotoCaptureDelegate) {
        stateLock.lock()
        let identifier = ObjectIdentifier(delegate)
        activeDelegates[identifier] = nil
        abandonedDelegates[identifier] = nil
        stateLock.unlock()
    }
}

final class CameraCapture: PhotoCapturing {
    private let authorization: CameraAuthorizationProviding
    private let sessionFactory: () -> Result<PhotoSessionProviding, CameraCaptureError>
    private let temporaryDirectory: URL
    private let scheduler: CameraScheduling
    private let timeout: TimeInterval

    init(authorization: CameraAuthorizationProviding = AVCameraAuthorization(),
         sessionFactory: @escaping () -> Result<PhotoSessionProviding, CameraCaptureError> = AVPhotoSession.make,
         temporaryDirectory: URL = FileManager.default.temporaryDirectory,
         scheduler: CameraScheduling = DispatchCameraScheduler(),
         timeout: TimeInterval = 10) {
        self.authorization = authorization
        self.sessionFactory = sessionFactory
        self.temporaryDirectory = temporaryDirectory
        self.scheduler = scheduler
        self.timeout = timeout
    }

    func capture(completion: @escaping (Result<URL, CameraCaptureError>) -> Void) {
        switch authorization.authorizationStatus {
        case .authorized:
            captureAuthorized(completion: completion)
        case .notDetermined:
            authorization.requestAccess { granted in
                guard granted else {
                    completion(.failure(.denied))
                    return
                }
                self.captureAuthorized(completion: completion)
            }
        case .denied:
            completion(.failure(.denied))
        case .restricted:
            completion(.failure(.restricted))
        @unknown default:
            completion(.failure(.restricted))
        }
    }

    private func captureAuthorized(
        completion: @escaping (Result<URL, CameraCaptureError>) -> Void
    ) {
        let session: PhotoSessionProviding
        switch sessionFactory() {
        case .success(let createdSession):
            session = createdSession
        case .failure(let error):
            completion(.failure(error))
            return
        }

        let stateLock = NSLock()
        var didFinish = false
        var timeoutCancellation: ScheduledCancellation?

        let finish: (Result<Data, CameraCaptureError>) -> Void = { [temporaryDirectory] result in
            stateLock.lock()
            guard !didFinish else {
                stateLock.unlock()
                return
            }
            didFinish = true
            let cancellation = timeoutCancellation
            timeoutCancellation = nil
            stateLock.unlock()

            cancellation?.cancel()
            session.stop()

            switch result {
            case .success(let jpeg):
                let url = temporaryDirectory
                    .appendingPathComponent("BLEUnlock-intruded-\(UUID().uuidString)")
                    .appendingPathExtension("jpg")
                do {
                    try jpeg.write(to: url, options: .atomic)
                    completion(.success(url))
                } catch {
                    completion(.failure(.fileWriteFailed))
                }
            case .failure(let error):
                completion(.failure(error))
            }
        }

        session.captureJPEG(completion: finish)

        let cancellation = scheduler.schedule(after: timeout) {
            finish(.failure(.timeout))
        }
        stateLock.lock()
        let captureAlreadyFinished = didFinish
        if !captureAlreadyFinished {
            timeoutCancellation = cancellation
        }
        stateLock.unlock()
        if captureAlreadyFinished {
            cancellation.cancel()
        }
    }
}

final class AVCameraAuthorization: CameraAuthorizationProviding {
    var authorizationStatus: AVAuthorizationStatus {
        AVCaptureDevice.authorizationStatus(for: .video)
    }

    func requestAccess(completion: @escaping (Bool) -> Void) {
        AVCaptureDevice.requestAccess(for: .video, completionHandler: completion)
    }
}

private final class DispatchScheduledCancellation: ScheduledCancellation {
    private let lock = NSLock()
    private var workItem: DispatchWorkItem?

    init(workItem: DispatchWorkItem) {
        self.workItem = workItem
    }

    func cancel() {
        lock.lock()
        let item = workItem
        workItem = nil
        lock.unlock()
        item?.cancel()
    }
}

final class DispatchCameraScheduler: CameraScheduling {
    private let queue: DispatchQueue

    init(queue: DispatchQueue = DispatchQueue.global(qos: .utility)) {
        self.queue = queue
    }

    @discardableResult
    func schedule(after interval: TimeInterval,
                  _ block: @escaping () -> Void) -> ScheduledCancellation {
        let workItem = DispatchWorkItem(block: block)
        queue.asyncAfter(deadline: .now() + interval, execute: workItem)
        return DispatchScheduledCancellation(workItem: workItem)
    }
}

final class AVPhotoSession: PhotoSessionProviding {
    private let session: AVCaptureSession
    private let output: AVCapturePhotoOutput
    private let queue = DispatchQueue(label: "jp.sone.BLEUnlock.camera-capture")
    private let lifecycle = PhotoSessionLifecycle()

    private init(session: AVCaptureSession, output: AVCapturePhotoOutput) {
        self.session = session
        self.output = output
    }

    static func make() -> Result<PhotoSessionProviding, CameraCaptureError> {
        guard let camera = AVCaptureDevice.default(for: .video) else {
            return .failure(.noCamera)
        }

        let input: AVCaptureDeviceInput
        do {
            input = try AVCaptureDeviceInput(device: camera)
        } catch {
            return .failure(.setupFailed)
        }

        let session = AVCaptureSession()
        let output = AVCapturePhotoOutput()
        session.beginConfiguration()
        defer { session.commitConfiguration() }

        guard session.canAddInput(input), session.canAddOutput(output) else {
            return .failure(.setupFailed)
        }
        session.addInput(input)
        session.addOutput(output)
        return .success(AVPhotoSession(session: session, output: output))
    }

    func captureJPEG(completion: @escaping (Result<Data, CameraCaptureError>) -> Void) {
        queue.async { [self] in
            let proxy = AVPhotoCaptureDelegateProxy(completion: completion) { [lifecycle] proxy in
                lifecycle.didFinishCallback(for: proxy)
            }
            guard lifecycle.install(delegate: proxy) else {
                proxy.abandon()
                return
            }
            guard lifecycle.performIfActive({ session.startRunning() }) else {
                proxy.abandon()
                lifecycle.didFinishCallback(for: proxy)
                return
            }
            guard lifecycle.performIfActive({
                output.capturePhoto(with: AVCapturePhotoSettings(), delegate: proxy)
            }) else {
                proxy.abandon()
                lifecycle.didFinishCallback(for: proxy)
                return
            }
        }
    }

    func stop() {
        lifecycle.cancel()
        queue.async { [session] in
            if session.isRunning {
                session.stopRunning()
            }
        }
    }
}

private final class AVPhotoCaptureDelegateProxy: NSObject,
                                                 AVCapturePhotoCaptureDelegate,
                                                 AbandonablePhotoCaptureDelegate {
    private let lock = NSLock()
    private var didComplete = false
    private var completion: ((Result<Data, CameraCaptureError>) -> Void)?
    private let callbackFinished: (AVPhotoCaptureDelegateProxy) -> Void

    init(completion: @escaping (Result<Data, CameraCaptureError>) -> Void,
         callbackFinished: @escaping (AVPhotoCaptureDelegateProxy) -> Void) {
        self.completion = completion
        self.callbackFinished = callbackFinished
    }

    func photoOutput(_ output: AVCapturePhotoOutput,
                     didFinishProcessingPhoto photo: AVCapturePhoto,
                     error: Error?) {
        let result: Result<Data, CameraCaptureError>
        if error != nil {
            result = .failure(.captureFailed)
        } else if let data = photo.fileDataRepresentation() {
            result = .success(data)
        } else {
            result = .failure(.captureFailed)
        }
        finish(result)
    }

    private func finish(_ result: Result<Data, CameraCaptureError>) {
        lock.lock()
        guard !didComplete else {
            lock.unlock()
            return
        }
        didComplete = true
        let completion = self.completion
        self.completion = nil
        lock.unlock()
        completion?(result)
        callbackFinished(self)
    }

    func abandon() {
        lock.lock()
        completion = nil
        lock.unlock()
    }
}
