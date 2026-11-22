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
    private let onOpenChatSettings: (@MainActor @Sendable () -> Void)?
    private let speech: any SpeechService
    private let audioSession: AudioSessionCoordinator
    private let beforePlayback: @Sendable () async -> Void
    private let promotionCompleted: @MainActor () async throws -> Void
    private let currentRegionID: @Sendable () async -> String?
    @State private var sceneRegionID: String?
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dsLearningBackdropProvided) private var backdropProvided
    @State private var displayedStarAward: LearningStarAward?
    @State private var historyExpanded = false
    @State private var historyFilter = LearningHistoryFilter()
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    public init(character: CharacterDTO, service: any LearningServing & LearningDirectionServing, isVisible: Bool = true,
                audioSession: AudioSessionCoordinator = AudioSessionCoordinator(),
                speech: (any SpeechService)? = nil,
                currentRegionID: @escaping @Sendable () async -> String? = { nil },
                beforePlayback: @escaping @Sendable () async -> Void = {},
                cycleChanged: @escaping @Sendable () async -> Void = {},
                promotionCompleted: @escaping @MainActor () async throws -> Void = {},
                onOpenChatSettings: (@MainActor @Sendable () -> Void)? = nil) {
        self.character = character; self.isVisible = isVisible
        self.onOpenChatSettings = onOpenChatSettings
        self.speech = speech ?? AdaptiveSpeechService(audioSession: audioSession)
        self.audioSession = audioSession; self.beforePlayback = beforePlayback
        self.currentRegionID = currentRegionID; self.promotionCompleted = promotionCompleted
        _model = State(initialValue: CharacterLearningModel(characterID: character.id, service: service,
                                                           cycleChanged: cycleChanged, profileChanged: promotionCompleted))
    }
    #if DEBUG
    init(character: CharacterDTO, previewModel: CharacterLearningModel,
         currentRegionID: @escaping @Sendable () async -> String?) {
        self.init(character: character, service: previewModel.service, currentRegionID: currentRegionID)
        _model = State(initialValue: previewModel)
    }
    #endif
    private var theme: LearningTheme { LearningTheme(name: character.displayName) }
    public var body: some View {
        GeometryReader { viewport in
            ScrollViewReader { reader in
            ScrollView {
                VStack(alignment: .leading, spacing: Puff.Space.m) {
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
                        historySection.modifier(LearningPaper())
                    } else if model.isBusy {
                        PuffLoadingDots()
                            .frame(maxWidth: .infinity).padding(.vertical, 40)
                            .accessibilityLabel("正在载入")
                    }
                }
                .padding(.horizontal, Puff.Space.m).padding(.top, Puff.Space.xs).padding(.bottom, Puff.Space.m)
                .frame(maxWidth: 600).frame(maxWidth: .infinity)
            }
            .task(id: isVisible ? model.starAward?.id : nil) {
                displayedStarAward = nil
                guard isVisible, let award = model.starAward else { return }
                reader.scrollTo("learning.star.destination", anchor: .center)
                do { try await Task.sleep(for: .milliseconds(100)) } catch { return }
                guard !Task.isCancelled, model.starAward?.id == award.id else { return }
                displayedStarAward = award
            }
            }
        }
        .background {
            // 聊天里由聊天页提供同色底，城市只出现在卡片顶部的卡通场景里。
            if !backdropProvided { Puff.Palette.page.ignoresSafeArea() }
        }
        .fontDesign(.rounded)
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
                                  beforePlayback: beforePlayback, afterFinish: { await model.refreshCycle() },
                                  didEarnPoints: { level, points in await model.recordReward(level: level, points: points) })
        }
        .fullScreenCover(item: $model.presentedPromotion, onDismiss: { Task { await model.load() } }) { promotion in
            if let service = model.service as? any LearningPromotionServing {
                NavigationStack {
                    LearningPromotionView(promotion: promotion, service: service, onProfileChanged: promotionCompleted)
                }
            }
        }
        .fullScreenCover(item: $model.presentedAutomaticPromotion) { promotion in
            LearningPromotionCelebration(fromLevel: promotion.fromLevel, toLevel: promotion.toLevel,
                message: "九颗星已点亮，新的旅程已经开启。",
                close: { model.presentedAutomaticPromotion = nil },
                continueJourney: { model.presentedAutomaticPromotion = nil })
        }
        .onChange(of: isVisible, initial: true) { _, visible in model.setPageVisible(visible) }
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
        let avatarSize: CGFloat = compact ? 72 : 88
        return VStack(spacing: 0) {
            // 卡片顶部是旅伴所在城市的卡通街景，头像压在街景下沿。
            PuffCityScene(regionID: sceneRegionID, viewport: .east, isActive: isVisible)
                .frame(height: compact ? 104 : 128)
                .clipShape(RoundedRectangle(cornerRadius: Puff.Radius.huge - 6, style: .continuous))
                .padding([.horizontal, .top], 6)
            VStack(spacing: compact ? 18 : 24) {
                VStack(spacing: compact ? 8 : 10) {
                    if let onOpenChatSettings {
                        Button(action: onOpenChatSettings) {
                            learningAvatar(size: avatarSize)
                        }
                        .buttonStyle(.puffSquish)
                        .accessibilityLabel("\(character.displayName)的聊天设置")
                        .accessibilityHint("打开聊天设置")
                        .accessibilityIdentifier("learning.character.settings")
                    } else {
                        learningAvatar(size: avatarSize)
                            .accessibilityHidden(true)
                    }
                    Text(character.displayName)
                        .font(.puff(.title2, Puff.Weight.title))
                        .foregroundStyle(Puff.Palette.ink)
                        .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, -avatarSize / 2)
                .frame(maxWidth: .infinity)
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("learning.character.identity")

                VStack(spacing: 8) {
                    LearningMeter(value: state.characters, total: state.threshold, candy: theme.candy)
                        .frame(maxWidth: 260)
                    Text("\(percentage)% 聊天进度")
                        .font(.puff(.caption, Puff.Weight.label)).monospacedDigit()
                        .foregroundStyle(Puff.Palette.inkSoft)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("练习解锁进度")
                .accessibilityValue("\(percentage)% 聊天进度")
                .accessibilityIdentifier("learning.unlock.progress")

                VStack(spacing: compact ? 12 : 16) {
                    if let journey = model.journey { levelProgress(journey) }
                    Text(challengeStatus(state))
                        .font(.puff(.subheadline, Puff.Weight.label))
                        .foregroundStyle(unlocked ? theme.candy.deep : Puff.Palette.inkSoft)
                        .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                    if unlocked { challengeAction(state) }
                }
            }
            .padding(.horizontal, Puff.Space.l)
            .padding(.bottom, Puff.Space.l)
        }
        .frame(maxWidth: .infinity)
        .puffCard(radius: Puff.Radius.huge)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("learning.challenge.card")
    }
    private func learningAvatar(size: CGFloat) -> some View {
        PuffAvatar(name: character.displayName, size: size,
                   imageName: character.card.avatarAssetName,
                   remoteURL: character.card.avatarRemoteURL.flatMap(URL.init(string:)),
                   candy: theme.candy)
            .padding(5)
            .background(Puff.Palette.card, in: Circle())
    }

    private func challengeAction(_ state: BackendLearningCharacter) -> some View {
        let preparing = model.isPreparing && state.activeAttemptId == nil
        let unavailable = state.activeAttemptId == nil && !model.canStartNewChallenge
        return Button { Task { await model.open() } } label: {
            HStack(spacing: 10) {
                if model.isBusy { ProgressView().controlSize(.small).tint(.white) }
                Text(state.activeAttemptId != nil ? "继续挑战" : unavailable ? "题目准备中" : preparing ? "刷新状态" : "开启单元挑战")
                if !model.isBusy && !unavailable && !preparing {
                    Image(systemName: "arrow.right").font(.subheadline.weight(Puff.Weight.icon)).accessibilityHidden(true)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(PuffCandyButtonStyle(unavailable ? PuffCandy.sky : theme.candy))
        .disabled(model.isBusy || model.isChangingDirection || unavailable)
        .accessibilityLabel(state.activeAttemptId != nil ? "继续挑战" : unavailable ? "暂不可开启新挑战" : preparing ? "刷新状态" : "开启单元挑战")
        .accessibilityIdentifier("learning.start")
    }
    private func challengeStatus(_ state: BackendLearningCharacter) -> String {
        state.activeAttemptId != nil || state.characters >= state.threshold ? "单元练习已解锁" : "单元练习尚未解锁"
    }
    private func levelProgress(_ journey: LearningJourney) -> some View {
        // Keep the completed level visible until its ninth star has landed.
        let progress = journey.levels.first { $0.level == (model.starAward?.level ?? journey.currentLevel) }
        return VStack(spacing: 12) {
            Text(learningLevelName(progress?.level ?? journey.currentLevel))
                .font(.puff(.headline, Puff.Weight.title))
                .fixedSize(horizontal: false, vertical: true)
            journeyStars(journey)
            nextStar(progress)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity, minHeight: 44)
        .foregroundStyle(Puff.Palette.ink)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("learning.level.progress")
        .id("learning.star.destination")
    }
    private func journeyStars(_ journey: LearningJourney) -> some View {
        LearningAchievementStars(earned: model.starAward?.from ?? journey.current?.stars ?? 0, award: displayedStarAward) { model.consumeStarAward($0) }
    }
    private func nextStar(_ current: LearningLevelProgress?) -> some View {
        let complete = (current?.stars ?? 0) >= 9
        let total = max(1, current?.pointsPerStar ?? 60)
        let points = complete ? total : min(total, max(0, current?.currentStarPoints ?? 0))
        let label = complete ? "9 星已达成" : "下一星 \(points)/\(total)分"
        return HStack(spacing: 8) {
            Text(label).font(.puff(.caption2, Puff.Weight.label)).monospacedDigit().foregroundStyle(Puff.Palette.inkSoft)
            LearningMeter(value: points, total: total, candy: .sunny, height: 6)
                .frame(width: 136)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(complete ? label : "下一星")
        .accessibilityValue(complete ? "已全部点亮" : "\(points)/\(total) 积分")
        .accessibilityIdentifier("learning.next-star.progress")
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
                    HStack(spacing: Puff.Space.s) {
                        PuffIconBubble("list.star", candy: theme.candy)
                        Text("挑战记录")
                            .font(.puff(.headline, Puff.Weight.title))
                            .foregroundStyle(Puff.Palette.ink)
                        Image(systemName: historyExpanded ? "chevron.up" : "chevron.down")
                            .font(.caption.weight(Puff.Weight.icon)).foregroundStyle(Puff.Palette.inkFaint)
                    }
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.puffSquish)
                .accessibilityValue(historyExpanded ? "已展开" : "已折叠")
                .accessibilityHint(historyExpanded ? "收起挑战记录" : "展开挑战记录")
                .accessibilityIdentifier("learning.history.toggle")
                Spacer()
                if model.isBusy { ProgressView().controlSize(.small).tint(theme.tint) }
                if historyExpanded && !model.history.isEmpty {
                    historyFilterMenu
                }
            }.frame(minHeight: 44)
            if historyExpanded {
                if let error = model.historyError {
                    LearningPageError(message: error) { Task { await model.retryHistory() } }
                        .padding(.top, 12).disabled(model.isBusy)
                        .accessibilityIdentifier("learning.history.error")
                }
                if items.isEmpty {
                    if model.historyError == nil {
                        Text(historyFilter.isActive
                             ? (model.nextCursor == nil ? "暂无符合筛选的记录" : "已载入的记录中暂无匹配项，可载入更多记录。")
                             : "完成挑战后，在这里回顾。")
                            .font(.puff(.subheadline, Puff.Weight.body)).foregroundStyle(Puff.Palette.inkSoft)
                            .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 20)
                    }
                } else {
                    LazyVStack(spacing: 0) {
                        ForEach(items) { item in
                            Rectangle().fill(Puff.Palette.line).frame(height: 1)
                            historyRow(item)
                        }
                    }
                }
                if model.nextCursor != nil {
                    Button { Task { await model.loadMore() } } label: {
                        Label("更多记录", systemImage: "chevron.down")
                            .font(.puff(.subheadline, Puff.Weight.emphasis))
                            .foregroundStyle(theme.tint)
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.puffSquish)
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
            .font(.puff(.caption, Puff.Weight.label))
            .padding(.leading, 8).frame(minWidth: 44, minHeight: 44)
        }
        .foregroundStyle(historyFilter.isActive ? theme.tint : Puff.Palette.inkSoft)
        .accessibilityLabel("筛选挑战记录")
        .accessibilityValue(historyFilter.isActive ? historyFilter.summary : "未筛选")
        .accessibilityIdentifier("learning.history.filter")
    }
    private func historyRow(_ item: LearningHistory.Item) -> some View {
        let complete = item.firstCompletedAt != nil && item.correctCount == item.questionCount
        return Button { Task { await model.open(item.id) } } label: {
            VStack(alignment: .leading, spacing: 9) {
                Text(item.title).font(.puff(.subheadline, Puff.Weight.title))
                    .foregroundStyle(Puff.Palette.ink)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                    .multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
                Text("\(historyDate(item)) · \(learningLevelName(item.level))")
                    .font(.puff(.caption, Puff.Weight.label)).foregroundStyle(Puff.Palette.inkSoft)
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
                    Image(systemName: "chevron.right").font(.caption2.weight(Puff.Weight.icon))
                        .foregroundStyle(Puff.Palette.inkFaint).accessibilityHidden(true)
                }
            }
            .padding(.vertical, 17).padding(.horizontal, 6).frame(maxWidth: .infinity, minHeight: 78, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.puffRow).disabled(model.isBusy)
        .accessibilityLabel("\(item.title)，\(historyDate(item))，\(learningLevelName(item.level))，答对 \(item.correctCount)/\(item.questionCount)，\(historyPointsText(item))，\(historyActionLabel(item))")
        .accessibilityHint(complete ? "查看挑战" : item.firstCompletedAt == nil ? "继续挑战" : "补答剩余题目")
        .accessibilityIdentifier("learning.history.\(item.id.uuidString)")
    }
    private func historyMetadata(_ item: LearningHistory.Item) -> some View {
        (Text("答对 \(item.correctCount)/\(item.questionCount)")
            .foregroundColor(LearningAccuracyBand(correct: item.correctCount, total: item.questionCount).tint)
         + Text(" · \(historyActionLabel(item))").foregroundColor(Puff.Palette.inkSoft))
            .font(.puff(.caption, Puff.Weight.label)).monospacedDigit()
    }
    private func historyPoints(_ item: LearningHistory.Item) -> some View {
        Text(historyPointsText(item)).font(.puff(.subheadline, Puff.Weight.emphasis)).monospacedDigit()
            .foregroundStyle((item.earnedPoints ?? 0) > 0 ? LearningTheme.rewardTint : Puff.Palette.inkSoft)
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

/// 糖果色进度条：浅灰底槽 + 彩色填充，填充端是圆头。
private struct LearningMeter: View {
    let value: Int
    let total: Int
    let candy: PuffCandy
    var height: CGFloat = 14
    var body: some View {
        GeometryReader { geometry in
            let fraction = min(1, max(0, Double(value) / Double(max(1, total))))
            Capsule().fill(Puff.Palette.cloud)
                .overlay(alignment: .leading) {
                    Capsule().fill(candy.base)
                        .frame(width: max(fraction > 0 ? height : 0, geometry.size.width * fraction))
                }
        }.frame(height: height)
    }
}

struct LearningPageError: View {
    let message: String
    let retry: () -> Void
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(PuffCandy.tangerine.deep).accessibilityHidden(true)
            Text(message).font(.puff(.subheadline, Puff.Weight.label))
                .foregroundStyle(Puff.Palette.ink)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button(action: retry) {
                Image(systemName: "arrow.clockwise").font(.body.weight(Puff.Weight.icon)).frame(width: 44, height: 44)
            }
            .buttonStyle(.puffSquish)
            .foregroundStyle(PuffCandy.tangerine.deep)
            .accessibilityLabel("重新载入")
        }
        .padding(.leading, 16).padding(.trailing, 4).padding(.vertical, 8)
        .background(PuffCandy.tangerine.wash, in: RoundedRectangle(cornerRadius: Puff.Radius.large, style: .continuous))
    }
}
