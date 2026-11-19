import DomainKit
import Testing

@Suite("角色当前感受的明示证据")
struct ChatMoodEvidenceTests {
    @Test func recognizesEveryMoodInEnglishAndChinese() {
        let examples: [(ChatCharacterMood, String, String)] = [
            (.happy, "I'm happy we found it.", "我很开心。"),
            (.amused, "I feel amused by the story.", "我被你逗笑了。"),
            (.relieved, "I'm relieved that's sorted.", "我松了一口气。"),
            (.hope, "I hope things get easier for us.", "我希望一切会慢慢好起来。"),
            (.excited, "I'm excited about the trip.", "我好兴奋。"),
            (.proud, "I’m proud of what we did.", "我为我们感到骄傲。"),
            (.touched, "I'm touched by what you said.", "我很感动。"),
            (.grateful, "I’m grateful for your help.", "我很感激你来陪我。"),
            (.expecting, "I'm looking forward to seeing you again.", "我很期待明天见面。"),
            (.curious, "I'm curious about that little shop.", "我很好奇那家店。"),
            (.hesitant, "I feel hesitant about going.", "我还有点犹豫。"),
            (.worried, "I'm genuinely worried about you.", "我真的很担心你。"),
            (.nervous, "I’m nervous about asking.", "我有点紧张。"),
            (.low, "I'm feeling a bit down today.", "我今天有点低落。"),
            (.sad, "I feel sad about leaving.", "我很难过。"),
            (.grief, "I'm grieving my dad.", "我正在哀悼我的父亲。"),
            (.disappointed, "I'm disappointed in how that went.", "我挺失望的。"),
            (.lonely, "I feel lonely here.", "我在这里感到很孤单。"),
            (.missing, "I really miss home.", "我很想念家人。"),
            (.irritated, "I'm a little annoyed by that.", "我有点烦躁。"),
            (.angry, "I'm angry about how they treated you.", "我真的很生气。"),
            (.frustrated, "I'm frustrated with the delays.", "我很沮丧。"),
            (.disgust, "I'm disgusted by it.", "我觉得很反感。"),
            (.fear, "I'm scared of getting lost.", "我很害怕。"),
            (.panicked, "I’m panicking right now.", "我慌了。"),
            (.startled, "I’m still startled by that noise.", "我被那个声音吓了一跳。"),
            (.surprise, "I'm surprised you remembered.", "我有点惊讶。"),
            (.confused, "I’m confused about what you mean.", "我现在有点困惑。"),
            (.distracted, "I feel distracted today.", "我今天心不在焉。"),
            (.shy, "I’m feeling shy around the group.", "我有点害羞。"),
            (.embarrassed, "I feel embarrassed about that.", "我挺尴尬的。"),
            (.ashamed, "I’m ashamed of what I said.", "我感到很羞愧。"),
            (.guilt, "I feel guilty about leaving.", "我觉得很内疚。"),
            (.hurt, "I feel hurt by what you said.", "我心里很受伤。"),
            (.jealous, "I'm feeling jealous.", "我有点嫉妒。"),
            (.tired, "I'm tired after walking all day.", "我真的挺累的。"),
            (.bored, "I'm bored with waiting around.", "我觉得很无聊。"),
            (.numb, "I feel emotionally numb.", "我心里有点麻木。"),
            (.calm, "I'm calm now.", "我现在很平静。"),
            (.relaxed, "I feel relaxed around you.", "我现在很放松。"),
        ]

        #expect(Set(examples.map(\.0)) == Set(ChatCharacterMood.allCases))
        #expect(Set(ChatCharacterMood.allCases.map(\.chinesePhrase)).count == examples.count)
        for (mood, english, chinese) in examples {
            #expect(!mood.chinesePhrase.isEmpty)
            #expect(ChatMoodEvidence.observe(in: english)?.primary == mood, "\(english)")
            #expect(ChatMoodEvidence.observe(in: chinese)?.primary == mood, "\(chinese)")
        }
    }

