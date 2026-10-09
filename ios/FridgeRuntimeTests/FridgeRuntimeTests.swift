import XCTest
import UIKit
import SwiftUI
@testable import Fridge
final class FridgeRuntimeTests: XCTestCase {
    @MainActor private func checkRecipesThroughNativeController(_ model: NativeAppModel) async throws {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:path) }
        let store = HouseholdStore(file:path)
        for name in ["トマト","卵","玉ねぎ"] { var food = Food(); food.name = name; food.quantity = 3; try store.put(food) }
        model.aiReady = true
        await model.makeRecipes(store:store)
        XCTAssertNil(model.alert,model.alert ?? "")
        XCTAssertEqual(model.recipes.count,3)
        XCTAssertTrue(model.recipes.allSatisfy { !$0.name.isEmpty && !$0.steps.isEmpty })
        XCTAssertTrue(model.recipes.allSatisfy { $0.name.range(of:"[ぁ-んァ-ヶ一-龯]",options:.regularExpression) != nil },"Recipe titles must be Japanese")
        print("NATIVE_RECIPES: \(model.recipes.map(\.name))")
    }
    @MainActor func testPublicAPIStartupAndConsecutiveImages() async throws {
        executionTimeAllowance = 360
        let configURL = try XCTUnwrap(Bundle(for:Self.self).url(forResource:"config",withExtension:"json"))
        let config = try XCTUnwrap(JSONSerialization.jsonObject(with:Data(contentsOf:configURL)) as? [String:String])
        let model = NativeAppModel(), ai = model.ai
        try await ai.load(URL(fileURLWithPath:try XCTUnwrap(config["modelPath"]))) { print("NATIVE_READY_PHASE: \($0)") }
        let text = try await ai.run("Reply exactly BLUE-47, with no other words.")
        XCTAssertTrue(text.contains("BLUE-47"),text)
        // Ten images exceeded the former 2048-token retained conversation.
        // Each new color must be independent, even after a settings "restart".
        for index in 0..<10 {
            let (color,name) = index.isMultiple(of:2) ? (UIColor.red,"red"):(UIColor.blue,"blue")
            let jpeg = await MainActor.run {
                let format = UIGraphicsImageRendererFormat(); format.scale = 1
                return UIGraphicsImageRenderer(size:CGSize(width:384,height:384),format:format).image { ctx in color.setFill(); ctx.fill(CGRect(x:0,y:0,width:384,height:384)) }.jpegData(compressionQuality:0.85)!
            }
            let result = try await ai.run("Name the color of the CURRENT image. Answer with one English word. Ignore previous images.",image:jpeg)
            print("NATIVE_PUBLIC_IMAGE \(name): \(result)"); XCTAssertTrue(result.lowercased().contains(name),result)
            if index == 4 { try await ai.load(URL(fileURLWithPath:try XCTUnwrap(config["modelPath"]))) { print("RENEW: \($0)") } }
        }
        let apple = try XCTUnwrap(Bundle.main.url(forResource:"apple",withExtension:"png",subdirectory:"Probe"))
        let scanStore = HouseholdStore(file:FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        model.aiReady = true
        await model.recognize(store:scanStore,photo:try Data(contentsOf:apple))
        let response = model.lastAnswer
        print("NATIVE_PUBLIC_FOOD: \(response)")
        XCTAssertEqual(model.candidate?.name,"りんご"); XCTAssertEqual(model.candidate?.quantity,2)
        XCTAssertNotNil(model.capturedImage); XCTAssertFalse(model.aiBusy); XCTAssertTrue(scanStore.active.isEmpty)
        let region = try XCTUnwrap(model.foodRegions.first)
        XCTAssertEqual(region.name,"りんご"); XCTAssertEqual(region.count,2)
        let expected = CGRect(x:0.17,y:0.275,width:0.66,height:0.365)
        let overlap = region.rect.intersection(expected)
        let intersection = overlap.isNull ? 0:overlap.width*overlap.height
        let union = region.rect.width*region.rect.height+expected.width*expected.height-intersection
        XCTAssertGreaterThan(intersection/union,0.5,"Food boxes must locate the apples, not just return valid coordinates")
        let renderer = ImageRenderer(content:FrozenFoodImage(image:try XCTUnwrap(model.capturedImage),regions:model.foodRegions,processing:false).frame(width:390,height:420))
        if let image = renderer.uiImage {
            let attachment = XCTAttachment(image:image); attachment.name = "Actual Gemma food boxes"; attachment.lifetime = .keepAlways; add(attachment)
        }
        model.nextFood(); XCTAssertNil(model.capturedImage); XCTAssertTrue(model.foodRegions.isEmpty)
        // Exercise the same native error class the device hit, then prove the
        // next request works without rebuilding the model or retaining history.
        do {
            _ = try await ai.run(String(repeating:"apple ",count:3000))
            XCTFail("Oversized prompt should exceed the 2048-token context")
        } catch {
            let message = error.localizedDescription.lowercased()
            XCTAssertTrue(message.contains("prefill") || message.contains("input token ids are too long"),error.localizedDescription)
        }
        let recovered = try await ai.run("Reply exactly BLUE-47, with no other words.")
        XCTAssertTrue(recovered.contains("BLUE-47"),recovered)
        print("NATIVE_ERROR_RECOVERY: \(recovered)")
        // Match normal use: scanning and recipes share one loaded engine.
        // Recreating multiple engines in one process intermittently hangs the
        // upstream runtime during the next Apple startup check on Simulator.
        try await checkRecipesThroughNativeController(model)
        try await ai.unload()
        attachNativeLogs()
    }
    private func attachNativeLogs() {
        let root = FileManager.default.urls(for:.documentDirectory,in:.userDomainMask)[0].appendingPathComponent("NativeAI")
        for folder in (try? FileManager.default.contentsOfDirectory(at:root,includingPropertiesForKeys:nil)) ?? [] {
            for name in ["phases.txt","native-stderr.txt"] {
                if let data = try? Data(contentsOf:folder.appendingPathComponent(name)) {
                    let attachment = XCTAttachment(data:data,uniformTypeIdentifier:"public.plain-text")
                    attachment.name = "NativeAI-\(folder.lastPathComponent)-\(name)"; attachment.lifetime = .keepAlways; add(attachment)
                }
            }
        }
    }
}
