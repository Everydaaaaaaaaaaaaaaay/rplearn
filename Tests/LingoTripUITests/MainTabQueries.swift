import XCTest

extension XCUIApplication {
    var mainTabButtons: XCUIElementQuery { otherElements["main.tabs"].buttons }
}
