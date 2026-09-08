@testable import ChatFeature
import Testing

@MainActor
struct ChatProfileWordLookupTests {
    @Test("资料页只把英文词交给现有点词弹窗")
    func filtersNonEnglishProfileTokens() {
        let tokens = ChatProfileWordLookup.tokens(
            for: "quiet, observant，也很 practical。",
            cacheKey: "profile-word-filter-test"
        )

        #expect(tokens.compactMap(\.word) == ["quiet", "observant", "practical"])
        #expect(tokens.map(\.display).joined() == "quiet, observant，也很 practical。")
    }
}
