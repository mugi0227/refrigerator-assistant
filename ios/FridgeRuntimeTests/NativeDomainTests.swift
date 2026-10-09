import XCTest
import UIKit
@testable import Fridge
final class NativeDomainTests: XCTestCase {
    func testActualWebExportFixture() throws {
        let url = try XCTUnwrap(Bundle(for:Self.self).url(forResource:"legacy-backup",withExtension:"json"))
        let home = try Household.importBackup(Data(contentsOf:url))
        XCTAssertEqual(home.items.count,2)
        XCTAssertEqual(home.items.first?.barcode,"04901330578909")
        XCTAssertEqual(home.items.first?.opened,true)
        XCTAssertEqual(home.items.last?.quantity,0)
        XCTAssertEqual(home.staples.first?.target,200)
        XCTAssertEqual(home.shopping.first?.done,true)
        XCTAssertEqual(home.settings.location,"freezer")
        XCTAssertFalse(home.settings.externalLookup)
    }
    func testDatesAndGS1Barcode() {
        XCTAssertFalse(FoodRules.validDate("2026-02-30")); XCTAssertTrue(FoodRules.validDate("2028-02-29"))
        XCTAssertEqual(FoodRules.dateFromLabel("賞味期限 ２０２６．１０．３１"),"2026-10-31")
        XCTAssertNil(FoodRules.dateFromLabel("10/31"))
        XCTAssertNil(FoodRules.dateFromLabel("賞味期限 2026.10.31 / 2026.11.01"))
        XCTAssertEqual(NativeReading.barcode("4901330578909")?.code,"04901330578909")
        XCTAssertNil(NativeReading.barcode("https://example.com/?command=delete"))
        XCTAssertEqual(NativeReading.barcode("(01)04901330578909(17)261031")?.expiry?.type,"use_by")
        XCTAssertEqual(NativeReading.barcode("(01)04901330578909(15)260200")?.expiry?.date,"2026-02-28")
        XCTAssertNil(NativeReading.barcode("4901330578900"))
    }
    func testPrintedEvidenceAndManufactureExclusion() {
        func line(_ text: String, _ y: Double = 0.5) -> [String:Any] { ["text":text,"confidence":0.9,"x":0.1,"y":y,"width":0.7,"height":0.05] }
        XCTAssertEqual(NativeReading.printed([line("賞味期限 2026.10.31")])?.type,"best_before")
        XCTAssertEqual(NativeReading.printed([line("2026.10.31")])?.type,"unknown")
        XCTAssertNil(NativeReading.printed([line("製造年月日 2026.10.31")]))
        XCTAssertNil(NativeReading.printed([line("賞味期限 2026.10.31"),line("消費期限 2026.11.01")]))
        XCTAssertEqual(NativeReading.printed([line("賞味期限",0.56),line("2026.10.31")])?.type,"best_before")
        XCTAssertEqual(NativeReading.printed([line("賞味期限",0.9),line("2026.10.31")])?.type,"unknown")
        var dotted = line("賞味期限27:02:01 LA"); dotted["confidence"] = 0.30
        XCTAssertEqual(NativeReading.printed([dotted])?.date,"2027-02-01")
        dotted["text"] = "27:02:01 LA"; XCTAssertNil(NativeReading.printed([dotted]))
        dotted["text"] = "賞味期限27:02:30"; XCTAssertNil(NativeReading.printed([dotted]))
        dotted["text"] = "製造年月日27:02:01"; XCTAssertNil(NativeReading.printed([dotted]))
        XCTAssertNil(NativeReading.printed([line("12:03:05")]))
    }
    @MainActor func testPersistenceConsumptionUndoAndLegacyImport() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:directory) }
        let path = directory.appendingPathComponent("home.json"), store = HouseholdStore(file:path)
        var food = Food(); food.name = "牛乳"; food.quantity = 3; food.expiryType = "best_before"; food.expiryDate = "2026-10-31"
        try store.put(food); XCTAssertEqual(HouseholdStore(file:path).active.first?.name,"牛乳")
        try store.consume(id:food.id,amount:1); XCTAssertEqual(store.active.first?.quantity,2)
        try store.undo(store.state.events[0].id); XCTAssertEqual(store.active.first?.quantity,3)
        XCTAssertThrowsError(try store.undo(store.state.events[1].id))
        var candidate = food; candidate.quantity = 2; try store.consume(candidate:candidate); XCTAssertEqual(store.active.first?.quantity,1)
        let legacy: [String:Any] = ["version":1,"items":[try JSONSerialization.jsonObject(with:JSONEncoder().encode(food))],"staples":[],"shopping":[],"settings":["sound":false,"location":"freezer"]]
        try store.restore(JSONSerialization.data(withJSONObject:legacy)); XCTAssertEqual(store.active.first?.quantity,3); XCTAssertFalse(store.state.settings.sound)
        XCTAssertEqual(store.state.settings.location,"freezer"); XCTAssertTrue(store.state.events.isEmpty)
        var bad = legacy; bad["items"] = [try JSONSerialization.jsonObject(with:JSONEncoder().encode(food)),try JSONSerialization.jsonObject(with:JSONEncoder().encode(food))]
        XCTAssertThrowsError(try store.restore(JSONSerialization.data(withJSONObject:bad)))
        XCTAssertEqual(HouseholdStore(file:path).active.first?.quantity,3)
        let exported = try Household.importBackup(store.export()); XCTAssertEqual(exported.items.count,1)
    }
    func testVisionUncertaintyAndMissingCount() throws {
        XCTAssertNil(try NativeReading.observation("{\"kind\":\"none\"}",location:"fridge"))
        XCTAssertThrowsError(try NativeReading.observation("{\"kind\":\"produce\",\"name\":\"apple\",\"multiple\":true}",location:"fridge"))
        XCTAssertThrowsError(try NativeReading.observation("{\"kind\":\"produce\",\"name\":\"apple and banana\",\"mixed_food_types\":true}",location:"fridge"))
        let food = try NativeReading.observation("{\"kind\":\"produce\",\"name\":\"apple\",\"count\":null}",location:"fridge")
        XCTAssertEqual(food?.name,"りんご"); XCTAssertEqual(food?.quantity,0); XCTAssertNil(food?.expiryDate)
    }
    func testJapaneseFoodReplyAndExpiryEvidence() throws {
        let json = #"{"種類":"野菜・果物","名前":"にんじん","個数":3,"複数種類":false,"不確か":false,"位置":[{"名前":"にんじん","個数":3,"範囲":[100,200,800,900]}]}"#
        XCTAssertEqual(try NativeReading.observation(json,location:"fridge")?.name,"にんじん")
        XCTAssertEqual(FoodRegion.parse(json).first?.name,"にんじん")
        XCTAssertEqual(try NativeReading.observation(json.replacingOccurrences(of:"野菜・果物",with:"果物"),location:"fridge")?.kind,"produce")
        XCTAssertEqual(FoodRules.japaneseFoodName("salad"),"サラダ")
        XCTAssertEqual(FoodRules.japaneseFoodName("unrecognized food"),"食品（名前を確認）")
        let good = #"{"読めた":true,"日付":"2027-02-01","印字":"賞味期限 27.02.01 LA","不確か":false}"#
        XCTAssertEqual(NativeReading.expiryObservation(good)?.type,"best_before")
        XCTAssertNil(NativeReading.expiryObservation(good.replacingOccurrences(of:"賞味期限",with:"製造年月日")))
        XCTAssertNil(NativeReading.expiryObservation(good.replacingOccurrences(of:"27.02.01",with:"27.02.02")))
        XCTAssertNil(NativeReading.expiryObservation(good.replacingOccurrences(of:"27.02.01",with:"02.01")))
        XCTAssertNil(NativeReading.expiryObservation(good.replacingOccurrences(of:"false",with:"true")))
        XCTAssertEqual(NativeReading.expiryObservation("賞味期限 27.02.01 LA")?.date,"2027-02-01")
        XCTAssertEqual(NativeReading.expiryObservation("消費期限 2026/10/12")?.type,"use_by")
        XCTAssertNil(NativeReading.expiryObservation("2027-02-01"))
        XCTAssertNil(NativeReading.expiryObservation("読取不可"))
        XCTAssertNil(NativeReading.expiryObservation("賞味期限 2027.02.01 と推測します"))
        XCTAssertNil(NativeReading.expiryObservation("賞味期限 2027.02.01 / 2027.02.02"))
    }
    @MainActor func testAIExpiryRequiresSeparateConfirmation() throws {
        let store = HouseholdStore(file:FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        let model = NativeAppModel(); model.cameraRunning = true
        model.codes([["text":"4901330578909"]],store:store); let selected = model.candidate?.id
        model.beginExpiry()
        model.aiExpiryProposal = PrintedDate(date:"2027-02-01",type:"best_before",raw:"賞味期限 27.02.01")
        XCTAssertNil(model.candidate?.expiryDate); XCTAssertTrue(store.active.isEmpty)
        model.aiBusy = true; model.applyAIExpiry(); XCTAssertNil(model.candidate?.expiryDate)
        model.aiBusy = false; model.applyAIExpiry()
        XCTAssertEqual(model.candidate?.expiryDate,"2027-02-01"); XCTAssertEqual(model.candidate?.id,selected)
        XCTAssertFalse(model.expiryMode); XCTAssertNil(model.aiExpiryProposal); XCTAssertTrue(store.active.isEmpty)
        model.acceptPrinted([["text":"賞味期限 2028.01.01","confidence":0.9]],stamp:10)
        model.acceptPrinted([["text":"賞味期限 2028.01.01","confidence":0.9]],stamp:11)
        XCTAssertEqual(model.candidate?.expiryDate,"2027-02-01")
        model.beginExpiry(); model.aiExpiryProposal = PrintedDate(date:"2028-01-01",type:"unknown",raw:"28.01.01")
        model.nextFood(); model.applyAIExpiry(); XCTAssertNil(model.candidate)
    }
    func testFoodRegionCoordinatesRejectInventedOrInvalidPositions() {
        let json = #"{"kind":"produce","boxes":[{"label":"apple","count":2,"box_2d":[200,100,700,900]},{"label":"bad","count":1,"box_2d":[-1,0,1001,999]}]}"#
        let boxes = FoodRegion.parse(json)
        XCTAssertEqual(boxes.count,1); XCTAssertEqual(boxes.first?.name,"りんご"); XCTAssertEqual(boxes.first?.count,2)
        XCTAssertEqual(boxes.first?.rect,CGRect(x:0.1,y:0.2,width:0.8,height:0.5))
        XCTAssertTrue(FoodRegion.parse(#"{"kind":"produce","name":"apple","count":2}"#).isEmpty)
        XCTAssertEqual(FoodRegion.imageFrame(image:CGSize(width:600,height:300),canvas:CGSize(width:300,height:400)),CGRect(x:0,y:125,width:300,height:150))
    }
    @MainActor func testFrozenResultAndExpiryModeProtectSelectedItem() throws {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = HouseholdStore(file:path), model = NativeAppModel(); model.cameraRunning = true
        model.codes([["text":"4901330578909"]],store:store)
        let selected = model.candidate?.id
        model.beginExpiry(); XCTAssertTrue(model.expiryMode); XCTAssertEqual(model.candidate?.id,selected)
        model.codes([["text":"4901234567894"]],store:store); XCTAssertEqual(model.candidate?.id,selected)
        model.endExpiry(); XCTAssertFalse(model.expiryMode)
        model.capturedImage = UIImage()
        model.acceptPrinted([["text":"賞味期限 2027.02.01","confidence":0.9]],stamp:1)
        model.acceptPrinted([["text":"賞味期限 2027.02.01","confidence":0.9]],stamp:2)
        XCTAssertNil(model.candidate?.expiryDate)
        model.nextFood(); XCTAssertNil(model.capturedImage); XCTAssertNil(model.candidate); XCTAssertFalse(model.paused)
        XCTAssertTrue(store.active.isEmpty)
    }
    @MainActor func testSaveAndCancelRearmBarcodeAfterFrozenExpiry() async throws {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:path) }
        let store = HouseholdStore(file:path), model = NativeAppModel(); model.cameraRunning = true
        model.codes([["text":"4901330578909"]],store:store)
        var first = try XCTUnwrap(model.candidate); first.name = "牛乳"
        model.beginExpiry(); model.capturedImage = UIImage(); model.paused = true
        try model.confirm(first,store:store); try model.confirm(first,store:store)
        XCTAssertEqual(store.state.events.count,1)
        XCTAssertNil(model.capturedImage); XCTAssertFalse(model.paused); XCTAssertFalse(model.expiryMode)
        model.codes([["text":"4901330578909"]],store:store); XCTAssertNil(model.candidate)
        model.codes([["text":"4901234567894"]],store:store)
        XCTAssertEqual(model.candidate?.barcode,"04901234567894")
        model.beginExpiry(); model.capturedImage = UIImage(); model.paused = true
        model.cancelCandidate()
        XCTAssertNil(model.capturedImage); XCTAssertFalse(model.expiryMode); XCTAssertFalse(model.paused)
        model.codes([["text":"4901234567894"]],store:store); XCTAssertNil(model.candidate)
        try await Task.sleep(nanoseconds:1_600_000_000)
        model.codes([["text":"4901234567894"]],store:store)
        XCTAssertEqual(model.candidate?.barcode,"04901234567894")
        XCTAssertEqual(store.state.events.count,1)
        model.cancelCandidate(); model.nextFood()
        model.codes([["text":"4901234567894"]],store:store)
        XCTAssertNotNil(model.candidate)
    }
    @MainActor func testInvalidDirectSaveKeepsCandidateForEditing() throws {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = HouseholdStore(file:path), model = NativeAppModel()
        var food = Food(); food.name = "牛乳"; food.expiryDate = "2027-02-01"
        model.candidate = food; model.capturedImage = UIImage()
        XCTAssertThrowsError(try model.confirm(food,store:store))
        XCTAssertEqual(model.candidate?.id,food.id); XCTAssertNotNil(model.capturedImage)
        XCTAssertTrue(store.active.isEmpty)
        food.expiryType = "best_before"; try model.confirm(food,store:store)
        XCTAssertEqual(store.active.count,1); XCTAssertNil(model.candidate); XCTAssertNil(model.capturedImage)
    }
    @MainActor func testCountdownCannotCommitAfterTargetChangeOrReview() async throws {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:path) }
        let store = HouseholdStore(file:path), model = NativeAppModel()
        var food = Food(); food.name = "トマト"
        model.stage(food,store:store)
        try await Task.sleep(nanoseconds:5_100_000_000)
        XCTAssertTrue(store.active.isEmpty)
        XCTAssertEqual(model.candidate?.name,"トマト"); XCTAssertEqual(model.countdown,0)
        try model.confirm(food,store:store); try model.confirm(food,store:store)
        XCTAssertEqual(store.active.count,1); XCTAssertEqual(store.state.events.count,1)
        model.nextFood(); model.stage(food,store:store); model.registrationForReview()
        XCTAssertNil(model.pending)
        model.paused = false; model.stage(food,store:store); model.nextFood()
        XCTAssertNil(model.pending); XCTAssertEqual(model.countdown,0)
    }
    @MainActor func testBarcodeThenExpiryUsesDateNotRawTextAndNeverSaves() throws {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = HouseholdStore(file:path), model = NativeAppModel(); model.cameraRunning = true
        model.codes([["text":"4901330578909","x":"0.2","y":"0.3","width":"0.2","height":"0.1"]],store:store)
        XCTAssertEqual(model.marks.count,1)
        XCTAssertEqual(model.candidate?.barcode,"04901330578909")
        func line(_ suffix: String) -> [[String:Any]] { [["text":"賞味期限 2026.10.31 \(suffix)","confidence":0.95,"x":0.2,"y":0.3,"width":0.4,"height":0.05,"metadataX":0.3,"metadataY":0.2,"metadataWidth":0.05,"metadataHeight":0.4]] }
        model.acceptPrinted(line("AB"),stamp:1)
        XCTAssertNil(model.candidate?.expiryDate); XCTAssertTrue(model.marks.contains { $0.isDate })
        model.acceptPrinted(line("CD"),stamp:1); XCTAssertNil(model.candidate?.expiryDate)
        model.acceptPrinted(line("CD"),stamp:2)
        XCTAssertEqual(model.candidate?.expiryDate,"2026-10-31")
        XCTAssertEqual(model.candidate?.expiryType,"best_before"); XCTAssertTrue(store.active.isEmpty)
        model.registrationForReview(); model.acceptPrinted(line("EF"),stamp:3)
        XCTAssertEqual(model.candidate?.expiryDate,"2026-10-31")
        model.nextFood(); XCTAssertNil(model.candidate); XCTAssertTrue(model.marks.isEmpty)
    }
    @MainActor func testDemoDoesNotSaveAndPauseCancelsPending() throws {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = HouseholdStore(file:path), model = NativeAppModel()
        model.demoFood(store:store); model.commit(try XCTUnwrap(model.pending),store:store)
        XCTAssertTrue(store.active.isEmpty); XCTAssertFalse(FileManager.default.fileExists(atPath:path.path))
        model.nextFood(); model.demoFood(store:store); model.pauseScan(); XCTAssertNil(model.pending); XCTAssertEqual(model.countdown,0)
    }
}
