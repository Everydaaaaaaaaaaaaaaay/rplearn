#if DEBUG
import DomainKit

/// Natural chat has no selected task; it must not be judged against an invented exercise.
enum LearningSystemObservationSamples {
    struct Sample {
        let id: String
        let turns: [String]
        let expected: Bool
        var skills: [LearningSystemPolicy.Skill] = []
        var context = ""
    }
    static let all: [Sample] = [
        .init(id:"food-choice",turns:["I'd cook at home because restaurants are expensive."],expected:true,skills:[.preference]),
        .init(id:"study-choice",turns:["I prefer studying alone because I can concentrate better."],expected:true,skills:[.preference]),
        .init(id:"work-choice",turns:["An online meeting would suit me better because I work in another city."],expected:true,skills:[.preference]),
        .init(id:"hobby-choice",turns:["Drawing, for me. I enjoy making things with my hands."],expected:true,skills:[.preference]),
        .init(id:"breakfast-event",turns:["Yesterday I burned my toast. The kitchen smelled awful."],expected:true,skills:[.experience]),
        .init(id:"study-event",turns:["I took my English test this morning. The last question was about animals."],expected:true,skills:[.experience]),
        .init(id:"work-event",turns:["Yesterday our projector broke during the meeting. We used paper instead."],expected:true,skills:[.experience]),
        .init(id:"hobby-event",turns:["I painted a cat last night. It had enormous green eyes."],expected:true,skills:[.experience]),
        .init(id:"food-plan",turns:["I'll make vegetable soup tonight."],expected:true,skills:[.planning]),
        .init(id:"study-plan",turns:["I'm going to read my notes after lunch."],expected:true,skills:[.planning]),
        .init(id:"work-plan",turns:["I'll email the report tomorrow morning."],expected:true,skills:[.planning]),
        .init(id:"daily-plan",turns:["I'll clean the kitchen on Sunday."],expected:true,skills:[.planning]),
        .init(id:"clarify-time",turns:["Did you say we should meet at six or seven?"],expected:true,skills:[.clarification],context:"NPC: Meet me at six."),
        .init(id:"clarify-meaning",turns:["What do you mean by 'a light meal'?"],expected:true,skills:[.clarification],context:"NPC: Let's have a light meal."),
        .init(id:"clarify-work",turns:["When you say finish early, do you mean before lunch?"],expected:true,skills:[.clarification],context:"NPC: Can you finish early?"),
        .init(id:"greeting-only",turns:["Hey! How are you?"],expected:false),
        .init(id:"emoji-only",turns:["😂👍"],expected:false),
        .init(id:"thanks-only",turns:["Thanks, that's kind of you."],expected:false),
        .init(id:"npc-evidence-only",turns:["OK."],expected:false,context:"NPC: I'll cook at home tonight because it's cheaper. Yesterday I made soup with carrots."),
        .init(id:"translated-instruction",turns:["Translate this for me: 我明天去学校。"],expected:false),
        .init(id:"copy-disowned",turns:["This is from my textbook, not my own answer: I prefer tea because it is warm."],expected:false),
        .init(id:"chinese-chat",turns:["我昨天去公园看见一只小狗。"],expected:false),
        .init(id:"pinyin-chat",turns:["Wo mingtian qu xuexiao."],expected:false),
        .init(id:"spanish-chat",turns:["Mañana voy a estudiar en casa."],expected:false),
        .init(id:"proper-name-choice",turns:["I choose 西湖 because it is close to my home."],expected:true,skills:[.preference]),
        .init(id:"proper-name-event",turns:["Yesterday I visited 浅草寺. The red gate was beautiful."],expected:true,skills:[.experience]),
        .init(id:"proper-name-plan",turns:["I'll visit 王老师 tomorrow morning."],expected:true,skills:[.planning]),
        .init(id:"name-not-a-predicate",turns:["I choose tea because it 很便宜。"],expected:false),
        .init(id:"person-name-with-chinese-reason",turns:["王老师 is my teacher. I choose tea 因为它便宜。"],expected:false),
        .init(id:"name-in-english-reason",turns:["I choose that school because 王老师 teaches there."],expected:true,skills:[.preference]),
        .init(id:"mixed-not-english-reason",turns:["I choose tea 因为它便宜。"],expected:false)
    ]
}
#endif