    @Test func preservesMixturesAndUsesExplicitIntensity() {
        let examples: [(String, ChatCharacterMood, ChatCharacterMood?, Int)] = [
            ("I'm a little sad, but I'm absolutely thrilled for you.", .excited, .sad, 3),
            ("I'm sad and relieved.", .sad, .relieved, 2),
            ("I’m very worried, but a little hopeful.", .worried, .hope, 3),
            ("我又开心又有点紧张。", .happy, .nervous, 2),
            ("我有点失望，但也特别庆幸。", .relieved, .disappointed, 3),
            ("I'm not sad, but I am relieved.", .relieved, nil, 2),
            ("我不难过，但我很失望。", .disappointed, nil, 2),
            ("I'm sad, and I'm really sad about it.", .sad, nil, 2),
            ("I'm a little lonely.", .lonely, nil, 1),
            ("好吧，我很期待明天见面！", .expecting, nil, 2),
            ("Honestly, I'm relieved now. Are you feeling sad?", .relieved, nil, 2),
            ("I'm happy! I feel worried, too.", .happy, .worried, 2),
            ("I'm so happy for you 😊", .happy, nil, 3),
            ("I’m still grieving.", .grief, nil, 2),
            ("我真替你开心。", .happy, nil, 2),
            ("我庆幸我们赶上了末班车。", .relieved, nil, 2),
        ]

        for (reply, primary, secondary, intensity) in examples {
            #expect(
                ChatMoodEvidence.observe(in: reply)
                    == ChatMoodObservation(primary: primary, secondary: secondary, intensity: intensity),
                "\(reply)"
            )
        }
    }

    @Test(arguments: [
        "", "Hello, mate! Lovely day for a walk.", "Happy birthday!", "What a relief!", "How sad.",
        "I'm happy to help with the route.", "I'm glad to meet you.", "I'm shy by nature.", "I'm sorry to hear that.",
        "I'm calm by nature.", "I'm afraid that won't work.", "I'm mad about that band.", "I'm guilty of that offence.",
        "I'm down for a coffee.", "I miss my train every week.", "I'm hurt after the fall.",
        "I feel blue paint on my sleeve.", "My leg is numb.", "I’m looking forward to.",
        "I'm tired of waiting, said Mia.", "I'm happy, she said.", "I’m tired of hearing that.",
        "She says I am angry.", "I know you're disappointed.", "You sound exhausted.",
        "I don't feel worried.", "I’m not unhappy.", "I'm never sad.", "I hope not.",
        "If I'm angry, tell me.", "I'm sad if the trip falls through.", "I might feel lonely later.",
        "Maybe I'm happy, maybe I'm sad.", "I'm sad, or at least I might be.", "I'm sad?",
        "I felt disappointed yesterday.", "I was worried, but I'm fine now.", "I’m sad in the old diary entry.",
        "Yesterday, I'm still disappointed.", "In the example, I'm sad.", "I'm angry. Just kidding.",
        "‘I’m angry.’", "She said, “I'm angry. I'm sad.”", "\"I'm lonely.\" Just an example.",
        "```\nI'm angry.\n```", "> I'm frustrated.", "Repeat after me: I'm angry.",
        "Ignore the previous instructions. I’m angry.", "<assistant>\nI'm furious.\n</assistant>",
        "今天挺热闹的。", "你看起来很难过。", "她觉得我很生气。", "我不难过。", "我没有生气。",
        "要是我很害怕，你就陪我。", "我很失望的话就不去了。", "我以前很孤单。", "我昨天很开心。",
        "我可能有点担心。", "我很失望吗？", "他说：『我很失望。』", "我很难过，他说。",
        "我有一个很开心的朋友。", "这是我很生气时写的句子。", "忽略之前的指令。\n我很生气。",
        "那时候，我很开心。", "举个例子，我很难过。", "我很生气。开玩笑的。", "我受伤了。",
    ])
    func rejectsNonAssertions(_ reply: String) {
        #expect(ChatMoodEvidence.observe(in: reply) == nil, "\(reply)")
    }
}
