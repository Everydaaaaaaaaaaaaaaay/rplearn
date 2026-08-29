import DesignSystem
import Foundation
import PersistenceKit
import SwiftUI

public struct RosterDependencies: Sendable {
    public let rosterStore: RosterStore
    public let economyStore: EconomyStore
    public let regionName: @Sendable (String) -> String

    public init(
        rosterStore: RosterStore,
        economyStore: EconomyStore,
        regionName: @escaping @Sendable (String) -> String = {
            $0.replacingOccurrences(of: "_", with: " ").capitalized
        }
    ) {
        self.rosterStore = rosterStore
        self.economyStore = economyStore
        self.regionName = regionName
    }
}

enum RosterPresentationPolicy {
    static func sorted(_ contacts: [CharacterDTO]) -> [CharacterDTO] {
        contacts.sorted {
            $0.card.name.localizedStandardCompare($1.card.name) == .orderedAscending
        }
    }

    static func filtered(
        _ contacts: [CharacterDTO],
        query: String,
        regionName: (String) -> String
    ) -> [CharacterDTO] {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedQuery.isEmpty else { return sorted(contacts) }
        return sorted(
            contacts.filter { character in
                [
                    character.card.name,
                    character.card.nationality,
                    character.card.occupation,
                    character.card.regionID,
                    regionName(character.card.regionID),
                ].contains { $0.localizedCaseInsensitiveContains(normalizedQuery) }
            }
        )
    }

    static func favoriteContacts(
        in contacts: [CharacterDTO],
        isSearching: Bool
    ) -> [CharacterDTO] {
        guard !isSearching else { return [] }
        return sorted(contacts.filter(\.isFavorite))
    }

    static func friendGroupContacts(in contacts: [CharacterDTO]) -> [CharacterDTO] {
        sorted(contacts.filter { !$0.isFavorite })
    }

    static func isCapacityNearLimit(occupied: Int, limit: Int) -> Bool {
        guard limit > 0 else { return true }
        return Double(occupied) / Double(limit) >= 0.8
    }
}

public struct CharacterProfileView: View {
    private let character: CharacterDTO
    private let regionName: String
    private let rosterStore: RosterStore
    private let onFavoriteChanged: @MainActor (Bool) -> Void
    private let chatBuilder: @MainActor (CharacterDTO) -> AnyView
    private let callBuilder: (@MainActor (CharacterDTO) -> AnyView)?

    @State private var isFavorite: Bool
    @State private var relationship: PersistenceKit.RelationshipSnapshot
    @State private var isUpdatingFavorite = false
    @State private var failedFavoriteTarget: Bool?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    public init(
        character: CharacterDTO,
        regionName: String,
        rosterStore: RosterStore,
        onFavoriteChanged: @escaping @MainActor (Bool) -> Void = { _ in },
        chatBuilder: @escaping @MainActor (CharacterDTO) -> AnyView,
        callBuilder: (@MainActor (CharacterDTO) -> AnyView)? = nil
    ) {
        self.character = character
        self.regionName = regionName
        self.rosterStore = rosterStore
        self.onFavoriteChanged = onFavoriteChanged
        self.chatBuilder = chatBuilder
        self.callBuilder = callBuilder
        _isFavorite = State(initialValue: character.isFavorite)
        _relationship = State(initialValue: character.relationship)
    }

    private var card: CharacterCard { character.card }

