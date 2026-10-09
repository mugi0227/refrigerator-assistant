import XCTest
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
    @MainActor func testCountdownCannotCommitAfterTargetChangeOrReview() async throws {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:path) }
        let store = HouseholdStore(file:path), model = NativeAppModel()
        var food = Food(); food.name = "トマト"
        model.stage(food,store:store)
        model.registrationForReview()
        try await Task.sleep(nanoseconds:5_100_000_000)
        XCTAssertTrue(store.active.isEmpty)
        model.paused = false; model.stage(food,store:store); model.nextFood()
        XCTAssertNil(model.pending); XCTAssertEqual(model.countdown,0)
    }
    @MainActor func testDemoDoesNotSaveAndPauseCancelsPending() throws {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = HouseholdStore(file:path), model = NativeAppModel()
        model.demoFood(store:store); model.commit(try XCTUnwrap(model.pending),store:store)
        XCTAssertTrue(store.active.isEmpty); XCTAssertFalse(FileManager.default.fileExists(atPath:path.path))
        model.nextFood(); model.demoFood(store:store); model.pauseScan(); XCTAssertNil(model.pending); XCTAssertEqual(model.countdown,0)
    }
}
