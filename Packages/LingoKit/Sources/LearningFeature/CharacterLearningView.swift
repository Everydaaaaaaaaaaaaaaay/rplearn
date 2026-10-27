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
    private let currentRegionID: @Sendable () async -> String?
    @State private var sceneRegionID: String?
    @Environment(\.scenePhase) private var scenePhase
    @State private var showJourney = false
    @State private var historyExpanded = false
    @State private var historyFilter = LearningHistoryFilter()
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    public init(character: CharacterDTO, service: any LearningServing & LearningDirectionServing, isVisible: Bool = true,
                audioSession: AudioSessionCoordinator = AudioSessionCoordinator(),
                speech: (any SpeechService)? = nil,
                currentRegionID: @escaping @Sendable () async -> String? = { nil },
                beforePlayback: @escaping @Sendable () async -> Void = {},
                cycleChanged: @escaping @Sendable () async -> Void = {}) {
        self.character = character; self.isVisible = isVisible
        self.speech = speech ?? AdaptiveSpeechService(audioSession: audioSession)
        self.audioSession = audioSession; self.beforePlayback = beforePlayback
        self.currentRegionID = currentRegionID
        _model = State(initialValue: CharacterLearningModel(characterID: character.id, service: service,
                                                           cycleChanged: cycleChanged))
    }
    private var theme: LearningTheme { LearningTheme(role: model.state?.roleKey ?? character.card.name.components(separatedBy: " ").first?.lowercased() ?? "") }
    public var body: some View {
        GeometryReader { viewport in
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let error = model.error ?? model.directionError {
                        LearningPageError(message: error) {
                            Task {
                                if let pending = model.pendingDirection { await model.selectDirection(pending) }
                                else { await model.load() }
                            }
                        }
                    }
                    if let state = model.state {
                        challengeCard(state, compact: viewport.size.height < 650)
                        Spacer(minLength: 0)
                        historySection.modifier(LearningPaper(opacity: 0.96))
                    } else if model.isBusy {
                        ProgressView("正在载入…")
                            .font(.subheadline).frame(maxWidth: .infinity).padding(.vertical, 32)
                            .modifier(LearningPaper(opacity: 0.96))
                    }
                }
                .frame(minHeight: max(0, viewport.size.height - 24), alignment: .top)
                .padding(.horizontal, 20).padding(.top, 8).padding(.bottom, 16)
                .frame(maxWidth: 600).frame(maxWidth: .infinity)
            }
        }
        .background { LearningCityBackdrop(regionID: sceneRegionID) }
        .tint(theme.tint)
        .refreshable { await reloadPage() }
        .task(id: isVisible) { if isVisible { await reloadPage() } }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active && isVisible { Task { await reloadPage() } }
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
        .accessibilityIdentifier("learning.character")
    }
    private func reloadPage() async {
        async let load: Void = model.load()
        if let regionID = await currentRegionID(), !Task.isCancelled { sceneRegionID = regionID }
        await load
    }
    private func challengeCard(_ state: BackendLearningCharacter, compact: Bool) -> some View {
        let unlocked = state.activeAttemptId != nil || state.characters >= state.threshold
        let percentage = learningChatPercentage(characters: state.characters, threshold: state.threshold)
        return VStack(spacing: compact ? 20 : 28) {
            VStack(spacing: compact ? 10 : 14) {
                AvatarBadge(name: character.displayName, size: compact ? 64 : 88,
                            imageName: character.card.avatarAssetName,
                            remoteURL: character.card.avatarRemoteURL.flatMap(URL.init(string:)),
                            usesPendingPlaceholder: true)
                    .accessibilityHidden(true)
                Text(character.displayName).font(.title2.weight(.semibold))
                    .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("learning.character.identity")

            VStack(spacing: 8) {
                LearningMeter(value: state.characters, total: state.threshold, tint: theme.tint)
                    .frame(maxWidth: 260)
                Text("\(percentage)% 聊天进度")
                    .font(.caption).monospacedDigit().foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("练习解锁进度")
            .accessibilityValue("\(percentage)% 聊天进度")
            .accessibilityIdentifier("learning.unlock.progress")

            VStack(spacing: compact ? 12 : 16) {
                if let journey = model.journey { globalCard(journey) }
                Text(challengeStatus(state)).font(.subheadline).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                if unlocked { challengeAction(state) }
            }
        }
        .padding(.vertical, compact ? 0 : 8)
        .frame(maxWidth: .infinity, minHeight: compact ? 0 : 436)
        .modifier(LearningPaper(opacity: 0.96))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("learning.challenge.card")
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
        state.activeAttemptId != nil || state.characters >= state.threshold ? "单元练习已解锁" : "单元练习尚未解锁"
    }
    private func globalCard(_ journey: LearningJourney) -> some View {
        Button { showJourney = true } label: {
            VStack(spacing: 12) {
                Text(generalProgressTitle(journey)).font(.headline)
                    .fixedSize(horizontal: false, vertical: true)
                journeyStars(journey)
                nextStar(journey.current)
            }
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, minHeight: 44).contentShape(Rectangle())
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
        return level
    }
    private func nextStar(_ current: LearningLevelProgress?) -> some View {
        Text((current?.stars ?? 0) >= 9 ? "9 星已达成" : "下一星 \(current?.currentStarPoints ?? 0)/\(current?.pointsPerStar ?? 60) 积分")
            .font(.caption).monospacedDigit().foregroundStyle(.secondary)
    }
    private var visibleHistory: [LearningHistory.Item] {
        model.history.filter(historyFilter.matches)
    }
    private var historySection: some View {
        let items = visibleHistory
        return VStack(alignment: .leading, spacing: 0) {
            HStack {
                Button {
                    historyExpanded.toggle()
                } label: {
                    HStack(spacing: 10) {
                        Text("挑战记录").font(.headline)
                        Image(systemName: historyExpanded ? "chevron.up" : "chevron.down")
                            .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(LearningPressStyle()).foregroundStyle(.primary)
                .accessibilityValue(historyExpanded ? "已展开" : "已折叠")
                .accessibilityHint(historyExpanded ? "收起挑战记录" : "展开挑战记录")
                .accessibilityIdentifier("learning.history.toggle")
                Spacer()
                if model.isBusy { ProgressView().controlSize(.small) }
                if historyExpanded && !model.history.isEmpty {
                    historyFilterMenu
                }
            }.frame(minHeight: 44)
            if historyExpanded {
                if items.isEmpty {
                    Text(historyFilter.isActive
                         ? (model.nextCursor == nil ? "暂无符合筛选的记录" : "已载入的记录中暂无匹配项，可载入更多记录。")
                         : "完成挑战后，在这里回顾。")
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
    }
    private var historyFilterMenu: some View {
        Menu {
            Toggle("待补答", isOn: $historyFilter.onlyUnfinished)
            Section("答对比例") {
                Picker("答对比例", selection: $historyFilter.accuracy) {
                    ForEach(LearningHistoryAccuracyFilter.allCases) { filter in
                        Text(filter.title).tag(filter)
                    }
                }.pickerStyle(.inline)
            }
            if historyFilter.isActive {
                Button("清除筛选", systemImage: "xmark.circle") { historyFilter = LearningHistoryFilter() }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: historyFilter.isActive ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease")
                if historyFilter.isActive {
                    Text(historyFilter.summary).fixedSize(horizontal: false, vertical: true)
                }
            }
            .font(.caption.weight(.medium))
            .padding(.leading, 8).frame(minWidth: 44, minHeight: 44)
        }
        .foregroundStyle(historyFilter.isActive ? theme.tint : Color.secondary)
        .accessibilityLabel("筛选挑战记录")
        .accessibilityValue(historyFilter.isActive ? historyFilter.summary : "未筛选")
        .accessibilityIdentifier("learning.history.filter")
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
        (Text("答对 \(item.correctCount)/\(item.questionCount)")
            .foregroundColor(LearningAccuracyBand(correct: item.correctCount, total: item.questionCount).tint)
         + Text(" · \(historyActionLabel(item))").foregroundColor(.secondary))
            .font(.caption).monospacedDigit()
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
        }.frame(height: 12)
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
