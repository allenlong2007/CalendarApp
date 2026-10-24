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
        XCTAssertTrue(app.staticTexts["Two weeks"].waitForExistence(timeout: 5))
        let currentPage = app.otherElements["calendarPage.0"]
        let rows = currentPage.otherElements.matching(identifier: "landscapeWeekRow")
        XCTAssertEqual(rows.count, 2)
        XCTAssertLessThanOrEqual(currentPage.frame.width, app.frame.width)
        let dayNumbers = rows.element(boundBy: 0).descendants(matching: .any).matching(identifier: "weekDayNumber")
        XCTAssertEqual(dayNumbers.count, 7)
        for day in dayNumbers.allElementsBoundByIndex {
            XCTAssertGreaterThanOrEqual(day.frame.minX, currentPage.frame.minX - 1)
            XCTAssertLessThanOrEqual(day.frame.maxX, currentPage.frame.maxX + 1)
        }
        saveScreenshot("Phone landscape two weeks")

        // Saturday in the first row must be visible and open that exact day.
        let saturday = Calendar.current.date(byAdding: .day,
            value: 7 - Calendar.current.component(.weekday, from: now),
            to: Calendar.current.startOfDay(for: now))!
        dayNumbers.element(boundBy: 6).tap()
        XCTAssertTrue(app.segmentedControls.buttons["Day"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.segmentedControls.buttons["Day"].isSelected)
        let dayFormatter = DateFormatter()
        dayFormatter.dateFormat = "EEEE, MMMM d"
        XCTAssertTrue(app.staticTexts[dayFormatter.string(from: saturday)].waitForExistence(timeout: 5))
        pager.swipeLeft()
        let sunday = Calendar.current.date(byAdding: .day, value: 1, to: saturday)!
        XCTAssertTrue(app.staticTexts[dayFormatter.string(from: sunday)].waitForExistence(timeout: 5))
        pager.swipeRight()
        XCTAssertTrue(app.staticTexts[dayFormatter.string(from: saturday)].waitForExistence(timeout: 5))
        saveScreenshot("Phone landscape day")

        XCUIDevice.shared.orientation = .portrait
        XCTAssertTrue(app.segmentedControls.buttons["Day"].waitForExistence(timeout: 5))
        pager.swipeLeft()
        XCTAssertTrue(app.staticTexts[dayFormatter.string(from: sunday)].waitForExistence(timeout: 5))
        pager.swipeRight()
        XCTAssertTrue(app.staticTexts[dayFormatter.string(from: saturday)].waitForExistence(timeout: 5))
        saveScreenshot("Phone portrait day")
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
