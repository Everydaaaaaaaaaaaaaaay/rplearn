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
                    BrandMascotView(pose: .celebrate, size: 104, showsShadow: true)
                    VStack(spacing: 8) {
                        Text("测评完成").font(.subheadline.weight(.semibold)).foregroundStyle(Color.dsSkyDeep)
                        Text(result.hasSufficientEvidence ? result.difficultyLevel.displayName : "还需要一些作答信息")
                            .font(.system(.title, design: .rounded, weight: .bold))
                            .multilineTextAlignment(.center)
                        Text("已答 \(result.answeredCount) 题 · 正确 \(result.correctCount) 题 · 跳过 \(result.skippedCount) 题")
                            .font(.caption).foregroundStyle(Color.dsPaperInkSecondary)
                        if result.stopReason == .threeMistakes {
                            Text("累计答错 3 次，本次测评已结束。")
                                .font(.subheadline).foregroundStyle(Color.dsPaperInkSecondary)
                        }

                        Text(result.hasSufficientEvidence
                        ? (result.answeredCount < 8
                           ? "本次题量较少，这是一个初步的学习起点建议。先从合适的内容开始，之后可以再调整。"
                           : "建议从这个难度开始学习。结果只用于安排学习内容，你也可以按实际体验调整。")
                        : "本次有效作答较少，暂不推荐新水平。你可以沿用当前水平，也可以手动调整。")
                        .font(.subheadline).foregroundStyle(Color.dsPaperInkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    }
                    .placementPaperPanel()
                    .accessibilityIdentifier("placement.result")
                    VStack(spacing: DSSpacing.md) {
                        ForEach(result.skillResults) { skillResultRow($0) }
                    }.placementPaperPanel(padding: DSSpacing.lg)
                    DSWorkbenchPaperSheet(padding: 0) {
                        levelSelectionButton(title: "最终应用水平",
                            detail: result.hasSufficientEvidence ? "可采用建议，也可以自行选择。" : "当前水平未改变，可自行选择。",
                            recommendedLevel: result.hasSufficientEvidence ? result.difficultyLevel : nil)
                    }
                    Text("这是学习难度建议，不代表学历或任何考试认证。")
                        .font(.footnote).foregroundStyle(Color.dsPaperInkSecondary)
                }
                .frame(maxWidth: 560).padding(DSSpacing.lg).frame(maxWidth: .infinity)
            }
            .placementScrollEdgeBlend()
            .safeAreaInset(edge: .bottom, spacing: 0) {
                VStack(spacing: DSSpacing.sm) {
                    if let errorMessage {
                        Text(errorMessage).font(.caption).foregroundStyle(Color.dsDanger)
                    }
                    Button { applySelectedLevel(testResult: result) } label: {
                        if isApplying { ProgressView().tint(.white) }
                        else { Text("应用\(selectedLevel.displayName)") }
                    }
                    .buttonStyle(.dsWorkbenchAction)
                    .accessibilityIdentifier("placement.apply")
                    Button("重新测评") { start() }
                        .buttonStyle(.dsAction(.secondary, fullWidth: true))
                        .accessibilityIdentifier("placement.restart")
                }
                .disabled(isApplying)
                .frame(maxWidth: 560)
                .padding(.horizontal, DSSpacing.lg)
                .padding(.vertical, DSSpacing.sm)
                .frame(maxWidth: .infinity)
                .background(.regularMaterial)
            }
        } else { loadingView }
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
        .accessibilityIdentifier("placement.chooseLevel")
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
        .disabled(currentQuestion?.skill == .listening && listeningPlayCount == 0)
        .accessibilityIdentifier("placement.option.\(originalIndex)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityRemoveTraits(isSelected ? [] : .isSelected)
    }

    func skillResultRow(_ result: PlacementSkillResult) -> some View {
        HStack(spacing: DSSpacing.sm) {
            Label(result.skill.displayName, systemImage: skillIcon(result.skill))
                .font(.subheadline.weight(.semibold))
                .frame(width: 118, alignment: .leading)
            if result.total > 0 {
                ProgressView(value: result.accuracy).tint(.dsSky)
            } else { Spacer() }
            Text(result.total > 0 ? "\(result.correct)/\(result.total)" : "未作答")
                .font(.caption.monospacedDigit())
                .foregroundStyle(Color.dsPaperInkSecondary)
                .frame(width: 48, alignment: .trailing)
        }
    }

    func prepareIfNeeded() async {
        guard !hasPrepared else { return }
        hasPrepared = true
        await prepare(force: false)
        if startsWithLevelSelection && phase == .introduction { openLevelSelection() }
    }

    func prepare(force: Bool) async {
        if force {
            questions = []
            session = nil
            questionBankError = nil
            phase = .loading
        }
        do {
            let profile = try await deps.economyStore.profile()
            currentLevel = profile.difficultyLevel
            selectedLevel = profile.difficultyLevel
            do {
                let questionBankURL = deps.questionBankURL
                // 文件读取、JSON 解码和完整题库校验不占用主线程。
                questions = try await Task.detached(priority: .userInitiated) {
                    try PlacementQuestionBank.load(from: questionBankURL)
                }.value
                session = PlacementSession(questions: questions, priorLevel: profile.difficultyLevel)
                questionBankError = nil
            } catch {
                questions = []
                session = nil
                questionBankError = "测试题库暂时无法载入，你仍可直接选择并应用水平。"
            }
            errorMessage = nil
            if startsWithQuestions {
                if !questions.isEmpty { start() }
                else { phase = .introduction }
                return
            }
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
        guard !questions.isEmpty else { errorMessage = "题库暂时不可用，请重新载入或直接选择水平。"; return }
        stopQuestionAudio()
        session = PlacementSession(questions: questions, priorLevel: currentLevel)
        guard session?.current != nil else { return }
        result = nil; errorMessage = nil
        withAnimation(reduceMotion ? nil : .snappy) { phase = .question }
    }

    func select(_ originalIndex: Int) {
        session?.select(originalIndex)
        Haptics.impact(.light)
    }

    func previousQuestion() {
        guard session?.canGoBack == true else { return }
        stopQuestionAudio()
        session?.goBack()
    }

    func advanceQuestion(skipping: Bool) {
        guard var updated = session else { return }
        if skipping { updated.skip() }
        else { guard updated.confirm() else { return } }
        stopQuestionAudio()
        session = updated
        if updated.isComplete {
            let outcome = updated.engine.result()
            result = outcome
            selectedLevel = outcome.hasSufficientEvidence ? outcome.difficultyLevel : currentLevel
            withAnimation(reduceMotion ? nil : .snappy) { phase = .result }
        }
    }

    func stopQuestionAudio() {
        listeningGeneration = UUID()
        listeningPlayer.stop()
        isListeningAudioLoading = false; isListeningAudioPlaying = false
        errorMessage = nil
    }

    func playListeningQuestion(_ question: PlacementQuestion) {
        guard PlacementListeningPolicy.canPlay(currentCount: listeningPlayCount),
              !isListeningAudioLoading, let text = question.audioText else { return }
        isListeningAudioLoading = true
        let generation = listeningGeneration
        Task {
            await deps.speech.stopSpeaking()
            guard generation == listeningGeneration, currentQuestion?.id == question.id else { return }
            listeningPlayer.play(text: text, question: question.prompt, completedPlays: listeningPlayCount, started: {
                guard generation == listeningGeneration, currentQuestion?.id == question.id else { return }
                isListeningAudioPlaying = true
                Haptics.impact(.light)
            }, completed: { success in
                guard generation == listeningGeneration, currentQuestion?.id == question.id else { return }
                isListeningAudioLoading = false; isListeningAudioPlaying = false
                if success { session?.recordListeningPlay() }
                else { errorMessage = "听力音频暂时无法播放，可以重试或跳过本题。" }
            })
        }
    }

    func applySelectedLevel(testResult: PlacementResult?) {
        let preserveSource = testResult?.hasSufficientEvidence == false
        let testResult = testResult.flatMap { $0.hasSufficientEvidence ? $0 : nil }
        let level = selectedLevel
        guard level != currentLevel else {
            saveSelectedLevel(level: level, testResult: testResult, preserveSource: preserveSource)
            return
        }
        isApplying = true; errorMessage = nil
        Task {
            defer { isApplying = false }
            do {
                let summary = try await deps.levelChangeSummary(level)
                pendingLevelChange = PendingLevelChange(level: level, result: testResult,
                    summary: "从\(currentLevel.displayName)切换到\(level.displayName)。\n\n新对话和之后开启的挑战会采用新难度；已经开启的挑战保持原有难度。\n\n\(summary)\n\n切换不会赠送学习点数或星星。")
                showLevelChangeConfirmation = true
            } catch { errorMessage = "暂时无法确认目标水平的进度，请联网后重试。当前水平没有改变。" }
        }
    }

    func saveSelectedLevel(level: DifficultyLevel, testResult: PlacementResult?, preserveSource: Bool = false) {
        isApplying = true
        errorMessage = nil
        Task {
            do {
                let updated = try await deps.profileCommands.updateProfile { profile in
                    if profile.difficultyLevel != level || !preserveSource {
                        profile.proficiencySource = testResult?.difficultyLevel == level
                            ? .placement
                            : .selfReported
                    }
                    profile.difficultyLevel = level
                    if let testResult {
                        profile.placementScore = testResult.score
                        profile.placementCompletedAt = .now
                    }
                }
                isApplying = false
                Haptics.notify(.success)
                if usesNativeNavigation {
                    currentLevel = updated.difficultyLevel
                    selectedLevel = updated.difficultyLevel
                    session = questions.isEmpty ? nil : PlacementSession(questions: questions, priorLevel: updated.difficultyLevel)
                    phase = .introduction
                }
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