    public var body: some View {
        ScrollView {
            VStack(spacing: DSSpacing.md) {
                profileHero
                contactActions
                relationshipCard
                infoCard("性格", text: card.personality, icon: "sparkles")
                hobbiesCard
                infoCard("外貌", text: card.appearance, icon: "person.crop.rectangle")
                if let speechStyle = card.speechStyle {
                    infoCard("说话风格", text: speechStyle, icon: "quote.bubble")
                }
                if let background = card.background {
                    infoCard("背景故事", text: background, icon: "book.closed")
                }
                infoCard(
                    "相识于",
                    text: character.metAt.formatted(date: .abbreviated, time: .omitted),
                    icon: "mappin.and.ellipse"
                )
            }
            .padding(DSSpacing.md)
        }
        .background(Color.dsBackground)
        .navigationTitle(card.name)
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if let failedFavoriteTarget {
                SaveErrorBanner(
                    message: "特别关心没有保存成功",
                    retry: { setFavorite(failedFavoriteTarget) },
                    dismiss: { self.failedFavoriteTarget = nil }
                )
                .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(reduceMotion ? nil : DSAnimation.snappy, value: failedFavoriteTarget)
        .task {
            await reloadRelationship()
        }
        .onReceive(NotificationCenter.default.publisher(for: .rosterRelationshipDidChange)) { note in
            guard let characterID = note.object as? UUID, characterID == character.id else { return }
            Task { await reloadRelationship() }
        }
    }

    private var profileHero: some View {
        VStack(spacing: DSSpacing.sm) {
            AvatarBadge(name: card.name, size: 96)
            Text(card.name)
                .font(.title2.bold())
                .multilineTextAlignment(.center)
            Text(
                [
                    character.isMainCharacter ? "剧情旅伴" : "旅行朋友",
                    card.occupation,
                    regionName,
                ].joined(separator: " · ")
            )
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            Text("\(card.nationality) · \(card.age) 岁")
                .font(.footnote)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
        .dsSurface(.grouped)
        .accessibilityElement(children: .combine)
    }

    private var contactActions: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: DSSpacing.sm))
            : AnyLayout(HStackLayout(spacing: DSSpacing.sm))

