import XCTest
import UIKit
@testable import Fridge

/// Run alone in a new test host. The complete suite has its own long engine test.
final class GemmaImageSmokeTests: XCTestCase {
    @MainActor func testE2BImagesAndEngineReuse() async throws {
        executionTimeAllowance = 180
        let configURL = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "config", withExtension: "json"))
        let config = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: configURL)) as? [String: String])
        let url = URL(fileURLWithPath: try XCTUnwrap(config["modelPath"]))
        let ai = NativeAI()
        try await ai.load(url) { print("GEMMA_SMOKE_STARTUP: \($0)") }
        // Two production prompts, one existing public food fixture and one
        // synthetic Japanese label. No private photograph enters CI or the IPA.
        let appleURL = try XCTUnwrap(Bundle.main.url(forResource:"apple",withExtension:"png",subdirectory:"Probe"))
        let foodJSON = try await ai.run(NativeReading.prompt,image:Data(contentsOf:appleURL))
        print("GEMMA_SMOKE_FOOD_JSON: \(foodJSON)")
        XCTAssertNotNil(NativeReading.object(from:foodJSON),foodJSON)
        let food = try XCTUnwrap(NativeReading.observation(foodJSON,location:"fridge"))
        XCTAssertEqual(food.name,"りんご",foodJSON); XCTAssertEqual(food.quantity,2,foodJSON)
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        let label = try XCTUnwrap(UIGraphicsImageRenderer(size:CGSize(width:1024,height:576),format:format).image { context in
            UIColor.white.setFill(); context.fill(CGRect(x:0,y:0,width:1024,height:576))
            let attributes: [NSAttributedString.Key:Any] = [.font:UIFont.systemFont(ofSize:60),.foregroundColor:UIColor.black]
            ("消費期限 26.11.03" as NSString).draw(at:CGPoint(x:50,y:150),withAttributes:attributes)
            ("製造年月日 26.11.01" as NSString).draw(at:CGPoint(x:50,y:330),withAttributes:attributes)
        }.jpegData(compressionQuality:0.9))
        let expiryJSON = try await ai.run(NativeReading.expiryPrompt,image:label)
        print("GEMMA_SMOKE_EXPIRY_JSON: \(expiryJSON)")
        XCTAssertNoThrow(try JSONSerialization.jsonObject(with:Data(expiryJSON.utf8)),expiryJSON)
        let expiry = try XCTUnwrap(NativeReading.expiryObservation(expiryJSON),expiryJSON)
        XCTAssertEqual(expiry.date,"2026-11-03",expiryJSON); XCTAssertEqual(expiry.type,"use_by",expiryJSON)
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
