import BackendKit
import DomainKit
import Foundation
import LLMKit
import PersistenceKit
import Testing

/// 显式设置 RUN_LIVE_AI_EVAL=1 时才访问生产 AI 网关；默认测试不会产生请求或额度消耗。
@Suite("真实 AI 分级对话评测")
struct LiveLearnerConversationEvaluationTests {
    private final class EmptyCredentials: AuthCredentialStore, @unchecked Sendable {
        func load() throws -> StoredAuthCredential? { nil }
        func remove() throws {}
        func save(_ credential: StoredAuthCredential) throws {}
    }

    private struct Scenario {
        let id: String
        let learner: LearnerContext
        let firstMessage: String
        let followUp: String
        let relevanceTerms: [String]
    }

    @Test("生产网关在四种水平与目标下保持角色、分级和话题有效性")
    func evaluatesProductionConversationProfiles() async throws {
        guard ProcessInfo.processInfo.environment["RUN_LIVE_AI_EVAL"] == "1" else { return }

        let backend = BackendClient(
            configuration: .live,
            credentialStore: EmptyCredentials()
        )
        let llm = BackendLLMProvider(
            backend: backend,
            guestID: "codex-live-learner-eval-v1"
        )
        let card = CharacterCard(
            name: "Oliver Bennett",
            age: 24,
            gender: .male,
            nationality: "British",
            regionID: "london",
            occupation: "bookseller",
            hobbies: ["football", "indie music", "walking around London"],
            appearance: "messy brown hair and a green jacket",
            personality: "dry humour, curious, warm underneath",
            speechStyle: "casual British English; says mate occasionally",
            background: "grew up in Kent and now works near Covent Garden"
        )

        let scenarioFilter = ProcessInfo.processInfo.environment["LIVE_AI_EVAL_SCENARIO"]
        for scenario in scenarios where scenarioFilter == nil || scenario.id == scenarioFilter {
            let firstHistory = [
                message(role: .user, text: scenario.firstMessage, order: 0),
            ]
            let firstReply = try await llm.complete(
                PromptBuilder.roleplayRequest(
                    card: card,
                    learner: scenario.learner,
                    history: firstHistory
                )
            )
            let secondHistory = [
                firstHistory[0],
                message(role: .assistant, text: firstReply, order: 1),
                message(role: .user, text: scenario.followUp, order: 2),
            ]
            let secondReply = try await llm.complete(
                PromptBuilder.roleplayRequest(
                    card: card,
                    learner: scenario.learner,
                    history: secondHistory
                )
            )

            evaluate(firstReply, scenario: scenario, turn: 1)
            evaluate(secondReply, scenario: scenario, turn: 2)
            let combined = "\(firstReply) \(secondReply)".lowercased()
            #expect(
                scenario.relevanceTerms.contains { combined.contains($0) },
                "回复没有体现 \(scenario.id) 的目标语境"
            )
            print("LIVE_AI_EVAL|\(scenario.id)|turn1|\(flatten(firstReply))")
            print("LIVE_AI_EVAL|\(scenario.id)|turn2|\(flatten(secondReply))")
        }
    }

    private var scenarios: [Scenario] {
        [
            Scenario(
                id: "beginner_travel",
                learner: LearnerContext(
                    nickname: "Mia",
                    difficulty: .primary3,
                    goal: .travel,
                    studyStage: .primary
                ),
                firstMessage: "I want go London. What I do at airport?",
                followUp: "Plane. I have one bag.",
                relevanceTerms: ["airport", "plane", "bag", "passport", "ticket"]
            ),
            Scenario(
                id: "senior_exam",
                learner: LearnerContext(
                    nickname: "Leo",
                    difficulty: .senior2,
                    goal: .exam,
                    studyStage: .seniorHigh
                ),
                firstMessage: "I think social media has good and bad sides. How can I express this in an essay?",
                followUp: "It connects friends, but it can waste our time.",
                relevanceTerms: ["essay", "however", "although", "connect", "time"]
            ),
            Scenario(
                id: "university_study_abroad",
                learner: LearnerContext(
                    nickname: "Yuki",
                    difficulty: .undergraduate,
                    goal: .studyAbroad,
                    studyStage: .university
                ),
                firstMessage: "I'm nervous about speaking up in seminars. What would you do?",
                followUp: "I usually have an idea, but I worry that my English will sound awkward.",
                relevanceTerms: ["seminar", "speak", "idea", "question", "awkward"]
            ),
            Scenario(
                id: "advanced_culture",
                learner: LearnerContext(
                    nickname: "Lin",
                    difficulty: .advanced,
                    goal: .culture,
                    studyStage: .working
                ),
                firstMessage: "Can politeness sometimes prevent honest cross-cultural conversations?",
                followUp: "I notice people often agree publicly but signal disagreement indirectly.",
                relevanceTerms: ["polite", "honest", "disagree", "indirect", "culture"]
            ),
        ]
    }

    private func evaluate(
        _ rawReply: String,
        scenario: Scenario,
        turn: Int
    ) {
        let messages = RoleplayReplyFormatter.messages(from: rawReply)
        let flattened = flatten(rawReply)
        let lowercase = flattened.lowercased()

        #expect((1...3).contains(messages.count), "\(scenario.id) 第 \(turn) 轮气泡数量异常")
        #expect(!flattened.isEmpty)
        #expect(!containsCJK(flattened), "\(scenario.id) 第 \(turn) 轮混入中文")
        #expect(!lowercase.contains("as an ai"))
        #expect(!lowercase.contains("language model"))
        #expect(flattened.count <= 500, "\(scenario.id) 第 \(turn) 轮过长")
        #expect(
            messages.allSatisfy { wordCount($0) <= RoleplayReplyFormatter.maximumWordsPerMessage },
            "\(scenario.id) 第 \(turn) 轮存在过长气泡：\(messages)"
        )

        if [.primary1, .primary2, .primary3].contains(scenario.learner.difficulty) {
            let longestMessage = messages
                .map { wordCount($0) }
                .max() ?? 0
            #expect(longestMessage <= 8, "初学者单条消息过长：\(longestMessage) 词")
            #expect(flattened.contains("?"), "初学者回复缺少容易接续的问题")
        }
    }

    private func message(
        role: MessageRole,
        text: String,
        order: Int
    ) -> MessageDTO {
        MessageDTO(
            id: UUID(),
            role: role,
            kind: .text,
            text: text,
            orderIndex: order
        )
    }

    private func flatten(_ value: String) -> String {
        value
            .split(whereSeparator: \.isNewline)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func containsCJK(_ value: String) -> Bool {
        value.unicodeScalars.contains {
            (0x3400...0x9FFF).contains($0.value)
        }
    }

    private func wordCount(_ value: String) -> Int {
        value.split { !$0.isLetter && $0 != "'" }.count
    }
}
