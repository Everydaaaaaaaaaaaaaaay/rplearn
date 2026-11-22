import XCTest

@MainActor
final class ChatNavigationTests: XCTestCase {
    /// 聊天页的顶栏画在页面里、随页面一起滑走（不切换系统导航栏的显隐，返回按钮和头像不会单独漂移）。
    /// 左缘拖过一半停住再松手，仍应回到信息列表。
    func testEdgeSwipeBackFromChatReturnsToList() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment = ["UI_TEST_SKIP_ONBOARDING": "1", "UI_TEST_REQUIRE_AUTHENTICATION": "0",
            "UI_TEST_DISABLE_BACKGROUND_REFRESH": "1", "UI_TEST_MARKETING_CAPTURE": "1",
            "LINGOTRIP_BACKEND_URL": "http://127.0.0.1:9"]
        app.launch()
        defer { app.terminate() }

        let row = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Ruby Walker")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 15))
        row.tap()
        let identity = app.descendants(matching: .any)["chat.identity"].firstMatch
        XCTAssertTrue(identity.waitForExistence(timeout: 8))

        app.coordinate(withNormalizedOffset: CGVector(dx: 0.01, dy: 0.5))
            .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.6, dy: 0.5)),
                   withVelocity: .slow, thenHoldForDuration: 0.8)
        XCTAssertTrue(identity.waitForNonExistence(timeout: 5), "左缘滑过一半松手应返回信息列表")
        XCTAssertTrue(row.isHittable)

        // 返回按钮本身也能退出。
        row.tap()
        XCTAssertTrue(identity.waitForExistence(timeout: 8))
        let back = app.buttons["chat.back"]
        XCTAssertTrue(back.waitForExistence(timeout: 3) && back.isHittable, "聊天页应显示返回按钮")
        back.tap()
        XCTAssertTrue(identity.waitForNonExistence(timeout: 5))
    }
}
