import XCTest

@MainActor
final class ActivitySceneTests: XCTestCase {
    func testSceneLoopControlsAndRouteReturn() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["UI_TEST_SKIP_ONBOARDING"] = "1"
        app.launchEnvironment["UI_TEST_DISABLE_BACKGROUND_REFRESH"] = "1"
        app.launchEnvironment["UI_TEST_HOME_DESTINATION"] = "activities"
        app.launch()
        defer { app.terminate() }
        let preview = app.buttons["activities.scenePreview"]
        XCTAssertTrue(preview.waitForExistence(timeout: 15))
        preview.tap()
        let motion = app.buttons["activities.motion"]
        XCTAssertTrue(motion.waitForExistence(timeout: 5))
        let looping = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            let value = motion.value as? String ?? ""
            return value.contains("播放中") && value.contains("循环2")
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [looping], timeout: 25), .completed)
        motion.tap()
        XCTAssertEqual(motion.value as? String, "静态")
        let still = XCTAttachment(screenshot: app.screenshot())
        still.name = "activity-scene-static"
        still.lifetime = .keepAlways
        add(still)
        motion.tap()
        XCTAssertTrue((motion.value as? String ?? "").contains("动态"))
        // Exercise navigation while the video is playing, not just an isolated player.
        app.buttons["activities.scene.walk"].tap()
        XCTAssertTrue(app.buttons["返回"].waitForExistence(timeout: 3))
        // The shared scene container keeps the root mounted at opacity zero.
        // XCTest can retain its AX node even though it is not visible or hittable.
        let covered = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in !motion.isHittable }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [covered], timeout: 3), .completed)
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.01, dy: 0.5))
        start.press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.7, dy: 0.5)))
        let returned = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in motion.isHittable }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [returned], timeout: 3), .completed)
        XCTAssertTrue(app.buttons["activities.scene.coffee"].exists)
        XCTAssertTrue(app.buttons["activities.scene.culture"].exists)
        app.buttons["关闭场景样板"].tap()
        XCTAssertTrue(preview.waitForExistence(timeout: 3))
    }
}
