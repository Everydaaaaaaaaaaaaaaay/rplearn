import XCTest

/// 从隐藏系统导航栏的蓬蓬页进入使用系统栏的子页面后，中途取消的左缘返回不能把顶栏和返回按钮弄丢。
@MainActor
final class NavigationBarRecoveryTests: XCTestCase {
    func testMeSettingsKeepsBackAfterCancelledSwipe() {
        let app = launch(tab: "me")
        defer { app.terminate() }
        let entry = app.buttons["设置，AI、语音与偏好"]
        XCTAssertTrue(entry.waitForExistence(timeout: 15))
        entry.tap()
        assertCancelledSwipesKeepBack(in: app, title: "设置")
        XCTAssertTrue(entry.waitForExistence(timeout: 5))
    }

    func testContactProfileKeepsBackAfterCancelledSwipe() {
        let app = launch(tab: "contacts")
        defer { app.terminate() }
        let entry = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Oliver")).firstMatch
        XCTAssertTrue(entry.waitForExistence(timeout: 15))
        entry.tap()
        XCTAssertTrue(app.buttons["发消息"].waitForExistence(timeout: 5))
        assertCancelledSwipesKeepBack(in: app, title: nil)
        XCTAssertTrue(entry.waitForExistence(timeout: 5))
    }

    func testStoryHubKeepsBackAfterCancelledSwipe() {
        let app = launch(tab: "home")
        defer { app.terminate() }
        let entry = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "剧情，")).firstMatch
        XCTAssertTrue(entry.waitForExistence(timeout: 15))
        entry.tap()
        XCTAssertTrue(app.buttons["story.mainline"].waitForExistence(timeout: 5))
        assertCancelledSwipesKeepBack(in: app, title: "剧情")
        XCTAssertTrue(entry.waitForExistence(timeout: 5))
    }

    private func launch(tab: String) -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment = ["UI_TEST_SKIP_ONBOARDING": "1", "UI_TEST_DISABLE_BACKGROUND_REFRESH": "1",
            "LINGOTRIP_BACKEND_URL": "http://127.0.0.1:9", "UI_TEST_TAB": tab, "UI_TEST_CITY_TAB_REGION": "london"]
        app.launch()
        return app
    }

    /// 左缘短拖两次、慢慢松手（返回被取消），返回按钮和标题都应还在，最后用返回按钮退出。
    private func assertCancelledSwipesKeepBack(in app: XCUIApplication, title: String?) {
        let back = app.buttons.matching(NSPredicate(format: "identifier == 'BackButton' OR label == '返回'")).firstMatch
        XCTAssertTrue(back.waitForExistence(timeout: 5), "进入后应有返回按钮")
        for _ in 0..<2 {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.01, dy: 0.5))
                .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.5)),
                       withVelocity: .slow, thenHoldForDuration: 0.4)
            XCTAssertTrue(back.waitForExistence(timeout: 3) && back.isHittable, "取消返回后返回按钮应还在")
            if let title { XCTAssertTrue(app.staticTexts[title].exists, "取消返回后标题应还在") }
        }
        back.tap()
    }
}
