import Foundation
import NaturalLanguage
import SwiftUI

/// One representation for article blanks and the corresponding sentence in a review card.
enum PracticePassageText {
    enum Part: Equatable {
        case prose(String)
        case gap(Int)
    }
    static func parts(_ source: String) -> [Part] {
        guard let regex = try? NSRegularExpression(pattern: "____([0-9]+)____") else { return [.prose(source)] }
        let text = source as NSString
        var output: [Part] = []; var cursor = 0
        for match in regex.matches(in: source, range: NSRange(location: 0, length: text.length)) {
            output.append(.prose(text.substring(with: NSRange(location: cursor, length: match.range.location - cursor))))
            if let number = Int(text.substring(with: match.range(at: 1))) { output.append(.gap(number)) }
            cursor = NSMaxRange(match.range)
        }
        output.append(.prose(text.substring(from: cursor)))
        return output
    }
    static func gapLabel(_ number: Int, answer: String) -> String {
        // Nonbreaking spaces keep the period, two spaces and the answer's first word together.
        "\(number).\u{00A0}\u{00A0}" + (answer.isEmpty ? String(repeating: "\u{2007}", count: 4) : answer)
    }
    static func sentence(in source: String, containingGap number: Int) -> String? {
        guard let marker = source.range(of: "____\(number)____") else { return nil }
        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = source
        var found: String?
        tokenizer.enumerateTokens(in: source.startIndex..<source.endIndex) { range, _ in
            if range.overlaps(marker) { found = String(source[range]).trimmingCharacters(in: .whitespacesAndNewlines); return false }
            return true
        }
        return found ?? source.components(separatedBy: "\n\n").first { $0.contains("____\(number)____") }
    }
}

struct PracticeGapUnderline: TextAttribute {
    var isReference = false
}

/// Draw a single rule at the line's baseline: no underscore glyphs or skipped-ink gaps.
struct PracticeGapTextRenderer: TextRenderer {
    func draw(layout: Text.Layout, in context: inout GraphicsContext) {
        for line in layout {
            for run in line {
                context.draw(run)
                if let mark = run[PracticeGapUnderline.self] {
                    let bounds = run.typographicBounds.rect
                    let descent = line.typographicBounds.descent
                    let y = line.typographicBounds.rect.maxY - descent + max(1.5, descent * 0.35)
                    var path = Path()
                    path.move(to: CGPoint(x: bounds.minX, y: y))
                    path.addLine(to: CGPoint(x: bounds.maxX, y: y))
                    context.stroke(path, with: .color(mark.isReference ? PracticePaper.correct : PracticePaper.accent), lineWidth: 1)
                }
            }
        }
    }
}

struct PracticeReviewSentence: View {
    let sentence: String
    let number: Int
    let reference: String

    var body: some View {
        content.font(.body).lineSpacing(5).textRenderer(PracticeGapTextRenderer())
    }
    private var content: Text {
        PracticePassageText.parts(sentence).reduce(Text("")) { text, part in
            switch part {
            case .prose(let value): return text + Text(value)
            case .gap(let index):
                return text + Text(PracticePassageText.gapLabel(index, answer: index == number ? reference : ""))
                    .foregroundColor(index == number ? PracticePaper.correct : .secondary)
                    .customAttribute(PracticeGapUnderline(isReference: index == number))
            }
        }
    }
}
