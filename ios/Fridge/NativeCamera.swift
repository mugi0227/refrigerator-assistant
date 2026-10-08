import AVFoundation
import CoreImage
import ImageIO
import Vision
import UIKit
import OSLog

// Session/delegate state stays on queue; shared AI input is protected by lock.
final class NativeCamera: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, AVCaptureMetadataOutputObjectsDelegate, @unchecked Sendable {
    private let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "fridge.camera")
    private let context = CIContext(options: [.cacheIntermediates: false])
    private let logger = Logger(subsystem: "jp.mugilab.fridge", category: "Camera")
    private let lock = NSLock()
    private var latest: Data?
    private var device: AVCaptureDevice?
    private var videoOutput: AVCaptureVideoDataOutput?
    private var metadataOutput: AVCaptureMetadataOutput?
    private var barcodeRegion = CGRect(x: 0, y: 0, width: 1, height: 1)
    private var lastFrame: TimeInterval = 0
    private var lastFallback: TimeInterval = 0
    private var lastMetadata: TimeInterval = 0
    private var lastCodes: [String] = []
    private var lastCodeEvent: TimeInterval = 0
    private var configured = false
    private var regionConfigured = false
    var onFrame: ((String, [[String: String]]) -> Void)?
    var onCodes: (([[String: String]]) -> Void)?

    func makePreviewLayer() -> AVCaptureVideoPreviewLayer {
        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspectFill
        return layer
    }

    func start() async throws {
        let granted: Bool
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: granted = true
        case .notDetermined: granted = await AVCaptureDevice.requestAccess(for: .video)
        default: granted = false
        }
        guard granted else { throw FridgeError.message("カメラが許可されていません。iPhoneの設定から許可してください。") }
        try await withCheckedThrowingContinuation { (promise: CheckedContinuation<Void, Error>) in
            queue.async {
                do {
                    if !self.configured { try self.configureSession() }
                    try self.configureFocus(at: CGPoint(x: 0.5, y: 0.5))
                    self.lastFrame = 0; self.lastMetadata = 0; self.lastFallback = 0
                    self.lastCodes = []; self.lastCodeEvent = 0
                    self.regionConfigured = false
                    self.session.startRunning()
                    promise.resume()
                } catch { promise.resume(throwing: error) }
            }
        }
    }

    private func configureSession() throws {
        session.beginConfiguration(); defer { session.commitConfiguration() }
        // Prefer a virtual camera so close subjects can use another lens.
        let types: [AVCaptureDevice.DeviceType] = [.builtInTripleCamera, .builtInDualWideCamera, .builtInWideAngleCamera]
        guard let chosen = types.compactMap({ AVCaptureDevice.default($0, for: .video, position: .back) }).first else {
            throw FridgeError.message("背面カメラを利用できません。")
        }
        do {
            for preset in [AVCaptureSession.Preset.hd1920x1080, .hd1280x720, .high] {
                if session.canSetSessionPreset(preset) { session.sessionPreset = preset; break }
            }
            let input = try AVCaptureDeviceInput(device: chosen)
            guard session.canAddInput(input) else { throw FridgeError.message("カメラ入力を開始できません。") }
            session.addInput(input)
            let video = AVCaptureVideoDataOutput(); video.alwaysDiscardsLateVideoFrames = true
            video.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
            video.setSampleBufferDelegate(self, queue: queue)
            guard session.canAddOutput(video) else { throw FridgeError.message("カメラ映像を取得できません。") }
            session.addOutput(video)
            if let connection = video.connection(with: .video), connection.isVideoRotationAngleSupported(90) { connection.videoRotationAngle = 90 }
            videoOutput = video
            let metadata = AVCaptureMetadataOutput()
            if session.canAddOutput(metadata) {
                session.addOutput(metadata); metadata.setMetadataObjectsDelegate(self, queue: queue)
                let wanted: [AVMetadataObject.ObjectType] = [.ean13, .ean8, .upce, .qr, .dataMatrix, .code128]
                metadata.metadataObjectTypes = wanted.filter { metadata.availableMetadataObjectTypes.contains($0) }
                metadataOutput = metadata
            }
            device = chosen
            try chosen.lockForConfiguration(); defer { chosen.unlockForConfiguration() }
            if chosen.activePrimaryConstituentDeviceSwitchingBehavior != .unsupported {
                chosen.setPrimaryConstituentDeviceSwitchingBehavior(.auto, restrictedSwitchingBehaviorConditions: [])
            }
            // Virtual zoom 1 is usually ultra-wide. Begin at the wide field of
            // view while leaving automatic close-focus fallback enabled.
            if chosen.constituentDevices.contains(where: { $0.deviceType == .builtInUltraWideCamera }),
               let wideZoom = chosen.virtualDeviceSwitchOverVideoZoomFactors.first {
                chosen.videoZoomFactor = min(max(CGFloat(wideZoom.doubleValue), chosen.minAvailableVideoZoomFactor), chosen.maxAvailableVideoZoomFactor)
            }
            NotificationCenter.default.addObserver(self, selector: #selector(subjectAreaChanged), name: AVCaptureDevice.subjectAreaDidChangeNotification, object: chosen)
            configured = true
            logger.info("Camera configured: \(chosen.deviceType.rawValue, privacy: .public); minimum focus mm: \(chosen.minimumFocusDistance); preset: \(self.session.sessionPreset.rawValue, privacy: .public)")
        } catch {
            for input in session.inputs { session.removeInput(input) }
            for output in session.outputs { session.removeOutput(output) }
            device = nil; videoOutput = nil; metadataOutput = nil
            throw error
        }
    }

    private func configureFocus(at point: CGPoint) throws {
        guard let device else { throw FridgeError.message("カメラを開始してからピントを合わせてください。") }
        try device.lockForConfiguration(); defer { device.unlockForConfiguration() }
        if device.isFocusPointOfInterestSupported { device.focusPointOfInterest = point }
        if device.isFocusModeSupported(.continuousAutoFocus) { device.focusMode = .continuousAutoFocus }
        if device.isAutoFocusRangeRestrictionSupported { device.autoFocusRangeRestriction = .near }
        if device.isSmoothAutoFocusSupported { device.isSmoothAutoFocusEnabled = false }
        if device.isExposurePointOfInterestSupported { device.exposurePointOfInterest = point }
        if device.isExposureModeSupported(.continuousAutoExposure) { device.exposureMode = .continuousAutoExposure }
        device.isSubjectAreaChangeMonitoringEnabled = true
    }

    func focus(at point: CGPoint) async throws {
        try await withCheckedThrowingContinuation { (promise: CheckedContinuation<Void, Error>) in
            queue.async {
                do {
                    guard self.session.isRunning else { throw FridgeError.message("カメラを開始してからピントを合わせてください。") }
                    try self.configureFocus(at: point); promise.resume()
                } catch { promise.resume(throwing: error) }
            }
        }
    }
    @objc private func subjectAreaChanged() { queue.async { try? self.configureFocus(at: CGPoint(x: 0.5, y: 0.5)) } }

    func updateVisibleRegion(_ region: CGRect) {
        queue.async {
            let clipped = region.intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
            guard !clipped.isNull, clipped.width > 0, clipped.height > 0 else { return }
            self.metadataOutput?.rectOfInterest = clipped
            self.regionConfigured = true
            if let video = self.videoOutput {
                let r = video.outputRectConverted(fromMetadataOutputRect: clipped)
                // Vision uses a bottom-left origin; AVFoundation uses top-left.
                self.barcodeRegion = CGRect(x: r.minX, y: 1 - r.maxY, width: r.width, height: r.height)
            }
        }
    }
    func stop() async {
        await withCheckedContinuation { (promise: CheckedContinuation<Void, Never>) in queue.async {
            self.session.stopRunning(); self.lock.lock(); self.latest = nil; self.lock.unlock(); promise.resume()
        } }
    }
    deinit { NotificationCenter.default.removeObserver(self) }
    func image() throws -> Data { lock.lock(); defer { lock.unlock() }; guard let latest else { throw FridgeError.message("カメラ映像を待っています。食品を枠に映してください。") }; return latest }

    private func emitCodes(_ codes: [[String: String]], at now: TimeInterval) {
        guard !codes.isEmpty else { return }
        let values = codes.compactMap { $0["text"] }.sorted()
        guard values != lastCodes || now - lastCodeEvent >= 0.75 else { return }
        lastCodes = values; lastCodeEvent = now; onCodes?(codes)
    }
    func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput objects: [AVMetadataObject], from connection: AVCaptureConnection) {
        guard session.isRunning, regionConfigured else { return }
        let codes = objects.compactMap { object -> [String: String]? in
            guard let code = object as? AVMetadataMachineReadableCodeObject, let value = code.stringValue else { return nil }
            return ["text": value, "format": code.type.rawValue]
        }
        guard !codes.isEmpty else { return }
        let now = Date().timeIntervalSince1970; lastMetadata = now; emitCodes(codes, at: now)
    }
    func captureOutput(_ output: AVCaptureOutput, didOutput buffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        let now = Date().timeIntervalSince1970
        guard session.isRunning, now - lastFrame >= 0.5, let pixels = CMSampleBufferGetImageBuffer(buffer) else { return }
        lastFrame = now
        autoreleasepool {
            let image = CIImage(cvPixelBuffer: pixels)
            // Decode the high-resolution visible image, independently of Gemma
            // and the small AI crop. Native metadata is the fast primary path.
            if regionConfigured, now - lastMetadata >= 1, now - lastFallback >= 1 {
                lastFallback = now
                if let codes = try? CameraBarcodeReader.detect(image, region: barcodeRegion) { emitCodes(codes, at: now) }
            }
            guard let input = CameraImageProcessor.aiJPEG(image, context: context),
                  let thumbnail = CameraImageProcessor.thumbnailJPEG(image, context: context) else { return }
            lock.lock(); latest = input; lock.unlock()
            // Hidden HTML image is only a thumbnail, never the visible preview.
            onFrame?(thumbnail.base64EncodedString(), [])
        }
    }
}

