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
    @State private var celebrateCompletion = false
    @State private var showsTranslation = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(promotion: LearningPromotion, service: any LearningPromotionServing,
                onProfileChanged: @escaping @MainActor () async throws -> Void) {
        _promotion = State(initialValue: promotion); self.service = service
        self.onProfileChanged = onProfileChanged
    }
    public var body: some View {
        Group {
            if promotion.isCompleted {
                LearningPromotionCelebration(fromLevel: promotion.fromLevel, toLevel: promotion.toLevel,
                    message: promotion.story.beats.last?.text ?? "Take your time. We can read it together.",
                    animate: celebrateCompletion, primaryEnabled: profileRefreshed && !busy, error: error,
                    retry: { Task { await retry() } }, close: { dismiss() }, continueJourney: { dismiss() })
            } else {
                ceremony
            }
        }
        .preferredColorScheme(.dark)
        .alert("进入\(learningLevelName(promotion.toLevel))？", isPresented: $showConfirmation) {
            Button("确认进入下一水平") { Task { await complete() } }
            Button("继续保留当前水平", role: .cancel) {}
        } message: { Text("这会改变之后聊天和新挑战的难度，已开始的挑战及原有学习进度会保留。") }
        .task { if promotion.isCompleted { await refreshProfile() } }
    }
    private var ceremony: some View {
        ScrollView {
            VStack(spacing: 22) {
                LearningPromotionCrest().scaleEffect(0.72).frame(height: 190)
                Text(promotion.story.title).font(.system(.largeTitle, design: .serif).weight(.semibold))
                    .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                Text("\(learningLevelName(promotion.fromLevel)) → \(learningLevelName(promotion.toLevel))")
                    .font(.headline).foregroundStyle(LearningAchievementGold.light).multilineTextAlignment(.center)
                ProgressView(value: Double(promotion.acknowledgedBeats), total: Double(max(1, promotion.story.beats.count)))
                    .tint(LearningAchievementGold.main).accessibilityLabel("晋升旅程进度")
                if let error { LearningErrorBanner(message: error) { Task { await retry() } } }
                if promotion.status == "superseded" {
                    VStack(spacing: 18) {
                        Text("进阶课程已更新").font(.title2.bold())
                        Text("这段剧情已被新版课程替代。返回学习页后，可按最新课程继续进阶。")
                            .foregroundStyle(.secondary)
                        LearningPrimaryButton(title: "返回学习页", tint: LearningAchievementGold.main) { dismiss() }
                    }.modifier(LearningPaper(opacity: 0.8))
                } else if let beat = promotion.currentBeat {
                    VStack(alignment: .leading, spacing: 18) {
                        Text(beat.speaker).font(.caption.weight(.semibold)).foregroundStyle(LearningAchievementGold.light)
                        Text(beat.text).font(.system(.title2, design: .serif)).lineSpacing(7)
                        Button(showsTranslation ? "收起中文" : "查看中文") { showsTranslation.toggle() }
                            .font(.footnote).frame(minHeight: 44)
                        if showsTranslation { Text(beat.translation).foregroundStyle(.secondary).lineSpacing(5) }
                    }.frame(maxWidth: .infinity, minHeight: 170, alignment: .leading)
                        .modifier(LearningPaper(opacity: 0.8)).id(beat.id)
                    LearningPrimaryButton(title: "继续", tint: LearningAchievementGold.main, busy: busy) {
                        Task { await advance() }
                    }.accessibilityIdentifier("learning.promotion.continue")
                } else {
                    VStack(spacing: 16) {
                        Text("准备翻开下一页？").font(.title2.bold())
                        Text("确认后进入\(learningLevelName(promotion.toLevel))。新的聊天与挑战将采用这一难度，原档进度会保留。")
                            .foregroundStyle(.secondary).multilineTextAlignment(.center)
                        LearningPrimaryButton(title: "确认晋升", tint: LearningAchievementGold.main, busy: busy) { showConfirmation = true }
                            .accessibilityIdentifier("learning.promotion.confirm")
                    }.modifier(LearningPaper(opacity: 0.8))
                }
                Text("课程学习进度 · 不等同于英语能力认证")
                    .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }.padding(24).frame(maxWidth: 600).frame(maxWidth: .infinity)
        }
        .safeAreaInset(edge: .top) {
            HStack {
                Text("晋升仪式").font(.headline)
                Spacer()
                Button { dismiss() } label: { Image(systemName: "xmark").frame(width: 44, height: 44) }
                    .accessibilityLabel("关闭晋升界面")
            }.padding(.horizontal, 20)
        }
        .background { LearningAchievementBackdrop() }.foregroundStyle(.white).tint(LearningAchievementGold.light)
        .toolbar(.hidden, for: .navigationBar)
    }
    private func advance() async {
        guard !busy else { return }; busy = true; defer { busy = false }
        let id = advanceRequestID ?? UUID(); advanceRequestID = id
        do { promotion = try await service.advanceLearningPromotion(promotion, requestID: id); advanceRequestID = nil; error = nil; showsTranslation = false }
        catch { await recover(error) }
    }
    private func complete() async {
        guard !busy else { return }; busy = true; defer { busy = false }
        let command = completion ?? LearningPromotionCommand(requestID: UUID(), promotion: promotion); completion = command
        do {
            let saved = try await service.completeLearningPromotion(promotion.id, command: command)
            guard saved.isCompleted else { throw BackendClientError.invalidResponse }
            celebrateCompletion = true; promotion = saved
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
