import BackendKit
import CoreKit
import DomainKit
import DesignSystem
import PersistenceKit
import SwiftUI
import SpeechKit

public struct CharacterLearningView: View {
    @State private var model: CharacterLearningModel
    private let character: CharacterDTO
    private let isVisible: Bool
    private let speech: any SpeechService
    private let audioSession: AudioSessionCoordinator
    private let beforePlayback: @Sendable () async -> Void
    @Environment(\.scenePhase) private var scenePhase
    @State private var showJourney = false
    @State private var showDirections = false
    @State private var onlyUnfinished = false
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    public init(character: CharacterDTO, service: any LearningServing & LearningDirectionServing, isVisible: Bool = true,
                audioSession: AudioSessionCoordinator = AudioSessionCoordinator(),
                speech: (any SpeechService)? = nil,
                beforePlayback: @escaping @Sendable () async -> Void = {},
                cycleChanged: @escaping @Sendable () async -> Void = {}) {
        self.character = character; self.isVisible = isVisible
        self.speech = speech ?? AdaptiveSpeechService(audioSession: audioSession)
        self.audioSession = audioSession; self.beforePlayback = beforePlayback
        _model = State(initialValue: CharacterLearningModel(characterID: character.id, service: service,
                                                           cycleChanged: cycleChanged))
    }
    private var theme: LearningTheme { LearningTheme(role: model.state?.roleKey ?? character.card.name.components(separatedBy: " ").first?.lowercased() ?? "") }
    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if let error = model.error ?? model.directionError {
                    LearningPageError(message: error) {
                        Task {
                            if let pending = model.pendingDirection { await model.selectDirection(pending) }
                            else { await model.load() }
                        }
                    }
                }
                directionRow
                if let state = model.state {
                    progressCard(state).modifier(LearningPaper())
                    if let journey = model.journey { globalCard(journey) }
                    historySection
                } else if model.isBusy {
                    ProgressView("正在载入…")
                        .font(.subheadline).frame(maxWidth: .infinity).padding(.vertical, 32)
                }
            }
            .padding(.horizontal, 20).padding(.top, 12).padding(.bottom, 28)
            .frame(maxWidth: 600).frame(maxWidth: .infinity)

        }
        .background(Color.dsBackground)
        .tint(theme.tint)
        .refreshable { await model.load() }
        .task(id: isVisible) { if isVisible { await model.load() } }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active && isVisible { Task { await model.load() } }
        }
        .onReceive(NotificationCenter.default.publisher(for: .roleplayConversationDidChange)) { notification in
            if isVisible && notification.object as? UUID == character.id { Task { await model.load() } }
        }
        .fullScreenCover(item: $model.presentedAttempt, onDismiss: { Task { await model.challengeClosed() } }) { attempt in
            LearningChallengeView(attempt: attempt, character: character, service: model.service, audioSession: audioSession, speech: speech,
                                  beforePlayback: beforePlayback, afterFinish: { await model.refreshCycle() })
        }
        .sheet(isPresented: $showJourney) {
            NavigationStack {
                LearningProgressOverview(service: model.service)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button { showJourney = false } label: { Image(systemName: "xmark") }
                                .accessibilityLabel("关闭学习进度")
                        }
                    }
            }
        }
        .sheet(isPresented: $showDirections) {
            LearningDirectionPicker(model: model)
                .tint(theme.tint)
        }
        .accessibilityIdentifier("learning.character")
    }
    private var directionRow: some View {
        Button { showDirections = true } label: {
            HStack(spacing: 10) {
                Text("练习方向").font(.caption).foregroundStyle(.secondary)
                Spacer(minLength: 8)
                Text(model.selectedDirection?.title ?? "选择练习方向")
                    .font(.subheadline.weight(.semibold))
                    .multilineTextAlignment(.trailing)
                if model.isBusy || model.isChangingDirection { ProgressView().controlSize(.small) }
                else if model.selectedDirection?.status != "available", model.directions != nil {
                    Text("准备中").font(.caption).foregroundStyle(.secondary)
                }
                Image(systemName: "chevron.down").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
            }
            .frame(minHeight: 44).contentShape(Rectangle())
        }
        .buttonStyle(.plain).foregroundStyle(.primary)
        .accessibilityIdentifier("learning.direction")
    }
    private func progressCard(_ state: BackendLearningCharacter) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 6) {
                    challengeTitle
                    statusLabel(state)
                }
            } else {
                HStack(alignment: .firstTextBaseline) {
                    challengeTitle
                    Spacer(minLength: 8)
                    statusLabel(state)
                }
            }
            VStack(alignment: .leading, spacing: 14) {
                characterCount(state)
                LearningMeter(value: state.characters, total: state.threshold, tint: theme.tint)
                    .accessibilityLabel("挑战进度")
                    .accessibilityValue("\(state.characters) / \(state.threshold) 字符")
                if state.activeAttemptId != nil || state.characters >= state.threshold {
                    if dynamicTypeSize.isAccessibilitySize {
                        VStack(alignment: .leading, spacing: 14) {
                            challengeDetail(state)
                            challengeAction(state)
                        }
                    } else {
                        HStack(spacing: 16) {
                            challengeDetail(state)
                            Spacer(minLength: 0)
                            challengeAction(state)
                        }
                    }
                } else { challengeDetail(state) }
            }
        }
    }
    private func statusLabel(_ state: BackendLearningCharacter) -> some View {
        Text(challengeStatus(state)).font(.caption.weight(.medium)).foregroundStyle(theme.tint)
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(theme.tint.opacity(0.08), in: Capsule())
    }
    private func challengeDetail(_ state: BackendLearningCharacter) -> some View {
        let text = state.activeAttemptId != nil ? "接着完成上次的练习"
            : state.characters < state.threshold ? "还差 \(max(0, state.threshold - state.characters)) 个聊天字符"
            : model.isPreparing ? "新单元正在准备" : "聊天进度已满"
        return Text(text).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
    }
    private func challengeAction(_ state: BackendLearningCharacter) -> some View {
        let preparing = model.isPreparing && state.activeAttemptId == nil
        let unavailable = state.activeAttemptId == nil && !model.canStartNewChallenge
        return Button { Task { await model.open() } } label: {
            HStack(spacing: 8) {
                if model.isBusy {
                    ProgressView().controlSize(.small)
                }
                Text(state.activeAttemptId != nil ? "继续挑战" : unavailable ? "题目准备中" : preparing ? "刷新状态" : "开始挑战")
                    .font(.subheadline.weight(.semibold))
            }
            .frame(maxWidth: dynamicTypeSize.isAccessibilitySize ? .infinity : nil, minHeight: 44)
            .padding(.horizontal, 16)
            .foregroundStyle(unavailable ? Color.secondary : Color.dsSurface)
            .background(unavailable ? Color.secondary.opacity(0.10) : theme.tint, in: Capsule())
        }
        .buttonStyle(LearningPressStyle())
        .disabled(model.isBusy || model.isChangingDirection || (state.activeAttemptId == nil && !model.canStartNewChallenge))
        .accessibilityLabel(state.activeAttemptId != nil ? "继续挑战" : unavailable ? "暂不可开启新挑战" : preparing ? "刷新状态" : "开始挑战")
        .accessibilityIdentifier("learning.start")
    }
    private var challengeTitle: some View {
        Text("单元挑战").font(.headline)
    }
    private func characterCount(_ state: BackendLearningCharacter) -> some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 4) {
                    Text(state.characters.formatted()).font(.system(.largeTitle, design: .rounded, weight: .semibold))
                    Text("目标 \(state.threshold.formatted()) 字符").font(.caption).foregroundStyle(.secondary)
                }
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text(state.characters.formatted()).font(.system(.largeTitle, design: .rounded, weight: .semibold))
                    Text("/ \(state.threshold.formatted()) 字符").font(.caption).foregroundStyle(.secondary)
                }
            }
        }.monospacedDigit().accessibilityElement(children: .combine)
    }
    private func challengeStatus(_ state: BackendLearningCharacter) -> String {
        if state.activeAttemptId != nil { return "进行中" }
        if model.pendingDirection != nil { return "方向待确认" }
        if model.directions == nil { return "方向未同步" }
        if !model.canStartNewChallenge { return "题目准备中" }
        if model.isPreparing { return "单元准备中" }
        return state.characters >= state.threshold ? "可开启" : "聊天积累中"
    }
    private func globalCard(_ journey: LearningJourney) -> some View {
        Button { showJourney = true } label: {
            HStack(spacing: 14) {
                Image(systemName: "star.fill").font(.system(size: 18, weight: .medium))
                    .foregroundStyle(theme.tint).frame(width: 38, height: 38)
                    .background(theme.tint.opacity(0.08), in: Circle()).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 6) {
                    Text(generalProgressTitle(journey)).font(.subheadline.weight(.semibold))
                    nextStar(journey.current).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(.tertiary)
            }.padding(.vertical, 4).contentShape(Rectangle())
        }
        .buttonStyle(LearningPressStyle()).foregroundStyle(.primary)
        .accessibilityHint("查看学习进度")
        .accessibilityIdentifier("learning.journey")
    }
    private func generalProgressTitle(_ journey: LearningJourney) -> String {
        let level = learningLevelName(journey.currentLevel)
        return model.directions?.selectedDirection == "general" ? level : "通用英语 · \(level)"
    }
    private func nextStar(_ current: LearningLevelProgress?) -> some View {
        Text((current?.stars ?? 0) >= 9 ? "9 星已达成" : "\(current?.stars ?? 0)/9 星 · 下一星 \(current?.currentStarPoints ?? 0)/\(current?.pointsPerStar ?? 60) 积分")
            .font(.caption).monospacedDigit().foregroundStyle(.secondary)
    }
    private var visibleHistory: [LearningHistory.Item] {
        onlyUnfinished ? model.history.filter { $0.firstCompletedAt != nil && $0.correctCount < $0.questionCount } : model.history
    }
    private var historySection: some View {
        let items = visibleHistory
        return VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("挑战记录").font(.headline)
                Spacer()
                if model.isBusy { ProgressView().controlSize(.small) }
                if !model.history.isEmpty {
                    Button { onlyUnfinished.toggle() } label: {
                        Label("待补答", systemImage: onlyUnfinished ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease")
                            .font(.caption.weight(.medium)).padding(.horizontal, 10).frame(minHeight: 44)
                    }
                    .buttonStyle(.plain).foregroundStyle(onlyUnfinished ? theme.tint : Color.secondary)
                    .accessibilityLabel(onlyUnfinished ? "显示全部记录" : "仅看待补答")
                    .accessibilityValue(onlyUnfinished ? "已筛选" : "未筛选")
                    .accessibilityIdentifier("learning.history.filter")
                }
            }.frame(minHeight: 44)
            if items.isEmpty {
                Text(onlyUnfinished ? "暂时没有需要补答的练习" : "完成一次挑战后，答题情况和获得的积分会记录在这里。")
                    .font(.subheadline).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 20)
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(items) { item in
                        Divider()
                        historyRow(item)
                    }
                }
            }
            if model.nextCursor != nil {
                Button { Task { await model.loadMore() } } label: {
                    Label("更多记录", systemImage: "chevron.down").font(.subheadline.weight(.medium))
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .accessibilityLabel("载入更多记录").disabled(model.isBusy)
            }
        }
    }
    private func historyRow(_ item: LearningHistory.Item) -> some View {
        let complete = item.firstCompletedAt != nil && item.correctCount == item.questionCount
        return Button { Task { await model.open(item.id) } } label: {
            VStack(alignment: .leading, spacing: 9) {
                Text(item.title).font(.subheadline.weight(.semibold))
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                    .multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
                Text("\(historyDate(item)) · \(learningLevelName(item.level))")
                    .font(.caption).foregroundStyle(.secondary)
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    if dynamicTypeSize.isAccessibilitySize {
                        VStack(alignment: .leading, spacing: 5) {
                            historyMetadata(item)
                            historyPoints(item)
                        }
                    } else {
                        historyMetadata(item)
                        Spacer(minLength: 0)
                        historyPoints(item)
                    }
                    Image(systemName: "chevron.right").font(.caption2.weight(.semibold))
                        .foregroundStyle(.tertiary).accessibilityHidden(true)
                }
            }
            .padding(.vertical, 17).frame(maxWidth: .infinity, minHeight: 78, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(LearningPressStyle()).foregroundStyle(.primary).disabled(model.isBusy)
        .accessibilityLabel("\(item.title)，\(historyDate(item))，\(learningLevelName(item.level))，答对 \(item.correctCount)/\(item.questionCount)，\(historyPointsText(item))，\(historyActionLabel(item))")
        .accessibilityHint(complete ? "查看挑战" : item.firstCompletedAt == nil ? "继续挑战" : "补答剩余题目")
        .accessibilityIdentifier("learning.history.\(item.id.uuidString)")
    }
    private func historyMetadata(_ item: LearningHistory.Item) -> some View {
        Text("答对 \(item.correctCount)/\(item.questionCount) · \(historyActionLabel(item))")
            .font(.caption).monospacedDigit().foregroundStyle(.secondary)
    }
    private func historyPoints(_ item: LearningHistory.Item) -> some View {
        Text(historyPointsText(item)).font(.subheadline.weight(.semibold)).monospacedDigit()
            .foregroundStyle((item.earnedPoints ?? 0) > 0 ? LearningTheme.rewardTint : Color.secondary)
    }
    private func historyPointsText(_ item: LearningHistory.Item) -> String {
        item.earnedPoints.map { "获得 \($0) 积分" } ?? "积分待同步"
    }
    private func historyDate(_ item: LearningHistory.Item) -> String {
        let date = (try? Date.ISO8601FormatStyle(includingFractionalSeconds: true).parse(item.startedAt))
            ?? (try? Date.ISO8601FormatStyle().parse(item.startedAt))
        return date?.formatted(.dateTime.month(.twoDigits).day(.twoDigits).hour().minute(.twoDigits)) ?? ""
    }
    private func historyActionLabel(_ item: LearningHistory.Item) -> String {
        if item.firstCompletedAt == nil { return "继续" }
        return item.correctCount == item.questionCount ? "已完成" : "补答 \(max(0, item.questionCount - item.correctCount)) 题"
    }

}

