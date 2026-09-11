/// 规则回退：lemma 表未命中时，按英语构词规则生成候选原型（纯函数，可单测）。
/// 生成顺序即尝试顺序，命中即止。
public enum WordFormRules {
    public static func candidates(for word: String) -> [String] {
        let w = word.lowercased()
        var results: [String] = []

        func add(_ candidate: String) {
            guard candidate.count >= 2, candidate != w, !results.contains(candidate) else { return }
            results.append(candidate)
        }

        // 所有格：dog's / teachers'
        if w.hasSuffix("'s") { add(String(w.dropLast(2))) }
        if w.hasSuffix("'") { add(String(w.dropLast())) }

        // 复数/三单：ies→y、es、s
        if w.hasSuffix("ies") {
            add(String(w.dropLast())) // toasties → toastie, cookies → cookie
            add(String(w.dropLast(3)) + "y")
        }
        if w.hasSuffix("es") { add(String(w.dropLast(2))) }
        if w.hasSuffix("s"), !w.hasSuffix("ss") { add(String(w.dropLast())) }

        // 过去式：ied→y、ed（含双写还原与补 e）
        if w.hasSuffix("ied") { add(String(w.dropLast(3)) + "y") }
        if w.hasSuffix("ed") {
            let stem = String(w.dropLast(2))
            add(stem)
            add(stem + "e") // hoped → hope
            if isDoubledConsonantEnding(stem) { add(String(stem.dropLast())) } // stopped → stop
        }

        // 进行时：ing（含补 e 与双写还原）
        if w.hasSuffix("ing") {
            let stem = String(w.dropLast(3))
            add(stem)
            add(stem + "e") // making → make
            if isDoubledConsonantEnding(stem) { add(String(stem.dropLast())) } // running → run
        }

        // 比较级/最高级：ier/iest→y、er/est（含补 e 与双写还原）
        if w.hasSuffix("iest") { add(String(w.dropLast(4)) + "y") }
        if w.hasSuffix("ier") { add(String(w.dropLast(3)) + "y") }
        if w.hasSuffix("est") {
            let stem = String(w.dropLast(3))
            add(stem)
            add(stem + "e") // nicest → nice
            if isDoubledConsonantEnding(stem) { add(String(stem.dropLast())) } // biggest → big
        }
        if w.hasSuffix("er") {
            let stem = String(w.dropLast(2))
            add(stem)
            add(stem + "e") // nicer → nice
            if isDoubledConsonantEnding(stem) { add(String(stem.dropLast())) } // bigger → big
        }

        return results
    }

    private static func isDoubledConsonantEnding(_ stem: String) -> Bool {
        guard stem.count >= 2 else { return false }
        let chars = Array(stem)
        let last = chars[chars.count - 1]
        let secondLast = chars[chars.count - 2]
        guard last == secondLast else { return false }
        return !"aeiou".contains(last)
    }
}
