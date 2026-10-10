import XCTest
final class FridgeUITests: XCTestCase {
    func testNativePersistenceAndNoWebView() {
        continueAfterFailure = false
        let app = XCUIApplication(); app.launch()
        let add = app.buttons["addFood"]
        XCTAssertTrue(add.waitForExistence(timeout:20)); XCTAssertEqual(app.webViews.count,0)
        // One-tap presets put real foods on the shelves, so the screenshots show the fridge as people see it.
        for (index,preset) in ["牛乳","卵","トマト"].enumerated() {
            add.tap()
            let button = app.buttons["preset-\(preset)"]; XCTAssertTrue(button.waitForExistence(timeout:5))
            if index == 0 { snapshot(app,"Add sheet with presets") }
            button.tap()
            if index == 2 { snapshot(app,"Add sheet after tapping a preset") }
            app.buttons["saveFoodToolbar"].tap()
            XCTAssertTrue(app.buttons.matching(NSPredicate(format:"label BEGINSWITH %@",preset)).firstMatch.waitForExistence(timeout:5))
        }
        add.tap()
        let name = app.textFields["foodName"]; XCTAssertTrue(name.waitForExistence(timeout:5)); name.tap(); name.typeText("native-persistence-probe")
        app.buttons["saveFoodToolbar"].tap()
        let probe = app.buttons.matching(NSPredicate(format:"label CONTAINS %@","native-persistence-probe")).firstMatch
        XCTAssertTrue(probe.waitForExistence(timeout:10))
        snapshot(app,"Fridge shelves")
        probe.tap()
        XCTAssertTrue(app.buttons["consumeOne"].waitForExistence(timeout:5))
        snapshot(app,"Food detail sheet")
        app.buttons["consumeOne"].tap()
        XCTAssertTrue(app.buttons["undoToast"].waitForExistence(timeout:5))
        app.buttons["undoToast"].tap()
        XCTAssertTrue(probe.waitForExistence(timeout:5))
        app.terminate(); app.launch(); XCTAssertTrue(probe.waitForExistence(timeout:10))
        for tab in ["買い物","スキャン","献立","設定"] {
            app.tabBars.buttons[tab].tap(); XCTAssertEqual(app.webViews.count,0)
            snapshot(app,"Native \(tab)")
        }
        XCTAssertTrue(app.buttons["loadAI"].exists); XCTAssertTrue(app.staticTexts["v0.3.7 · ネイティブ版"].exists)
        app.tabBars.buttons["買い物"].tap(); app.textFields["買うもの"].tap(); app.textFields["買うもの"].typeText("bread"); app.buttons["追加"].tap()
        XCTAssertTrue(app.buttons["bread"].waitForExistence(timeout:5))
        snapshot(app,"Shopping with memo")
        app.terminate(); app.launch(); app.tabBars.buttons["買い物"].tap(); XCTAssertTrue(app.buttons["bread"].waitForExistence(timeout:5))
    }
    private func snapshot(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot:app.screenshot()); shot.name = name; shot.lifetime = .keepAlways; add(shot)
    }
    func testScannerCandidateRequiresConfirmation() {
        let app = XCUIApplication(); app.launch(); app.tabBars.buttons["スキャン"].tap()
        app.buttons["scanMenu"].tap(); app.buttons["操作デモ：牛乳と期限"].tap()
        XCTAssertTrue(app.buttons["reviewCandidate"].waitForExistence(timeout:5))
        app.buttons["readExpiry"].tap()
        XCTAssertTrue(app.buttons["撮影を終える"].waitForExistence(timeout:5))
        XCTAssertFalse(app.buttons["aiShutter"].exists)
        // The read date and an in-place register button are shown without leaving expiry mode.
        XCTAssertTrue(app.staticTexts["adoptedExpiry"].exists); XCTAssertTrue(app.buttons["registerFromExpiry"].exists)
        let expiry = XCTAttachment(screenshot:app.screenshot()); expiry.name = "Expiry mode adopted date"; expiry.lifetime = .keepAlways; add(expiry)
        app.buttons["撮影を終える"].tap()
        app.buttons["期限を手入力"].tap()
        XCTAssertTrue(app.buttons["applyExpiry"].waitForExistence(timeout:5))
        XCTAssertFalse(app.textFields["foodName"].exists)
        app.buttons["applyExpiry"].tap()
        XCTAssertTrue(app.buttons["reviewCandidate"].waitForExistence(timeout:5))
        let shot = XCTAttachment(screenshot:app.screenshot()); shot.name = "Scanner candidate chips"; shot.lifetime = .keepAlways; add(shot)
        app.buttons["reviewCandidate"].tap()
        XCTAssertFalse(app.textFields["foodName"].exists)
        XCTAssertFalse(app.buttons["reviewCandidate"].exists)
        XCTAssertTrue(app.staticTexts["scanStatus"].label.contains("デモ"))
    }
    func testFrozenImageProcessingAndNextCapture() {
        let app = XCUIApplication(); app.launch(); app.tabBars.buttons["スキャン"].tap()
        app.buttons["scanMenu"].tap(); app.buttons["表示テスト：AIの静止画"].tap()
        XCTAssertTrue(app.otherElements["frozenAIImage"].waitForExistence(timeout:3) || app.images["AIに渡した写真"].exists)
        let busy = XCTAttachment(screenshot:app.screenshot()); busy.name = "Frozen image rainbow processing"; busy.lifetime = .keepAlways; add(busy)
        XCTAssertTrue(app.buttons["nextCapture"].waitForExistence(timeout:10))
        XCTAssertTrue(app.staticTexts["りんご · 2個"].exists)
        let done = XCTAttachment(screenshot:app.screenshot()); done.name = "Frozen image food labels"; done.lifetime = .keepAlways; add(done)
        app.buttons["expandPhoto"].tap()
        XCTAssertTrue(app.buttons["閉じる"].waitForExistence(timeout:5))
        let enlarged = XCTAttachment(screenshot:app.screenshot()); enlarged.name = "Full photo with food labels"; enlarged.lifetime = .keepAlways; add(enlarged)
        app.buttons["閉じる"].tap()
        app.buttons["reviewCandidate"].tap()
        XCTAssertFalse(app.buttons["reviewCandidate"].exists)
        XCTAssertFalse(app.images["AIに渡した写真"].exists)
        XCTAssertTrue(app.buttons["nextCapture"].exists)
    }
}
