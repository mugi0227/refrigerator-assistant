import XCTest
import UIKit
@testable import Fridge

/// Run alone in a new test host. The complete suite has its own long engine test.
final class GemmaImageSmokeTests: XCTestCase {
    @MainActor func testE2BImagesAndEngineReuse() async throws {
        executionTimeAllowance = 120
        let configURL = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "config", withExtension: "json"))
        let config = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: configURL)) as? [String: String])
        let url = URL(fileURLWithPath: try XCTUnwrap(config["modelPath"]))
        let ai = NativeAI()
        try await ai.load(url) { print("GEMMA_SMOKE_STARTUP: \($0)") }
        let text = try await ai.run("Reply exactly BLUE-47, with no other words.")
        XCTAssertTrue(text.contains("BLUE-47"), text)
        for (size, color, name) in [(CGSize(width: 384, height: 384), UIColor.red, "red"),
                                    (CGSize(width: 576, height: 1024), UIColor.blue, "blue")] {
            let format = UIGraphicsImageRendererFormat(); format.scale = 1
            let data = try XCTUnwrap(UIGraphicsImageRenderer(size: size, format: format).image { context in
                color.setFill(); context.fill(CGRect(origin: .zero, size: size))
            }.jpegData(compressionQuality: 0.85))
            let output = try await ai.run("Name the color of the CURRENT image. Answer with one English word.", image: data)
            XCTAssertTrue(output.lowercased().contains(name), output)
            print("GEMMA_SMOKE_IMAGE: \(Int(size.width))x\(Int(size.height)) \(output)")
        }
        // The settings start button must renew the same engine, not recreate it.
        try await ai.load(url) { print("GEMMA_SMOKE_REUSE: \($0)") }
        let sameNeedsRelaunch = await ai.requiresRelaunch(for: url)
        let otherNeedsRelaunch = await ai.requiresRelaunch(for: url.appendingPathExtension("other"))
        XCTAssertFalse(sameNeedsRelaunch); XCTAssertTrue(otherNeedsRelaunch)
        try await ai.unload()
        do {
            try await ai.load(url) { _ in }
            XCTFail("A torn-down native engine must never be initialized again in this process")
        } catch { XCTAssertEqual(error.localizedDescription, AIEngineLifetime.relaunchMessage) }
        print("GEMMA_SMOKE_RELAUNCH: guarded before native reinitialization")
    }
}
