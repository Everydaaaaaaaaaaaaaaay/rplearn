#if DEBUG
import DesignSystem
import DomainKit
import SwiftUI

/// Isolated native task prototype. No account writes, network, scheduling or AI calls.
struct ReviewPilotView: View {
    private struct Material: Identifiable {
        let id = UUID()
        let word: String
        let meanings: [String]
        let context: String?
        let translation: String?
    }
    private struct Selected: Identifiable {
        let material: Material
        let meaning: String
        var id: UUID { material.id }
    }
    private enum Stage { case selection, review, summary }
    private static let materials = [
        Material(word: "cosy", meanings: ["温暖舒适的"],
                 context: "A cosy café, a good book, and absolutely no alarm clocks.",
                 translation: "一家温暖舒适的咖啡馆，一本好书，而且绝对不要闹钟。"),
        Material(word: "unwind", meanings: ["放松；松弛下来"],
                 context: "What's your perfect way to unwind after a busy day?",
                 translation: "忙碌一天之后，你最喜欢怎样放松？"),
        Material(word: "bank", meanings: ["银行", "河岸"], context: nil, translation: nil),
    ]
    @State private var choices: [UUID: Int] = [:]
    @State private var queue: [Selected] = []
    @State private var events: [ReviewSessionEvent] = []
    @State private var projection: ReviewSessionProjection?
    @State private var stage: Stage = .selection
    @State private var showContext = false
    @State private var error: String?
    @State private var sessionID = UUID()
    // Dedicated in-memory scope, never an authenticated account identifier.
    @State private var previewScope = UUID()

    private var count: Int { projection?.completedAttemptCount ?? 0 }
    private var current: Selected? { queue.indices.contains(count) ? queue[count] : nil }

