import CoreKit
import DesignSystem
import DomainKit
import PersistenceKit
import SpeechKit
import SwiftUI

extension PlacementTestView {
    @ViewBuilder
    var resultView: some View {
        if let result {
            ScrollView {
                VStack(spacing: DSSpacing.lg) {
                    BrandMascotView(
                        pose: .celebrate,
                        size: 112,
                        showsShadow: true
                    )

                    VStack(spacing: 5) {
                        Text("校准完成")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color.dsSkyDeep)
                        Text(result.difficultyLevel.displayName)
                            .font(.system(.largeTitle, design: .rounded, weight: .bold))
                        Text("完成 \(result.answeredCount) 道 · 测试建议水平")
                            .font(.caption)
                            .foregroundStyle(Color.dsPaperInkSecondary)
                    }

                    VStack(spacing: DSSpacing.md) {
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text("综合校准")
                                    .font(.caption)
                                    .foregroundStyle(Color.dsPaperInkSecondary)
                                Text("\(result.score) / 100")
                                    .font(.title2.bold().monospacedDigit())
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 3) {
                                Text("90% 估计区间")
                                    .font(.caption)
                                    .foregroundStyle(Color.dsPaperInkSecondary)
                                Text("\(result.scoreRange.lowerBound)–\(result.scoreRange.upperBound)")
                                    .font(.headline.monospacedDigit())
                            }
                        }

                        Divider()

                        HStack {
                            Label("判断稳定度", systemImage: "checkmark.seal")
                                .font(.subheadline.weight(.semibold))
                            Spacer()
                            Text(
                                "\(result.confidenceLabel) · "
                                    + "\(Int((result.levelConfidence * 100).rounded()))%"
                            )
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(Color.dsSkyDeep)
                        }

                        HStack {
                            Label("CSE 参考", systemImage: "flag")
                                .font(.subheadline.weight(.semibold))
                            Spacer()
                            Text("\(result.difficultyLevel.cseReference) · 非认证")
                                .font(.subheadline)
                                .foregroundStyle(Color.dsPaperInkSecondary)
                        }

                        HStack {
                            Label("CEFR 辅助参考", systemImage: "globe.europe.africa")
                                .font(.subheadline.weight(.semibold))
                            Spacer()
                            Text("\(result.referenceLevel.rawValue) · 非认证")
                                .font(.subheadline)
                                .foregroundStyle(Color.dsPaperInkSecondary)
                        }

                        Divider()

                        ForEach(result.skillResults) { skillResult in
                            skillResultRow(skillResult)
                        }
                    }
                    .placementPaperPanel(padding: DSSpacing.lg)

                    DSWorkbenchPaperSheet(padding: 0) {
                        levelSelectionButton(
                            title: "最终应用水平",
                            detail: selectedLevel == result.difficultyLevel
                                ? "当前采用测试建议；你也可以自由选择其他水平。"
                                : "你选择了不同于测试建议的水平。",
                            recommendedLevel: result.difficultyLevel
                        )
                    }

                    Text(
                        "年级结果表示人教版一年级起点教材的学习进度估计；四六级结果表示相近学习难度。"
                            + "这是用于调整学习内容的短测，不代表通过任何官方考试。"
                            + "测试结果只是建议，最终应用哪个水平由你决定，也可以稍后再次修改。"
                    )
                        .font(.footnote)
                        .foregroundStyle(Color.dsPaperInkSecondary)
                        .fixedSize(horizontal: false, vertical: true)

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundStyle(Color.dsDanger)
                    }

