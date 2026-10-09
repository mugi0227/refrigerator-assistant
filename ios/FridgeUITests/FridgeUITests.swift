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
        XCTAssertTrue(app.buttons["loadAI"].exists); XCTAssertTrue(app.staticTexts["v0.3.0 · ネイティブ版"].exists)
        app.tabBars.buttons["買い物"].tap(); app.textFields["買うもの"].tap(); app.textFields["買うもの"].typeText("bread"); app.buttons["追加"].tap()
        XCTAssertTrue(app.buttons["bread"].waitForExistence(timeout:5))
        app.terminate(); app.launch(); app.tabBars.buttons["買い物"].tap(); XCTAssertTrue(app.buttons["bread"].waitForExistence(timeout:5))
    }
}
