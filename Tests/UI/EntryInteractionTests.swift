import XCTest

@MainActor
final class EntryInteractionTests: XCTestCase {
    let app = XCUIApplication(bundleIdentifier: "com.gaoyiming.MoneyNote.SettingsRegression")
    override func setUpWithError() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        app.launchArguments = ["--preview-data"]
        app.launch()
        app.activate()
        XCTAssertEqual(app.state, .runningForeground)
        XCTAssertTrue(app.buttons["addTransaction"].waitForExistence(timeout: 15))
    }
    override func tearDownWithError() throws {
        XCUIDevice.shared.orientation = .portrait
        app.terminate()
    }
    private func visibleButton(_ id: String) -> XCUIElement {
        for _ in 0..<8 {
            if let b = app.buttons.matching(identifier: id).allElementsBoundByIndex.first(where: { $0.isHittable }) { return b }
            app.swipeUp()
        }
        XCTFail("Button unreachable: \(id)\n\(app.debugDescription)")
        return app.buttons[id].firstMatch
    }
    private func snapshot(_ name: String) {
        let a = XCTAttachment(screenshot: app.screenshot()); a.name = name; a.lifetime = .keepAlways; add(a)
    }
    func testEntrySurvivesRotationAndBackNavigation() throws {
        XCTAssertTrue(app.buttons["addTransaction"].isHittable)
        app.buttons["addTransaction"].tap()
        XCTAssertTrue(app.buttons["entryNext"].waitForExistence(timeout: 5))
        visibleButton("清空").tap()
        visibleButton("2").tap(); visibleButton("5").tap()
        XCTAssertTrue(app.staticTexts["¥25"].exists)
        XCUIDevice.shared.orientation = .landscapeLeft
        snapshot("amount-landscape")
        XCTAssertTrue(app.staticTexts["¥25"].exists, "Resizing must retain the amount")
        visibleButton("entryNext").tap()
        XCTAssertTrue(app.staticTexts["一级分类"].waitForExistence(timeout: 5))
        visibleButton("entryBack").tap()
        XCTAssertTrue(app.staticTexts["¥25"].waitForExistence(timeout: 3))
        XCUIDevice.shared.orientation = .portrait
        visibleButton("entryNext").tap()
        visibleButton("餐饮").tap()
        XCTAssertTrue(app.buttons["不分子类"].waitForExistence(timeout: 4))
        app.buttons["不分子类"].tap()
        XCTAssertTrue(app.buttons["saveTransaction"].waitForExistence(timeout: 4))
        snapshot("entry-details")
        visibleButton("entryBack").tap()
        XCTAssertTrue(app.staticTexts["一级分类"].waitForExistence(timeout: 4))
        visibleButton("餐饮").tap(); app.buttons["不分子类"].tap()
        XCTAssertTrue(app.buttons["saveTransaction"].waitForExistence(timeout: 4))
        visibleButton("saveTransaction").tap()
        XCTAssertTrue(app.buttons["关闭提示"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["关闭提示"].isHittable)
        snapshot("saved-notice-safe-area")
        app.buttons["关闭提示"].tap()
        XCTAssertTrue(app.buttons["addTransaction"].exists)
    }
    func testTabsShareMonthAndSettingsCanClose() throws {
        XCTAssertTrue(app.buttons["上个月"].firstMatch.isHittable)
        app.buttons["上个月"].firstMatch.tap()
        let month = Calendar.current.date(byAdding: .month, value: -1, to: .now)!
        let title = month.formatted(.dateTime.year().month(.wide).locale(Locale(identifier: "zh_CN")))
        XCTAssertTrue(app.staticTexts[title].waitForExistence(timeout: 5), "Confirm the month changed before switching tabs")
        for tab in ["统计", "预算", "账本", "明细"] {
            app.buttons[tab].firstMatch.tap()
            if tab != "账本" { XCTAssertTrue(app.staticTexts[title].exists) }
            snapshot("tab-" + tab)
        }
        app.buttons["设置"].tap()
        XCTAssertTrue(app.navigationBars["设置"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["完成"].isHittable)
        app.buttons["完成"].tap()
        XCTAssertTrue(app.buttons["addTransaction"].waitForExistence(timeout: 4))
    }
}
