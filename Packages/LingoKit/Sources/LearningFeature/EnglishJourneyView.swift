import BackendKit
import DesignSystem
import DomainKit
import PersistenceKit
import SwiftUI

/// 全局水平与剧情只读取服务端状态；调整水平由 App 接入既有档案流程。
public struct EnglishJourneyView: View {
    private let learning: any LearningServing
    private let mainline: any MainlineServing
    private let onChooseLevel: () -> Void
    private let onCalibrate: () -> Void
    private let onOpenChapter: (MainlineChapter) -> Void
    @State private var journey: LearningJourney?
    @State private var route: BackendMainlineProgress?
    @State private var error: String?
    @State private var isLoading = false
    @Environment(\.scenePhase) private var scenePhase

    public init(learning: any LearningServing, mainline: any MainlineServing,
                onChooseLevel: @escaping () -> Void, onCalibrate: @escaping () -> Void,
                onOpenChapter: @escaping (MainlineChapter) -> Void) {
        self.learning = learning; self.mainline = mainline
        self.onChooseLevel = onChooseLevel; self.onCalibrate = onCalibrate; self.onOpenChapter = onOpenChapter
    }
    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                VStack(alignment: .leading, spacing: 10) {
                    Label("每一段对话，都通向远方", systemImage: "sparkles").font(.caption.weight(.medium)).foregroundStyle(Color.dsSkyDeep)
                    Text("把学会的，\n带去下一站。").font(.system(.largeTitle, design: .serif).weight(.semibold))
                    Text("旅伴各有自己的挑战，你的英语旅程只有一条。").font(.subheadline).foregroundStyle(.secondary)
                }.padding(.vertical, 12)
                if let error { LearningErrorBanner(message: error) { Task { await load() } } }
                if let journey, let progress = journey.current {
                    levelCard(journey, progress: progress)
                    if let route { routeCard(route) }
                    pastLevels(journey)
                } else if isLoading { ProgressView("正在载入英语旅程…").frame(maxWidth: .infinity).padding(50) }
            }.padding(22).frame(maxWidth: 680).frame(maxWidth: .infinity)
        }
        .background(Color.dsBackground).tint(.dsSkyDeep)
        .navigationTitle("英语旅程").navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .task { await load() }.refreshable { await load() }
        .onChange(of: scenePhase) { _, value in if value == .active { Task { await load() } } }
        .accessibilityIdentifier("learning.journey")
    }
    private func levelCard(_ journey: LearningJourney, progress: LearningLevelProgress) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("当前英语水平").font(.caption).foregroundStyle(.secondary)
                    Text(learningLevelName(journey.currentLevel)).font(.title.bold())
                }
                Spacer()
                Image(systemName: "book.closed.fill").font(.title).foregroundStyle(Color.dsSkyDeep)
                    .padding(14).background(Color.dsSkyDeep.opacity(0.09), in: RoundedRectangle(cornerRadius: 16)).rotationEffect(.degrees(8))
            }
            LearningStars(earned: progress.stars, tint: .dsSkyDeep)
            ProgressView(value: Double(progress.currentStarPoints), total: Double(progress.pointsPerStar)).tint(.dsSkyDeep)
            HStack {
                Text(progress.stars == 9 ? "九星里程碑已达成" : "向第 \(progress.stars + 1) 颗星出发").font(.subheadline.weight(.semibold))
                Spacer()
                Text("\(progress.currentStarPoints) / \(progress.pointsPerStar)").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
            Text("每道首次答对的题积累 1 点，60 点点亮一颗星。补答可获得遗漏的点数。九颗星之后，还需要完成本级学习目标与迁移挑战，才可进阶。")
                .font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Divider()
            ViewThatFits(in: .horizontal) {
                HStack { levelButton; Spacer(); calibrationButton }
                VStack(alignment: .leading) { levelButton; calibrationButton }
            }
        }.modifier(LearningPaper())
    }
    private var levelButton: some View {
        Button("调整英语水平", systemImage: "slider.horizontal.3", action: onChooseLevel)
            .font(.subheadline.weight(.semibold)).padding(.vertical, 10).accessibilityIdentifier("learning.changeLevel")
    }
    private var calibrationButton: some View {
        Button("做一次水平校准", action: onCalibrate).font(.subheadline).padding(.vertical, 10)
    }
    private func routeCard(_ route: BackendMainlineProgress) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .firstTextBaseline) {
                Text("故事的下一站").font(.title2.bold())
                Spacer()
                Label("累计 \(route.earnedStars)", systemImage: "star.fill").font(.caption.weight(.semibold)).foregroundStyle(Color.dsSkyDeep)
            }
            Text("不同年级获得的星星共同开启主线。调整水平不会增加星星；已完成的故事随时可以重温。")
                .font(.subheadline).foregroundStyle(.secondary)
            ForEach(route.chapters) { item in
                if let chapter = MainlineCatalog.chapters.first(where: { $0.regionID == item.regionId }) {
                    Button { onOpenChapter(chapter) } label: {
                        HStack(alignment: .top, spacing: 15) {
                            ZStack {
                                Circle().fill(item.canOpen ? Color.dsSkyDeep.opacity(0.13) : Color.secondary.opacity(0.08))
                                Image(systemName: item.state == "completed" ? "checkmark" : item.canOpen ? "play.fill" : "lock.fill")
                                    .font(.subheadline.weight(.semibold)).foregroundStyle(item.canOpen ? Color.dsSkyDeep : .secondary)
                            }.frame(width: 42, height: 42)
                            VStack(alignment: .leading, spacing: 7) {
                                Text("第 \(item.sequence) 站 · \(chapter.title)").font(.headline)
                                Text(chapter.subtitle).font(.caption).foregroundStyle(.secondary)
                                Text(item.statusText).font(.caption.weight(.semibold)).foregroundStyle(Color.dsSkyDeep)
                                if item.state == "locked" { Text("累计 \(item.requiredStars) 星 · 完成前一章").font(.caption2).foregroundStyle(.secondary) }
                            }
                            Spacer(minLength: 0)
                        }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                    }.buttonStyle(LearningPressStyle()).foregroundStyle(.primary).disabled(!item.canOpen)
                        .padding(.vertical, 8)
                    if item.sequence < route.chapters.count { Divider().padding(.leading, 57) }
                }
            }
        }.modifier(LearningPaper())
    }
    @ViewBuilder private func pastLevels(_ journey: LearningJourney) -> some View {
        let levels = journey.levels.filter { $0.points > 0 && $0.level != journey.currentLevel }
        if !levels.isEmpty {
            VStack(alignment: .leading, spacing: 16) {
                Text("走过的里程碑").font(.title2.bold())
                ForEach(levels, id: \.level) { level in
                    HStack { Text(learningLevelName(level.level)); Spacer(); Text("\(level.stars) 星 · \(level.points) 点").foregroundStyle(.secondary) }
                }
                Text("换过的水平分别保留进度，回来时从这里继续。").font(.caption).foregroundStyle(.secondary)
            }.modifier(LearningPaper())
        }
    }
    private func load() async {
        guard !isLoading else { return }
        isLoading = true; defer { isLoading = false }
        do {
            async let progress = learning.learningJourney()
            async let mainlineProgress = mainline.mainlineProgress()
            let (nextJourney, nextRoute) = try await (progress, mainlineProgress)
            journey = nextJourney; route = nextRoute; error = nil
        } catch { self.error = "旅程暂时无法更新，请联网后重试。" }
    }
}
