import XCTest
import UIKit
@testable import Fridge
final class FridgeRuntimeTests: XCTestCase {
    func testPublicAPIStartupAndConsecutiveImages() async throws {
        executionTimeAllowance = 240
        let configURL = try XCTUnwrap(Bundle(for:Self.self).url(forResource:"config",withExtension:"json"))
        let config = try XCTUnwrap(JSONSerialization.jsonObject(with:Data(contentsOf:configURL)) as? [String:String])
        let ai = NativeAI()
        try await ai.load(URL(fileURLWithPath:try XCTUnwrap(config["modelPath"]))) { print("NATIVE_READY_PHASE: \($0)") }
        let text = try await ai.run("Reply exactly BLUE-47, with no other words.")
        XCTAssertTrue(text.contains("BLUE-47"),text)
        for (color,name) in [(UIColor.red,"red"),(UIColor.blue,"blue")] {
            let jpeg = await MainActor.run {
                let format = UIGraphicsImageRendererFormat(); format.scale = 1
                return UIGraphicsImageRenderer(size:CGSize(width:384,height:384),format:format).image { ctx in color.setFill(); ctx.fill(CGRect(x:0,y:0,width:384,height:384)) }.jpegData(compressionQuality:0.85)!
            }
            let result = try await ai.run("Name the color of the CURRENT image. Answer with one English word. Ignore previous images.",image:jpeg)
            print("NATIVE_PUBLIC_IMAGE \(name): \(result)"); XCTAssertTrue(result.lowercased().contains(name),result)
        }
        let apple = try XCTUnwrap(Bundle.main.url(forResource:"apple",withExtension:"png",subdirectory:"Probe"))
        let response = try await ai.run(NativeReading.prompt,image:Data(contentsOf:apple))
        print("NATIVE_PUBLIC_FOOD: \(response)")
        let food = try NativeReading.observation(response,location:"fridge")
        XCTAssertEqual(food?.name,"りんご"); XCTAssertNil(food?.expiryDate)
        try await ai.unload()
    }
}
