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
                "Mate, nobody says \"sir\" in London unless they're taking the mick 😁 Just \"hey\" works fine with me!",
                "You watching British period dramas or something? That's where people talk like that",
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

    @Test("超出三条时仍保持每条最多两句")
    func neverMergesOverflowBackIntoALongBubble() {
        let raw = "One. Two. Three. Four. Five. Six. Seven. Eight."

        #expect(
            RoleplayReplyFormatter.messages(from: raw) == [
                "One. Two.",
                "Three. Four.",
                "Five. Six.",
                "Seven. Eight.",
            ]
        )
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
