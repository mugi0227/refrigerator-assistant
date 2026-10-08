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
        let ready = await ai.isReady()
        XCTAssertTrue(ready)
        try await ai.checkImageInference()
        let text = try await ai.infer(prompt: "Reply with exactly BLUE-47 and nothing else.", image: nil, maxOutputTokens: 32)
        let answer = try XCTUnwrap(text["text"] as? String)
        print("FRIDGE_RUNTIME_TEXT: \(answer)")
        XCTAssertTrue(answer.contains("BLUE-47"), answer)
        for side in [320, 384] {
            let jpeg = await MainActor.run {
                let format = UIGraphicsImageRendererFormat(); format.scale = 1
                return UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format).image { context in
                    UIColor.white.setFill(); context.fill(CGRect(x: 0, y: 0, width: side, height: side))
                    UIColor.red.setFill(); context.fill(CGRect(x: 20, y: 20, width: side - 40, height: side - 40))
                }.jpegData(compressionQuality: 0.85)!
            }
            let dimensions = try XCTUnwrap(UIImage(data: jpeg)?.cgImage)
            XCTAssertEqual(dimensions.width, side); XCTAssertEqual(dimensions.height, side)
            let input = XCTAttachment(data: jpeg, uniformTypeIdentifier: "public.jpeg")
            input.name = "Actual Gemma input \(side)px"; input.lifetime = .keepAlways; add(input)
            let result = try await ai.infer(prompt: "Name the color of the large rectangle in this image. Answer in English with one word.", image: jpeg, maxOutputTokens: 32)
            let reply = try XCTUnwrap(result["text"] as? String)
            print("FRIDGE_RUNTIME_IMAGE_\(side): \(reply)")
            XCTAssertTrue(reply.lowercased().contains("red"), reply)
        }
        try await ai.unload()
    }
}
