import XCTest

/// Hangout flows against the in-memory mocks (`-uiTesting -uiTestingSignedIn`, signed in as Zach).
/// The other members answer with preset choices (Services/DemoPersonas.swift); every group
/// has options nobody vetoes, so voting yes everywhere always produces a winner.
final class HangoutFlowUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-uiTestingSignedIn"]
        app.launch()
        return app
    }

    private func element(_ app: XCUIApplication, _ id: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    private func waitFor(_ el: XCUIElement, _ timeout: TimeInterval = 10,
                         file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(el.waitForExistence(timeout: timeout), "Missing \(el)", file: file, line: line)
    }

    private func scrollTo(_ el: XCUIElement, in app: XCUIApplication) {
        var tries: Int = 0
        while (!el.exists || !el.isHittable) && tries < 6 {
            app.swipeUp()
            tries += 1
        }
    }

    private func openHangout(_ id: String, in app: XCUIApplication) {
        waitFor(app.buttons["createHangoutButton"])
        let row: XCUIElement = element(app, "hangoutRow_\(id)")
        if !row.waitForExistence(timeout: 3) || !row.isHittable {
            scrollTo(row, in: app)
        }
        waitFor(row)
        row.tap()
    }

    /// Taps Yes `count` times, letting each card fly off first.
    private func swipeYes(_ count: Int, in app: XCUIApplication) {
        let yes: XCUIElement = app.buttons["swipeYes"]
        waitFor(yes)
        for _ in 0..<count {
            XCTAssertTrue(yes.waitForExistence(timeout: 5))
            yes.tap()
            usleep(400_000)
        }
    }

    // MARK: Tests

    /// 08: swipe all 8 seeded slots → the group moves on to the survey (09).
    func testSwipeAllTimesReachesSurvey() {
        let app = launch()
        openHangout("h_voting_times", in: app)

        waitFor(element(app, "swipeCard"))
        waitFor(element(app, "viewAvailabilityButton"))
        swipeYes(8, in: app)

        waitFor(element(app, "surveyCounter"), 15)
        waitFor(element(app, "swipeSkip"))
    }

    /// 08a: View availability opens the one-day calendar and comes back.
    func testDayViewOpensAndCloses() {
        let app = launch()
        openHangout("h_voting_times", in: app)

        let view: XCUIElement = app.buttons["viewAvailabilityButton"]
        waitFor(view)
        view.tap()
        waitFor(element(app, "ideaBlock"))
        waitFor(element(app, "ideaStatus"))
        app.buttons["dayViewBack"].tap()
        waitFor(app.buttons["swipeYes"])
    }

    /// 09 → 11 → 12: answer the survey, vote on the cards, land on "It's a plan".
    func testSurveyAndCardsReachConfirmed() {
        let app = launch()
        openHangout("h_survey", in: app)

        waitFor(element(app, "surveyCounter"))
        let skip: XCUIElement = element(app, "swipeSkip")
        waitFor(skip)
        skip.tap()                 // "I don't care" on the first question
        usleep(400_000)
        swipeYes(13, in: app)

        waitFor(element(app, "cardsCounter"), 15)
        swipeYes(9, in: app)       // 3 people → 9 cards

        waitFor(element(app, "matchView"), 15)
        waitFor(element(app, "notGoingButton"))
    }

    /// 05 → 05a → 06 → new hangout → starting point → times to swipe.
    func testCreateHangoutReachesTimes() {
        let app = launch()
        let create: XCUIElement = app.buttons["createHangoutButton"]
        waitFor(create)
        create.tap()

        let seth: XCUIElement = element(app, "friendRow_u_seth")
        waitFor(seth)
        seth.tap()
        element(app, "friendRow_u_matt").tap()
        element(app, "inviteContinueButton").tap()

        let next: XCUIElement = element(app, "planNextButton")
        waitFor(next)
        next.tap()

        let submit: XCUIElement = app.buttons["createHangoutSubmit"]
        waitFor(submit)
        submit.tap()

        let cont: XCUIElement = element(app, "continueToTimesButton")
        waitFor(cont, 15)
        cont.tap()

        waitFor(app.buttons["swipeYes"], 20)
        waitFor(element(app, "swipeCard"))
    }
}
