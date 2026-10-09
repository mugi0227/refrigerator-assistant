import XCTest
import UIKit
@testable import Fridge

final class FridgeRuntimeTests: XCTestCase {
    func testActualGemmaTextAndJPEGInference() async throws {
        let configURL = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "config", withExtension: "json"))
        let config = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: configURL)) as? [String: String])
        let modelPath = try XCTUnwrap(config["modelPath"])
        let ai = LocalAI()
        print("FRIDGE_RUNTIME_BACKEND: \(LocalAI.runtimeLabel)")
        let cache = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try await ai.load(URL(fileURLWithPath: modelPath), cache: cache)
        try await ai.checkImageInference()
        let ready = await ai.isReady()
        XCTAssertTrue(ready)
        let text = try await ai.infer(prompt: "Reply with exactly BLUE-47 and nothing else.", image: nil, maxOutputTokens: 32)
        let answer = try XCTUnwrap(text["text"] as? String)
        print("FRIDGE_RUNTIME_TEXT: \(answer)")
        XCTAssertTrue(answer.contains("BLUE-47"), answer)
        for (side, colorName) in [(320, "red"), (384, "blue")] {
            let jpeg = await MainActor.run {
                let format = UIGraphicsImageRendererFormat(); format.scale = 1
                return UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format).image { context in
                    UIColor.white.setFill(); context.fill(CGRect(x: 0, y: 0, width: side, height: side))
                    (colorName == "red" ? UIColor.red : UIColor.blue).setFill(); context.fill(CGRect(x: 20, y: 20, width: side - 40, height: side - 40))
                }.jpegData(compressionQuality: 0.85)!
            }
            let dimensions = try XCTUnwrap(UIImage(data: jpeg)?.cgImage)
            XCTAssertEqual(dimensions.width, side); XCTAssertEqual(dimensions.height, side)
            let input = XCTAttachment(data: jpeg, uniformTypeIdentifier: "public.jpeg")
            input.name = "Actual Gemma input \(side)px"; input.lifetime = .keepAlways; add(input)
            let result = try await ai.infer(prompt: "Name the color of the large rectangle in this image. Answer in English with one word.", image: jpeg, maxOutputTokens: 32)
            let reply = try XCTUnwrap(result["text"] as? String)
            print("FRIDGE_RUNTIME_IMAGE_\(side): \(reply)")
            XCTAssertTrue(reply.lowercased().contains(colorName), reply)
        }
        // Use the app's real scanner prompt, generated from promptFor(null),
        // rather than validating only one-word toy prompts.
        let promptURL = try XCTUnwrap(Bundle.main.url(forResource: "scanner-prompt", withExtension: "txt", subdirectory: "Web"))
        let appleURL = try XCTUnwrap(Bundle.main.url(forResource: "apple", withExtension: "png", subdirectory: "Probe"))
        let scanned = try await ai.infer(prompt: String(contentsOf: promptURL, encoding: .utf8), image: Data(contentsOf: appleURL), maxOutputTokens: 256)
        let scannedText = try XCTUnwrap(scanned["text"] as? String)
        print("FRIDGE_RUNTIME_SCANNER_JSON: \(scannedText)")
        let scannedStart = try XCTUnwrap(scannedText.firstIndex(of: "{"))
        let scannedEnd = try XCTUnwrap(scannedText.lastIndex(of: "}"))
        let scannedJSON = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(scannedText[scannedStart...scannedEnd].utf8)) as? [String: Any])
        XCTAssertEqual(scannedJSON["kind"] as? String, "produce", scannedText)
        let name = scannedJSON["name"] as? String ?? ""
        XCTAssertTrue(["りんご", "リンゴ", "林檎", "apple"].contains(where: { name.lowercased().contains($0) }), scannedText)
        XCTAssertTrue(scannedJSON["expiry"] is NSNull, scannedText)
        // Exercise readable food/expiry text and complete streamed JSON, not
        // only a color word. This is a generated label, not a camera benchmark.
        let label = await MainActor.run {
            let format = UIGraphicsImageRendererFormat(); format.scale = 1
            return UIGraphicsImageRenderer(size: CGSize(width: 384, height: 384), format: format).image { context in
                UIColor.white.setFill(); context.fill(CGRect(x: 0, y: 0, width: 384, height: 384))
                let attributes: [NSAttributedString.Key: Any] = [.font: UIFont.boldSystemFont(ofSize: 44), .foregroundColor: UIColor.black]
                ("MILK" as NSString).draw(at: CGPoint(x: 40, y: 40), withAttributes: attributes)
                let small: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 26), .foregroundColor: UIColor.black]
                ("BEST BEFORE" as NSString).draw(at: CGPoint(x: 40, y: 170), withAttributes: small)
                ("2026-10-31" as NSString).draw(at: CGPoint(x: 40, y: 220), withAttributes: attributes.merging([.font: UIFont.boldSystemFont(ofSize: 36)]) { _, new in new })
            }.jpegData(compressionQuality: 0.85)!
        }
        let input = XCTAttachment(data: label, uniformTypeIdentifier: "public.jpeg")
        input.name = "Generated milk expiry label"; input.lifetime = .keepAlways; add(input)
        let result = try await ai.infer(prompt: "Read the food name and BEST BEFORE date printed in this image. Return only JSON with keys food and date. Use the English food name and YYYY-MM-DD date. Do not guess.", image: label, maxOutputTokens: 64)
        let reply = try XCTUnwrap(result["text"] as? String)
        print("FRIDGE_RUNTIME_FOOD_LABEL: \(reply)")
        let start = try XCTUnwrap(reply.firstIndex(of: "{"))
        let end = try XCTUnwrap(reply.lastIndex(of: "}"))
        let data = try XCTUnwrap(String(reply[start...end]).data(using: .utf8))
        let food = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: String])
        XCTAssertEqual(food["food"]?.lowercased(), "milk", reply)
        XCTAssertEqual(food["date"], "2026-10-31", reply)
        try await ai.unload()
        let unloaded = await ai.isReady()
        XCTAssertFalse(unloaded)
    }

    func testCancellationIsScopedToOneOperation() throws {
        let cancellation = InferenceCancellation()
        let old = InferenceOperation(); cancellation.set(old); cancellation.cancel()
        XCTAssertThrowsError(try old.check())
        let next = InferenceOperation(); cancellation.set(next)
        old.cancel() // A late watchdog must not touch the next request.
        XCTAssertNoThrow(try next.check())
        cancellation.cancel()
        XCTAssertThrowsError(try next.check())
        cancellation.set(nil)
    }
}
