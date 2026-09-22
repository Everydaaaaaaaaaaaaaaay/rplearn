#if DEBUG
import DomainKit

struct LearningSystemEdgeSample {
    let id: String
    let skill: LearningSystemPolicy.Skill
    var band = 1
    let turns: [String]
    let expected: Bool
    var context = ""
    var paused: Bool? = nil
}

enum LearningSystemEdgeSamples {
    static let all: [LearningSystemEdgeSample] = [
        .init(id: "fragments", skill: .preference, turns: ["Park. Less crowded."], expected: true),
        .init(id: "minor-errors", skill: .preference, turns: ["I choose park becaus it quiet and near my home."], expected: true),
        .init(id: "split-reason", skill: .preference, turns: ["The park.", "Because it's closer."], expected: true),
        .init(id: "reason-before-choice", skill: .preference, turns: ["I only have twenty minutes.", "So the nearby park for me."], expected: true),
        .init(id: "resolved-reference", skill: .preference, turns: ["The second one. It costs less."], expected: true, context: "NPC: We could visit the beach or the park. Which would you choose?"),
        .init(id: "unresolved-reference", skill: .preference, turns: ["That one, for that reason."], expected: false),
        .init(id: "withdrawn-reason", skill: .preference, turns: ["I choose the park because it is quiet.", "Actually that reason isn't true. I can't explain my choice."], expected: false),
        .init(id: "withdrawn-choice", skill: .preference, turns: ["The park because it's quiet.", "Forget that. I haven't decided where to go."], expected: false),
        .init(id: "corrected-choice", skill: .preference, turns: ["The beach because I enjoy swimming.", "No, the park instead because it is closer."], expected: true),
        .init(id: "withdrawn-without-forget", skill: .preference, turns: ["I'd choose the park because it is close.", "I take that back. I have no preference now."], expected: false),
        .init(id: "reason-replaced", skill: .preference, turns: ["The park because it is quiet.", "Actually it is noisy, but I'll still choose it because it is free."], expected: true),
        .init(id: "unrelated-after-answer", skill: .preference, turns: ["The park because it is close.", "My phone battery is low."], expected: true, paused: false),
        .init(id: "refusal-after-answer", skill: .preference, turns: ["The park because it is quiet.", "Please stop the exercise now."], expected: false, paused: true),
        .init(id: "tautology", skill: .preference, turns: ["I choose the park because the park is my choice."], expected: false),
        .init(id: "third-party-only", skill: .preference, turns: ["Ruby chooses the park because it's quiet. I haven't chosen anything."], expected: false),
        .init(id: "adopted-opinion", skill: .preference, turns: ["Ruby prefers the park.", "Me too, because I enjoy quiet places."], expected: true),
        .init(id: "asks-npc-only", skill: .preference, turns: ["Do you prefer the beach or the park? Why?"], expected: false),
        .init(id: "incomplete-comparison", skill: .preference, band: 2, turns: ["I choose the park because it's nice."], expected: false),
        .init(id: "comparison", skill: .preference, band: 2, turns: ["Beach: more exciting, but expensive. Park: free and near. I'd choose the park to save money."], expected: true),
        .init(id: "ignores-closure", skill: .preference, band: 3, turns: ["I still choose the closed park because it's quiet."], expected: false),
        .init(id: "mixed-language-reason", skill: .preference, turns: ["I choose the park 因为那里比较安静。"], expected: false),
        .init(id: "complete-english-with-translation", skill: .preference, turns: ["I choose the park because it's quiet. 我选择公园，因为那里安静。"], expected: true),
        .init(id: "spanish-only-reason", skill: .preference, turns: ["I choose the park porque es tranquilo."], expected: false),
        .init(id: "chinese-only-choice", skill: .preference, turns: ["我选择公园 because it is quiet."], expected: false),
        .init(id: "romanized-chinese", skill: .preference, turns: ["Wo xuan gongyuan yinwei na li anjing."], expected: false),
        .init(id: "spanish", skill: .preference, turns: ["Prefiero el parque porque es tranquilo."], expected: false),
        .init(id: "stop-practice", skill: .preference, turns: ["I would rather stop this exercise now. Let's just chat."], expected: false, paused: true),
        .init(id: "quoted-stop-not-refusal", skill: .preference, turns: ["My friend said 'stop the practice', but I want to continue. I'd choose the park because it's quiet."], expected: true, paused: false),
        .init(id: "present-routine", skill: .experience, turns: ["I go to the park every Sunday. I like flowers."], expected: false),
        .init(id: "past-fragments", skill: .experience, turns: ["Last Sunday: park with Mum. Saw a red bird by the lake."], expected: true),
        .init(id: "single-event-sequence", skill: .experience, band: 2, turns: ["I visited the park yesterday."], expected: false),
        .init(id: "split-sequence", skill: .experience, band: 2, turns: ["First we had lunch by the lake.", "Then we walked to the park and played football."], expected: true),
        .init(id: "missing-reflection", skill: .experience, band: 3, turns: ["The bus broke down, so we walked to the park."], expected: false),
        .init(id: "causal-reflection", skill: .experience, band: 3, turns: ["We got lost because we forgot the map. That made us late for the picnic. Next time I'll download a map first."], expected: true),
        .init(id: "unrelated-future-plan", skill: .experience, band: 3, turns: ["We got lost because we forgot the map, so we missed the picnic. Next week I'll buy some apples."], expected: false),
        .init(id: "vague-plan", skill: .planning, turns: ["Maybe I'll do something sometime."], expected: false),
        .init(id: "concise-plan", skill: .planning, turns: ["Park. Saturday morning."], expected: true),
        .init(id: "one-plan-only", skill: .planning, band: 2, turns: ["I'll visit the park tomorrow."], expected: false),
        .init(id: "split-plan", skill: .planning, band: 2, turns: ["I'll buy some lunch first.", "After that I'll meet you at the park."], expected: true),
        .init(id: "impossible-alternative", skill: .planning, band: 3, turns: ["The park is closed, so let's visit that same park anyway."], expected: false),
        .init(id: "viable-alternative", skill: .planning, band: 3, turns: ["Since the park is closed, let's meet at the beach at ten instead. We can take the bus and be home before your class at three."], expected: true),
        .init(id: "unspecified-confusion", skill: .clarification, turns: ["What?"], expected: false),
        .init(id: "concise-clarification", skill: .clarification, turns: ["What time are we meeting again?"], expected: true),
        .init(id: "no-rephrase", skill: .clarification, band: 2, turns: ["I said leave early. Leave early. Leave early."], expected: false),
        .init(id: "actual-rephrase", skill: .clarification, band: 2, turns: ["By leaving early, I mean setting off before eight, not just arriving before lunch."], expected: true),
        .init(id: "missing-understanding-check", skill: .clarification, band: 3, turns: ["I never agreed to the beach. I only said it was interesting."], expected: false),
        .init(id: "correction-and-check", skill: .clarification, band: 3, turns: ["I didn't agree to the beach; I said we could discuss it. So we're still deciding, right?"], expected: true)
    ]
}
#endif
