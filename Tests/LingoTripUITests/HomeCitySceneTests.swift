import XCTest

@MainActor
final class HomeCitySceneTests: XCTestCase {
    func testLondon() { verifyScene("london", city: "伦敦") }
    func testMelbourne() { verifyScene("melbourne", city: "墨尔本") }
    func testNewyork() { verifyScene("newyork", city: "纽约") }
    func testCapetown() { verifyScene("capetown", city: "开普敦") }
    func testSingapore() { verifyScene("singapore", city: "新加坡") }
    func testDublin() { verifyScene("dublin", city: "都柏林") }
    func testEdinburgh() { verifyScene("edinburgh", city: "爱丁堡") }
    func testVancouver() { verifyScene("vancouver", city: "温哥华") }
    func testAuckland() { verifyScene("auckland", city: "奥克兰") }
    func testNairobi() { verifyScene("nairobi", city: "内罗毕") }
    func testToronto() { verifyScene("toronto", city: "多伦多") }
    func testSydney() { verifyScene("sydney", city: "悉尼") }
    func testNeworleans() { verifyScene("neworleans", city: "新奥尔良") }
    func testManchester() { verifyScene("manchester", city: "曼彻斯特") }
    func testKingston() { verifyScene("kingston", city: "金斯敦") }

    private func verifyScene(_ id: String, city: String) {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["UI_TEST_SKIP_ONBOARDING"] = "1"
        app.launchEnvironment["UI_TEST_DISABLE_BACKGROUND_REFRESH"] = "1"
        app.launchEnvironment["UI_TEST_TAB"] = "home"
        app.launchEnvironment["UI_TEST_REGION"] = id
        app.launch()
        defer { app.terminate() }
        let map = app.buttons["世界地图"]
        XCTAssertTrue(map.waitForExistence(timeout: 15))
        XCTAssertTrue(map.isHittable)
        XCTAssertTrue(app.buttons["城市活动"].isHittable)
        let story = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "剧情，")).firstMatch
        XCTAssertTrue(story.isHittable)
        let location = app.descendants(matching: .any).matching(
            NSPredicate(format: "label BEGINSWITH %@ AND label ENDSWITH %@", "当前驻地，", city)
        ).firstMatch
        XCTAssertTrue(location.exists, "城市名称必须与背景同步更新")
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "home-city-\(id)"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        map.tap()
        let back = app.buttons["返回首页"]
        XCTAssertTrue(back.waitForExistence(timeout: 4))
        back.tap()
        XCTAssertTrue(map.waitForExistence(timeout: 4))

        // 两种门向验证剧情；各城实际点击活动，防止 isHittable 漏掉底栏遮挡。
        if id == "london" || id == "edinburgh" {
            story.tap()
            XCTAssertTrue(app.navigationBars["剧情"].waitForExistence(timeout: 4))
            app.navigationBars.buttons.firstMatch.tap()
            XCTAssertTrue(map.waitForExistence(timeout: 4))
        }
        app.buttons["城市活动"].tap()
        let activitiesBack = app.buttons["activities.back"]
        XCTAssertTrue(activitiesBack.waitForExistence(timeout: 4))
        activitiesBack.tap()
        XCTAssertTrue(map.waitForExistence(timeout: 4))
    }
}
