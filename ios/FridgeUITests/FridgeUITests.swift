import XCTest

final class FridgeUITests: XCTestCase {
    func testNativeSettingsAndInventorySurviveRelaunch() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launch()
        let addFood = app.buttons["＋ 手入力"]
        XCTAssertTrue(addFood.waitForExistence(timeout: 20))
        addFood.tap()
        let name = app.textFields["食品名"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap(); name.typeText("ios-persistence-probe")
        app.buttons["追加する"].tap()
        XCTAssertTrue(app.staticTexts["ios-persistence-probe"].waitForExistence(timeout: 5))
        app.terminate(); app.launch()
        XCTAssertTrue(app.staticTexts["ios-persistence-probe"].waitForExistence(timeout: 15))
        app.buttons["設定を開く"].tap()
        let native = app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "iOSネイティブ")).firstMatch
        XCTAssertTrue(native.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["モデルを保存して起動"].isEnabled)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Native settings"; screenshot.lifetime = .keepAlways
        add(screenshot)
    }
}
