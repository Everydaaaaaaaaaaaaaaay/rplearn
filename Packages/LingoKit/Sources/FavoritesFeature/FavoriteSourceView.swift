import DesignSystem
import PersistenceKit
import SwiftUI

/// Context stays collapsed until requested, so the word list remains easy to scan.
struct FavoriteSourceView: View {
    let favoriteID: UUID
    let store: FavoritesStore
    @State private var expanded = false
    @State private var source: FavoriteSourceDTO?
    @State private var isLoading = false
    @State private var failed = false

    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            VStack(alignment: .leading, spacing: 8) {
                if isLoading {
                    ProgressView().accessibilityLabel("正在读取原句")
                } else if failed {
                    Button("原句读取失败，重试") { Task { await load() } }
                        .buttonStyle(.borderless)
                } else if let source {
                    Text(source.speaker)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(PuffCandy.sky.deep)
                    Text(source.text)
                        .font(.subheadline)
                        .foregroundStyle(Puff.Palette.ink)
                        .lineSpacing(4)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                    if let translation = source.translationZh, !translation.isEmpty {
                        Text(translation)
                            .font(.footnote)
                            .foregroundStyle(Puff.Palette.inkSoft)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                } else {
                    Text("原消息暂不可用，单词收藏仍会保留。")
                        .font(.footnote)
                        .foregroundStyle(Puff.Palette.inkSoft)
                }
            }
            .padding(.top, 6)
            .padding(.bottom, 8)
        } label: {
            Label("当时的原句", systemImage: "text.bubble")
                .font(.footnote.weight(.medium))
                .foregroundStyle(PuffCandy.sky.deep)
                .padding(.vertical, 5)
        }
        .tint(PuffCandy.sky.deep)
        .task(id: expanded) {
            if expanded { await load() }
        }
    }

    @MainActor
    private func load() async {
        isLoading = true
        failed = false
        defer { isLoading = false }
        do { source = try await store.source(for: favoriteID) }
        catch { failed = true }
    }
}
