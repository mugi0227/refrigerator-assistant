import XCTest

final class FridgeUITests: XCTestCase {
    func testComparisonLaunchAndMissingModelMessage() {
        continueAfterFailure = false
        let app = XCUIApplication(); app.launch()
        let start = app.buttons["startReferenceProbe"]
        XCTAssertTrue(start.waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["＋ 手入力"].exists)
        start.tap()
        XCTAssertTrue(app.staticTexts["probeStatus"].label.contains("保存済みモデルが見つかりません"))
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Reference probe launch"; screenshot.lifetime = .keepAlways; add(screenshot)
        let openInventory = app.buttons["通常の冷蔵庫画面を開く"]
        // SwiftUI Form lazily creates offscreen rows on smaller iPhones.
        for _ in 0..<4 {
            if openInventory.exists && openInventory.isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(openInventory.exists && openInventory.isHittable)
        openInventory.tap()
        XCTAssertTrue(app.buttons["＋ 手入力"].waitForExistence(timeout: 15))
    }
    func testNativeSettingsAndInventorySurviveRelaunch() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--inventory-ui-test"]
        app.launch()
        let addFood = app.buttons["＋ 手入力"]
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
        XCTAssertTrue(app.staticTexts["ios-persistence-probe"].waitForExistence(timeout: 10), app.debugDescription)
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
