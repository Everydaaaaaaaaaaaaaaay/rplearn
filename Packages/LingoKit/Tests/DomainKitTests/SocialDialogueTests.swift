import XCTest
@testable import DomainKit

final class SocialDialogueTests: XCTestCase {
    func testUnsolicitedContactMetadataCannotGrantFriendship() throws {
        let json = "{\"english\":\"Hello there.\",\"chinese\":\"你好。\",\"acceptsContact\":true}"
        XCTAssertFalse(try SocialDialogueService.decode(json, invitesContact: false).acceptsContact)
        XCTAssertTrue(try SocialDialogueService.decode(json, invitesContact: true).acceptsContact)
    }

    func testRejectsOverlongSpeechEmptyTranslationsAndInvalidPayload() {
        for json in [
            "{\"english\":\"\(String(repeating: "word ", count: 29))\",\"chinese\":\"你好。\",\"acceptsContact\":false}",
            "{\"english\":\"\(String(repeating: "a", count: 181))\",\"chinese\":\"你好。\",\"acceptsContact\":false}",
            "{\"english\":\"Hello.\",\"chinese\":\"  \",\"acceptsContact\":false}",
            "not-json"
        ] {
            XCTAssertThrowsError(try SocialDialogueService.decode(json, invitesContact: false))
        }
    }
}
