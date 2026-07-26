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
