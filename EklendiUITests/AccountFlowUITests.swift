import XCTest

/// Account flows against the in-memory mocks (`-uiTesting`).
/// Mock rules: any 6-digit code verifies; seeded users use password123; Zach = 5555550100.
/// Note: 5555550101 is seeded as Seth in MockStore, so sign-up uses an unused number.
final class AccountFlowUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func launch(_ extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting"] + extra
        app.launch()
        return app
    }

    private func element(_ app: XCUIApplication, _ id: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    private func waitFor(_ el: XCUIElement, _ timeout: TimeInterval = 10, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(el.waitForExistence(timeout: timeout), "Missing \(el)", file: file, line: line)
    }

    private func scrollTo(_ el: XCUIElement, in app: XCUIApplication) {
        var tries: Int = 0
        while !el.isHittable && tries < 6 {
            app.swipeUp()
            tries += 1
        }
    }

    private func type(_ text: String, into el: XCUIElement) {
        waitFor(el)
        el.tap()
        el.typeText(text)
    }

    private func connectAppleCalendar(_ app: XCUIApplication) {
        let toggle: XCUIElement = app.buttons["appleCalendarToggle"]
        waitFor(toggle)
        toggle.tap()
        let on = NSPredicate(format: "value == %@", "On")
        expectation(for: on, evaluatedWith: app.buttons["appleCalendarToggle"], handler: nil)
        waitForExpectations(timeout: 10)
    }

    // MARK: Tests

    func testSignUpOnboardingLandsOnHome() {
        let app = launch()

        let signUp: XCUIElement = app.buttons["signUpLink"]
        waitFor(signUp)
        signUp.tap()

        type("5555550177", into: app.textFields["signUpPhoneField"])
        app.buttons["phoneNextButton"].tap()

        type("123456", into: app.textFields["codeField"])
        app.buttons["codeNextButton"].tap()

        type("hangout123", into: app.secureTextFields["newPasswordField"])
        app.buttons["createAccountButton"].tap()

        // Onboarding: name → calendars/buffer/home → interests.
        type("Taylor Test", into: app.textFields["nameField"])
        app.buttons["nameContinueButton"].tap()

        connectAppleCalendar(app)
        app.buttons["bufferPlus"].tap()
        let location: XCUIElement = app.textFields["homeLocationField"]
        scrollTo(location, in: app)
        type("Hyde Park, Chicago", into: location)
        app.buttons["connectContinueButton"].tap()

        let skip: XCUIElement = app.buttons["interestsSkipButton"]
        waitFor(skip)
        skip.tap()

        waitFor(app.buttons["createHangoutButton"])
        // New mock accounts get a seat in Seth's hangout that needs swipes.
        waitFor(element(app, "hangoutRow_h_voting_times"))
    }

    func testOnboardingRejectsZipOnlyAndSavesInterests() {
        let app = launch(["-uiTestingOnboarding"])

        type("Riley", into: app.textFields["nameField"])
        app.buttons["nameContinueButton"].tap()

        // Calendar is required.
        let cont: XCUIElement = app.buttons["connectContinueButton"]
        waitFor(cont)
        connectAppleCalendar(app)

        let location: XCUIElement = app.textFields["homeLocationField"]
        scrollTo(location, in: app)
        type("60637", into: location)
        cont.tap()
        XCTAssertFalse(app.buttons["interestsSkipButton"].waitForExistence(timeout: 2), "Zip-only location must be rejected")

        type(", Hyde Park", into: location)
        cont.tap()

        let chip: XCUIElement = app.buttons["interestChip_Hiking"]
        waitFor(chip)
        chip.tap()
        app.buttons["interestsSaveButton"].tap()

        waitFor(app.buttons["createHangoutButton"])
    }

    func testLogInAddFriendAndLogOut() {
        let app = launch()

        type("5555550100", into: app.textFields["loginPhoneField"])
        type("password123", into: app.secureTextFields["loginPasswordField"])
        app.buttons["loginButton"].tap()

        waitFor(app.buttons["createHangoutButton"])
        waitFor(element(app, "hangoutRow_h_confirmed"))

        // Header icon → Friends tab; add Noah (on Eklendi, not yet a friend) by number.
        app.buttons["homeFriendsButton"].tap()
        type("5555550106", into: app.textFields["addFriendPhoneField"])
        app.buttons["addFriendButton"].tap()
        let noah: XCUIElement = element(app, "friendRow_u_noah")
        waitFor(noah)

        // Settings tab → log out.
        app.buttons["tabSettings"].tap()
        let signOut: XCUIElement = app.buttons["signOutButton"]
        waitFor(signOut)
        scrollTo(signOut, in: app)
        signOut.tap()

        waitFor(app.buttons["loginButton"])
    }
}
