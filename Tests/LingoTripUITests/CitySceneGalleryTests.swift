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
    private func open(_ id: String) {
        let button = app.buttons["sceneGallery.place.\(id)"]
        for _ in 0..<8 where !button.isHittable || button.frame.maxY > app.frame.maxY - 40 { app.swipeUp() }
        XCTAssertTrue(button.isHittable)
        button.tap()
        XCTAssertTrue(app.buttons["sceneGallery.back"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.images["activities.photo.loaded.\(id)"].waitForExistence(timeout: 5))
    }
    func testAllCitiesLoadTheirOwnPhotographs() {
        app.launch()
        XCTAssertTrue(app.buttons["sceneGallery.cities"].waitForExistence(timeout: 30))
        for (city, places) in placesByCity {
            chooseCity(city)
            capture("\(city)-place-list")
            for place in places {
                open(place)
                capture("\(place)-background")
                app.buttons["sceneGallery.back"].tap()
                XCTAssertTrue(app.buttons["sceneGallery.back"].waitForNonExistence(timeout: 5))
            }
        }
    }
    func testLargeTextCreditsOriginalAndFifthPlace() {
        app.launchArguments = ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        XCTAssertTrue(app.buttons["sceneGallery.cities"].waitForExistence(timeout: 30))
        open("london-southbank")
        capture("london-southbank-large")
        let credits = app.buttons["sceneGallery.credits"]
        for _ in 0..<4 where !credits.isHittable { app.swipeUp() }
        credits.tap()
        XCTAssertTrue(app.navigationBars["照片信息"].waitForExistence(timeout: 5))
        capture("scene-credits-large")
        app.navigationBars["照片信息"].buttons["完成"].tap()
        app.buttons["sceneGallery.original"].tap()
        XCTAssertTrue(app.buttons["sceneGallery.original.close"].waitForExistence(timeout: 5))
        capture("scene-original-large")
        app.buttons["sceneGallery.original.close"].tap()
        XCTAssertTrue(app.buttons["sceneGallery.original.close"].waitForNonExistence(timeout: 5))
        app.buttons["sceneGallery.back"].tap()
        open("london-primrose-hill")
        capture("fifth-scene-large")
        for _ in 0..<4 where !credits.isHittable { app.swipeUp() }
        XCTAssertTrue(credits.isHittable)
        capture("fifth-scene-large-controls")
        app.buttons["sceneGallery.back"].tap()
        XCTAssertTrue(app.buttons["sceneGallery.back"].waitForNonExistence(timeout: 5))
        chooseCity("nairobi")
        open("nairobi-city-market")
        capture("three-place-city-last-scene-large")
        for _ in 0..<4 where !credits.isHittable { app.swipeUp() }
        XCTAssertTrue(credits.isHittable)
        capture("three-place-city-last-scene-large-controls")
    }
}
