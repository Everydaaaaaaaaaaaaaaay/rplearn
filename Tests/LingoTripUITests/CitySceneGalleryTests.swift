import XCTest

@MainActor
final class CitySceneGalleryTests: XCTestCase {
    private var app: XCUIApplication!
    private let placesByCity: [(String, [String])] = [
        ("london", ["london-southbank", "london-bloomsbury-cafe", "london-borough-market", "london-marylebone-bookshop", "london-primrose-hill"]),
        ("newyork", ["newyork-high-line", "newyork-grand-central", "newyork-union-square-market", "newyork-coney-island", "newyork-greenwich-village"]),
        ("singapore", ["singapore-tiong-bahru-market", "singapore-joo-chiat", "singapore-botanic-gardens", "singapore-marina-bay"]),
        ("sydney", ["sydney-bondi", "sydney-circular-quay", "sydney-glebe-market", "sydney-newtown-bookshop"]),
        ("melbourne", ["melbourne-fitzroy-cafe", "melbourne-laneways", "melbourne-queen-victoria-market", "melbourne-state-library"]),
        ("toronto", ["toronto-kensington", "toronto-islands", "toronto-st-lawrence-market", "toronto-distillery-district"]),
        ("vancouver", ["vancouver-gastown", "vancouver-false-creek", "vancouver-granville-market", "vancouver-stanley-park"]),
        ("edinburgh", ["edinburgh-dean-village", "edinburgh-old-town", "edinburgh-calton-hill"]),
        ("dublin", ["dublin-trinity", "dublin-grand-canal", "dublin-georges-arcade"]),
        ("auckland", ["auckland-mount-eden", "auckland-wynyard-quarter", "auckland-otara-market"]),
        ("capetown", ["capetown-bo-kaap", "capetown-sea-point", "capetown-greenmarket"]),
        ("manchester", ["manchester-afflecks", "manchester-castlefield", "manchester-central-library"]),
        ("neworleans", ["neworleans-jackson-square", "neworleans-frenchmen-street", "neworleans-french-market"]),
        ("nairobi", ["nairobi-national-museum", "nairobi-karura-forest", "nairobi-city-market"]),
        ("kingston", ["kingston-devon-house", "kingston-emancipation-park", "kingston-waterfront"])
    ]
    override func setUp() async throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchEnvironment = [
            "UI_TEST_SKIP_ONBOARDING": "1", "UI_TEST_REQUIRE_AUTHENTICATION": "0",
            "UI_TEST_DISABLE_BACKGROUND_REFRESH": "1", "UI_TEST_TAB": "scenes-preview",
            "LINGOTRIP_BACKEND_URL": "http://127.0.0.1:9",
        ]
    }
    override func tearDown() async throws { app.terminate() }
    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
    private func chooseCity(_ city: String) {
        app.buttons["sceneGallery.cities"].tap()
        let button = app.buttons["sceneGallery.city.\(city)"]
        for _ in 0..<8 where !button.isHittable || button.frame.maxY > app.frame.maxY - 40 { app.swipeUp() }
        XCTAssertTrue(button.isHittable)
        button.tap()
    }
    private func assertScene(_ id: String) {
        let title = app.descendants(matching: .any)["activities.scene.title.\(id)"]
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        XCTAssertTrue(app.images["activities.photo.loaded.\(id)"].waitForExistence(timeout: 5))
        let visit = app.buttons["activities.place.\(id)"]
        XCTAssertTrue(visit.isHittable)
        XCTAssertEqual(visit.label, "去这里逛逛")
        XCTAssertGreaterThanOrEqual(visit.frame.height, 44)
        XCTAssertLessThanOrEqual(visit.frame.maxY, app.frame.maxY)
        XCTAssertFalse(title.frame.intersects(app.buttons["activities.scene.next"].frame))
    }
    private func swipeScene(left: Bool) {
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: left ? 0.8 : 0.2, dy: 0.4))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: left ? 0.2 : 0.8, dy: 0.4))
        start.press(forDuration: 0.05, thenDragTo: end)
    }
    func testAllCitiesLoadTheirOwnPhotographs() {
        app.launch()
        XCTAssertTrue(app.buttons["sceneGallery.cities"].waitForExistence(timeout: 30))
        for (city, places) in placesByCity {
            chooseCity(city)
            for (index, place) in places.enumerated() {
                if index > 0 { app.buttons["activities.scene.next"].tap() }
                assertScene(place)
                XCTAssertEqual(app.buttons["activities.scene.previous"].isEnabled, index > 0)
                XCTAssertEqual(app.buttons["activities.scene.next"].isEnabled, index < places.count - 1)
                capture("\(place)-fullscreen")
            }
        }
    }
    func testSwipeArrowsAndVisitSelectTheSameScene() {
        app.launch()
        XCTAssertTrue(app.buttons["sceneGallery.cities"].waitForExistence(timeout: 30))
        assertScene("london-southbank")
        capture("outline-button-southbank")
        swipeScene(left: true)
        assertScene("london-bloomsbury-cafe")
        app.buttons["activities.scene.next"].tap()
        assertScene("london-borough-market")
        capture("outline-button-market")
        swipeScene(left: false)
        assertScene("london-bloomsbury-cafe")
        app.buttons["activities.scene.previous"].tap()
        assertScene("london-southbank")
        app.buttons["activities.place.london-southbank"]
            .coordinate(withNormalizedOffset: CGVector(dx: 0.1, dy: 0.5)).tap()
        XCTAssertTrue(app.alerts["人物剧情正在接入"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.alerts.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "泰晤士河南岸")).firstMatch.exists)
        app.alerts.buttons["知道了"].tap()
        assertScene("london-southbank")
    }
    func testLargeTextCreditsOriginalAndFifthPlace() {
        app.launchArguments = ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        XCTAssertTrue(app.buttons["sceneGallery.cities"].waitForExistence(timeout: 30))
        assertScene("london-southbank")
        capture("fullscreen-southbank-large")
        app.buttons["sceneGallery.cities"].tap()
        capture("city-picker-large")
        app.buttons["取消"].tap()
        app.buttons["activities.scene.more"].tap()
        app.buttons["照片信息"].tap()
        XCTAssertTrue(app.navigationBars["照片信息"].waitForExistence(timeout: 5))
        capture("fullscreen-credits-large")
        app.navigationBars["照片信息"].buttons["完成"].tap()
        app.buttons["activities.scene.more"].tap()
        app.buttons["查看全图"].tap()
        XCTAssertTrue(app.buttons["sceneGallery.original.close"].waitForExistence(timeout: 5))
        capture("fullscreen-original-large")
        app.buttons["sceneGallery.original.close"].tap()
        XCTAssertTrue(app.buttons["sceneGallery.original.close"].waitForNonExistence(timeout: 5))
        for _ in 0..<4 { app.buttons["activities.scene.next"].tap() }
        assertScene("london-primrose-hill")
        capture("fullscreen-fifth-large")
        chooseCity("nairobi")
        assertScene("nairobi-national-museum")
        capture("fullscreen-long-title-large")
        for _ in 0..<2 { app.buttons["activities.scene.next"].tap() }
        assertScene("nairobi-city-market")
        capture("fullscreen-three-place-city-last-large")
    }
}
