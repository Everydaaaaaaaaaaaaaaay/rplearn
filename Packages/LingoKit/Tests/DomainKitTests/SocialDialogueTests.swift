import XCTest
import LLMKit
import PersistenceKit
@testable import DomainKit

final class SocialDialogueTests: XCTestCase {
    private let validJSON = "{\"english\":\"Hello there.\",\"chinese\":\"你好。\",\"acceptsContact\":false}"

    func testAcceptsJSONCodeFenceWithoutChangingTheReply() throws {
        let reply = try SocialDialogueService.decode("```json\n\(validJSON)\n```", invitesContact: false)
        XCTAssertEqual(reply.english, "Hello there.")
    }

    func testRepairsInvalidReplyOnceWithSameCharacterAndTurn() async throws {
        let responses = ReplySequence(["not-json", validJSON])
        let client = MockLLMProvider(completeHandler: { await responses.next($0) })
        let reply = try await requestReply(client)
        XCTAssertEqual(reply.english, "Hello there.")
        let requests = await responses.requests
        XCTAssertEqual(requests.count, 2)
        XCTAssertNotEqual(requests[0].operationID, requests[1].operationID)
        XCTAssertEqual(requests[1].parentOperationID, requests[0].operationID)
        XCTAssertEqual(requests[0].messages, requests[1].messages)
    }

    func testInvalidReplyRepairIsBoundedAndHasReadableError() async {
        let responses = ReplySequence(["{}", "{}"])
        let client = MockLLMProvider(completeHandler: { await responses.next($0) })
        do {
            _ = try await requestReply(client)
            XCTFail("Invalid replies must not be committed")
        } catch {
            XCTAssertTrue(error is SocialDialogueService.DialogueError)
            XCTAssertFalse(error.localizedDescription.contains("error 0"))
        }
        let requests = await responses.requests
        XCTAssertEqual(requests.count, 2)
    }

    func testAccessRestrictionDoesNotTriggerFormatRepair() async {
        let responses = ReplySequence([])
        let client = MockLLMProvider(completeHandler: {
            _ = await responses.next($0)
            throw LLMError.accessRestricted("额度已用完")
        })
        do {
            _ = try await requestReply(client)
            XCTFail("Must propagate quota restrictions")
        } catch {
            XCTAssertEqual(error as? LLMError, .accessRestricted("额度已用完"))
        }
        let count = await responses.requests.count
        XCTAssertEqual(count, 1)
    }

    private func requestReply(_ client: any LLMClient) async throws -> SocialDialogueService.Reply {
        let card = CharacterCard(name: "Sam", age: 30, gender: .male, nationality: "British",
            regionID: "london", occupation: "teacher", hobbies: ["园艺"], appearance: "", personality: "kind")
        return try await SocialDialogueService(llm: client).reply(card: card, context: "湖边写短笺",
            history: "", userLine: nil, invitesContact: false, alreadyKnown: false, difficulty: .junior3)
    }

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

private actor ReplySequence {
    private var responses: [String]
    private(set) var requests: [LLMRequest] = []
    init(_ responses: [String]) { self.responses = responses }
    func next(_ request: LLMRequest) -> String {
        requests.append(request)
        return responses.isEmpty ? "{}" : responses.removeFirst()
    }
}
