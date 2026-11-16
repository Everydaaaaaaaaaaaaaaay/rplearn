#if DEBUG
import BackendKit
import DesignSystem
import HomeFeature
import SwiftUI

/// Native proposal previews, selected only in the isolated Debug workspace.
struct DebugActivityHubDesignPreview: View {
    let onOpen: (HomeDestination) -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var creditedPhoto: BackendActivityPhoto?

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: 16) {
                    cityEntrance
                        .frame(height: min(340, max(260, geometry.size.height * 0.49)))
                    appointmentEntrance
                    secondaryEntrances
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .background {
            DSSceneBackdrop(imageName: "contacts_london_glass", tone: .cool)
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            DebugHubDesignHeader(title: "活动")
        }
        .foregroundStyle(Color.dsSceneTextPrimary)
        .toolbar(.hidden, for: .navigationBar)
        .dsSceneTabBarBackground()
        .sheet(item: $creditedPhoto) { ActivityPhotoCredits(photo: $0) }
    }

    private var cityEntrance: some View {
        ZStack(alignment: .bottomLeading) {
            if let photo = DebugHubDesignAssets.parkPhoto {
                ActivityPlacePhoto(photo: photo)
            }
            LinearGradient(colors: [.black.opacity(0.08), .clear, .black.opacity(0.64)],
                           startPoint: .top, endPoint: .bottom)
                .allowsHitTesting(false)
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text("城市活动").font(.subheadline.weight(.medium)).tracking(1)
                    Spacer()
                    if let photo = DebugHubDesignAssets.parkPhoto {
                        Button { creditedPhoto = photo } label: {
                            Image(systemName: "ellipsis").frame(width: 44, height: 44)
                        }
                        .accessibilityLabel("照片信息")
                    }
                }
                Spacer(minLength: 24)
                Text("伦敦")
                    .font(.system(.largeTitle, design: .serif, weight: .regular))
                    .tracking(3)
                Button { onOpen(.activities) } label: {
                    Text("去这里逛逛")
                        .font(.body.weight(.medium)).tracking(1.5)
                        .padding(.horizontal, 24)
                        .frame(minHeight: 48)
                        .overlay { Capsule().strokeBorder(.white, lineWidth: 1) }
                        .contentShape(Capsule())
                }
                .buttonStyle(DSSceneEntranceButtonStyle())
                .accessibilityIdentifier("hub.design.activities")
            }
            .padding(24)
            .foregroundStyle(.white)
        }
        .background(Color.dsTravelNavy)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(.white.opacity(0.5), lineWidth: 0.8)
        }
    }

    private var appointmentEntrance: some View {
        Button { onOpen(.appointments) } label: {
            HStack(spacing: 14) {
                AvatarBadge(name: "Oliver", size: 48, imageName: "avatar_oliver")
                VStack(alignment: .leading, spacing: 6) {
                    Text("赴约").font(.caption).foregroundStyle(Color.dsSceneTextTertiary)
                    Text("和 Oliver 一起散步").font(.body.weight(.medium))
                        .fixedSize(horizontal: false, vertical: true)
                    Text("明天 15:00 · 泰晤士河南岸")
                        .font(.caption).foregroundStyle(Color.dsSceneTextSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.dsSceneTextTertiary)
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .dsSceneGlass(radius: 22, interactive: true, legibility: .shielded)
            .contentShape(RoundedRectangle(cornerRadius: 22))
        }
        .buttonStyle(DSSceneEntranceButtonStyle())
        .accessibilityIdentifier("hub.design.appointments")
    }

    @ViewBuilder private var secondaryEntrances: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(spacing: 16) {
                storyEntrance.frame(height: 180)
                mapEntrance.frame(height: 150)
            }
        } else {
            GeometryReader { geometry in
                HStack(spacing: 14) {
                    storyEntrance.frame(width: (geometry.size.width - 14) * 0.59)
                    mapEntrance
                }
            }
            .frame(height: 156)
        }
    }

    private var storyEntrance: some View {
        Button { onOpen(.stories) } label: {
            ZStack(alignment: .bottomLeading) {
                if let photo = DebugHubDesignAssets.bookshopPhoto {
                    ActivityPlacePhoto(photo: photo)
                }
                LinearGradient(colors: [.clear, .black.opacity(0.76)],
                               startPoint: .top, endPoint: .bottom)
                VStack(alignment: .leading, spacing: 7) {
                    Text("剧情").font(.body.weight(.medium))
                    Text("出发之后 · 伦敦").font(.caption)
                        .foregroundStyle(.white.opacity(0.85))
                }
                .padding(18)
                .foregroundStyle(.white)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
        .buttonStyle(DSSceneEntranceButtonStyle())
        .accessibilityIdentifier("hub.design.stories")
        .contextMenu {
            if let photo = DebugHubDesignAssets.bookshopPhoto {
                Button("照片信息") { creditedPhoto = photo }
            }
        }
    }

    private var mapEntrance: some View {
        Button { onOpen(.map) } label: {
            ZStack(alignment: .topTrailing) {
                Image(systemName: "globe.europe.africa")
                    .font(.system(size: 76, weight: .ultraLight))
                    .foregroundStyle(Color.dsSceneTextTertiary.opacity(0.22))
                    .padding(.top, 12).padding(.trailing, 12)
                VStack(alignment: .leading, spacing: 7) {
                    Spacer(minLength: 24)
                    Text("世界地图").font(.body.weight(.medium))
                    HStack {
                        Text("15 座城市").font(.caption)
                        Spacer(minLength: 0)
                        Image(systemName: "arrow.up.right").font(.system(size: 11))
                    }
                    .foregroundStyle(Color.dsSceneTextSecondary)
                }
                .padding(18)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .dsSceneGlass(radius: 22, interactive: true, legibility: .shielded)
            .contentShape(RoundedRectangle(cornerRadius: 22))
        }
        .buttonStyle(DSSceneEntranceButtonStyle())
        .accessibilityIdentifier("hub.design.map")
    }
}

struct DebugMyHubDesignPreview: View {
    let onAccount: () -> Void
    let onLearning: () -> Void
    let onFavorites: () -> Void
    let onMemory: () -> Void
    let onSubscription: () -> Void
    let onSettings: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                profile
                learning
                VStack(spacing: 0) {
                    entry("收藏夹", symbol: "bookmark", action: onFavorites)
                    divider
                    entry("记忆档案", symbol: "text.book.closed", action: onMemory)
                }
                .dsSceneGlass(radius: 22, legibility: .shielded)
                VStack(spacing: 0) {
                    entry("会员订阅", symbol: "person.crop.circle.badge.checkmark", value: "免费版", action: onSubscription)
                    divider
                    entry("金币", symbol: "circle.circle", value: "0", action: onAccount)
                    divider
                    entry("AI 积分", symbol: "sparkles", value: "联网查看", action: onAccount)
                }
                .dsSceneGlass(radius: 22, legibility: .shielded)
            }
            .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 24)
        }
        .scrollBounceBehavior(.basedOnSize)
        .background {
            DSSceneBackdrop(imageName: "contacts_london_glass", tone: .cool)
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            DebugHubDesignHeader(title: "我的", onSettings: onSettings)
        }
        .foregroundStyle(Color.dsSceneTextPrimary)
        .toolbar(.hidden, for: .navigationBar)
        .dsSceneTabBarBackground()
    }

    private var profile: some View {
        Button(action: onAccount) {
            HStack(spacing: 16) {
                UserAvatar(name: "旅行者", size: 58)
                VStack(alignment: .leading, spacing: 7) {
                    Text("旅行者").font(.title2.weight(.medium))
                    Label("伦敦", systemImage: "mappin")
                        .font(.subheadline).foregroundStyle(Color.dsSceneTextSecondary)
                }
                Spacer(minLength: 0)
                chevron
            }
            .padding(22).frame(maxWidth: .infinity, alignment: .leading)
            .dsSceneGlass(radius: 22, interactive: true, legibility: .shielded)
        }
        .buttonStyle(DSSceneEntranceButtonStyle())
        .accessibilityIdentifier("hub.design.profile")
    }

    private var learning: some View {
        Button(action: onLearning) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: "book.pages")
                    .font(.system(size: 22, weight: .regular)).frame(width: 26, height: 28)
                VStack(alignment: .leading, spacing: 8) {
                    Text("英语旅程").font(.body.weight(.medium))
                    Text("初中三年级 · 日常交流").font(.subheadline)
                        .foregroundStyle(Color.dsSceneTextSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("等待校准").font(.caption).foregroundStyle(Color.dsSceneTextTertiary)
                }
                Spacer(minLength: 0)
                chevron.padding(.top, 6)
            }
            .padding(20).frame(maxWidth: .infinity, alignment: .leading)
            .dsSceneGlass(radius: 22, interactive: true, legibility: .shielded)
        }
        .buttonStyle(DSSceneEntranceButtonStyle())
        .accessibilityIdentifier("hub.design.learning")
    }

    private func entry(_ title: String, symbol: String, value: String? = nil,
                       action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: symbol).font(.system(size: 19, weight: .regular))
                    .frame(width: 26)
                Text(title).font(.body)
                Spacer(minLength: 8)
                if let value {
                    Text(value).font(.subheadline).foregroundStyle(Color.dsSceneTextTertiary)
                }
                chevron
            }
            .padding(.horizontal, 20).padding(.vertical, 18)
            .frame(minHeight: 60)
            .contentShape(Rectangle())
        }
        .buttonStyle(DSSceneEntranceButtonStyle())
    }

    private var chevron: some View {
        Image(systemName: "chevron.right").font(.system(size: 12, weight: .medium))
            .foregroundStyle(Color.dsSceneTextTertiary)
    }

    private var divider: some View {
        Rectangle().fill(Color.dsSceneTextPrimary.opacity(0.12)).frame(height: 0.5)
            .padding(.leading, 60).padding(.trailing, 20)
    }
}