/// 角色页的全局摘要；英语水平调整入口由 App 装配。
public struct LearningProgressOverview: View {
    private let service: any LearningServing
    @State private var journey: LearningJourney?
    @State private var error: String?
    public init(service: any LearningServing) { self.service = service }
    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if let error { LearningPageError(message: error) { Task { await load() } } }
                if let journey, let current = journey.current {
                    VStack(alignment: .leading, spacing: 20) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(learningLevelName(journey.currentLevel)).font(.title2.weight(.semibold))
                            Spacer()
                            Text("\(current.stars)/9 星").font(.subheadline).monospacedDigit().foregroundStyle(.secondary)
                        }
                        LearningMilestones(earned: current.stars, tint: .dsSkyDeep)
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text(current.stars >= 9 ? "本级累计" : "下一颗星").font(.subheadline)
                                Spacer()
                                Text(current.stars >= 9 ? "\(current.points) 点" : "\(current.currentStarPoints)/\(current.pointsPerStar) 点")
                                    .font(.subheadline.weight(.semibold)).monospacedDigit()
                            }
                            LearningMeter(value: current.stars >= 9 ? current.targetPoints : current.currentStarPoints,
                                          total: current.stars >= 9 ? current.targetPoints : current.pointsPerStar, tint: .dsSkyDeep)
                        }
                    }.padding(.vertical, 16)
                } else if error == nil {
                    ProgressView("正在载入…").frame(maxWidth: .infinity).padding(.vertical, 32)
                }
            }.padding(16).frame(maxWidth: 600).frame(maxWidth: .infinity)
        }
        .background(Color.dsBackground).navigationTitle("学习进度").navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }
    private func load() async {
        do { journey = try await service.learningJourney(); error = nil }
        catch is CancellationError {} catch { self.error = error.localizedDescription }
    }
}

