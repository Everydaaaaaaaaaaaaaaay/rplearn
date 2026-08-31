import CoreKit
import DesignSystem
import DictKit
import DomainKit
import LLMKit
import PersistenceKit
import SpeechKit
import SwiftUI

struct ActivityMomentSheet: View {
    let presentation: ActivityMomentPresentation
    let onDismiss: () -> Void

    private var activity: Region.Activity { presentation.activity }
    private var region: Region { presentation.region }

    var body: some View {
        ScrollView {
            VStack(spacing: DSSpacing.lg) {
                Capsule()
                    .fill(.tertiary)
                    .frame(width: 36, height: 5)

                ZStack(alignment: .bottomLeading) {
                    GeometryReader { proxy in
                        Image("home_activity_\(region.id)")
                            .resizable()
                            .scaledToFill()
                            .frame(width: proxy.size.width, height: 190)
                            .clipped()
                    }
                    LinearGradient(
                        colors: [.clear, .black.opacity(0.82)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    VStack(alignment: .leading, spacing: 4) {
                        Label("探索完成", systemImage: "checkmark.seal.fill")
                            .font(.caption.weight(.black))
                            .foregroundStyle(activity.category.tint)
                        Text(activity.titleZh)
                            .font(.system(.title2, design: .rounded, weight: .black))
                            .lineLimit(1)
                            .minimumScaleFactor(0.76)
                    }
                    .foregroundStyle(.white)
                    .padding(DSSpacing.md)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 190)
                .clipShape(RoundedRectangle(cornerRadius: DSRadius.hero, style: .continuous))

                VStack(alignment: .leading, spacing: DSSpacing.sm) {
                    Text("本次见闻")
                        .font(.caption.weight(.black))
                        .foregroundStyle(activity.category.tint)
                    Text(activity.outcomeZh)
                        .font(.body)
                        .fixedSize(horizontal: false, vertical: true)

                    Divider()

                    HStack {
                        Label(region.nameZh, systemImage: "mappin.and.ellipse")
                        Spacer()
                        Label("\(activity.durationMinutes) 分钟", systemImage: "clock")
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                    if let companionName = presentation.companionName {
                        Label(
                            "与 \(firstName(companionName)) 一起完成",
                            systemImage: "person.2.fill"
                        )
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(activity.category.tint)
                    }
                }
                .dsSurface(.elevated)

                Label(
                    momentSummary,
                    systemImage: "sparkles"
                )
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

                Button("收下这段见闻") {
                    onDismiss()
                }
                .buttonStyle(.dsAction(.tinted(activity.category.tint)))
            }
            .padding(DSSpacing.md)
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.hidden)
    }

    private var momentSummary: String {
        if let companionName = presentation.companionName {
            return "这次没有遇见新角色，但你和 \(firstName(companionName)) 一起留下了一段共同见闻。"
        }
        return "这次没有遇见新角色，但城市依然留下了一段只属于你的片刻。"
    }

    private func firstName(_ value: String) -> String {
        value.split(whereSeparator: \.isWhitespace).first.map(String.init) ?? value
    }
}