        return layout {
            NavigationLink {
                chatBuilder(character)
            } label: {
                contactActionLabel("发消息", systemImage: "bubble.left.fill")
            }
            .buttonStyle(.borderedProminent)
            .tint(Color.dsSky)

            if let callBuilder {
                NavigationLink {
                    callBuilder(character)
                } label: {
                    contactActionLabel("打电话", systemImage: "phone.fill")
                }
                .buttonStyle(.bordered)
                .tint(Color.dsSkyDeep)
            }

            Button {
                setFavorite(!isFavorite)
            } label: {
                contactActionLabel(
                    isFavorite ? "已特别关心" : "特别关心",
                    systemImage: isFavorite ? "star.fill" : "star"
                )
                .contentTransition(reduceMotion ? .opacity : .symbolEffect(.replace))
            }
            .buttonStyle(.bordered)
            .tint(isFavorite ? Color.dsSunset : Color.dsSkyDeep)
            .disabled(isUpdatingFavorite)
            .accessibilityValue(isFavorite ? "已开启" : "未开启")
            .accessibilityHint(isFavorite ? "双击取消特别关心" : "双击设为特别关心")
        }
    }

    private func contactActionLabel(_ title: String, systemImage: String) -> some View {
        VStack(spacing: 5) {
            Image(systemName: systemImage)
                .font(.title3)
            Text(title)
                .font(.caption.weight(.semibold))
                .multilineTextAlignment(.center)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, minHeight: 58)
    }

    private var relationshipCard: some View {
        VStack(alignment: .leading, spacing: DSSpacing.sm) {
            HStack(alignment: .firstTextBaseline) {
                Label("好感度", systemImage: "heart.text.square")
                    .font(.headline)
                    .foregroundStyle(Color.dsSunset)
                Spacer(minLength: DSSpacing.sm)
                Text("\(relationship.displayAffinity) / 150")
                    .font(.headline.monospacedDigit())
                    .contentTransition(.numericText())
            }

            ProgressView(value: relationship.projectedAffinity(), total: 150)
                .tint(Color.dsSunset)
                .accessibilityLabel("好感度")
                .accessibilityValue("\(relationship.displayAffinity)，满分 150")

            Text("反映角色在互动中形成的了解、信任、默契、关心与尊重。英语水平不会影响好感度。")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Divider()

            relationshipDimension("相互了解", value: relationship.familiarity)
            relationshipDimension("信任", value: relationship.trust)
            relationshipDimension("默契", value: relationship.rapport)
            relationshipDimension("关心与互惠", value: relationship.care)
            relationshipDimension("尊重", value: relationship.respect)

            if let event = relationship.latestEvent {
                HStack(alignment: .top, spacing: DSSpacing.xs) {
                    Text(
                        event.delta >= 0
                            ? "+\(event.delta, specifier: "%.1f")"
                            : "\(event.delta, specifier: "%.1f")"
                    )
                    .font(.caption.monospacedDigit().weight(.semibold))
                    .foregroundStyle(event.delta >= 0 ? Color.dsSuccess : Color.dsWarning)
                    Text(event.reasonZh)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel(
                    "最近一次互动好感度变化 \(event.delta, specifier: "%.1f")，\(event.reasonZh)"
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .dsSurface(.grouped)
    }

    private func relationshipDimension(_ title: String, value: Double) -> some View {
        HStack(spacing: DSSpacing.sm) {
            Text(title)
                .font(.subheadline)
                .frame(width: dynamicTypeSize.isAccessibilitySize ? nil : 72, alignment: .leading)
            ProgressView(value: min(max(value, 0), 1))
                .tint(Color.dsSky)
            Text("\(Int((min(max(value, 0), 1) * 100).rounded()))%")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(minWidth: 36, alignment: .trailing)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title)，\(Int((min(max(value, 0), 1) * 100).rounded()))%")
    }

    @MainActor
    private func reloadRelationship() async {
        guard let latest = try? await rosterStore.character(id: character.id) else { return }
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.25)) {
            relationship = latest.relationship
        }
    }

    private func setFavorite(_ newValue: Bool) {
        guard !isUpdatingFavorite else { return }
        let previousValue = isFavorite
        failedFavoriteTarget = nil
        isUpdatingFavorite = true
        withAnimation(reduceMotion ? nil : DSAnimation.snappy) {
            isFavorite = newValue
        }
        onFavoriteChanged(newValue)

        Task {
            do {
                try await rosterStore.setFavorite(
                    characterID: character.id,
                    isFavorite: newValue
                )
                Haptics.selection()
            } catch {
                withAnimation(reduceMotion ? nil : DSAnimation.snappy) {
                    isFavorite = previousValue
                }
                onFavoriteChanged(previousValue)
                failedFavoriteTarget = newValue
            }
            isUpdatingFavorite = false
        }
    }

    private var hobbiesCard: some View {
        VStack(alignment: .leading, spacing: DSSpacing.sm) {
            Label("爱好", systemImage: "heart.fill")
                .font(.headline)
                .foregroundStyle(Color.dsSunset)
            FlowLayout(spacing: 6, lineSpacing: 7) {
                ForEach(card.localizedHobbies, id: \.self) { DSChip($0, tint: .dsSky) }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .dsSurface(.grouped)
    }

    private func infoCard(_ title: String, text: String, icon: String) -> some View {
        VStack(alignment: .leading, spacing: DSSpacing.xs) {
            Label(title, systemImage: icon)
                .font(.headline)
                .foregroundStyle(Color.dsSky)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .dsSurface(.grouped)
    }
}

private struct SaveErrorBanner: View {
    let message: String
    let retry: () -> Void
    let dismiss: () -> Void

    var body: some View {
        HStack(spacing: DSSpacing.sm) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Color.dsDanger)
                .accessibilityHidden(true)
            Text(message)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.primary)
            Spacer(minLength: 0)
            Button("重试", action: retry)
                .font(.footnote.weight(.semibold))
            Button(action: dismiss) {
                Image(systemName: "xmark")
                    .frame(width: 30, height: 30)
            }
            .accessibilityLabel("关闭错误提示")
        }
        .padding(.leading, DSSpacing.md)
        .padding(.trailing, DSSpacing.xs)
        .padding(.vertical, DSSpacing.xs)
        .background(.thickMaterial, in: Capsule())
        .overlay { Capsule().stroke(Color.dsBorder, lineWidth: 1) }
        .padding(.horizontal, DSSpacing.md)
        .padding(.bottom, DSSpacing.xs)
        .shadow(color: .black.opacity(0.12), radius: 10, y: 4)
    }
}
