import XCTest

@MainActor
final class PhoneCalendarNavigationTests: XCTestCase {
    override func tearDown() {
        XCUIApplication().terminate()
        XCUIDevice.shared.orientation = .portrait
        super.tearDown()
    }

    func testMonthWeekSwipesAndLandscape() {
        let app = XCUIApplication()
        XCUIDevice.shared.orientation = .portrait
        launch(app)
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
        XCTAssertTrue(app.buttons["Calendar view: Month"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.navigationBars.count, 0, "Landscape uses only its compact calendar header")
        let header = app.otherElements["landscapeCalendarHeader"]
        XCTAssertLessThanOrEqual(header.frame.height, 40)
        let currentPage = app.otherElements["calendarPage.0"]
        let rows = currentPage.otherElements.matching(identifier: "landscapeWeekRow")
        XCTAssertEqual(rows.count, 2)
        XCTAssertLessThanOrEqual(currentPage.frame.width, pager.frame.width)
        let dayNumbers = rows.element(boundBy: 0).descendants(matching: .any).matching(identifier: "weekDayNumber")
        XCTAssertEqual(dayNumbers.count, 7)
        XCTAssertTrue(dayNumbers.element(boundBy: 0).label.hasPrefix("Sunday"))
        XCTAssertTrue(dayNumbers.element(boundBy: 6).label.hasPrefix("Saturday"))
        for day in dayNumbers.allElementsBoundByIndex {
            XCTAssertGreaterThanOrEqual(day.frame.minX, pager.frame.minX - 1)
            XCTAssertLessThanOrEqual(day.frame.maxX, pager.frame.maxX + 1)
        }
        saveScreenshot("Phone landscape two weeks")

        // Saturday in the first row must be visible and open that exact day.
        let saturday = Calendar.current.date(byAdding: .day,
            value: 7 - Calendar.current.component(.weekday, from: now),
            to: Calendar.current.startOfDay(for: now))!
        dayNumbers.element(boundBy: 6).tap()
        XCTAssertTrue(app.buttons["Calendar view: Day"].waitForExistence(timeout: 5))
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

    func testRotationFromEveryCalendarTab() {
        for mode in ["Month", "Week", "Day", "Agenda"] {
            let app = XCUIApplication()
            XCUIDevice.shared.orientation = .portrait
            launch(app)
            app.segmentedControls.buttons[mode].tap()
            XCUIDevice.shared.orientation = .landscapeLeft
            XCTAssertTrue(app.buttons["Calendar view: Month"].waitForExistence(timeout: 5))
            app.terminate()
        }
    }

    func testEmailTextBecomesReviewableVoiceDraft() {
        let app = XCUIApplication()
        XCUIDevice.shared.orientation = .portrait
        launch(app)
        app.buttons["Add or Delete by Voice"].tap()
        let system = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        for _ in 0..<2 {
            let alert = system.alerts.firstMatch
            if alert.waitForExistence(timeout: 2) {
                let deny = alert.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'Allow'")).allElementsBoundByIndex.first { $0.label.localizedCaseInsensitiveContains("don't") || $0.label.contains("Don’t") }
                deny?.tap()
            }
        }
        let command = app.textFields["Or type it here"]
        XCTAssertTrue(command.waitForExistence(timeout: 8))
        command.tap()
        command.typeText("Add the event from that email\n")
        let email = app.textViews["Email text"]
        XCTAssertTrue(email.waitForExistence(timeout: 5))
        email.tap()
        email.typeText("Dentist appointment\nAppointment: December 5, 2030 at 3:30 PM\nLocation: 123 Main Street")
        app.buttons["Use Email Text"].tap()
        XCTAssertTrue(app.buttons["Edit Details"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Dentist appointment"].exists)
        saveScreenshot("Voice email draft")
    }

    private func launch(_ app: XCUIApplication) {
        app.launch()
        let system = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        for _ in 0..<3 {
            let alert = system.alerts.firstMatch
            guard alert.waitForExistence(timeout: 2) else { break }
            if alert.buttons["Allow Full Access"].exists { alert.buttons["Allow Full Access"].tap() }
            else if alert.buttons["Allow"].exists { alert.buttons["Allow"].tap() }
            else { break }
        }
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
