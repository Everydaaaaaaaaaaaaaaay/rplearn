import DesignSystem
import PersistenceKit
import SwiftUI

// Shared by whole-passage practice and the remaining listening / short-question flows.
enum PracticePaper {
    static let canvas = Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? UIColor(red: 0.10, green: 0.12, blue: 0.11, alpha: 1) : UIColor(red: 0.96, green: 0.95, blue: 0.92, alpha: 1) })
    static let sheet = Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? UIColor(red: 0.14, green: 0.16, blue: 0.15, alpha: 1) : UIColor(red: 1, green: 0.995, blue: 0.98, alpha: 1) })
    static let accent = Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? UIColor(red: 0.65, green: 0.79, blue: 0.70, alpha: 1) : UIColor(red: 0.25, green: 0.39, blue: 0.32, alpha: 1) })
    static let incorrect = Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? UIColor(red: 1, green: 0.48, blue: 0.48, alpha: 1) : UIColor(red: 0.72, green: 0.15, blue: 0.20, alpha: 1) })
    static let correct = Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? UIColor(red: 0.48, green: 0.81, blue: 0.59, alpha: 1) : UIColor(red: 0.16, green: 0.43, blue: 0.27, alpha: 1) })
}

struct PracticeCompanionHeader: View {
    let character: CharacterDTO
    let message: String
    @ScaledMetric(relativeTo: .title) private var avatarSize = 112

    var body: some View {
        VStack(spacing: 24) {
            AvatarBadge(name: character.displayName, size: min(avatarSize, 148), imageName: character.card.avatarAssetName,
                        remoteURL: character.card.avatarRemoteURL.flatMap(URL.init(string:)), usesPendingPlaceholder: true)
                .accessibilityLabel(character.displayName)
                .accessibilityIdentifier("practice.companion.avatar")
            Text(message)
                .font(.system(.title3, design: .rounded, weight: .medium)).lineSpacing(5)
                .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 340)
                .accessibilityIdentifier("practice.companion.message")
        }.frame(maxWidth: .infinity)
    }
}

struct PracticeBookendButton: View {
    let title: String
    var busy = false
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(title).multilineTextAlignment(.center)
                .font(.body.weight(.semibold))
                .frame(maxWidth: .infinity, minHeight: 56).padding(.horizontal, 20)
                .foregroundStyle(PracticePaper.sheet)
                .background(PracticePaper.accent, in: RoundedRectangle(cornerRadius: 18))
                .overlay { if busy { ProgressView().tint(PracticePaper.sheet).frame(maxWidth: .infinity, alignment: .trailing).padding(.trailing, 20) } }
        }.buttonStyle(LearningPressStyle()).disabled(busy)
    }
}

struct PracticeCoverPage<Accessory: View>: View {
    let character: CharacterDTO
    let message: String
    let kind: String
    let minutes: Int
    let buttonTitle: String
    let start: () -> Void
    let close: () -> Void
    @ViewBuilder var accessory: () -> Accessory

    var body: some View {
        VStack(spacing: 0) {
            PracticeBookendClose(action: close)
            accessory()
            GeometryReader { geometry in
                ScrollView {
                    VStack(spacing: 44) {
                        PracticeCompanionHeader(character: character, message: message)
                        VStack(spacing: 12) {
                            Text(kind).font(.title2.weight(.semibold))
                                .accessibilityIdentifier("practice.task.kind")
                            Text("预计\(PracticeTimeEstimate.label(minutes))分钟完成")
                                .font(.subheadline).foregroundStyle(.secondary)
                                .accessibilityIdentifier("practice.task.time")
                        }.multilineTextAlignment(.center).frame(maxWidth: .infinity)
                        PracticeBookendButton(title: buttonTitle, action: start)
                            .accessibilityIdentifier("practice.start")
                    }
                    .padding(.horizontal, 28).padding(.top, max(40, min(96, geometry.size.height * 0.12)))
                    .padding(.bottom, 40).frame(maxWidth: 520).frame(maxWidth: .infinity)
                }.scrollIndicators(.hidden)
            }
        }.background(PracticePaper.canvas.ignoresSafeArea())
    }
}

enum PracticeTimeEstimate {
    static func label(_ minutes: Int) -> String {
        let upper = max(2, minutes)
        return "\(max(1, Int((Double(upper) * 0.65).rounded())))–\(upper)"
    }
}

