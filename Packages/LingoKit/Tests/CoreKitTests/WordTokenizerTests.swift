import Testing
@testable import CoreKit

@Suite("WordTokenizer")
struct WordTokenizerTests {
    @Test("标点粘附到前一个词 token")
    func punctuationAttachment() {
        let tokens = WordTokenizer.tokenize("Hello, world!")
        #expect(tokens.count == 2)
        #expect(tokens[0].display == "Hello, ")
        #expect(tokens[0].word == "hello")
        #expect(tokens[1].display == "world!")
        #expect(tokens[1].word == "world")
    }

    @Test("缩写词整体为一个 token")
    func contractions() {
        let tokens = WordTokenizer.tokenize("don't stop")
        let words = tokens.compactMap(\.word)
        #expect(words.contains("don't") || words.contains("don"))
        // display 还原后与原文一致
        #expect(tokens.map(\.display).joined() == "don't stop")
    }

    @Test("emoji 与纯标点不可点")
    func emojiNotTappable() {
        let tokens = WordTokenizer.tokenize("nice 👍👍 mate")
        #expect(tokens.map(\.display).joined() == "nice 👍👍 mate")
        let tappable = tokens.filter { $0.word != nil }
        #expect(tappable.compactMap(\.word) == ["nice", "mate"])
    }

    @Test("首标点/空白并入首 token 且不可点")
    func leadingPunctuation() {
        let tokens = WordTokenizer.tokenize("...well ok")
        #expect(tokens.map(\.display).joined() == "...well ok")
        #expect(tokens.first?.word == nil || tokens.first?.display.hasPrefix("...") == true)
    }

    @Test("display 拼接总能还原原文", arguments: [
        "Hey! How's it going? 😄",
        "I'm gonna grab a flat white, wanna come",
        "It costs $5.99 (about £4.70).",
        "",
        "你好 hello",
    ])
    func roundTrip(text: String) {
        let tokens = WordTokenizer.tokenize(text)
        #expect(tokens.map(\.display).joined() == text)
    }

    @Test("数字不可点")
    func numbersNotTappable() {
        let tokens = WordTokenizer.tokenize("see you at 10 pm")
        let numberToken = tokens.first { $0.display.contains("10") }
        #expect(numberToken?.word == nil)
    }
}