                    Button {
                        applySelectedLevel(testResult: result)
                    } label: {
                        if isApplying {
                            ProgressView().tint(.white)
                        } else {
                            Text("应用 \(selectedLevel.displayName)")
                        }
                    }
                    .buttonStyle(.dsWorkbenchAction)
                    .disabled(isApplying)
                }
                .frame(maxWidth: 560)
                .padding(DSSpacing.lg)
                .frame(maxWidth: .infinity)
            }
            .placementScrollEdgeBlend()
        } else {
            loadingView
        }
    }

    var failureView: some View {
        VStack(spacing: DSSpacing.md) {
            Image(systemName: "exclamationmark.triangle")
                .font(.largeTitle)
                .foregroundStyle(Color.dsSunset)
            Text("校准页暂时无法载入")
                .font(.title3.bold())
            Text(errorMessage ?? "请稍后再试。")
                .font(.subheadline)
                .foregroundStyle(Color.dsPaperInkSecondary)
            Button("重新载入") {
                Task { await prepare(force: true) }
            }
            .buttonStyle(.dsAction(.secondary, fullWidth: false))
        }
        .padding(DSSpacing.lg)
        .placementPaperPanel(padding: 0)
        .padding(DSSpacing.lg)
    }

    func informationRow(
        icon: String,
        title: String,
        detail: String
    ) -> some View {
        HStack(spacing: DSSpacing.sm) {
            Image(systemName: icon)
                .foregroundStyle(Color.dsSkyDeep)
                .frame(width: 34, height: 34)
                .background(Color.dsSky.opacity(0.1), in: RoundedRectangle(cornerRadius: 9))
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(Color.dsPaperInkSecondary)
            }
            Spacer()
        }
        .padding(DSSpacing.sm)
    }

    func levelSelectionButton(
        title: String,
        detail: String,
        recommendedLevel: DifficultyLevel?
    ) -> some View {
        Button {
            openLevelSelection()
        } label: {
            HStack(spacing: DSSpacing.md) {
                Image(systemName: "gauge.with.dots.needle.33percent")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Color.dsSkyDeep)
                    .frame(width: 42, height: 42)
                    .background(Color.dsSky.opacity(0.1), in: RoundedRectangle(cornerRadius: 11))

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.caption)
                        .foregroundStyle(Color.dsPaperInkSecondary)
                    Text(selectedLevel.displayName)
                        .font(.headline)
                        .foregroundStyle(Color.dsPaperInk)
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(Color.dsPaperInkSecondary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: DSSpacing.xs)
                VStack(alignment: .trailing, spacing: 5) {
                    if recommendedLevel == selectedLevel {
                        Text("测试建议")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(Color.dsSkyDeep)
                    }
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.dsPaperInkSecondary)
                }
            }
            .padding(DSSpacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title)，当前选择 \(selectedLevel.displayName)")
        .accessibilityHint("打开全部英语水平列表")
    }

    func openLevelSelection() {
        levelSelectionReturnPhase = phase == .result ? .result : .introduction
        withAnimation(reduceMotion ? nil : .snappy) {
            phase = .levelSelection
        }
    }

    func closeLevelSelection() {
        withAnimation(reduceMotion ? nil : .snappy) {
            phase = levelSelectionReturnPhase
        }
    }

    func optionButton(
        _ text: String,
        originalIndex: Int
    ) -> some View {
        let isSelected = selectedOriginalIndex == originalIndex
        return Button {
            select(originalIndex)
        } label: {
            HStack(spacing: DSSpacing.sm) {
                Text(optionLetter(for: originalIndex))
                    .font(.caption.bold())
                    .foregroundStyle(isSelected ? .white : Color.dsSkyDeep)
                    .frame(width: 28, height: 28)
                    .background(isSelected ? Color.dsSky : Color.dsSky.opacity(0.1), in: Circle())
                Text(text)
                    .font(.body)
                    .foregroundStyle(Color.dsPaperInk)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
            }
            .padding(DSSpacing.md)
            .frame(maxWidth: .infinity, minHeight: 58, alignment: .leading)
            .background(
                isSelected ? Color.dsSky.opacity(0.14) : Color.dsPaperInk.opacity(0.045),
                in: RoundedRectangle(cornerRadius: DSRadius.inline)
            )
            .overlay {
                RoundedRectangle(cornerRadius: DSRadius.inline)
                    .stroke(
                        isSelected ? Color.dsSky.opacity(0.45) : Color.dsPaperInk.opacity(0.08),
                        lineWidth: 0.8
                    )
            }
        }
        .buttonStyle(.plain)
        .disabled(
            selectedOriginalIndex != nil
                || (currentQuestion?.skill == .listening && listeningPlayCount == 0)
        )
    }

    func skillResultRow(_ result: PlacementSkillResult) -> some View {
        HStack(spacing: DSSpacing.sm) {
            Label(result.skill.displayName, systemImage: skillIcon(result.skill))
                .font(.subheadline.weight(.semibold))
                .frame(width: 118, alignment: .leading)
            ProgressView(value: result.accuracy)
                .tint(.dsSky)
            Text("\(result.correct)/\(result.total)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(Color.dsPaperInkSecondary)
                .frame(width: 34, alignment: .trailing)
        }
    }

    func prepareIfNeeded() async {
        guard questions.isEmpty else { return }
        await prepare(force: false)
    }

    func prepare(force: Bool) async {
        if force {
            questions = []
            engine = nil
            questionBankError = nil
            phase = .loading
        }
        do {
            let profile = try await deps.economyStore.profile()
            currentLevel = profile.difficultyLevel
            selectedLevel = profile.difficultyLevel
            do {
                questions = try PlacementQuestionBank.load(from: deps.questionBankURL)
                engine = AdaptivePlacementEngine(priorLevel: profile.difficultyLevel)
                questionBankError = nil
            } catch {
                questions = []
                engine = nil
                questionBankError = "测试题库暂时无法载入，你仍可直接选择并应用水平。"
            }
            errorMessage = nil
            #if DEBUG
            if ProcessInfo.processInfo.environment["UI_TEST_PLACEMENT_QUESTION"] == "1" {
                start()
                return
            }
            let initialPhase: Phase =
                ProcessInfo.processInfo.environment["UI_TEST_PLACEMENT_LEVEL_SELECTION"] == "1"
                    ? .levelSelection
                    : .introduction
            #else
            let initialPhase: Phase = .introduction
            #endif
            withAnimation(reduceMotion ? nil : .snappy) {
                phase = initialPhase
            }
        } catch {
            errorMessage = "学习档案暂时无法载入，请稍后再试。"
            phase = .failure
        }
    }

    func start() {
        guard let engine,
              let question = engine.nextQuestion(in: questions)
        else { return }
        currentQuestion = question
        optionOrder = Array(question.options.indices).shuffled()
        selectedOriginalIndex = nil
        listeningPlayCount = 0
        withAnimation(reduceMotion ? nil : .snappy) {
            phase = .question
        }
    }

    func select(_ originalIndex: Int) {
        guard selectedOriginalIndex == nil,
              let question = currentQuestion,
              var updatedEngine = engine
        else { return }
        selectedOriginalIndex = originalIndex
        listeningPlayer.stop()
        Haptics.impact(.light)
        Task { await deps.speech.stopSpeaking() }

        Task {
            if !reduceMotion {
                try? await Task.sleep(for: .milliseconds(220))
            }
            updatedEngine.record(question: question, selectedIndex: originalIndex)
            engine = updatedEngine
            if updatedEngine.shouldStop
                || updatedEngine.nextQuestion(in: questions) == nil
            {
                result = updatedEngine.result()
                selectedLevel = result?.difficultyLevel ?? currentLevel
                await deps.speech.stopSpeaking()
                withAnimation(reduceMotion ? nil : .snappy) {
                    phase = .result
                }
                return
            }
            guard let next = updatedEngine.nextQuestion(in: questions) else { return }
            withAnimation(reduceMotion ? nil : .snappy) {
                currentQuestion = next
                optionOrder = Array(next.options.indices).shuffled()
                selectedOriginalIndex = nil
                listeningPlayCount = 0
            }
        }
    }

    func playListeningQuestion(_ question: PlacementQuestion) {
        guard PlacementListeningPolicy.canPlay(currentCount: listeningPlayCount),
              !isListeningAudioLoading,
              let audioAssetName = question.audioAssetName
        else { return }
        isListeningAudioLoading = true
        Task {
            await deps.speech.stopSpeaking()
            let didStart = await listeningPlayer.play(assetName: audioAssetName)
            guard currentQuestion?.id == question.id else {
                isListeningAudioLoading = false
                return
            }
            if didStart {
                listeningPlayCount += 1
                Haptics.impact(.light)
            } else {
                errorMessage = "听力音频暂时无法播放，请重试。"
            }
            isListeningAudioLoading = false
        }
    }

    func applySelectedLevel(testResult: PlacementResult?) {
        let level = selectedLevel
        isApplying = true
        errorMessage = nil
        Task {
            do {
                let updated = try await deps.profileCommands.updateProfile { profile in
                    profile.difficultyLevel = level
                    profile.proficiencySource = testResult?.difficultyLevel == level
                        ? .placement
                        : .selfReported
                    if let testResult {
                        profile.placementScore = testResult.score
                        profile.placementCompletedAt = .now
                    }
                }
                isApplying = false
                Haptics.notify(.success)
                onComplete(updated)
            } catch {
                isApplying = false
                errorMessage = "所选英语水平暂时保存失败，请再试一次。"
            }
        }
    }

    func skillIcon(_ skill: PlacementSkill) -> String {
        switch skill {
        case .vocabulary: "textformat.abc"
        case .grammar: "character.cursor.ibeam"
        case .reading: "doc.text"
        case .listening: "headphones"
        }
    }

    func optionLetter(for originalIndex: Int) -> String {
        guard let presentedIndex = optionOrder.firstIndex(of: originalIndex) else { return "" }
        return String(UnicodeScalar(65 + presentedIndex)!)
    }
}
