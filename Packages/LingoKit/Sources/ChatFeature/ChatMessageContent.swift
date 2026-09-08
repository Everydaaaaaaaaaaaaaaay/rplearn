import CoreKit
import DesignSystem
import DictKit
import DomainKit
import Foundation
import LLMKit
import PersistenceKit
import SpeechKit
import SwiftUI
import Translation

extension ChatView {
// MARK: - 教练纠错

    @ViewBuilder
    func userMessageBubble(
        _ message: MessageDTO,
        groupPosition: MessageBubbleGroupPosition
    ) -> some View {
        if CoachService.decode(fromJSON: message.coachReviewJSON)?.hasIssues == true {
            MessageBubble(
                side: .outgoing,
                groupPosition: groupPosition,
                leadingAccessory: { coachButton(message) },
                contextMenu: { bubbleMenu(message) }
            ) {
                tappableText(message, textColor: .white)
            }
        } else {
            MessageBubble(
                side: .outgoing,
                groupPosition: groupPosition,
                contextMenu: { bubbleMenu(message) }
            ) {
                tappableText(message, textColor: .white)
            }
        }
    }

    /// 紧贴用户气泡中线的纠错入口；可见尺寸克制，触控区域保持 44pt。
    func coachButton(_ message: MessageDTO) -> some View {
        let isExpanded = expandedCoachMessageIDs.contains(message.id)
        return Button {
            Haptics.selection()
            withAnimation(DSAnimation.snappy) {
                if isExpanded {
                    expandedCoachMessageIDs.remove(message.id)
                } else {
                    expandedCoachMessageIDs.insert(message.id)
                }
            }
        } label: {
            BrandMascotView(pose: .coach, size: 28, showsShadow: false)
                .scaleEffect(isExpanded ? 1.06 : 1)
                .frame(width: 32, height: 32)
                .background {
                    Circle()
                        .fill(isExpanded ? Color.dsBrandCream : Color.dsSurface)
                        .shadow(color: Color.dsCoach.opacity(0.18), radius: 4, y: 2)
                }
                .overlay {
                    Circle()
                        .stroke(Color.dsCoach.opacity(isExpanded ? 0.55 : 0.3), lineWidth: 1)
                }
                .frame(width: 44, height: 44)
                .contentShape(Circle())
                .animation(DSAnimation.snappy, value: isExpanded)
        }
        .buttonStyle(.pressableCard)
        .accessibilityLabel(isExpanded ? "收起改进建议" : "查看改进建议")
        .accessibilityAddTraits(isExpanded ? .isSelected : [])
    }