private struct DebugHubDesignHeader: View {
    let title: String
    var onSettings: (() -> Void)?

    var body: some View {
        HStack {
            Color.clear.frame(width: 44, height: 44)
            Text(title).font(.headline).frame(maxWidth: .infinity)
            if let onSettings {
                Button(action: onSettings) {
                    Image(systemName: "gearshape").font(.system(size: 21, weight: .regular))
                        .frame(width: 44, height: 44)
                        .dsSceneGlass(radius: 22, interactive: true)
                }
                .buttonStyle(.plain).accessibilityLabel("设置")
            } else {
                Color.clear.frame(width: 44, height: 44)
            }
        }
        .foregroundStyle(Color.dsSceneTextPrimary)
        .padding(.horizontal, 16).padding(.top, 4).padding(.bottom, 12)
    }
}

private enum DebugHubDesignAssets {
    private struct Release: Decodable {
        struct Preview: Decodable { let catalogs: [BackendActivityCatalog] }
        let preview: Preview
    }

    private static let london: BackendActivityCatalog? = {
        guard let url = Bundle.main.url(forResource: "activity-world-release", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let release = try? JSONDecoder().decode(Release.self, from: data) else { return nil }
        return release.preview.catalogs.first { $0.cityId == "london" }
    }()

    static let parkPhoto = london?.places.first { $0.id == "london-primrose-hill" }?.photo
    static let bookshopPhoto = london?.places.first { $0.id == "london-marylebone-bookshop" }?.photo
}
#endif