enum CameraBarcodeReader {
    static func detect(_ image: CIImage, region: CGRect = CGRect(x: 0, y: 0, width: 1, height: 1)) throws -> [[String: String]] {
        let clipped = region.intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
        guard !clipped.isNull, clipped.width > 0, clipped.height > 0 else { return [] }
        #if !targetEnvironment(simulator)
        // Keep current Vision detection on real devices. A legacy CPU decoder
        // also works without the newer system detection model if it cannot load.
        if let codes = try? decode(image, region: clipped, revision: VNDetectBarcodesRequest.defaultRevision), !codes.isEmpty { return codes }
        #endif
        // Hosted Simulator runtimes cannot load the current detection model.
        // Test the same compatibility decoder that is a real-device fallback.
        return try decode(image, region: clipped, revision: VNDetectBarcodesRequestRevision1)
    }
    private static func decode(_ image: CIImage, region: CGRect, revision: Int) throws -> [[String: String]] {
        let request = VNDetectBarcodesRequest()
        request.revision = revision
        if revision == VNDetectBarcodesRequestRevision1 { request.usesCPUOnly = true }
        request.symbologies = [.ean13, .ean8, .upce, .qr, .dataMatrix, .code128]
        request.regionOfInterest = region
        try VNImageRequestHandler(ciImage: image, orientation: .up).perform([request])
        return (request.results ?? []).compactMap { code in
            guard let value = code.payloadStringValue else { return nil }
            return ["text": value, "format": code.symbology.rawValue]
        }
    }
}

enum CameraImageProcessor {
    static func aiJPEG(_ image: CIImage, context: CIContext) -> Data? {
        let bounds = image.extent, side = min(bounds.width, bounds.height) * 0.8
        guard side > 0 else { return nil }
        let roi = CGRect(x: bounds.midX - side/2, y: bounds.midY - side/2, width: side, height: side)
        let input = image.cropped(to: roi).transformed(by: CGAffineTransform(translationX: -roi.minX, y: -roi.minY))
            .transformed(by: CGAffineTransform(scaleX: 384/side, y: 384/side))
        guard let output = context.createCGImage(input, from: CGRect(x: 0, y: 0, width: 384, height: 384)) else { return nil }
        return UIImage(cgImage: output).jpegData(compressionQuality: 0.85)
    }
    static func thumbnailJPEG(_ image: CIImage, context: CIContext) -> Data? {
        let scale = 320 / max(image.extent.width, image.extent.height)
        guard scale > 0, scale.isFinite else { return nil }
        let thumbnail = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        guard let output = context.createCGImage(thumbnail, from: thumbnail.extent) else { return nil }
        return UIImage(cgImage: output).jpegData(compressionQuality: 0.65)
    }
}
