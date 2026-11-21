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

extension ChatTranscriptView {
// MARK: - 教练纠错

    /// 本条消息的点评。落库后仍按原文复核一次，历史误存的上文旧错句不再显示。
    func groundedCoachReview(_ message: MessageDTO) -> CoachReview? {
        CoachService.decode(fromJSON: message.coachReviewJSON)?
            .grounded(inLearnerMessage: message.text)
    }

    @ViewBuilder
    func userMessageBubble(
        _ message: MessageDTO,
        groupPosition: MessageBubbleGroupPosition
    ) -> some View {
        if groundedCoachReview(message)?.hasIssues == true {
            MessageBubble(
                side: .outgoing,
                groupPosition: groupPosition,
                leadingAccessory: { coachButton(message) },
                onMenuRequest: { presentBubbleMenu(message, frame: $0) },
                contextMenu: { bubbleMenu(message) }
            ) {
                tappableText(message, textColor: .white)
            }
        } else {
            MessageBubble(
                side: .outgoing,
                groupPosition: groupPosition,
                onMenuRequest: { presentBubbleMenu(message, frame: $0) },
                contextMenu: { bubbleMenu(message) }
            ) {
                tappableText(message, textColor: .white)
            }
        }
    }

    /// 紧贴用户气泡中线的纠错入口；可见尺寸克制，触控区域保持 44pt。
    func coachButton(_ message: MessageDTO) -> some View {
        let isExpanded = expandedCoachMessageIDs.contains(message.id)
        let persona = DSCoachPersona.assigned(to: message.id)
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
            Image(systemName: isExpanded ? "text.bubble.fill" : "text.bubble")
                .font(.system(size: 16, weight: .heavy))
                .foregroundStyle(isExpanded ? .white : PuffCandy.tangerine.deep)
                .frame(width: 32, height: 32)
                .background(isExpanded ? PuffCandy.tangerine.base : PuffCandy.tangerine.wash, in: Circle())
                .frame(width: 44, height: 44)
                .contentShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
                .animation(DSAnimation.snappy, value: isExpanded)
        }
        .buttonStyle(.puffSquish)
        .accessibilityLabel(isExpanded ? "收起\(persona.title)" : "查看\(persona.title)")
        .accessibilityAddTraits(isExpanded ? .isSelected : [])
    }

    /// 展开的纠错卡：错误片段 → 改法 + 中文讲解。
    @ViewBuilder
    func coachCard(_ message: MessageDTO) -> some View {
        if expandedCoachMessageIDs.contains(message.id),
           let review = groundedCoachReview(message),
           review.hasIssues {
            let persona = DSCoachPersona.assigned(to: message.id)
            CalloutCard(kind: .coach, coachPersona: persona) {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(Array(review.issues.enumerated()), id: \.offset) { index, issue in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 6) {
                                Text(issue.quote)
                                    .strikethrough()
                                    .foregroundStyle(.secondary)
                                Image(systemName: "arrow.right")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                Text(issue.correction)
                                    .fontWeight(.bold)
                                    .foregroundStyle(PuffCandy.mint.deep)
                            }
                            .font(.subheadline)
                            TappableGrammarTermText(
                                issue.explanationZh,
                                contextID: "coach-\(message.id.uuidString)-\(index)",
                                selection: grammarTermSelection,
                                onSelect: { selection in
                                    wordSelection = nil
                                    grammarTermSelection = selection
                                }
                            )
                                .font(.footnote)
                        }
                    }
                }
            }
            .transition(.opacity.combined(with: .move(edge: .top)))
        }
    }

    @ViewBuilder
    func translationFootnote(_ message: MessageDTO, alignment: HorizontalAlignment) -> some View {
        if viewModel.translatingMessageIDs.contains(message.id) {
            ProgressView()
                .controlSize(.small)
        } else if let translation = message.translationZh {
            Text(translation)
                .font(.puff(.footnote, .medium))
                .foregroundStyle(Puff.Palette.inkSoft)
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
                isPlaying: voicePlayer.playingMessageID == message.id,
                isLoading: voicePlayer.loadingMessageID == message.id,
                playbackFailed: voicePlayer.failedMessageID == message.id,
                showTranscript: transcriptVisibleMessageIDs.contains(message.id),
                textColor: textColor,
                onTogglePlay: { toggleVoicePlayback(message) }
            )
            .accessibilityIdentifier("chat.voice.\(message.id.uuidString)")
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

    func toggleVoicePlayback(_ message: MessageDTO) {
        let stopped = autoReadQueue.interrupt()
        Task {
            await voicePlayer.togglePlay(messageID: message.id) {
                await stopped?.value
                await deps.speech.stopSpeaking()
                return await viewModel.localVoiceFile(for: message)
            }
        }
    }

    func selectWord(_ selection: TokenSelection) {
        isTextInputFocused = false
        grammarTermSelection = nil
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

}

extension ChatView {
    /// 词典未收录时的 AI 简释兜底（fast 档）。
    var aiWordFallback: @Sendable (String) async -> String? {
        deps.lookupAIWordFallback
    }

    var wordFavoriteActions: WordFavoriteActions {
        deps.lookupWordFavoriteActions(
            sourceMessageID: wordSelection.flatMap { UUID(uuidString: $0.contextID) }
        )
    }
}
