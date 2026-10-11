import BackendKit
import SwiftUI

/// 先选当前声音再点图片；配对和播放互不代替，不自动补全剩余项。
struct LearningAudioMatchingControls: View {
    let question: LearningQuestion
    let attemptID: UUID
    let audio: LearningAudioOptionsModel
    let pictures: LearningImageModel
    @Binding var pairs: [LearningAnswer.Pair]
    let feedback: LearningGrade?
    let tint: Color
    @State private var focus: String?
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var current: String? { focus ?? question.audioOptions?.first?.id }
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            LearningAudioChoiceControls(question: question, attemptID: attemptID, audio: audio,
                selection: Binding(get: { current }, set: { focus = $0 }), tint: tint,
                selectionDisabled: false, selectionPrefix: "为声音配图")
            HStack {
                Text("\(pairs.count) / \(question.audioOptions?.count ?? 0)").monospacedDigit()
                    .accessibilityLabel("已配对 \(pairs.count) 项")
                Spacer()
                if let current, pairs.contains(where: { $0.left == current }), feedback == nil {
                    Button { pairs.removeAll { $0.left == current } } label: {
                        Image(systemName: "arrow.uturn.backward").font(.system(size: 20)).frame(width: 44, height: 44)
                    }.accessibilityLabel("撤销当前配对").accessibilityIdentifier("learning.sound.match.undo")
                }
            }.font(.caption).foregroundStyle(.secondary)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: dynamicTypeSize.isAccessibilitySize ? 1 : 2), spacing: 12) {
                ForEach(question.right ?? []) { option in
                    imageOption(option)
                }
            }
        }
    }
    private func imageOption(_ option: LearningOption) -> some View {
        let pair = pairs.first { $0.right == option.id }
        let number = pair.flatMap { p in question.audioOptions?.firstIndex(where: { $0.id == p.left }) }.map { $0 + 1 }
        let result = pair.flatMap { p in feedback?.pairResults?.first { $0.left == p.left } }
        let selected = pair?.left == current
        return Button {
            guard let current else { return }
            pairs.removeAll { $0.left == current || $0.right == option.id }
            pairs.append(.init(left: current, right: option.id))
        } label: {
            VStack(spacing: 8) {
                if let assetID = option.imageAssetId, let image = pictures.images[assetID] {
                    Image(uiImage: image).resizable().scaledToFit().frame(height: dynamicTypeSize.isAccessibilitySize ? 180 : 120)
                } else { ProgressView().frame(height: 120) }
                if let caption = option.caption { Text(caption).font(.body.weight(.medium)).foregroundStyle(.primary).fixedSize(horizontal: false, vertical: true) }
                HStack(spacing: 6) {
                    if let number {
                        Text("\(number)").font(.body.monospacedDigit().weight(.semibold))
                        Image(systemName: result.map { $0.correct ? "checkmark" : "xmark" } ?? "link").font(.system(size: 14, weight: .semibold))
                    } else { Image(systemName: "plus").font(.system(size: 16)) }
                }.frame(minHeight: 28).foregroundStyle(result.map { $0.correct ? Color.green : Color.red } ?? tint)
            }.frame(maxWidth: .infinity).padding(12)
                .background(selected ? tint.opacity(0.08) : Color.clear)
                .overlay(Rectangle().strokeBorder(selected ? tint : Color.secondary.opacity(0.25), lineWidth: selected ? 2 : 1))
                .contentShape(Rectangle())
        }.buttonStyle(.plain).disabled(feedback != nil)
            .accessibilityLabel([option.text, option.caption].compactMap { $0 }.joined(separator: "，"))
            .accessibilityValue((number.map { "已与声音 \($0) 配对" } ?? "未配对") + (result.map { $0.correct ? "，配对正确" : "，需要调整" } ?? ""))
            .accessibilityAddTraits(selected ? .isSelected : [])
            .accessibilityIdentifier("learning.sound.image.\(option.id)")
    }
}