private struct LearningMeter: View {
    let value: Int
    let total: Int
    let tint: Color
    var body: some View {
        GeometryReader { geometry in
            Capsule().fill(tint.opacity(0.10))
                .overlay(alignment: .leading) {
                    Capsule().fill(tint)
                        .frame(width: geometry.size.width * min(1, max(0, Double(value) / Double(max(1, total)))))
                }
        }.frame(height: 7)
    }
}

private struct LearningMilestones: View {
    let earned: Int
    let tint: Color
    var body: some View {
        HStack(spacing: 0) {
            ForEach(0..<9) { index in
                Image(systemName: index < earned ? "star.fill" : "star")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(index < earned ? tint : Color.secondary.opacity(0.6))
                if index < 8 {
                    Rectangle().fill(Color.secondary.opacity(0.12)).frame(height: 1).padding(.horizontal, 5)
                }
            }
        }
        .accessibilityElement(children: .ignore).accessibilityLabel("已点亮 \(earned) 颗星，共 9 颗")
    }
}

struct LearningPageError: View {
    let message: String
    let retry: () -> Void
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.circle").foregroundStyle(.secondary).accessibilityHidden(true)
            Text(message).font(.subheadline).frame(maxWidth: .infinity, alignment: .leading)
            Button(action: retry) {
                Image(systemName: "arrow.clockwise").font(.body.weight(.medium)).frame(width: 44, height: 44)
            }.accessibilityLabel("重新载入")
        }
        .padding(.leading, 16).padding(.trailing, 4).padding(.vertical, 8)
        .background(Color.dsSurface, in: RoundedRectangle(cornerRadius: 16))
    }
}
