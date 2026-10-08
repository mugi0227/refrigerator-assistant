import XCTest
import UIKit
import CoreImage
@testable import Fridge

final class CameraProcessingTests: XCTestCase {
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
        let excluded = try CameraBarcodeReader.detect(image, region: CGRect(x: 0, y: 0, width: 1, height: 0.25))
        XCTAssertTrue(excluded.isEmpty, "A code outside the visible ROI must not be returned")
        let crop = try XCTUnwrap(CameraImageProcessor.aiJPEG(image, context: context))
        let cropImage = try XCTUnwrap(UIImage(data: crop)?.cgImage)
        XCTAssertEqual(cropImage.width, 384); XCTAssertEqual(cropImage.height, 384)
        XCTAssertTrue(try CameraBarcodeReader.detect(XCTUnwrap(CIImage(data: crop))).isEmpty,
                      "Barcode decoding must not be limited to the AI crop")
        let thumbnail = try XCTUnwrap(CameraImageProcessor.thumbnailJPEG(image, context: context))
        let thumbImage = try XCTUnwrap(UIImage(data: thumbnail)?.cgImage)
        XCTAssertLessThanOrEqual(max(thumbImage.width, thumbImage.height), 320)
        print("FRIDGE_CAMERA_EAN13: \(gtin); visible ROI exclusion passed; AI 384px; thumbnail <=320px")
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
