import Testing
@testable import DomainKit

@Suite("角色回复分条")
struct RoleplayReplyFormatterTests {
    @Test("空段落会变成独立短消息且不保留异常留白")
    func removesBlankParagraphs() {
        let raw = """
        Mate, nobody says "sir" in London unless they're taking the mick 😁 Just "hey" works fine with me!


        You watching British period dramas or something? That's where people talk like that
        """

        #expect(
            RoleplayReplyFormatter.messages(from: raw) == [
                "Mate, nobody says \"sir\" in London unless they're taking the mick 😁",
                "Just \"hey\" works fine with me!",
                "You watching British period dramas or something?",
            ]
        )
    }

    @Test("一整段长回复按每条最多两句拆开")
    func splitsLongParagraphBySentences() {
        let raw = "One. Two! Three? Four. Five"

        #expect(
            RoleplayReplyFormatter.messages(from: raw) == [
                "One. Two!",
                "Three? Four.",
                "Five",
            ]
        )
    }

    @Test("超量回复最多保留三条且优先保留接续问题")
    func limitsOverflowAndKeepsFollowUpQuestion() {
        let raw = "One. Two. Three. Four. Five. Six. Seven. Eight."

        #expect(
            RoleplayReplyFormatter.messages(from: raw) == [
                "One. Two.",
                "Three. Four.",
                "Five. Six.",
            ]
        )

        let withQuestion = "One fairly long reaction goes right here. Another useful detail follows after that point. Extra detail probably should not survive here. What do you honestly think about all this? Final aside after the question."
        #expect(
            RoleplayReplyFormatter.messages(from: withQuestion) == [
                "One fairly long reaction goes right here.",
                "Another useful detail follows after that point.",
                "What do you honestly think about all this?",
            ]
        )

        let punctuationlessQuestion = "First longer reaction stays here.\nSecond longer detail stays too.\nThis part can go.\nYou settling in alright\nOne final aside."
        #expect(RoleplayReplyFormatter.messages(from: punctuationlessQuestion).last == "You settling in alright")
    }

    @Test("两句只有都很短时才放进同一气泡")
    func packsOnlyBriefSentencePairs() {
        let raw = "Just got in from the shop, mate. Rain is coming down hard outside. You settling in alright? London feels wild at first, but you get used to it."

        #expect(
            RoleplayReplyFormatter.messages(from: raw) == [
                "Just got in from the shop, mate.",
                "Rain is coming down hard outside. You settling in alright?",
                "London feels wild at first, but you get used to it.",
            ]
        )
    }

    @Test("超长单句优先在自然停顿处分开")
    func splitsLongSentenceAtClauseBoundary() {
        let raw = "Rain is absolutely pouring outside, so I am making tea and pretending my book will somehow finish writing itself while I stare at the wall."

        let messages = RoleplayReplyFormatter.messages(from: raw)
        #expect(messages == [
            "Rain is absolutely pouring outside,",
            "so I am making tea and pretending my book will somehow finish writing itself",
            "while I stare at the wall.",
        ])
        #expect(messages.allSatisfy { $0.split(whereSeparator: \.isWhitespace).count <= 16 })
    }

    @Test("Unicode 空行也会被彻底移除")
    func removesUnicodeBlankLines() {
        let raw = "first message\u{2028}\u{2028}\u{2029}second message"

        #expect(
            RoleplayReplyFormatter.messages(from: raw) == [
                "first message",
                "second message",
            ]
        )
    }

    @Test("保留真人式省略句号")
    func preservesMissingFinalPunctuation() {
        #expect(
            RoleplayReplyFormatter.messages(from: "yeah that works for me\nsee you there") == [
                "yeah that works for me",
                "see you there",
            ]
        )
    }

    @Test("流式预览折叠空白并隐藏测验内容")
    func streamingPreviewIsCompact() {
        let raw = "hey there\n\n  how are you  \n<quiz>{\"question\":\"hidden\"}</quiz>"
        #expect(RoleplayReplyFormatter.streamingPreview(from: raw) == "hey there how are you")
    }
}

@Suite("角色真人打字节奏")
struct RoleplayTypingPaceTests {
    private let pace = RoleplayTypingPace.standard

    @Test("文本越长等待越久且始终有上限")
    func scalesWithMessageLength() {
        let short = pace.delay(
            for: "yeah sure",
            messageIndex: 1,
            elapsedSinceTypingBegan: 0,
            variation: 0.5
        )
        let long = pace.delay(
            for: "I just got back from the shop and the rain is absolutely pouring outside",
            messageIndex: 1,
            elapsedSinceTypingBegan: 0,
            variation: 0.5
        )

        #expect(long > short)
        #expect(short >= pace.minimumDelay)
        #expect(long <= pace.maximumDelay)
    }

    @Test("首条消息扣除模型已经显示输入指示的时间")
    func creditsGenerationTimeToFirstMessage() {
        let target = pace.delay(
            for: "you alright",
            messageIndex: 0,
            elapsedSinceTypingBegan: 0,
            variation: 0.5
        )
        let partlyElapsed = pace.delay(
            for: "you alright",
            messageIndex: 0,
            elapsedSinceTypingBegan: target / 2,
            variation: 0.5
        )
        let fullyElapsed = pace.delay(
            for: "you alright",
            messageIndex: 0,
            elapsedSinceTypingBegan: target + 1,
            variation: 0.5
        )

        #expect(partlyElapsed < target)
        #expect(fullyElapsed == 0)
    }

    @Test("后续气泡保留独立输入时间并限制随机范围")
    func subsequentMessagesKeepTheirOwnDelay() {
        let fastVariation = pace.delay(
            for: "see you there",
            messageIndex: 2,
            elapsedSinceTypingBegan: 99,
            variation: -10
        )
        let slowVariation = pace.delay(
            for: "see you there",
            messageIndex: 2,
            elapsedSinceTypingBegan: 99,
            variation: 10
        )

        #expect(fastVariation >= pace.minimumDelay)
        #expect(slowVariation <= pace.maximumDelay)
        #expect(slowVariation > fastVariation)
    }
}
