import AVFoundation
import CoreImage
import ImageIO
import Vision
import UIKit

final class NativeCamera: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    private let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "fridge.camera")
    private let context = CIContext(options: [.cacheIntermediates: false])
    private let lock = NSLock()
    private var latest: Data?
    private var lastFrame: TimeInterval = 0
    private var configured = false
    var onFrame: ((String, [[String: String]]) -> Void)?

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
                    if !self.configured {
                        self.session.beginConfiguration(); defer { self.session.commitConfiguration() }
                        self.session.sessionPreset = .vga640x480
                        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else { throw FridgeError.message("背面カメラを利用できません。") }
                        let input = try AVCaptureDeviceInput(device: device)
                        guard self.session.canAddInput(input) else { throw FridgeError.message("カメラ入力を開始できません。") }
                        self.session.addInput(input)
                        let output = AVCaptureVideoDataOutput(); output.alwaysDiscardsLateVideoFrames = true
                        output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
                        output.setSampleBufferDelegate(self, queue: self.queue)
                        guard self.session.canAddOutput(output) else { throw FridgeError.message("カメラ映像を取得できません。") }
                        self.session.addOutput(output)
                        if let connection = output.connection(with: .video), connection.isVideoRotationAngleSupported(90) { connection.videoRotationAngle = 90 }
                        self.configured = true
                    }
                    self.lastFrame = 0; self.session.startRunning(); promise.resume()
                } catch { promise.resume(throwing: error) }
            }
        }
    }
    func stop() async {
        await withCheckedContinuation { (promise: CheckedContinuation<Void, Never>) in queue.async {
            self.session.stopRunning(); self.lock.lock(); self.latest = nil; self.lock.unlock(); promise.resume()
        } }
    }
    func image() throws -> Data { lock.lock(); defer { lock.unlock() }; guard let latest else { throw FridgeError.message("カメラ映像を待っています。食品を枠に映してください。") }; return latest }

    func captureOutput(_ output: AVCaptureOutput, didOutput buffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        let now = Date().timeIntervalSince1970
        guard now - lastFrame >= 0.35, let pixels = CMSampleBufferGetImageBuffer(buffer) else { return }
        lastFrame = now
        autoreleasepool {
            let image = CIImage(cvPixelBuffer: pixels), bounds = image.extent
            guard let full = context.createCGImage(image, from: bounds), let jpeg = UIImage(cgImage: full).jpegData(compressionQuality: 0.65) else { return }
            let side = min(bounds.width, bounds.height) * 0.8
            let roi = CGRect(x: bounds.midX - side/2, y: bounds.midY - side/2, width: side, height: side)
            guard let cropped = context.createCGImage(image, from: roi), let input = UIImage(cgImage: cropped).jpegData(compressionQuality: 0.85) else { return }
            lock.lock(); latest = input; lock.unlock()
            let request = VNDetectBarcodesRequest(); request.symbologies = [.ean13, .ean8, .upce, .qr, .dataMatrix, .code128]
            try? VNImageRequestHandler(cgImage: cropped).perform([request])
            let codes = (request.results ?? []).compactMap { result -> [String: String]? in guard let text = result.payloadStringValue else { return nil }; return ["text": text, "format": result.symbology.rawValue] }
            onFrame?(jpeg.base64EncodedString(), codes)
        }
    }
}