struct PracticeReviewItem: Identifiable {
    let id: String
    let location: String
    let prompt: String
    let answer: String
    let reference: String
    var needsReview = false
    var sentence: String?
    var gapNumber = 0
    var referenceContent = ""
}

struct PracticeSummaryPage: View {
    let character: CharacterDTO
    let message: String
    let correct: Int
    let total: Int
    let earnedPoints: Int
    let items: [PracticeReviewItem]
    var busy = false
    var revisit: ((String) -> Void)?
    let finish: () -> Void
    @ScaledMetric(relativeTo: .largeTitle) private var scoreSize = 44

    var body: some View {
        VStack(spacing: 0) {
            PracticeBookendClose(action: finish)
            ScrollView {
                VStack(spacing: 40) {
                    PracticeCompanionHeader(character: character, message: message)
                        .padding(.top, 28)
                    VStack(spacing: 12) {
                        Text("本次练习答对：").font(.title2.weight(.medium))
                        Text("\(correct)/\(total)题")
                            .font(.system(size: scoreSize, weight: .semibold, design: .rounded)).monospacedDigit()
                            .accessibilityIdentifier("practice.result.score")
                        Text("获得\(earnedPoints)积分！")
                            .font(.headline).foregroundStyle(PracticePaper.correct)
                            .accessibilityIdentifier("practice.result.points")
                    }.frame(maxWidth: .infinity)
                    if !items.isEmpty {
                        VStack(alignment: .leading, spacing: 18) {
                            Text("错题回顾").font(.title3.weight(.semibold))
                            ForEach(items) { item in
                                if let revisit {
                                    Button { revisit(item.id) } label: { reviewCard(item, opensDetail: true) }
                                        .buttonStyle(.plain)
                                        .accessibilityIdentifier("practice.review.\(item.id)")
                                } else { reviewCard(item, opensDetail: false) }
                            }
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }
                }.padding(.horizontal, 24).padding(.bottom, 32).frame(maxWidth: 600).frame(maxWidth: .infinity)
            }.scrollIndicators(.hidden)
            PracticeBookendButton(title: "结束练习", busy: busy, action: finish)
                .accessibilityIdentifier("practice.finish")
                .padding(.horizontal, 28).padding(.top, 12).padding(.bottom, 16).frame(maxWidth: 600)
        }.background(PracticePaper.canvas.ignoresSafeArea())
    }

    private func reviewCard(_ item: PracticeReviewItem, opensDetail: Bool) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(item.location).font(.caption).foregroundStyle(.secondary)
                Spacer()
                if opensDetail { Image(systemName: "arrow.up.right").font(.caption).foregroundStyle(PracticePaper.accent) }
            }
            if let sentence = item.sentence {
                PracticeReviewSentence(sentence: sentence, number: item.gapNumber, reference: item.referenceContent)
                    .accessibilityIdentifier("practice.review.sentence.\(item.id)")
            } else {
                Text(item.prompt).font(.body).foregroundStyle(.primary).lineSpacing(4)
            }
            VStack(alignment: .leading, spacing: 7) {
                Text("你的答案：\(item.answer.isEmpty ? "未作答" : item.answer)")
                    .foregroundStyle(item.needsReview ? Color.secondary : PracticePaper.incorrect)
                    .accessibilityIdentifier("practice.review.answer.\(item.id)")
                Text("参考答案：\(item.reference)").foregroundStyle(PracticePaper.correct)
                    .accessibilityIdentifier("practice.review.reference.\(item.id)")
                if item.needsReview { Text("表达待核对").foregroundStyle(.secondary) }
            }.font(.subheadline).lineSpacing(3)
        }.fixedSize(horizontal: false, vertical: true)
            .padding(18).frame(maxWidth: .infinity, alignment: .leading)
            .background(PracticePaper.sheet, in: RoundedRectangle(cornerRadius: 18))
    }
}

private struct PracticeBookendClose: View {
    let action: () -> Void
    var body: some View {
        HStack {
            Button(action: action) {
                Image(systemName: "xmark").font(.system(size: 14, weight: .medium)).frame(width: 44, height: 44)
                    .background(Color.primary.opacity(0.045), in: Circle())
            }.buttonStyle(.plain).accessibilityLabel("关闭练习")
            Spacer()
        }.padding(.horizontal, 22).padding(.top, 8)
    }
}
