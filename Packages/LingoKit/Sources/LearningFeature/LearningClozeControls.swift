import BackendKit
import DesignSystem
import SwiftUI

/// 原句内选择空位、共享词库填入；保留整句阅读，不拆成若干单选题。
struct LearningClozeControls: View {
    let question: LearningQuestion
    @Bindable var model: LearningChallengeModel
    let tint: Color

    private struct Piece: Identifiable {
        let id: Int
        let prefix: String
        let slot: String?
        let suffix: String
    }

    private func pieces(_ line: String) -> [Piece] {
        guard let regex = try? NSRegularExpression(pattern: #"([^\s{}]*)\{([a-z][a-z0-9_.-]{0,119})\}([^\s{}]*)|([^\s{}]+)"#) else { return [] }
        let text = line as NSString
        return regex.matches(in: line, range: NSRange(location: 0, length: text.length)).enumerated().map { index, match in
            func part(_ group: Int) -> String {
                let range = match.range(at: group)
                return range.location == NSNotFound ? "" : text.substring(with: range)
            }
            return Piece(id: index, prefix: part(2).isEmpty ? part(4) : part(1), slot: part(2).isEmpty ? nil : part(2), suffix: part(3))
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            ForEach(Array((question.passage ?? "").components(separatedBy: "\n").enumerated()), id: \.offset) { _, line in
                LearningFlowLayout(spacing: 6) {
                    ForEach(pieces(line)) { piece in
                        if let slot = piece.slot {
                            HStack(spacing: 0) {
                                if !piece.prefix.isEmpty { Text(piece.prefix) }
                                slotButton(slot)
                                if !piece.suffix.isEmpty { Text(piece.suffix) }
                            }
                        } else {
                            Text(piece.prefix).fixedSize(horizontal: false, vertical: true).frame(minHeight: 44)
                        }
                    }
                }
            }.font(.title3)
            Divider()
            HStack {
                Text("\(model.fills.count) / \(question.clozeSlotIDs.count)")
                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    .accessibilityLabel("已填 \(model.fills.count) 空，共 \(question.clozeSlotIDs.count) 空")
                Spacer()
                Button {
                    if let id = model.activeSlot { model.clearSlot(id) }
                } label: {
                    Image(systemName: "arrow.uturn.backward").frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }.buttonStyle(LearningPressStyle()).foregroundStyle(tint)
                    .disabled(!model.fills.contains { $0.slotId == model.activeSlot })
                    .accessibilityLabel("清除当前空位")
                    .accessibilityIdentifier("learning.cloze.undo")
            }
            LearningFlowLayout(spacing: 10) {
                ForEach(question.tokens ?? []) { token in
                    let used = model.fills.contains { $0.tokenId == token.id }
                    Button { model.fillSlot(with: token.id) } label: {
                        Text(token.text).font(.body.weight(.medium))
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, 16).padding(.vertical, 10).frame(minHeight: 44)
                            .background(Color.dsSurface, in: RoundedRectangle(cornerRadius: 8))
                            .overlay { RoundedRectangle(cornerRadius: 8).strokeBorder(Color.primary.opacity(0.14)) }
                    }.buttonStyle(LearningPressStyle()).foregroundStyle(.primary)
                        .disabled(used).opacity(used ? 0.25 : 1)
                        .accessibilityLabel(token.text)
                        .accessibilityHint(used ? "已填入句子" : "填入当前空位")
                        .accessibilityIdentifier("learning.cloze.token.\(token.id)")
                }
            }
        }.accessibilityElement(children: .contain)
            .accessibilityIdentifier("learning.cloze")
    }

    private func slotButton(_ id: String) -> some View {
        let number = (question.clozeSlotIDs.firstIndex(of: id) ?? 0) + 1
        let fill = model.fills.first { $0.slotId == id }
        let word = question.tokens?.first { $0.id == fill?.tokenId }?.text
        let selected = model.activeSlot == id
        let result = model.feedback?.slotResults?.first { $0.slotId == id }
        let color = result.map { $0.correct ? tint : Color.red } ?? tint
        return Button { model.selectSlot(id) } label: {
            HStack(spacing: 5) {
                Text(word ?? "\(number)").fontWeight(word == nil ? .regular : .semibold)
                if let result {
                    Image(systemName: result.correct ? "checkmark" : "xmark").font(.caption.bold())
                }
            }.foregroundStyle(word == nil && !selected ? Color.secondary : color)
                .padding(.horizontal, 10).frame(minWidth: 56, minHeight: 44)
                .background(selected && model.feedback == nil ? tint.opacity(0.08) : .clear)
                .overlay(alignment: .bottom) { Rectangle().fill(color.opacity(selected || result != nil ? 1 : 0.35)).frame(height: selected ? 2 : 1) }
                .contentShape(Rectangle())
        }.buttonStyle(LearningPressStyle())
            .accessibilityLabel("第 \(number) 空")
            .accessibilityValue((word ?? "未填写") + (result.map { $0.correct ? "，正确" : "，需要修改" } ?? ""))
            .accessibilityAddTraits(selected ? [.isSelected] : [])
            .accessibilityAction(named: "清除此空") { model.clearSlot(id) }
            .accessibilityIdentifier("learning.cloze.slot.\(id)")
    }
}
