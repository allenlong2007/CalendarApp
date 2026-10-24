import XCTest

@MainActor
final class PhoneCalendarNavigationTests: XCTestCase {
    override func tearDown() {
        XCUIDevice.shared.orientation = .portrait
        super.tearDown()
    }

    func testMonthWeekSwipesAndLandscape() {
        let app = XCUIApplication()
        XCUIDevice.shared.orientation = .portrait
        app.launch()
        let pager = app.scrollViews["calendarPeriodPager"]
        XCTAssertTrue(pager.waitForExistence(timeout: 10))
        let formatter = DateFormatter()
        formatter.dateFormat = "LLLL yyyy"
        let now = Date()
        let nextMonth = Calendar.current.date(byAdding: .month, value: 1, to: now)!
        pager.swipeLeft()
        XCTAssertTrue(app.staticTexts[formatter.string(from: nextMonth)].waitForExistence(timeout: 5))
        pager.swipeRight()
        XCTAssertTrue(app.staticTexts[formatter.string(from: now)].waitForExistence(timeout: 5))
        saveScreenshot("Phone portrait month")

        app.segmentedControls.buttons["Week"].tap()
        XCTAssertTrue(pager.waitForExistence(timeout: 5))
        pager.swipeLeft()
        XCTAssertTrue(app.otherElements["calendarPage.1"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.otherElements["calendarPage.1"].isHittable)
        pager.swipeRight()
        XCTAssertTrue(app.otherElements["calendarPage.0"].isHittable)
        saveScreenshot("Phone portrait week")

        XCUIDevice.shared.orientation = .landscapeLeft
        XCTAssertTrue(app.staticTexts["Three weeks"].waitForExistence(timeout: 5))
        let currentPage = app.otherElements["calendarPage.0"]
        XCTAssertEqual(currentPage.otherElements.matching(identifier: "landscapeWeekRow").count, 3)
        XCTAssertLessThanOrEqual(currentPage.frame.width, app.frame.width)
        saveScreenshot("Phone landscape three weeks")

        XCUIDevice.shared.orientation = .portrait
        XCTAssertTrue(app.segmentedControls.buttons["Week"].waitForExistence(timeout: 5))
        XCTAssertTrue(pager.exists)
    }

    private func saveScreenshot(_ name: String) {
        let screenshot = XCUIScreen.main.screenshot()
        try? screenshot.pngRepresentation.write(to: URL(fileURLWithPath: "/private/tmp/\(name).png"))
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
