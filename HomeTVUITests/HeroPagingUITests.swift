import XCTest

/// Focus-engine behaviour for the Watch Now hero's Left press (issue #40).
///
/// This is deliberately a UI test: a directional press only exists inside a running app driven by the
/// focus engine, so no unit test can cover it. The hero's page dots carry an accessibility label of
/// `Page <n> of <count>`, which is what these tests read to tell which featured title is showing.
///
/// Auto-advance stands down while a hero control holds focus, so the page only moves when the test
/// moves it. The hero itself is a fixture of `heroTitleCount` titles injected with MOCK_HERO, so these
/// tests neither depend on a live catalog nor quietly skip when one is unavailable.
final class HeroPagingUITests: XCTestCase {
    private var app: XCUIApplication!

    /// Featured titles the fixture injects. Three is the minimum that exercises paging back twice.
    private let heroTitleCount = 3

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchEnvironment["MOCK_HERO"] = String(heroTitleCount)
        app.launch()
    }

    /// Left on any page but the first pages back to the previous featured title and keeps focus in the
    /// hero — it must not escape to the sidebar.
    func testLeftPagesBackToThePreviousTitle() {
        assertHeroFixtureLoaded()

        pageForwardToSecondTitle()
        XCTAssertEqual(currentPage(), 2, "Setup should have paged the hero forward")

        focusPlay()
        XCUIRemote.shared.press(.left)

        XCTAssertTrue(waitForPage(1), "Left should page back to the first featured title")
        XCTAssertTrue(app.buttons["Play"].hasFocus, "Focus should return to Play, not leave the hero")
        XCTAssertFalse(isSidebarFocused, "Left should not hand focus to the sidebar while a previous title exists")
    }

    /// Repeated Left presses keep paging back, one title per press — the alternation bug (page, then
    /// sidebar, then page) showed up only from the second press onward.
    func testRepeatedLeftPressesKeepPaging() {
        assertHeroFixtureLoaded()

        pageForwardToSecondTitle()
        pageForwardToSecondTitle()
        XCTAssertEqual(currentPage(), 3, "Setup should have paged the hero forward twice")

        focusPlay()
        XCUIRemote.shared.press(.left)
        XCTAssertTrue(waitForPage(2), "First Left should page back")
        XCTAssertFalse(isSidebarFocused, "First Left should not hand focus to the sidebar")

        // The page dots flip as the slide crosses halfway, so the carousel is still animating here — and
        // it deliberately drops a page press while one is in flight. Let it settle before pressing again.
        waitForPagingToSettle()
        XCUIRemote.shared.press(.left)
        XCTAssertTrue(waitForPage(1), "Second Left should page back again, not open the sidebar")
        XCTAssertFalse(isSidebarFocused, "Second Left should not hand focus to the sidebar")
    }

    /// On the first featured title there is nothing to page back to, so Left is a genuine edge and the
    /// sidebar opens — the Apple TV behaviour the fix must preserve.
    func testLeftOnFirstTitleOpensTheSidebar() {
        assertHeroFixtureLoaded()

        focusPlay()
        XCTAssertEqual(currentPage(), 1, "Test should start on the first featured title")

        XCUIRemote.shared.press(.left)

        XCTAssertTrue(waitForSidebarFocus(), "Left on the first title should open the sidebar")
    }

    // MARK: - Helpers

    /// The hero's page-dots element, labelled `Page <n> of <count>`.
    private var pageIndicator: XCUIElement {
        app.descendants(matching: .any)
            .matching(NSPredicate(format: "label BEGINSWITH 'Page '"))
            .firstMatch
    }

    /// Fails the test rather than skipping it: the fixture is injected at launch, so a hero that is
    /// missing or the wrong length means something is broken, not merely unavailable.
    private func assertHeroFixtureLoaded(_ file: StaticString = #filePath, _ line: UInt = #line) {
        XCTAssertTrue(pageIndicator.waitForExistence(timeout: 30),
                      "Hero page dots never appeared", file: file, line: line)
        XCTAssertTrue(app.buttons["Play"].waitForExistence(timeout: 10),
                      "Hero Play button never appeared", file: file, line: line)
        XCTAssertEqual(pageCount(), heroTitleCount,
                       "Hero should show the injected MOCK_HERO fixture", file: file, line: line)
    }

    /// Parses `Page 2 of 6` into `2`.
    private func currentPage() -> Int {
        Int(pageIndicator.label.split(separator: " ").dropFirst().first ?? "") ?? 0
    }

    /// Parses `Page 2 of 6` into `6`.
    private func pageCount() -> Int {
        Int(pageIndicator.label.split(separator: " ").last ?? "") ?? 0
    }

    private func waitForPage(_ page: Int, timeout: TimeInterval = 5) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if currentPage() == page { return true }
            usleep(200_000)
        }
        return false
    }

    /// The sidebar's tab buttons stay in the accessibility tree even while it is collapsed, so mere
    /// existence proves nothing. Focus is the real signal: the sidebar has taken the move only when one
    /// of its tabs holds focus.
    private var isSidebarFocused: Bool {
        ["Search", "Watch Now", "Library", "Settings"].contains { app.buttons[$0].hasFocus }
    }

    private func waitForSidebarFocus(timeout: TimeInterval = 5) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if isSidebarFocused { return true }
            usleep(200_000)
        }
        return false
    }

    /// The model ignores a page press while a slide is in flight; the slide is ~0.5s.
    private func waitForPagingToSettle() {
        usleep(1_200_000)
    }

    /// Walks focus right to the Next chevron and pages forward one title with Select.
    private func pageForwardToSecondTitle() {
        let startPage = currentPage()
        focusPlay()
        // Right through the row (Info, then the Next chevron; the Watchlist button only exists when
        // signed in to Trakt, so step until the chevron takes focus).
        for _ in 0..<3 where !app.buttons["Next"].hasFocus {
            XCUIRemote.shared.press(.right)
        }
        XCTAssertTrue(app.buttons["Next"].hasFocus, "Could not focus the Next chevron")
        XCUIRemote.shared.press(.select)
        let target = startPage % pageCount() + 1
        XCTAssertTrue(waitForPage(target), "Next should have paged the hero forward to page \(target)")
        // The indicator flips mid-slide, so the carousel is still animating and would discard a second
        // page press. Callers page twice in a row, so settle before handing back.
        waitForPagingToSettle()
    }

    /// Returns focus to Play by stepping left through the row — without ever pressing Left *on* Play,
    /// which is the behaviour under test.
    private func focusPlay() {
        for _ in 0..<3 where !app.buttons["Play"].hasFocus {
            XCUIRemote.shared.press(.left)
        }
    }
}
