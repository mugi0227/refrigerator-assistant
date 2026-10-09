import XCTest

final class FridgeUITests: XCTestCase {
    func testNativeSettingsAndInventorySurviveRelaunch() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launch()
        let addFood = app.buttons["食品を追加"].firstMatch
        XCTAssertTrue(addFood.waitForExistence(timeout: 20))
        addFood.tap()
        let name = app.textFields["食品名"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap(); name.typeText("ios-persistence-probe")
        XCTAssertEqual(name.value as? String, "ios-persistence-probe")
        // WKWebView's keyboard covers the form submit button. Dismiss it like a
        // person would before tapping, instead of sending a tap through it.
        let done = app.toolbars.buttons["Done"].firstMatch
        XCTAssertTrue(done.waitForExistence(timeout: 5))
        done.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 5))
        app.buttons["追加する"].tap()
        // Shelf slots are buttons whose label includes the name, so match any element that carries it.
        let probe = NSPredicate(format: "label CONTAINS %@", "ios-persistence-probe")
        XCTAssertTrue(app.descendants(matching: .any).matching(probe).firstMatch.waitForExistence(timeout: 10), app.debugDescription)
        app.terminate(); app.launch()
        XCTAssertTrue(app.descendants(matching: .any).matching(probe).firstMatch.waitForExistence(timeout: 15))
        app.buttons["設定"].tap()
        app.buttons["野菜の読み取り・献立の準備（任意）"].tap()
        let native = app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "iOSネイティブ")).firstMatch
        XCTAssertTrue(native.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["モデルを保存して起動"].isEnabled)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Native settings"; screenshot.lifetime = .keepAlways
        add(screenshot)
    }
}
