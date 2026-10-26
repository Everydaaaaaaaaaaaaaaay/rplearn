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
                    VStack(spacing: 24) {
                        if let journey = model.journey {
                            globalCard(journey)
                            Divider()
                        }
                        progressCard(state)
                    }
                    .modifier(LearningPaper())
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("learning.challenge.card")
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
        let unlocked = state.activeAttemptId != nil || state.characters >= state.threshold
        return VStack(spacing: 22) {
            VStack(spacing: 14) {
                Image(systemName: state.activeAttemptId != nil ? "book.fill" : unlocked ? "book.closed.fill" : "lock.fill")
                    .font(.system(size: 26, weight: .regular))
                    .foregroundStyle(theme.tint)
                    .frame(width: 68, height: 68)
                    .background(theme.tint.opacity(0.08), in: Circle())
                    .padding(7)
                    .overlay { Circle().strokeBorder(theme.tint.opacity(0.18), lineWidth: 1) }
                    .accessibilityHidden(true)
                Text("单元挑战").font(.system(.title2, design: .serif, weight: .semibold))
                Text(challengeStatus(state)).font(.subheadline).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
            }
            if !unlocked {
                VStack(spacing: 10) {
                    LearningMeter(value: state.characters, total: state.threshold, tint: theme.tint)
                    Text("\(state.characters.formatted()) / \(state.threshold.formatted()) 聊天字符")
                        .font(.caption).monospacedDigit().foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("挑战进度，\(state.characters) / \(state.threshold) 字符")
            } else { challengeAction(state) }
        }
        .padding(.vertical, 6).frame(maxWidth: .infinity)
    }
    private func challengeAction(_ state: BackendLearningCharacter) -> some View {
        let preparing = model.isPreparing && state.activeAttemptId == nil
        let unavailable = state.activeAttemptId == nil && !model.canStartNewChallenge
        return Button { Task { await model.open() } } label: {
            HStack(spacing: 10) {
                if model.isBusy { ProgressView().controlSize(.small) }
                Text(state.activeAttemptId != nil ? "继续挑战" : unavailable ? "题目准备中" : preparing ? "刷新状态" : "开启单元挑战")
                    .font(.body.weight(.semibold))
                if !model.isBusy && !unavailable && !preparing {
                    Image(systemName: "arrow.right").font(.subheadline.weight(.medium)).accessibilityHidden(true)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 54).padding(.horizontal, 16)
            .foregroundStyle(unavailable ? Color.secondary : Color.dsSurface)
            .background(unavailable ? Color.secondary.opacity(0.10) : theme.tint, in: RoundedRectangle(cornerRadius: 18))
        }
        .buttonStyle(LearningPressStyle())
        .disabled(model.isBusy || model.isChangingDirection || unavailable)
        .accessibilityLabel(state.activeAttemptId != nil ? "继续挑战" : unavailable ? "暂不可开启新挑战" : preparing ? "刷新状态" : "开启单元挑战")
        .accessibilityIdentifier("learning.start")
    }
    private func challengeStatus(_ state: BackendLearningCharacter) -> String {
        if state.activeAttemptId != nil { return "挑战进行中" }
        if model.pendingDirection != nil { return "方向待确认" }
        if model.directions == nil { return "方向未同步" }
        if !model.canStartNewChallenge { return "题目准备中" }
        if model.isPreparing { return "新单元正在准备" }
        return state.characters >= state.threshold ? "新单元已解锁" : "在聊天中积累，开启下一程"
    }
    private func globalCard(_ journey: LearningJourney) -> some View {
        Button { showJourney = true } label: {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    Text(generalProgressTitle(journey)).font(.headline)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
                }
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: 10) { journeyStars(journey); nextStar(journey.current) }
                } else {
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 16) { journeyStars(journey); Spacer(minLength: 0); nextStar(journey.current) }
                        VStack(alignment: .leading, spacing: 10) { journeyStars(journey); nextStar(journey.current) }
                    }
                }
            }
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading).contentShape(Rectangle())
        }
        .buttonStyle(LearningPressStyle()).foregroundStyle(.primary)
        .accessibilityHint("查看学习进度")
        .accessibilityIdentifier("learning.journey")
    }
    private func journeyStars(_ journey: LearningJourney) -> some View {
        LearningMilestones(earned: journey.current?.stars ?? 0, tint: theme.tint)
    }
    private func generalProgressTitle(_ journey: LearningJourney) -> String {
        let level = learningLevelName(journey.currentLevel)
        return model.directions?.selectedDirection == "general" ? level : "通用英语 · \(level)"
    }
    private func nextStar(_ current: LearningLevelProgress?) -> some View {
        Text((current?.stars ?? 0) >= 9 ? "9 星已达成" : "下一星 \(current?.currentStarPoints ?? 0)/\(current?.pointsPerStar ?? 60) 积分")
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
                Text(onlyUnfinished ? "暂时没有需要补答的练习" : "完成挑战后，在这里回顾。")
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
        HStack(spacing: 7) {
            ForEach(0..<9) { index in
                Image(systemName: index < earned ? "star.fill" : "star")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(index < earned ? tint : Color.secondary.opacity(0.6))
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
