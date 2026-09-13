import XCTest

@MainActor
final class MyPagePerformanceTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchEnvironment["UI_TEST_SKIP_ONBOARDING"] = "1"
        app.launchEnvironment["UI_TEST_DISABLE_BACKGROUND_REFRESH"] = "1"
        app.launchEnvironment["LINGOTRIP_BACKEND_URL"] = "http://127.0.0.1:9"
    }

    override func tearDownWithError() throws {
        app.terminate()
        app = nil
    }

    @MainActor
    func testMyPageTabRoundTripPerformance() throws {
        launch(on: "messages")

        let messagesTab = app.tabBars.buttons["信息"]
        let meTab = app.tabBars.buttons["我的"]
        let settingsEntry = app.buttons["设置，AI、语音与偏好"]
        XCTAssertTrue(messagesTab.waitForExistence(timeout: 5))
        XCTAssertTrue(meTab.exists)

        let options = XCTMeasureOptions()
        options.iterationCount = 5
        measure(
            metrics: [XCTClockMetric(), XCTCPUMetric(), XCTMemoryMetric()],
            options: options
        ) {
            meTab.tap()
            XCTAssertTrue(settingsEntry.waitForExistence(timeout: 3))
            messagesTab.tap()
            XCTAssertTrue(messagesTab.waitForExistence(timeout: 3))
        }
    }

    @MainActor
    func testFavoritesRoundTripPerformance() throws {
        launch(on: "me")

        let favoritesEntry = app.buttons["收藏夹，单词与语法点"]
        XCTAssertTrue(favoritesEntry.waitForExistence(timeout: 5))

        let options = XCTMeasureOptions()
        options.iterationCount = 5
        measure(
            metrics: [XCTClockMetric(), XCTCPUMetric(), XCTMemoryMetric()],
            options: options
        ) {
            let currentFavoritesEntry = app.buttons["收藏夹，单词与语法点"]
            XCTAssertTrue(currentFavoritesEntry.waitForExistence(timeout: 3))
            currentFavoritesEntry.tap()
            let back = app.navigationBars.buttons.firstMatch
            XCTAssertTrue(back.waitForExistence(timeout: 3))
            back.tap()
            XCTAssertTrue(app.buttons["收藏夹，单词与语法点"].waitForExistence(timeout: 3))
        }
    }

    @MainActor
    func testSettingsRoundTripPerformance() throws {
        launch(on: "me")

        let settingsEntry = app.buttons["设置，AI、语音与偏好"]
        XCTAssertTrue(settingsEntry.waitForExistence(timeout: 5))

        let options = XCTMeasureOptions()
        options.iterationCount = 5
        measure(
            metrics: [XCTClockMetric(), XCTCPUMetric(), XCTMemoryMetric()],
            options: options
        ) {
            let currentSettingsEntry = app.buttons["设置，AI、语音与偏好"]
            XCTAssertTrue(currentSettingsEntry.waitForExistence(timeout: 3))
            currentSettingsEntry.tap()
            let back = app.navigationBars.buttons.firstMatch
            XCTAssertTrue(back.waitForExistence(timeout: 3))
            back.tap()
            XCTAssertTrue(app.buttons["设置，AI、语音与偏好"].waitForExistence(timeout: 3))
        }
    }

    @MainActor
    func testQuickTapKeepsSceneFeedbackVisibleBeforeNavigation() throws {
        launch(on: "me")

        let favoritesEntry = app.buttons["收藏夹，单词与语法点"]
        XCTAssertTrue(favoritesEntry.waitForExistence(timeout: 5))

        let start = ContinuousClock.now
        favoritesEntry.tap()
        let favoritesNavigationBar = app.navigationBars["收藏夹"]
        XCTAssertTrue(favoritesNavigationBar.waitForExistence(timeout: 2))
        let elapsed = ContinuousClock.now - start

        XCTAssertGreaterThanOrEqual(elapsed, .milliseconds(100))
        // XCUITest 轮询导航栏出现会引入额外的观测延迟；产品内部时序为 0.02 + 0.08 + 0.02 秒。
        XCTAssertLessThan(elapsed, .seconds(1.8))
    }

    @MainActor
    func testFavoritesSupportsLeadingEdgeSwipeBack() throws {
        launch(on: "me")

        let favoritesEntry = app.buttons["收藏夹，单词与语法点"]
        XCTAssertTrue(favoritesEntry.waitForExistence(timeout: 5))
        favoritesEntry.tap()
        XCTAssertTrue(app.navigationBars["收藏夹"].waitForExistence(timeout: 2))

        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.01, dy: 0.5))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.72, dy: 0.5))
        start.press(forDuration: 0.05, thenDragTo: end)

        XCTAssertTrue(favoritesEntry.waitForExistence(timeout: 2))
        XCTAssertFalse(app.navigationBars["收藏夹"].exists)
    }

    @MainActor
    func testSettingsSupportsLeadingEdgeSwipeBack() throws {
        launch(on: "me")

        let settingsEntry = app.buttons["设置，AI、语音与偏好"]
        XCTAssertTrue(settingsEntry.waitForExistence(timeout: 5))
        settingsEntry.tap()
        XCTAssertTrue(app.navigationBars["设置"].waitForExistence(timeout: 2))

        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.01, dy: 0.5))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.72, dy: 0.5))
        start.press(forDuration: 0.05, thenDragTo: end)

        XCTAssertTrue(settingsEntry.waitForExistence(timeout: 2))
        XCTAssertFalse(app.navigationBars["设置"].exists)
    }

    @MainActor
    func testLegacyTabBarUsesNativeFullWidthAppearance() throws {
        app.launchEnvironment["UI_TEST_FORCE_LEGACY_CHROME"] = "1"
        launch(on: "me")

        let capsule = app.descendants(matching: .any)["LegacyTabBarCapsule"]
        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: 5))
        XCTAssertFalse(capsule.exists)
        XCTAssertEqual(tabBar.frame.minX, app.frame.minX, accuracy: 1)
        XCTAssertEqual(tabBar.frame.maxX, app.frame.maxX, accuracy: 1)
        XCTAssertEqual(tabBar.frame.maxY, app.frame.maxY, accuracy: 1)
        XCTAssertGreaterThanOrEqual(tabBar.frame.height, 49)

        let labels = ["信息", "联系人", "首页", "我的", "测试"]
        for label in labels {
            let item = tabBar.buttons[label]
            XCTAssertTrue(item.exists)
            XCTAssertTrue(tabBar.frame.contains(CGPoint(x: item.frame.midX, y: item.frame.midY)))
        }
    }

    @MainActor
    func testAccountSubscriptionAndMemoryPages() throws {
        launch(on: "me")
        let profile = app.buttons["me.profile"]
        XCTAssertTrue(profile.waitForExistence(timeout: 10))
        let scene = XCTAttachment(screenshot: app.screenshot()); scene.name = "subscription-entry-size"; scene.lifetime = .keepAlways; add(scene)
        XCTAssertFalse(app.buttons["me.coinBalance"].exists)
        profile.tap()
        XCTAssertTrue(app.navigationBars["个人资料"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["profile.avatarPicker"].exists)
        let account = XCTAttachment(screenshot: app.screenshot()); account.name = "account-page"; account.lifetime = .keepAlways; add(account)
        app.navigationBars.buttons["返回"].tap()
        app.buttons["me.subscription"].tap()
        XCTAssertTrue(app.navigationBars["订阅与金币"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["订阅计划"].exists)
        XCTAssertTrue(app.staticTexts["金币充值"].exists)
        XCTAssertTrue(app.buttons["me.credits"].exists)
        let store = XCTAttachment(screenshot: app.screenshot()); store.name = "subscription-page"; store.lifetime = .keepAlways; add(store)
        app.buttons["me.credits"].tap()
        XCTAssertTrue(app.navigationBars["积分余额与明细"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["重试"].waitForExistence(timeout: 15))
        let credits = XCTAttachment(screenshot: app.screenshot()); credits.name = "credits-load-error"; credits.lifetime = .keepAlways; add(credits)
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(app.navigationBars["订阅与金币"].waitForExistence(timeout: 5))
        app.navigationBars.buttons["返回"].tap()
        app.buttons["记忆档案"].tap()
        XCTAssertTrue(app.staticTexts["记忆档案库"].waitForExistence(timeout: 5))
    }

    func testLevelDoneSavesImmediately() throws {
        launch(on: "me")
        XCTAssertTrue(app.buttons["me.level"].waitForExistence(timeout: 10))
        app.buttons["me.level"].tap()
        XCTAssertTrue(app.buttons["placement.chooseLevel"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "直接应用")).firstMatch.exists)
        app.buttons["placement.chooseLevel"].tap()
        let level = app.buttons["placement.level.primary2"]
        XCTAssertTrue(level.waitForExistence(timeout: 5))
        level.tap()
        app.buttons["完成"].tap()
        XCTAssertTrue(app.buttons["me.level"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["me.level"].label.contains("小学二年级"))
    }

    private func launch(on tab: String) {
        app.launchEnvironment["UI_TEST_TAB"] = tab
        app.launch()
    }
}
