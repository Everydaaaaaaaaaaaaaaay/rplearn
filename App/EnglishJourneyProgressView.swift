import PersistenceKit
import SwiftUI

/// 放在“英语旅程”的账号级学习进度与唯一主线，独立于任何角色。
struct EnglishJourneyProgressView: View {
    let environment: AppEnvironment
    let selectedDifficulty: DifficultyLevel
    @State private var model: UnitLearningModel?

    var body: some View {
        Group {
            if let progress = model?.globalProgress {
                VStack(alignment: .leading, spacing: 16) {
                    levelCard(progress)
                    mainlineCard(progress)
                }
            } else if let error = model?.globalError {
                ContentUnavailableView {
                    Label("学习进度暂不可用", systemImage: "wifi.exclamationmark")
                } description: {
                    Text(error)
                } actions: {
                    Button("重试") { Task { await model?.refreshGlobal() } }
                }
            } else if model == nil {
                ContentUnavailableView("登录后查看学习进度", systemImage: "person.crop.circle")
            } else {
                ProgressView("正在读取学习进度")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 28)
            }
        }
        .task {
            model = environment.unitLearning()
            await model?.refreshGlobal()
        }
        .onChange(of: model?.currentGrade) { _, _ in
            guard let model, model.globalProgress == nil else { return }
            Task { await model.refreshGlobal() }
        }
    }

    private func levelCard(_ progress: UnitLearningGlobalProgress) -> some View {
        VStack(alignment: .leading, spacing: 13) {
            Label("全局英语水平", systemImage: "star.circle")
                .font(.headline)
            Text(UnitLearningGrade.name(progress.grade))
                .font(.title2.bold())
            Text("本级答对 \(progress.gradeCorrect) / \(progress.gradeTarget) 道新题")
                .font(.subheadline.monospacedDigit())
            HStack(spacing: 5) {
                ForEach(0..<progress.starsPerGrade, id: \.self) { index in
                    Image(systemName: index < progress.stars ? "star.fill" : "star")
                        .foregroundStyle(index < progress.stars ? .yellow : .secondary)
                        .frame(maxWidth: .infinity)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("本级九颗星，已点亮 \(progress.stars) 颗")
            Text("每答对 \(progress.correctPerStar) 道新题点亮一颗星；九颗星后升一级。所有角色的挑战共同推进这一水平。")
                .font(.caption)
                .foregroundStyle(.secondary)
            if [.kindergarten, .undergraduate, .postgraduate, .advanced].contains(selectedDifficulty) {
                Text("聊天使用\(selectedDifficulty.displayName)档；当前单元题库覆盖小一至高三，这一档按\(UnitLearningGrade.name(progress.grade))练习。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 20))
        .accessibilityIdentifier("englishJourney.globalLevel")
    }

    private func mainlineCard(_ progress: UnitLearningGlobalProgress) -> some View {
        let unlocked = UnitLearningMainline.scenes.filter {
            $0.requiredCompletedLevels <= progress.completedLevels
        }
        let next = UnitLearningMainline.scenes.first {
            $0.requiredCompletedLevels > progress.completedLevels
        }
        return VStack(alignment: .leading, spacing: 13) {
            Text("旅行册 · 主线剧情").font(.title3.bold())
            Text("一条全局剧情。只有通过挑战完成年级进阶，才能解锁下一章；直接调整水平不会跳过章节。")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            ForEach(unlocked.reversed()) { scene in
                NavigationLink {
                    UnitLearningMainlineView(scene: scene)
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "book.pages.fill")
                            .foregroundStyle(.teal)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(scene.title).font(.headline)
                            Text(scene.setup).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 4)
                        Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
                    }
                    .padding(13)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
                }
                .buttonStyle(.plain)
            }
            if let next {
                Label("下一章：\(next.title) · 再完成 \(next.requiredCompletedLevels - progress.completedLevels) 次年级进阶", systemImage: "lock")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 20))
        .accessibilityIdentifier("englishJourney.mainline")
    }
}
