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

    func testSceneTabsReturnToRootOnReselectionAndSwitchBack() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["UI_TEST_SKIP_ONBOARDING"] = "1"
        app.launchEnvironment["UI_TEST_DISABLE_BACKGROUND_REFRESH"] = "1"
        app.launchEnvironment["LINGOTRIP_BACKEND_URL"] = "http://127.0.0.1:9"
        app.launchEnvironment["UI_TEST_TAB"] = "home"
        app.launch()
        defer { app.terminate() }

        for (title, entry) in [("活动", "世界地图"), ("我的", "设置，AI、语音与偏好")] {
            app.tabBars.buttons[title].tap()
            for switchesAway in [false, true] {
                XCTAssertTrue(app.buttons[entry].waitForExistence(timeout: 15))
                app.buttons[entry].tap()
                let back = title == "活动"
                    ? app.buttons["返回首页"]
                    : app.navigationBars["设置"].buttons.firstMatch
                XCTAssertTrue(back.waitForExistence(timeout: 5))
                if switchesAway { app.tabBars.buttons["联系人"].tap() }
                app.tabBars.buttons[title].tap()
                XCTAssertTrue(back.waitForNonExistence(timeout: 5), "点击标签应关闭二级页面")
                XCTAssertTrue(app.buttons[entry].isHittable, "初始页面入口应恢复可点击")
            }
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

        for (prefix, title) in [("个人资料，", "个人资料"), ("会员订阅", "会员订阅"),
                                ("收藏夹，", "收藏夹"), ("设置，", "设置"), ("记忆档案", "记忆档案")] {
            let entry = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", prefix)).firstMatch
            XCTAssertTrue(entry.waitForExistence(timeout: 15))
            entry.tap()
            let navigationBar = app.navigationBars[title]
            XCTAssertTrue(navigationBar.waitForExistence(timeout: 5))
            XCTAssertTrue(navigationBar.buttons.firstMatch.isHittable, "应显示原生返回按钮")
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.01, dy: 0.5))
                .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.5)))
            XCTAssertTrue(navigationBar.waitForNonExistence(timeout: 5), "左缘滑动应返回我的页")
            XCTAssertTrue(entry.isHittable)
        }
    }

    func testContactProfileReturnsToRoot() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["UI_TEST_SKIP_ONBOARDING"] = "1"
        app.launchEnvironment["UI_TEST_DISABLE_BACKGROUND_REFRESH"] = "1"
        app.launchEnvironment["UI_TEST_TAB"] = "contacts"
        app.launchEnvironment["LINGOTRIP_BACKEND_URL"] = "http://127.0.0.1:9"
        app.launch()
        defer { app.terminate() }

        for switchesAway in [false, true] {
            let entry = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Oliver")).firstMatch
            XCTAssertTrue(entry.waitForExistence(timeout: 15))
            entry.tap()
            let message = app.buttons["发消息"]
            XCTAssertTrue(message.waitForExistence(timeout: 5))
            if switchesAway { app.tabBars.buttons["活动"].tap() }
            app.tabBars.buttons["联系人"].tap()
            XCTAssertTrue(message.waitForNonExistence(timeout: 5))
            XCTAssertTrue(entry.waitForExistence(timeout: 5))
            XCTAssertTrue(entry.isHittable, "点击标签应返回联系人列表")
        }
    }
}
