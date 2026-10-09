import XCTest
import UIKit
import CoreImage
@testable import Fridge

final class CameraProcessingTests: XCTestCase {
    func testOutputPixelCoordinatesAreNormalizedBeforeVision() {
        let size = CGSize(width:1080,height:1920)
        let pixels = CGRect(x:135,y:180,width:810,height:1440)
        let roi = CameraCoordinates.visionRect(fromOutputPixels:pixels,size:size)
        XCTAssertEqual(roi.minX,0.125,accuracy:0.00001)
        XCTAssertEqual(roi.minY,0.15625,accuracy:0.00001)
        XCTAssertEqual(roi.width,0.75,accuracy:0.00001)
        XCTAssertEqual(roi.height,0.75,accuracy:0.00001)
        XCTAssertEqual(CameraCoordinates.outputPixels(fromVision:roi,size:size),pixels)
        XCTAssertEqual(CameraCoordinates.visionRect(fromOutputPixels:CGRect(origin:.zero,size:size),size:size),CGRect(x:0,y:0,width:1,height:1))
        let text = CameraCoordinates.outputPixels(fromVision:CGRect(x:0.1,y:0.7,width:0.5,height:0.03),size:size)
        XCTAssertEqual(text.minX,108,accuracy:0.01)
        XCTAssertEqual(text.minY,518.4,accuracy:0.01)
        XCTAssertEqual(text.width,540,accuracy:0.01)
        XCTAssertEqual(text.height,57.6,accuracy:0.01)
        XCTAssertEqual(CameraCoordinates.visionRect(fromOutputPixels:pixels,size:.zero),.zero)
    }
    @MainActor func testPrivateDotPrintedExpiryWhenProvided() throws {
        // Supplied through an ephemeral CI secret, never committed or attached.
        guard let url = Bundle(for:Self.self).url(forResource:"private-expiry",withExtension:"jpg") else {
            throw XCTSkip("Private physical label fixture was not supplied")
        }
        let image = try XCTUnwrap(CIImage(contentsOf:url))
        let roi = CameraCoordinates.visionRect(fromOutputPixels:image.extent,size:image.extent.size)
        let lines = try CameraTextReader.recognize(image,region:roi)
        print("PRIVATE_LABEL_OCR: \(lines)")
        let date = try XCTUnwrap(NativeReading.printed(lines))
        XCTAssertEqual(date.date,"2027-02-01")
        XCTAssertEqual(date.type,"best_before")
        let path = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:path) }
        let model = NativeAppModel(), store = HouseholdStore(file:path)
        model.cameraRunning = true
        model.codes([["text":"4901330578909"]],store:store)
        model.acceptPrinted(lines,stamp:1); model.acceptPrinted(lines,stamp:2)
        XCTAssertEqual(model.candidate?.expiryDate,"2027-02-01")
        XCTAssertEqual(model.candidate?.expiryType,"best_before")
        XCTAssertTrue(store.active.isEmpty)
    }
    func testPrintedExpiryRecognitionUsesHDFrameAndVisibleRegion() async throws {
        let png = await MainActor.run {
            let format = UIGraphicsImageRendererFormat(); format.scale = 1
            return UIGraphicsImageRenderer(size: CGSize(width: 1080, height: 1920), format: format).image { context in
                UIColor.white.setFill(); context.fill(CGRect(x: 0, y: 0, width: 1080, height: 1920))
                let attributes: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 52), .foregroundColor: UIColor.black]
                // Expiry is above the square AI crop, like a package lid.
                ("賞味期限 2026.10.31" as NSString).draw(at: CGPoint(x: 100, y: 350), withAttributes: attributes)
                ("製造年月日 2026.09.01" as NSString).draw(at: CGPoint(x: 100, y: 1300), withAttributes: attributes)
            }.pngData()!
        }
        let attachment = XCTAttachment(data: png, uniformTypeIdentifier: "public.png")
        attachment.name = "HD printed Japanese expiry"; attachment.lifetime = .keepAlways; add(attachment)
        let image = try XCTUnwrap(CIImage(data: png))
        // Aspect-fill removes the left/right margins on a tall iPhone screen.
        // Treating x=54 pixels as normalized would make this ROI empty.
        let roi = CameraCoordinates.visionRect(fromOutputPixels:CGRect(x:54,y:0,width:972,height:1920),size:CGSize(width:1080,height:1920))
        let lines = try CameraTextReader.recognize(image,region:roi)
        let text = lines.compactMap { $0["text"] as? String }.joined(separator: " | ")
        XCTAssertTrue(text.contains("賞味期限"), text); XCTAssertTrue(text.contains("2026.10.31"), text)
        XCTAssertTrue(text.contains("製造年月日"), text); XCTAssertTrue(text.contains("2026.09.01"), text)
        XCTAssertTrue(lines.allSatisfy { ($0["confidence"] as? Double ?? 0) > 0 && $0["x"] is Double })
        let bottomROI = CameraCoordinates.visionRect(fromOutputPixels:CGRect(x:0,y:1152,width:1080,height:768),size:CGSize(width:1080,height:1920))
        let bottom = try CameraTextReader.recognize(image, region: bottomROI)
        XCTAssertFalse(bottom.compactMap { $0["text"] as? String }.joined().contains("2026.10.31"))
        print("FRIDGE_CAMERA_OCR: \(text); high-resolution input and visible ROI verified")
    }
    func testEAN13OutsideAICropAndVisibleRegion() async throws {
        let gtin = "4901234567894"
        // Independent EAN-13 fixture: guards, parity, quiet zones and six-pixel
        // modules. Place it above the square AI crop in a portrait HD frame.
        let png = await MainActor.run {
            let l = ["0001101", "0011001", "0010011", "0111101", "0100011", "0110001", "0101111", "0111011", "0110111", "0001011"]
            let g = ["0100111", "0110011", "0011011", "0100001", "0011101", "0111001", "0000101", "0010001", "0001001", "0010111"]
            let parity = ["LLLLLL", "LLGLGG", "LLGGLG", "LLGGGL", "LGLLGG", "LGGLLG", "LGGGLL", "LGLGLG", "LGLGGL", "LGGLGL"]
            let digits = gtin.compactMap { $0.wholeNumberValue }
            var bars = "101"
            for (i, rule) in parity[digits[0]].enumerated() { bars += rule == "L" ? l[digits[i+1]] : g[digits[i+1]] }
            bars += "01010"
            for digit in digits[7...12] { bars += String(l[digit].map { $0 == "0" ? Character("1") : Character("0") }) }
            bars += "101"
            let format = UIGraphicsImageRendererFormat(); format.scale = 1
            return UIGraphicsImageRenderer(size: CGSize(width: 1080, height: 1920), format: format).image { context in
                UIColor.white.setFill(); context.fill(CGRect(x: 0, y: 0, width: 1080, height: 1920))
                UIColor.black.setFill()
                for (i, bit) in bars.enumerated() where bit == "1" { context.fill(CGRect(x: 200+i*6, y: 360, width: 6, height: 180)) }
            }.pngData()!
        }
        let image = try XCTUnwrap(CIImage(data: png)), context = CIContext()
        let attachment = XCTAttachment(data: png, uniformTypeIdentifier: "public.png")
        attachment.name = "HD EAN13 outside AI crop"; attachment.lifetime = .keepAlways; add(attachment)
        let codes = try CameraBarcodeReader.detect(image)
        XCTAssertTrue(codes.contains { $0["text"] == gtin }, "EAN13 decoding returned \(codes)")
        let box = try XCTUnwrap(codes.first { $0["text"] == gtin })
        XCTAssertEqual(try XCTUnwrap(Double(box["x"] ?? "")),200.0/1080,accuracy:0.04)
        XCTAssertEqual(try XCTUnwrap(Double(box["y"] ?? "")),1-540.0/1920,accuracy:0.04)
        XCTAssertGreaterThan(try XCTUnwrap(Double(box["width"] ?? "")),0.4)
        // Vision revision 1 may report a scanline rather than the full bar height.
        XCTAssertGreaterThan(try XCTUnwrap(Double(box["height"] ?? "")),0)
        let excluded = try CameraBarcodeReader.detect(image, region: CGRect(x: 0, y: 0, width: 1, height: 0.25))
        XCTAssertTrue(excluded.isEmpty, "A code outside the visible ROI must not be returned")
        let crop = try XCTUnwrap(CameraImageProcessor.aiJPEG(image, context: context))
        let cropImage = try XCTUnwrap(UIImage(data: crop)?.cgImage)
        XCTAssertEqual(cropImage.width, 576); XCTAssertEqual(cropImage.height, 1024)
        XCTAssertTrue(try CameraBarcodeReader.detect(XCTUnwrap(CIImage(data: crop))).contains { $0["text"] == gtin },
                      "The new AI image must include the package above the former central square")
        let lower = try XCTUnwrap(CameraImageProcessor.aiJPEG(image,context:context,region:CGRect(x:0,y:0,width:1,height:0.25)))
        XCTAssertTrue(try CameraBarcodeReader.detect(XCTUnwrap(CIImage(data:lower))).isEmpty)
        XCTAssertNil(CameraImageProcessor.aiJPEG(image,context:context,region:.zero))
        let thumbnail = try XCTUnwrap(CameraImageProcessor.thumbnailJPEG(image, context: context))
        let thumbImage = try XCTUnwrap(UIImage(data: thumbnail)?.cgImage)
        XCTAssertLessThanOrEqual(max(thumbImage.width, thumbImage.height), 320)
        print("FRIDGE_CAMERA_EAN13: \(gtin); visible ROI exclusion passed; AI portrait 576x1024; thumbnail <=320px")
    }

    func testQRCodeDecodeWithoutModel() throws {
        let filter = try XCTUnwrap(CIFilter(name: "CIQRCodeGenerator"))
        filter.setValue(Data("4901234567894".utf8), forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel")
        let qr = try XCTUnwrap(filter.outputImage).transformed(by: CGAffineTransform(scaleX: 8, y: 8))
        let white = CIImage(color: .white).cropped(to: qr.extent.insetBy(dx: -32, dy: -32))
        let image = qr.composited(over: white)
        let codes = try CameraBarcodeReader.detect(image)
        XCTAssertTrue(codes.contains { $0["text"] == "4901234567894" }, "QR decoding returned \(codes)")
        print("FRIDGE_CAMERA_QR: 4901234567894")
    }
}
