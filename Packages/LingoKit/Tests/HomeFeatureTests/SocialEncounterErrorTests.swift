import XCTest
import DomainKit
import LLMKit
@testable import HomeFeature

@MainActor
final class SocialEncounterErrorTests: XCTestCase {
    func testPreparationAndReplyFailuresHaveDistinctMessages() {
        let preparation = SocialEncounterModel.message(for: SocialEncounterModel.PreparationError.characterUnavailable)
        let reply = SocialEncounterModel.message(for: SocialDialogueService.DialogueError.invalidReply)
        XCTAssertTrue(preparation.contains("人物"))
        XCTAssertTrue(reply.contains("回复"))
        XCTAssertNotEqual(preparation, reply)
    }

    func testUnexpectedErrorsDoNotExposeImplementationDetails() {
        let message = SocialEncounterModel.message(for: NSError(domain: "Internal.Service", code: 123))
        XCTAssertFalse(message.contains("Internal.Service"))
        XCTAssertFalse(message.contains("123"))
        XCTAssertTrue(message.contains("重试"))
        XCTAssertEqual(SocialEncounterModel.message(for: LLMError.accessRestricted("额度已用完")), "额度已用完")
    }
}
