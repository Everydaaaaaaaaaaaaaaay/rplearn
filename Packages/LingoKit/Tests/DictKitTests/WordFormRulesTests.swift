import Testing
@testable import DictKit

@Suite("WordFormRules 规则回退")
struct WordFormRulesTests {
    @Test("复数还原")
    func plurals() {
        #expect(WordFormRules.candidates(for: "cats").contains("cat"))
        #expect(WordFormRules.candidates(for: "boxes").contains("box"))
        #expect(WordFormRules.candidates(for: "cities").contains("city"))
        // ss 结尾不误切
        #expect(!WordFormRules.candidates(for: "class").contains("clas"))
    }

    @Test("过去式还原：双写与补 e")
    func pastTense() {
        #expect(WordFormRules.candidates(for: "stopped").contains("stop"))
        #expect(WordFormRules.candidates(for: "hoped").contains("hope"))
        #expect(WordFormRules.candidates(for: "played").contains("play"))
        #expect(WordFormRules.candidates(for: "studied").contains("study"))
    }

    @Test("进行时还原：双写与补 e")
    func ingForms() {
        #expect(WordFormRules.candidates(for: "running").contains("run"))
        #expect(WordFormRules.candidates(for: "making").contains("make"))
        #expect(WordFormRules.candidates(for: "looking").contains("look"))
    }

    @Test("比较级/最高级还原")
    func comparatives() {
        #expect(WordFormRules.candidates(for: "bigger").contains("big"))
        #expect(WordFormRules.candidates(for: "nicer").contains("nice"))
        #expect(WordFormRules.candidates(for: "happiest").contains("happy"))
        #expect(WordFormRules.candidates(for: "faster").contains("fast"))
    }

    @Test("所有格还原")
    func possessives() {
        #expect(WordFormRules.candidates(for: "dog's").contains("dog"))
        #expect(WordFormRules.candidates(for: "teachers'").contains("teachers"))
    }

    @Test("大小写与去重")
    func normalization() {
        let candidates = WordFormRules.candidates(for: "Running")
        #expect(candidates.contains("run"))
        #expect(Set(candidates).count == candidates.count)
    }
}
