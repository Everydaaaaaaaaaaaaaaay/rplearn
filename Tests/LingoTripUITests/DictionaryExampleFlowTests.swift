import XCTest

/// Uses the shipped dictionary and real production translation resolver.
/// Run explicitly: creates a small number of paid, shared-cache translations.
@MainActor
final class DictionaryExampleFlowTests: XCTestCase {
    func testInsertedExampleRendersItsOwnEnglishTokens() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["RUN_LIVE_DICTIONARY_E2E"] == "1")
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment = [
            "UI_TEST_SKIP_ONBOARDING": "1", "UI_TEST_DISABLE_BACKGROUND_REFRESH": "1",
            "UI_TEST_WELCOME_CAPTURE": "1", "UI_TEST_DICTIONARY_EXAMPLES": "1",
            "UI_TEST_LAUGHING_EXAMPLES": "1", "UI_TEST_TAB": "contacts",
            "LINGOTRIP_BACKEND_URL": "https://rplearn.haruyuki.cn"
        ]
        app.launch()
        defer { app.terminate() }
        let ruby = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Ruby")).firstMatch
        XCTAssertTrue(ruby.waitForExistence(timeout: 25)); ruby.tap()
        let chat = app.buttons["发消息"]
        XCTAssertTrue(chat.waitForExistence(timeout: 5)); chat.tap()
        for opening in 0..<2 {
            let word = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "laughing")).firstMatch
            XCTAssertTrue(word.waitForExistence(timeout: 10)); word.tap()
            let sentence = "The laughing baby kicked her feet happily on the blanket."
            let generated = app.descendants(matching: .any)["dict.example." + sentence].firstMatch
            XCTAssertTrue(generated.waitForExistence(timeout: 60), app.debugDescription)
            // Check rendered tappable words, NOT only the model-derived row identifier:
            // the old cache rendered 'laughing children' under this correct identifier.
            XCTAssertTrue(generated.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "baby")).firstMatch.exists, app.debugDescription)
            XCTAssertFalse(generated.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "children")).firstMatch.exists)
            let original = app.descendants(matching: .any)["dict.example.laughing children"].firstMatch
            XCTAssertTrue(original.exists)
            XCTAssertTrue(original.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "children")).firstMatch.exists)
            for row in [generated, original] {
                XCTAssertTrue(row.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@ AND NOT (label CONTAINS %@)", "中文翻译：", "加载中")).firstMatch.waitForExistence(timeout: 120))
            }
            capture("laughing-correct-source-\(opening)", app)
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.02, dy: 0.3)).tap()
        }
    }

    func testOpeningStoryExamplesUseLiveTranslations() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["RUN_LIVE_DICTIONARY_E2E"] == "1")
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment = [
            "UI_TEST_ONBOARDING_WELCOME": "0", "UI_TEST_ONBOARDING_STORY": "1",
            "UI_TEST_DISABLE_BACKGROUND_REFRESH": "1",
            "UI_TEST_DICTIONARY_EXAMPLES": "1",
            "LINGOTRIP_BACKEND_URL": "https://rplearn.haruyuki.cn"
        ]
        app.launch()
        defer { app.terminate() }
        XCTAssertTrue(app.scrollViews["onboarding.story.messages"].waitForExistence(timeout: 20))
        let flat = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "flat")).firstMatch
        for _ in 0..<8 where !flat.exists {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.97, dy: 0.45)).tap()
        }
        XCTAssertTrue(flat.waitForExistence(timeout: 5), app.debugDescription)
        for (word, sentences) in [
            ("flat", ["a flat desk", "flat computer monitors", "the salt flats of Utah", "sail flat against the wind"]),
            ("white", ["as white as fresh snow", "voting patterns within the white population"]),
            ("a", ["He bought a new phone yesterday.", "a typical household circuit carries 15 to 50 amps"])
        ] {
            let target = app.buttons.matching(NSPredicate(format: "label MATCHES %@", "^" + word + "\\b.*")).firstMatch
            XCTAssertTrue(target.waitForExistence(timeout: 5))
            target.tap()
            for sentence in sentences {
                let row = app.descendants(matching: .any)["dict.example." + sentence].firstMatch
                XCTAssertTrue(row.waitForExistence(timeout: 15), app.debugDescription)
                let translated = row.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@ AND NOT (label CONTAINS %@)", "中文翻译：", "加载中")).firstMatch
                XCTAssertTrue(translated.waitForExistence(timeout: 120), app.debugDescription)
                XCTAssertFalse(row.staticTexts["翻译暂不可用，点击重试"].exists)
            }
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.65, dy: 0.84)).press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.65, dy: 0.60)))
            capture("opening-story-" + word, app)
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.02, dy: 0.3)).tap()
        }
    }

    func testTargetWordExamplesAndLiveTranslations() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["RUN_LIVE_DICTIONARY_E2E"] == "1", "Explicit live-provider opt-in required")
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment = [
            "UI_TEST_SKIP_ONBOARDING": "1",
            "UI_TEST_DISABLE_BACKGROUND_REFRESH": "1",
            "UI_TEST_WELCOME_CAPTURE": "1",
            "UI_TEST_DICTIONARY_EXAMPLES": "1",
            "UI_TEST_TAB": "contacts",
            "LINGOTRIP_BACKEND_URL": "https://rplearn.haruyuki.cn"
        ]
        app.launch()
        defer { app.terminate() }
        let ruby = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Ruby")).firstMatch
        XCTAssertTrue(ruby.waitForExistence(timeout: 25))
        ruby.tap()
        let chat = app.buttons["发消息"]
        XCTAssertTrue(chat.waitForExistence(timeout: 5))
        chat.tap()
        let just = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Just")).firstMatch
        XCTAssertTrue(just.waitForExistence(timeout: 10))
        just.tap()
        XCTAssertTrue(app.descendants(matching: .any)["dict.example.I've just finished my coffee."].firstMatch.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertFalse(app.descendants(matching: .any)["dict.example.I was merely asking"].firstMatch.exists)
        XCTAssertFalse(app.descendants(matching: .any)["dict.example.it is simply a matter of time"].firstMatch.exists)
        for sentence in ["I've just finished my coffee.", "I'm just looking, thank you."] {
            let row = app.descendants(matching: .any)["dict.example." + sentence].firstMatch
            XCTAssertTrue(row.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@ AND NOT (label CONTAINS %@)", "中文翻译：", "加载中")).firstMatch.waitForExistence(timeout: 120), app.debugDescription)
        }
        capture("just-target-examples", app)
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.02, dy: 0.3)).tap()
        let which = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Which")).firstMatch
        XCTAssertTrue(which.waitForExistence(timeout: 5))
        which.tap()
        XCTAssertTrue(app.descendants(matching: .any)["dict.example.Which would you prefer, tea or coffee?"].firstMatch.waitForExistence(timeout: 10), app.debugDescription)
        for sentence in ["Which would you prefer, tea or coffee?", "My bike, which I bought last year, needs a new tyre."] {
            let row = app.descendants(matching: .any)["dict.example." + sentence].firstMatch
            XCTAssertTrue(row.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@ AND NOT (label CONTAINS %@)", "中文翻译：", "加载中")).firstMatch.waitForExistence(timeout: 120), app.debugDescription)
        }
        capture("which-learner-examples", app)
    }

    func testSharedExamplesArriveWithoutBundledUpdate() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["RUN_LIVE_DICTIONARY_E2E"] == "1")
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment = [
            "UI_TEST_SKIP_ONBOARDING": "1", "UI_TEST_DISABLE_BACKGROUND_REFRESH": "1",
            "UI_TEST_WELCOME_CAPTURE": "1", "UI_TEST_DICTIONARY_EXAMPLES": "1",
            "UI_TEST_SHARED_EXAMPLES": "1", "UI_TEST_TAB": "contacts",
            "LINGOTRIP_BACKEND_URL": "https://rplearn.haruyuki.cn"
        ]
        app.launch()
        defer { app.terminate() }
        let ruby = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Ruby")).firstMatch
        XCTAssertTrue(ruby.waitForExistence(timeout: 25))
        ruby.tap()
        let chat = app.buttons["发消息"]
        XCTAssertTrue(chat.waitForExistence(timeout: 5))
        chat.tap()
        let word = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "The")).firstMatch
        XCTAssertTrue(word.waitForExistence(timeout: 10))
        word.tap()
        for sentence in ["Please close the window before you leave.", "The cat is sleeping on the warm sofa."] {
            let row = app.descendants(matching: .any)["dict.example." + sentence].firstMatch
            XCTAssertTrue(row.waitForExistence(timeout: 30), app.debugDescription)
            XCTAssertTrue(row.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@ AND NOT (label CONTAINS %@)", "中文翻译：", "加载中")).firstMatch.waitForExistence(timeout: 30), app.debugDescription)
        }
        capture("the-shared-examples", app)
    }

    func testRuntimeExamplesAndSharedReuse() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["RUN_LIVE_DICTIONARY_E2E"] == "1")
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment = [
            "UI_TEST_SKIP_ONBOARDING": "1", "UI_TEST_DISABLE_BACKGROUND_REFRESH": "1",
            "UI_TEST_WELCOME_CAPTURE": "1", "UI_TEST_DICTIONARY_EXAMPLES": "1",
            "UI_TEST_RUNTIME_EXAMPLES": "1", "UI_TEST_TAB": "contacts",
            "LINGOTRIP_BACKEND_URL": "https://rplearn.haruyuki.cn"
        ]
        app.launch()
        defer { app.terminate() }
        let ruby = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Ruby")).firstMatch
        XCTAssertTrue(ruby.waitForExistence(timeout: 25))
        ruby.tap()
        let chat = app.buttons["发消息"]
        XCTAssertTrue(chat.waitForExistence(timeout: 5))
        chat.tap()
        let word = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Murmuration")).firstMatch
        XCTAssertTrue(word.waitForExistence(timeout: 10))
        word.tap()
        let rows = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@", "dict.example."))
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in rows.count >= 2 }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 120), .completed, app.debugDescription)
        let identities = (0..<rows.count).map { rows.element(boundBy: $0).identifier }
        for id in identities {
            let row = app.descendants(matching: .any)[id].firstMatch
            XCTAssertTrue(row.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@ AND NOT (label CONTAINS %@)", "中文翻译：", "加载中")).firstMatch.waitForExistence(timeout: 10))
        }
        capture("murmuration-runtime-examples", app)
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.02, dy: 0.3)).tap()
        word.tap()
        for id in identities {
            XCTAssertTrue(app.descendants(matching: .any)[id].firstMatch.waitForExistence(timeout: 15))
        }
        capture("murmuration-shared-reuse", app)
    }

    private func capture(_ name: String, _ app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
