import XCTest

@MainActor
final class LiveListeningUITests: XCTestCase {
    func testEnglishQuestionAndTwoLivePasses() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment = ["UI_TEST_SKIP_ONBOARDING": "1", "UI_TEST_DISABLE_BACKGROUND_REFRESH": "1",
            "LINGOTRIP_BACKEND_URL": "http://127.0.0.1:9", "UI_TEST_TAB": "unit-challenge",
            "UI_TEST_LEARNING_QUESTION_ID": "s3.second.q01",
            "UI_TEST_LEARNING_UNIT_JSON": unit, "UI_TEST_LEARNING_SPEECH_JSON": script]
        app.launch(); addTeardownBlock { app.terminate() }
        XCTAssertTrue(app.staticTexts["What arrangement does the second speaker finally suggest?"].waitForExistence(timeout: 15))
        let play = app.buttons["learning.audio.play"]
        XCTAssertTrue(play.waitForExistence(timeout: 5))
        XCTAssertEqual(play.label, "第一遍 · 美音")
        play.tap()
        let second = NSPredicate(format: "label == %@", "第二遍 · 英音")
        expectation(for: second, evaluatedWith: play)
        waitForExpectations(timeout: 60)
        XCTAssertTrue(play.isEnabled)
        let choice = app.buttons["learning.option.b"]
        if !choice.isHittable { app.swipeUp() }
        XCTAssertTrue(choice.label.contains("Keep the event and move its start to after lunch."))
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "高三听力-英文题面-第二遍英音"
        screenshot.lifetime = .keepAlways; add(screenshot)
        play.tap()
        let finished = NSPredicate(format: "label == %@", "已听完两遍")
        expectation(for: finished, evaluatedWith: play)
        waitForExpectations(timeout: 60)
        XCTAssertFalse(play.isEnabled)
        XCTAssertFalse(app.buttons["learning.audio.slow"].isEnabled)
    }
    // Public, answer-free source question. Shortened speech is an engineering
    // fixture for actual on-device synthesis/playback, not a teaching recording.
    private let unit = #"""
{"id":"companion.senior3.paper-boat","version":2,"schemaVersion":1,"roleKey":"companion","level":"senior3","title":"桥下的纸船","summary":"桥下的纸船","scene":"雨后，你和同行者停在一座矮桥上。一只纸船在桥下的断枝旁缓缓打转。同行者的手指沿着栏杆，跟着纸船移动。纸船眼看就要漂出去，水流却又把它带回了那个小圈。","estimatedMinutes":14,"goalIds":["senior3.listen-discourse-position","senior3.argument-evidence-link","senior3.listen-precise-record","senior3.clarification-register"],"beats":[{"id":"opening.1","afterQuestion":0,"speaker":"旁白","text":"You and your companion stop on a low bridge after the rain. Below you, a paper boat turns slowly beside a fallen branch. Your companion follows it with one finger along the rail. Just as the boat seems ready to escape, the water carries it back into the same small circle.","translation":"雨后，你和同行者停在一座矮桥上。一只纸船在桥下的断枝旁缓缓打转。同行者的手指沿着栏杆，跟着纸船移动。纸船眼看就要漂出去，水流却又把它带回了那个小圈。"},{"id":"opening.2","afterQuestion":0,"speaker":"旁白","text":"You both lean on the rail and wait. A leaf slips past the branch, and the boat follows it for a moment before turning away. Your companion quietly draws another circle on the wet rail. Then a stronger ripple reaches the boat. It tips, straightens, and finally floats beneath the bridge.","translation":"你们靠着栏杆等着。一片叶子从断枝旁滑过去，纸船跟了一小段，又转开了。同行者在湿栏杆上悄悄画了一个圈。这时，一道稍强的水波推来。纸船歪了一下，重新稳住，终于漂进桥下。"},{"id":"opening.3","afterQuestion":0,"speaker":"旁白","text":"You hurry to the other side together. For a few seconds there is only dark water. Then the little boat appears, one corner folded down but still afloat. It drifts towards a patch of sunlight. Your companion lifts a hand in a small wave, and you continue your walk without deciding where to go next.","translation":"你们一起快步走到桥的另一侧。几秒钟里，眼前只有暗暗的水面。随后，小纸船出现了，一个角折了下来，却还浮着。它漂向一片阳光。同行者轻轻挥了一下手，你们继续往前走，还没有决定接下来去哪儿。"}],"questions":[{"id":"s3.second.q01","type":"listeningChoice","goalId":"senior3.listen-discourse-position","instruction":"听后选择","prompt":"What arrangement does the second speaker finally suggest?","hint":"听清最初的赞同之后，哪条新信息使提议发生变化。","options":[{"id":"a","text":"Cancel the event because there are too few helpers in the afternoon as well."},{"id":"b","text":"Keep the event and move its start to after lunch."},{"id":"c","text":"Keep the event on Saturday morning as planned."}],"audio":{"assetId":"audio.c2802e0ea80255ed25e65b931e02843cb196f422c22e31b0ac5c91e3c1a62f97"}}]}
"""#
    private let script = #"""
{"assetId":"audio.c2802e0ea80255ed25e65b931e02843cb196f422c22e31b0ac5c91e3c1a62f97","segments":[{"text":"The book swap will start after lunch.","pauseAfterMs":3000},{"text":"Question: What arrangement does the second speaker finally suggest?","pauseAfterMs":0}]}
"""#
}
