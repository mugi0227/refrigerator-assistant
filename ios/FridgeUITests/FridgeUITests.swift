import XCTest
final class FridgeUITests: XCTestCase {
    func testNativePersistenceAndNoWebView() {
        continueAfterFailure = false
        let app = XCUIApplication(); app.launch()
        XCTAssertTrue(app.buttons["＋ 手入力"].waitForExistence(timeout:20)); XCTAssertEqual(app.webViews.count,0)
        app.buttons["＋ 手入力"].tap()
        let name = app.textFields["foodName"]; XCTAssertTrue(name.waitForExistence(timeout:5)); name.tap(); name.typeText("native-persistence-probe")
        app.buttons["saveFoodToolbar"].tap()
        XCTAssertTrue(app.staticTexts["native-persistence-probe"].firstMatch.waitForExistence(timeout:10))
        app.terminate(); app.launch(); XCTAssertTrue(app.staticTexts["native-persistence-probe"].firstMatch.waitForExistence(timeout:10))
        for tab in ["買い物","スキャン","献立","設定"] {
            app.tabBars.buttons[tab].tap(); XCTAssertEqual(app.webViews.count,0)
            let shot = XCTAttachment(screenshot:app.screenshot()); shot.name = "Native \(tab)"; shot.lifetime = .keepAlways; add(shot)
        }
        XCTAssertTrue(app.buttons["loadAI"].exists); XCTAssertTrue(app.staticTexts["v0.3.2 · ネイティブ版"].exists)
        app.tabBars.buttons["買い物"].tap(); app.textFields["買うもの"].tap(); app.textFields["買うもの"].typeText("bread"); app.buttons["追加"].tap()
        XCTAssertTrue(app.buttons["bread"].waitForExistence(timeout:5))
        app.terminate(); app.launch(); app.tabBars.buttons["買い物"].tap(); XCTAssertTrue(app.buttons["bread"].waitForExistence(timeout:5))
    }
    func testScannerCandidateRequiresConfirmation() {
        let app = XCUIApplication(); app.launch(); app.tabBars.buttons["スキャン"].tap()
        app.buttons["scanMenu"].tap(); app.buttons["操作デモ：牛乳と期限"].tap()
        XCTAssertTrue(app.buttons["reviewCandidate"].waitForExistence(timeout:5))
        app.buttons["readExpiry"].tap()
        XCTAssertTrue(app.buttons["撮影を終える"].waitForExistence(timeout:5))
        XCTAssertFalse(app.buttons["aiShutter"].exists)
        app.buttons["撮影を終える"].tap()
        app.buttons["期限を手入力"].tap()
        XCTAssertTrue(app.buttons["applyExpiry"].waitForExistence(timeout:5))
        XCTAssertFalse(app.textFields["foodName"].exists)
        app.buttons["applyExpiry"].tap()
        XCTAssertTrue(app.buttons["reviewCandidate"].waitForExistence(timeout:5))
        let shot = XCTAttachment(screenshot:app.screenshot()); shot.name = "Scanner candidate chips"; shot.lifetime = .keepAlways; add(shot)
        app.buttons["reviewCandidate"].tap()
        XCTAssertTrue(app.textFields["foodName"].waitForExistence(timeout:5))
        XCTAssertEqual(app.textFields["foodName"].value as? String,"牛乳")
        app.buttons["saveFoodToolbar"].tap()
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
        app.buttons["reviewCandidate"].tap(); app.buttons["saveFoodToolbar"].tap()
        XCTAssertFalse(app.buttons["reviewCandidate"].exists)
        XCTAssertTrue(app.buttons["nextCapture"].exists)
    }
}