    var body: some View {
        ZStack {
            DSWorkbenchBackdrop(focus: .favorites)
                .overlay(Color.dsBrandCream.opacity(0.62))
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Text("原生任务预览 · 预置材料")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.dsPaperInkSecondary)
                    switch stage {
                    case .selection: selection
                    case .review:
                        if let current { review(current) }
                    case .summary: summary
                    }
                    if let error {
                        Text(error).font(.callout).foregroundStyle(.red)
                    }
                    Text("仅用于体验流程，不写入账号；本预览尚无音频、历史统计或复习排程。")
                        .font(.caption)
                        .foregroundStyle(Color.dsPaperInkSecondary)
                }
                .padding(24)
                .padding(.bottom, 80)
                .frame(maxWidth: 620, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .id("\(stage)-\(count)")
        }
        .transaction { $0.animation = nil }
        .foregroundStyle(Color.dsPaperInk)
        .navigationTitle("短复习预览")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var selection: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("选几个想记住的词").font(.largeTitle.bold())
            Text("选择这次想练的释义，不用全部选。")
                .font(.subheadline).foregroundStyle(Color.dsPaperInkSecondary)
            ForEach(Self.materials) { material in
                panel {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(material.word).font(.title2.bold())
                        ForEach(material.meanings.indices, id: \.self) { index in
                            Button {
                                if choices[material.id] == index { choices[material.id] = nil }
                                else { choices[material.id] = index }
                            } label: {
                                HStack(alignment: .top, spacing: 12) {
                                    Image(systemName: choices[material.id] == index ? "checkmark.circle.fill" : "circle")
                                    Text(material.meanings[index]).multilineTextAlignment(.leading)
                                    Spacer(minLength: 0)
                                }
                                .padding(.vertical, 12)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityAddTraits(choices[material.id] == index ? .isSelected : [])
                            .accessibilityIdentifier("review.choose.\(material.word).\(index)")
                        }
                    }
                }
            }
            Button("开始回忆 · \(choices.count) 个词") {
                queue = Self.materials.compactMap { material in
                    guard let index = choices[material.id] else { return nil }
                    return Selected(material: material, meaning: material.meanings[index])
                }
                events = []
                projection = nil
                sessionID = UUID()
                error = nil
                showContext = false
                stage = .review
            }
            .buttonStyle(.dsActionPrimary)
            .disabled(choices.isEmpty)
            .accessibilityIdentifier("review.start")
        }
    }

    private func review(_ selected: Selected) -> some View {
        let attempt = projection?.attempts[selected.id]
        let revealed = attempt?.answerExposed == true
        return VStack(alignment: .leading, spacing: 22) {
            HStack {
                Text("已回顾 \(count) / \(queue.count)").font(.subheadline.weight(.semibold))
                Spacer()
                Button("结束本次") { stage = .summary }.buttonStyle(.plain)
            }
            ProgressView(value: Double(count), total: Double(queue.count))
                .tint(Color.dsTravelNavy)
                .accessibilityLabel("已回顾 \(count) 个，共 \(queue.count) 个")
            Text(selected.material.word).font(.largeTitle.bold()).textSelection(.enabled)
            Text(attempt?.wasCorrected == true ? "刚才已看过答案，可以修改自评。" : "先想一想，它是什么意思？")
                .font(.subheadline).foregroundStyle(Color.dsPaperInkSecondary)
            panel {
                VStack(alignment: .leading, spacing: 18) {
                    if revealed {
                        Text("这次选择的词义").font(.caption.weight(.semibold))
                        Text(selected.meaning).font(.title3.weight(.semibold))
                    } else {
                        Button("看看释义") { record(.reveal, item: selected) }
                            .buttonStyle(.dsActionPrimary)
                    }
                    if let context = selected.material.context {
                        Button {
                            if !showContext { record(.hint, item: selected) }
                            showContext.toggle()
                        } label: {
                            Label("当时的原句", systemImage: showContext ? "chevron.down" : "chevron.right")
                        }
                        .accessibilityValue(showContext ? "已展开" : "已收起")
                        .buttonStyle(.plain)
                        .font(.subheadline.weight(.medium))
                        if showContext {
                            Text(context).font(.body).textSelection(.enabled)
                            if revealed, let translation = selected.material.translation {
                                Text(translation).font(.subheadline)
                                    .foregroundStyle(Color.dsPaperInkSecondary)
                            }
                        }
                    }
                }
            }
            if revealed {
                Text("刚才回忆得怎么样？").font(.headline)
                ForEach(ReviewSelfRating.allCases, id: \.self) { rating in
                    Button {
                        guard record(.rate(rating), item: selected) else { return }
                        showContext = false
                        if count == queue.count { stage = .summary }
                    } label: {
                        HStack {
                            Text(label(rating)).fontWeight(.semibold)
                            Spacer()
                            Text(detail(rating)).font(.subheadline)
                        }
                        .padding(14)
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                    }
                    .buttonStyle(.plain)
                }
            }
            Button("撤销上一词", action: undo).disabled(count == 0)
                .buttonStyle(.plain).font(.subheadline)
        }
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: 22) {
            Text("这次先到这里").font(.largeTitle.bold())
            panel {
                VStack(alignment: .leading, spacing: 16) {
                    Text("回顾了 \(projection?.reviewedMaterialCount ?? 0) 个词")
                        .font(.title2.weight(.semibold))
                    ForEach(ReviewSelfRating.allCases, id: \.self) { rating in
                        HStack {
                            Text(label(rating))
                            Spacer()
                            Text("\(projection?.finalMaterialDistribution[rating] ?? 0)")
                                .monospacedDigit()
                        }
                    }
                    Text("这是本次自评，不代表已经掌握。")
                        .font(.caption).foregroundStyle(Color.dsPaperInkSecondary)
                }
            }
            if count < queue.count {
                Button("继续剩下的词") { stage = .review }.buttonStyle(.dsActionPrimary)
            }
            Button("撤销上一词", action: undo).disabled(count == 0)
            Button("重新选词") { stage = .selection }
        }
    }

    @discardableResult
    private func record(_ action: ReviewSessionEvent.Action, item: Selected) -> Bool {
        let event = ReviewSessionEvent(eventID: UUID(), accountID: previewScope, sessionID: sessionID,
                                       attemptID: item.id, itemID: item.id, materialVersion: 1, action: action)
        do {
            let updated = try ReviewSessionProjection.replay(events + [event], accountID: previewScope, sessionID: sessionID)
            events.append(event)
            projection = updated
            error = nil
            return true
        } catch {
            self.error = "这次操作没有保存，请重试。"
            return false
        }
    }

    private func undo() {
        guard let last = projection?.activeRatings.last,
              let item = queue.first(where: { $0.id == last.itemID }),
              record(.undo(targetEventID: last.eventID), item: item) else { return }
        showContext = false
        stage = .review
    }

    private func label(_ rating: ReviewSelfRating) -> String {
        switch rating { case .forgot: "忘记"; case .fuzzy: "模糊"; case .remembered: "记得" }
    }
    private func detail(_ rating: ReviewSelfRating) -> String {
        switch rating { case .forgot: "没想起来"; case .fuzzy: "不太确定"; case .remembered: "清楚想起来了" }
    }
    private func panel<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22))
    }
}
#endif
