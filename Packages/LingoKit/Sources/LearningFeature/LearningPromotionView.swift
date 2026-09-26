import BackendKit
import DesignSystem
import SwiftUI

/// 剧情位置由服务端保存；不在客户端推断升级成功或变更档案。
public struct LearningPromotionView: View {
    private let service: any LearningPromotionServing
    private let onProfileChanged: @MainActor () async throws -> Void
    @State private var promotion: LearningPromotion
    @State private var busy = false
    @State private var error: String?
    @State private var advanceRequestID: UUID?
    @State private var completion: LearningPromotionCommand?
    @State private var showConfirmation = false
    @State private var profileRefreshed = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(promotion: LearningPromotion, service: any LearningPromotionServing,
                onProfileChanged: @escaping @MainActor () async throws -> Void) {
        _promotion = State(initialValue: promotion); self.service = service
        self.onProfileChanged = onProfileChanged
    }
    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                HStack {
                    Label("新的里程", systemImage: "sparkles").font(.caption.weight(.semibold)).foregroundStyle(Color.dsSkyDeep)
                    Spacer()
                    Text("\(min(promotion.acknowledgedBeats, promotion.story.beats.count)) / \(promotion.story.beats.count)").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                }
                Text(promotion.story.title).font(.system(.largeTitle, design: .serif).weight(.semibold))
                Text("\(learningLevelName(promotion.fromLevel)) → \(learningLevelName(promotion.toLevel))")
                    .font(.headline).foregroundStyle(Color.dsSkyDeep)
                ProgressView(value: Double(promotion.acknowledgedBeats), total: Double(max(1, promotion.story.beats.count))).tint(.dsSkyDeep)
                if let error { LearningErrorBanner(message: error) { Task { await retry() } } }
                if promotion.isCompleted {
                    VStack(alignment: .leading, spacing: 18) {
                        Image(systemName: "book.closed.fill").font(.largeTitle).foregroundStyle(Color.dsSkyDeep)
                        Text("这一程，已成为你的足迹。").font(.title2.bold())
                        Text(profileRefreshed ? "水平已更新。接下来的聊天与新挑战会采用新的难度，旧挑战仍保留原来的难度与进度。" : "进阶已经保存，正在同步你的最新档案。")
                            .font(.body).foregroundStyle(.secondary)
                    }.modifier(LearningPaper())
                    Button("返回英语旅程") { dismiss() }.buttonStyle(.borderedProminent).disabled(!profileRefreshed || busy)
                } else if promotion.status == "superseded" {
                    VStack(alignment: .leading, spacing: 18) {
                        Text("进阶课程已更新").font(.title2.bold())
                        Text("这段剧情已被新版课程替代。返回英语旅程后，可按最新课程继续进阶。")
                            .foregroundStyle(.secondary)
                        Button("返回英语旅程") { dismiss() }.buttonStyle(.borderedProminent)
                    }.modifier(LearningPaper())
                } else if let beat = promotion.currentBeat {
                    VStack(alignment: .leading, spacing: 22) {
                        Text(beat.speaker).font(.caption.weight(.semibold)).foregroundStyle(Color.dsSkyDeep)
                        Text(beat.text).font(.system(.title2, design: .serif)).lineSpacing(7)
                        Text(beat.translation).font(.body).foregroundStyle(.secondary).lineSpacing(5)
                    }.frame(maxWidth: .infinity, minHeight: 220, alignment: .leading).modifier(LearningPaper()).id(beat.id)
                    Button { Task { await advance() } } label: { Label(busy ? "正在保存…" : "继续", systemImage: "arrow.right") }
                        .buttonStyle(.borderedProminent).disabled(busy).accessibilityIdentifier("learning.promotion.continue")
                } else {
                    VStack(alignment: .leading, spacing: 18) {
                        Text("准备翻开下一页？").font(.title2.bold())
                        Text("确认后将进入\(learningLevelName(promotion.toLevel))。新发起的聊天与挑战会采用这一难度；当前挑战保持不变，原档的点数与星星会保留。")
                            .foregroundStyle(.secondary)
                        Button("确认进阶") { showConfirmation = true }.buttonStyle(.borderedProminent).disabled(busy)
                            .accessibilityIdentifier("learning.promotion.confirm")
                    }.modifier(LearningPaper())
                }
                Text("这是课程学习进度，不是英语能力认证。你仍可在英语旅程中手动调整水平。")
                    .font(.caption).foregroundStyle(.secondary)
            }.padding(24).frame(maxWidth: 620).frame(maxWidth: .infinity)
        }.background(Color.dsBackground).navigationTitle("水平进阶").navigationBarTitleDisplayMode(.inline)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: promotion.acknowledgedBeats)
            .alert("进入\(learningLevelName(promotion.toLevel))？", isPresented: $showConfirmation) {
                Button("确认进入下一水平") { Task { await complete() } }
                Button("继续保留当前水平", role: .cancel) {}
            } message: { Text("这会改变之后聊天和新挑战的难度，已开始的挑战及原有学习进度会保留。") }
            .task { if promotion.isCompleted { await refreshProfile() } }
            .accessibilityIdentifier("learning.promotion")
    }
    private func advance() async {
        guard !busy else { return }; busy = true; defer { busy = false }
        let id = advanceRequestID ?? UUID(); advanceRequestID = id
        do { promotion = try await service.advanceLearningPromotion(promotion, requestID: id); advanceRequestID = nil; error = nil }
        catch { await recover(error) }
    }
    private func complete() async {
        guard !busy else { return }; busy = true; defer { busy = false }
        let command = completion ?? LearningPromotionCommand(requestID: UUID(), promotion: promotion); completion = command
        do {
            promotion = try await service.completeLearningPromotion(promotion.id, command: command)
            completion = nil; error = nil
            try await onProfileChanged(); profileRefreshed = true
        } catch { await recover(error) }
    }
    private func recover(_ failure: Error) async {
        if case BackendClientError.api(_, let message, _, let status) = failure, status == 409 {
            advanceRequestID = nil; completion = nil
            if let latest = try? await service.learningPromotion(promotion.id) { promotion = latest }
            error = message
        } else { error = promotion.isCompleted ? "进阶已保存，档案暂未同步完成。请联网后重试。" : "暂时无法保存，请联网后重试。重复请求不会重复推进。" }
    }
    private func refreshProfile() async {
        guard !busy else { return }; busy = true; defer { busy = false }
        do { try await onProfileChanged(); profileRefreshed = true; error = nil }
        catch { self.error = "进阶已保存，档案暂未同步完成。请联网后重试。" }
    }
    private func retry() async {
        if promotion.isCompleted { await refreshProfile() }
        else if completion != nil { await complete() }
        else if advanceRequestID != nil { await advance() }
        else {
            do { promotion = try await service.beginLearningPromotion(level: promotion.fromLevel, requestID: UUID()); error = nil }
            catch { await recover(error) }
        }
    }
}
