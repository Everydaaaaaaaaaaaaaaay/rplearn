import XCTest

@MainActor
final class TabSceneTransitionTests: XCTestCase {
    func testRepeatedTabSelectionKeepsNativeSelectionAndSearchWorking() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["UI_TEST_SKIP_ONBOARDING"] = "1"
        app.launchEnvironment["UI_TEST_DISABLE_BACKGROUND_REFRESH"] = "1"
        app.launchEnvironment["LINGOTRIP_BACKEND_URL"] = "http://127.0.0.1:9"
        app.launchEnvironment["UI_TEST_TAB"] = "messages"
        app.launch()
        defer { app.terminate() }

        XCTAssertTrue(app.buttons["sceneSearch.open"].waitForExistence(timeout: 15))
        for _ in 0..<2 {
            for title in ["联系人", "活动", "我的", "信息"] {
                let tab = app.tabBars.buttons[title]
                tab.tap()
                XCTAssertTrue(tab.isSelected, "SwiftUI 与原生标签栏的选中状态必须一致")
            }
            for title in ["信息", "联系人"] {
                app.tabBars.buttons[title].tap()
                let open = app.buttons["sceneSearch.open"]
                XCTAssertTrue(open.waitForExistence(timeout: 3))
                open.tap()
                XCTAssertTrue(app.textFields["sceneSearch.field"].waitForExistence(timeout: 3))
                app.buttons["sceneSearch.dismissKeyboard"].tap()
                app.tabBars.buttons[title].tap()
                XCTAssertTrue(app.textFields["sceneSearch.field"].waitForNonExistence(timeout: 3))
                XCTAssertTrue(open.waitForExistence(timeout: 3))
            }
        }
    }

    func testSceneTabsPreserveChildAcrossSwitchAndReturnToRootOnReselection() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["UI_TEST_SKIP_ONBOARDING"] = "1"
        app.launchEnvironment["UI_TEST_DISABLE_BACKGROUND_REFRESH"] = "1"
        app.launchEnvironment["LINGOTRIP_BACKEND_URL"] = "http://127.0.0.1:9"
        app.launchEnvironment["UI_TEST_TAB"] = "home"
        app.launchEnvironment["UI_TEST_CITY_TAB_REGION"] = "london"
        app.launch()
        defer { app.terminate() }

        for (title, entry) in [("活动", "世界地图"), ("我的", "设置，AI、语音与偏好")] {
            let tabButton = app.tabBars.buttons[title]
            XCTAssertTrue(tabButton.waitForExistence(timeout: 15))
            tabButton.tap()
            XCTAssertTrue(app.buttons[entry].waitForExistence(timeout: 15))
            app.buttons[entry].tap()
            let back = title == "活动"
                ? app.buttons["返回首页"]
                : app.navigationBars["设置"].buttons.firstMatch
            XCTAssertTrue(back.waitForExistence(timeout: 5))

            // 切换到其他标签再切回时，保持子页面位置。
            app.tabBars.buttons["联系人"].tap()
            app.tabBars.buttons[title].tap()
            XCTAssertTrue(back.waitForExistence(timeout: 5), "切回标签应保留原二级页面")

            // 在子页面再次点击当前标签，立即回到首页。
            app.tabBars.buttons[title].tap()
            XCTAssertTrue(back.waitForNonExistence(timeout: 5), "再次点击当前标签应回到根页面")
            XCTAssertTrue(app.buttons[entry].waitForExistence(timeout: 5))
            XCTAssertTrue(app.buttons[entry].isHittable, "初始页面入口应恢复可点击")
        }
    }
    func testMePagesUseNativeBackAndEdgeSwipe() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["UI_TEST_SKIP_ONBOARDING"] = "1"
        app.launchEnvironment["UI_TEST_DISABLE_BACKGROUND_REFRESH"] = "1"
        app.launchEnvironment["LINGOTRIP_BACKEND_URL"] = "http://127.0.0.1:9"
        app.launchEnvironment["UI_TEST_TAB"] = "me"
        app.launch()
        defer { app.terminate() }

        for (identifier, title) in [("me.profile", "个人资料"), ("me.subscription", "会员订阅"),
                                    ("me.favorites", "收藏夹"), ("设置，AI、语音与偏好", "设置")] {
            let entry = app.buttons[identifier]
            XCTAssertTrue(entry.waitForExistence(timeout: 15))
            entry.tap()
            let navigationBar = app.navigationBars[title]
            XCTAssertTrue(navigationBar.waitForExistence(timeout: 5))
            XCTAssertTrue(navigationBar.buttons.firstMatch.isHittable, "应显示原生返回按钮")
            if title == "个人资料" {
                XCTAssertTrue(app.buttons["profile.avatarPicker"].exists)
                XCTAssertFalse(app.staticTexts["AI 积分"].exists)
            }
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.01, dy: 0.5))
                .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.5)))
            XCTAssertTrue(navigationBar.waitForNonExistence(timeout: 5), "左缘滑动应返回我的页")
            XCTAssertTrue(entry.isHittable)
        }
    }

    func testContactProfilePreservesAcrossSwitchAndReturnsToRootOnReselection() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["UI_TEST_SKIP_ONBOARDING"] = "1"
        app.launchEnvironment["UI_TEST_DISABLE_BACKGROUND_REFRESH"] = "1"
        app.launchEnvironment["UI_TEST_TAB"] = "contacts"
        app.launchEnvironment["LINGOTRIP_BACKEND_URL"] = "http://127.0.0.1:9"
        app.launch()
        defer { app.terminate() }

        let entry = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Oliver")).firstMatch
        XCTAssertTrue(entry.waitForExistence(timeout: 15))
        entry.tap()
        let message = app.buttons["发消息"]
        XCTAssertTrue(message.waitForExistence(timeout: 5))

        // 切去其他标签再切回，停留在角色资料页。
        app.tabBars.buttons["活动"].tap()
        app.tabBars.buttons["联系人"].tap()
        XCTAssertTrue(message.waitForExistence(timeout: 5), "切回联系人标签应保留当前资料页")

        // 再次点击当前标签，回到联系人列表。
        app.tabBars.buttons["联系人"].tap()
        XCTAssertTrue(message.waitForNonExistence(timeout: 5))
        XCTAssertTrue(entry.waitForExistence(timeout: 5))
        XCTAssertTrue(entry.isHittable, "再次点击当前标签应返回联系人列表")
    }
}
