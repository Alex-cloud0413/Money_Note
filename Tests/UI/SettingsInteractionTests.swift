import XCTest
import UIKit

@MainActor
final class SettingsInteractionTests: XCTestCase {
    let app = XCUIApplication(bundleIdentifier: "com.gaoyiming.MoneyNote.SettingsRegression")

    override func setUpWithError() throws {
        continueAfterFailure = false
        app.launchArguments = ["--preview-data"]
        app.launch()
        app.activate()
        XCTAssertEqual(app.state, .runningForeground)
        XCTAssertTrue(app.buttons["设置"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.buttons["设置"].isHittable)
        app.buttons["设置"].tap()
        XCTAssertTrue(app.navigationBars["设置"].waitForExistence(timeout: 5))
    }

    private func visible(_ query: XCUIElementQuery) -> XCUIElement? {
        query.allElementsBoundByIndex.first { $0.exists && $0.isHittable }
    }

    private func scrollTo(_ query: XCUIElementQuery) -> XCUIElement {
        for _ in 0..<6 {
            if let element = visible(query) { return element }
            app.swipeUp()
        }
        XCTFail("Control did not become visible: \(app.debugDescription)")
        return query.firstMatch
    }

    private func chooseAppearance(_ name: String) {
        let picker = scrollTo(app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "外观模式")))
        picker.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        let choice = app.buttons[name]
        XCTAssertTrue(choice.waitForExistence(timeout: 3), app.debugDescription)
        choice.tap()
    }

    private func backgroundBrightness() -> Double {
        let image = app.screenshot().image
        let cg = image.cgImage!
        let width = cg.width, height = cg.height
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let context = CGContext(data: &bytes, width: width, height: height,
                                bitsPerComponent: 8, bytesPerRow: width * 4,
                                space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))
        // The sheet's right margin contains only its paper background.
        let points = [0.28, 0.36, 0.44, 0.52, 0.60, 0.68]
        return points.map { fraction in
            let offset = (Int(Double(height) * fraction) * width + Int(Double(width) * 0.95)) * 4
            return Double(Int(bytes[offset]) + Int(bytes[offset + 1]) + Int(bytes[offset + 2])) / (3 * 255)
        }.reduce(0, +) / Double(points.count)
    }

    private func waitForBrightness(dark: Bool) {
        let predicate = NSPredicate { _, _ in
            let brightness = self.backgroundBrightness()
            return dark ? brightness < 0.35 : brightness > 0.75
        }
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: nil)], timeout: 5), .completed,
                       "Settings sheet did not immediately switch to \(dark ? "dark" : "light") appearance")
        XCTAssertTrue(app.navigationBars["设置"].exists, "Settings must remain open")
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = dark ? "settings-dark-without-dismiss" : "settings-light-without-dismiss"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testExportMonthButtonsChangeExactlyOneMonth() throws {
        let previous = scrollTo(app.buttons.matching(identifier: "上个月"))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let now = Date()
        let title: (Date) -> String = { date in
            date.formatted(.dateTime.year().month(.wide).locale(Locale(identifier: "zh_CN")))
        }
        let current = title(now)
        let prior = title(calendar.date(byAdding: .month, value: -1, to: now)!)
        XCTAssertNotNil(visible(app.staticTexts.matching(identifier: current)), "Export should start in current month")
        XCTAssertGreaterThanOrEqual(previous.frame.width, 44)
        XCTAssertGreaterThanOrEqual(previous.frame.height, 44)
        previous.coordinate(withNormalizedOffset: CGVector(dx: 0.1, dy: 0.5)).tap()
        XCTAssertTrue(app.staticTexts[prior].waitForExistence(timeout: 3), "Previous-month button must update export month")
        XCTAssertNotNil(visible(app.staticTexts.matching(identifier: prior)))
        visible(app.buttons.matching(identifier: "下个月"))!.tap()
        XCTAssertNotNil(visible(app.staticTexts.matching(identifier: current)), "Next-month button must reverse one step")
        for _ in 0..<3 { visible(app.buttons.matching(identifier: "上个月"))!.tap() }
        let earlier = title(calendar.date(byAdding: .month, value: -3, to: now)!)
        XCTAssertNotNil(visible(app.staticTexts.matching(identifier: earlier)), "Repeated taps must each change one month")
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "export-month-filter-changed"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testAppearanceChangesWhileSettingsStaysOpen() throws {
        chooseAppearance("浅色")
        // Establish a known light baseline, including on the unfixed version.
        app.navigationBars["设置"].buttons["完成"].tap()
        app.buttons["设置"].tap()
        waitForBrightness(dark: false)
        chooseAppearance("深色")
        waitForBrightness(dark: true)
        chooseAppearance("浅色")
        waitForBrightness(dark: false)
        chooseAppearance("深色")
        waitForBrightness(dark: true)
        chooseAppearance("跟随系统")
        waitForBrightness(dark: false)
    }
}