    /// 展开的纠错卡：错误片段 → 改法 + 中文讲解。
    @ViewBuilder
    func coachCard(_ message: MessageDTO) -> some View {
        if expandedCoachMessageIDs.contains(message.id),
           let review = CoachService.decode(fromJSON: message.coachReviewJSON),
           review.hasIssues {
            CalloutCard(kind: .coach) {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(Array(review.issues.enumerated()), id: \.offset) { _, issue in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 6) {
                                Text(issue.quote)
                                    .strikethrough()
                                    .foregroundStyle(.secondary)
                                Image(systemName: "arrow.right")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                Text(issue.correction)
                                    .foregroundStyle(Color.dsSuccess)
                            }
                            .font(.subheadline)
                            Text(issue.explanationZh)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .transition(.opacity.combined(with: .move(edge: .top)))
        }
    }

    // MARK: - 口语点评

    /// 语音消息的口语点评卡：自然度星级 + 中文点评 + 更自然说法建议。
    @ViewBuilder
    func speechReviewCard(_ message: MessageDTO) -> some View {
        if message.kind == .voice, let review = CoachService.decodeSpeech(fromJSON: message.speechReviewJSON) {
            CalloutCard(kind: .speech, trailing: {
                    Text(String(repeating: "★", count: review.clampedRating)
                        + String(repeating: "☆", count: 5 - review.clampedRating))
                        .font(.caption)
                        .foregroundStyle(Color.dsSpeech)
                }) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(review.commentZh)
                        .font(.footnote)
                        .foregroundStyle(.primary)
                    ForEach(Array(review.tips.enumerated()), id: \.offset) { _, tip in
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text(tip.quote)
                                    .strikethrough()
                                    .foregroundStyle(.secondary)
                                Image(systemName: "arrow.right").font(.caption2).foregroundStyle(.secondary)
                                Text(tip.better).foregroundStyle(Color.dsSpeech)
                            }
                            .font(.subheadline)
                            Text(tip.explanationZh)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }

    // MARK: - 语境出题

    /// 角色回复附带的小测：选项气泡 + 作答反馈 + 「不再弹题」。
    @ViewBuilder
    func quizCard(_ message: MessageDTO) -> some View {
        if let quiz = QuizService.decode(fromJSON: message.quizJSON) {
            let chosen = message.quizChosenIndex
            CalloutCard(kind: .quiz) {
                VStack(alignment: .leading, spacing: 10) {
                    Text(quiz.question)
                        .font(.subheadline.weight(.medium))
                    VStack(spacing: 6) {
                        ForEach(Array(quiz.options.enumerated()), id: \.offset) { index, option in
                            quizOption(message: message, quiz: quiz, index: index, option: option, chosen: chosen)
                        }
                    }
                    if let chosen {
                        let correct = chosen == quiz.answer
                        VStack(alignment: .leading, spacing: 4) {
                            Text(correct
                                ? "🎉 答对了！+\(QuizService.correctReward) 金币"
                                : "正确答案：\(QuizService.optionLabel(quiz.answer)). \(quiz.options[quiz.answer])")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(correct ? Color.dsSuccess : Color.dsWarning)
                            Text(quiz.explanationZh)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        .transition(.opacity)
                    }
                    Button {
                        Task { await viewModel.setQuizOptOut(!viewModel.conversationOptedOut) }
                    } label: {
                        Label(
                            "不再弹题",
                            systemImage: viewModel.conversationOptedOut ? "checkmark.square.fill" : "square"
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .animation(.snappy, value: chosen)
            .offset(x: shakingMessageID == message.id ? (shakePhase ? 7 : -7) : 0)
            .celebration(chosen == quiz.answer, tint: .dsSuccess, trigger: quizCelebrationTrigger)
        }
    }

    func quizOption(
        message: MessageDTO,
        quiz: Quiz,
        index: Int,
        option: String,
        chosen: Int?
    ) -> some View {
        let isAnswered = chosen != nil
        let isCorrect = index == quiz.answer
        let isChosen = index == chosen
        return Button {
            Task {
                await viewModel.answerQuiz(message: message, chosenIndex: index)
                if index == quiz.answer {
                    quizCelebrationTrigger += 1
                } else if !reduceMotion {
                    shakingMessageID = message.id
                    withAnimation(.linear(duration: 0.07).repeatCount(5, autoreverses: true)) {
                        shakePhase.toggle()
                    }
                    try? await Task.sleep(for: .milliseconds(420))
                    shakingMessageID = nil
                }
            }
        } label: {
            HStack(spacing: 8) {
                Text(QuizService.optionLabel(index))
                    .font(.subheadline.weight(.bold))
                    .monospaced()
                Text(option)
                    .font(.subheadline)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if isAnswered, isCorrect {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                } else if isChosen {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(quizOptionColor(isAnswered: isAnswered, isCorrect: isCorrect, isChosen: isChosen),
                        in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(isAnswered)
    }

    func quizOptionColor(isAnswered: Bool, isCorrect: Bool, isChosen: Bool) -> Color {
        if isAnswered, isCorrect { return .dsSuccess.opacity(0.22) }
        if isChosen { return .dsDanger.opacity(0.16) }
        return .dsSurface
    }

    @ViewBuilder
    func translationFootnote(_ message: MessageDTO, alignment: HorizontalAlignment) -> some View {
        if viewModel.translatingMessageIDs.contains(message.id) {
            ProgressView()
                .controlSize(.small)
        } else if let translation = message.translationZh {
            Text(translation)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: alignment == .trailing ? .trailing : .leading)
                .padding(alignment == .trailing ? .leading : .trailing, 48)
                .transition(.opacity)
        }
    }

    @ViewBuilder
    func tappableText(_ message: MessageDTO, textColor: Color?) -> some View {
        if message.kind == .voice {
            VoiceBubbleContent(
                message: .init(
                    duration: message.audioDuration ?? 0,
                    transcript: message.text,
                    hasAudio: message.audioFileName != nil || message.audioAssetID != nil
                ),
                isPlaying: voicePlayer.playingFileName != nil && voicePlayer.playingFileName == message.audioFileName,
                showTranscript: transcriptVisibleMessageIDs.contains(message.id),
                textColor: textColor,
                onTogglePlay: {
                    Task {
                        guard let fileName = await viewModel.localVoiceFile(for: message) else {
                            return
                        }
                        await voicePlayer.togglePlay(fileName: fileName)
                    }
                }
            )
        } else {
            let displayText = message.role == .assistant
                ? RoleplayReplyFormatter.streamingPreview(from: message.text)
                : message.text
            let tokens = TokenCache.tokens(
                for: displayText,
                cacheKey: message.id.uuidString
            )
            TappableText(
                tokens: tokens,
                contextID: message.id.uuidString,
                keywords: message.role == .assistant
                    ? KeywordAnnotator.decodeWords(fromJSON: message.keywordRangesJSON)
                    : [],
                textColor: textColor,
                selection: wordSelection,
                onSelect: selectWord
            )
        }
    }

    func selectWord(_ selection: TokenSelection) {
        isTextInputFocused = false
        wordSelection = selection
    }

    func presentGrammarAnalysis(for message: MessageDTO) {
        let sentence = RoleplayReplyFormatter.streamingPreview(from: message.text)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sentence.isEmpty else { return }
        let tokens = TokenCache.tokens(
            for: sentence,
            cacheKey: "grammar-\(message.id.uuidString)"
        )
        let localItems: [LocalGrammarAnalysisItem] = deps.grammarPoints.matches(in: tokens).compactMap { match -> LocalGrammarAnalysisItem? in
            guard let point = deps.grammarPoints.point(id: match.pointID) else { return nil }
            let matchedText = match.spanTokenIDs
                .compactMap { tokens.indices.contains($0) ? tokens[$0].display : nil }
                .joined()
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return LocalGrammarAnalysisItem(
                id: "\(point.id)-\(match.spanTokenIDs.map { String($0) }.joined(separator: "-"))",
                point: point,
                matchedText: matchedText
            )
        }
        isTextInputFocused = false
        Haptics.selection()
        grammarAnalysis = GrammarAnalysisRequest(
            id: message.id,
            sentence: sentence,
            learnerLevel: viewModel.learnerDifficulty.displayName,
            localItems: localItems
        )
    }

    /// 词典未收录时的 AI 简释兜底（fast 档）。
    var aiWordFallback: @Sendable (String) async -> String? {
        deps.lookupAIWordFallback
    }

    var wordFavoriteActions: WordFavoriteActions {
        deps.lookupWordFavoriteActions
    }
}
