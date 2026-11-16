import BackendKit
import DesignSystem
import DomainKit
import PersistenceKit
import SwiftUI

public struct HomeView: View {
    private let deps: HomeDependencies
    private let reloadToken: Int
    private let isVisible: Bool
    private let activityNamespace: String
    private let onInitialLoad: @MainActor () -> Void
    private let onOpenDestination: @MainActor (HomeDestination) -> Void
    private let onOpenAppointment: (@MainActor (UUID) -> Void)?

    @State private var profile: UserProfileDTO?
    @State private var completedStories: Set<String> = []
    @State private var profileError = false
    @State private var resumableTitle: String?
    @State private var appointment: BackendAppointment?
    @State private var companion: CharacterDTO?
    @State private var appointmentError = false
    @State private var showsBackgroundCredits = false
    @State private var creditedPhoto: BackendActivityPhoto?
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    public init(deps: HomeDependencies, reloadToken: Int = 0, isVisible: Bool = true,
                activityNamespace: String = "", onInitialLoad: @escaping @MainActor () -> Void = {},
                onOpenDestination: @escaping @MainActor (HomeDestination) -> Void = { _ in },
                onOpenAppointment: (@MainActor (UUID) -> Void)? = nil) {
        self.deps = deps
        self.reloadToken = reloadToken
        self.isVisible = isVisible
        self.activityNamespace = activityNamespace
        self.onInitialLoad = onInitialLoad
        self.onOpenDestination = onOpenDestination
        self.onOpenAppointment = onOpenAppointment
    }

    private var currentRegion: Region? {
        #if DEBUG
        if let requested = ProcessInfo.processInfo.environment["UI_TEST_REGION"],
           let region = deps.regionCatalog.region(id: requested) { return region }
        #endif
        return profile.flatMap { deps.regionCatalog.region(id: $0.currentRegionID) }
    }
    private var reloadKey: String { "\(reloadToken)-\(isVisible)" }
    private var places: [BackendActivityPlace] { CityActivityRelease.bundled()?.places(in: currentRegion?.id ?? "") ?? [] }
    private var cover: BackendActivityPlace? { places.first { $0.category == "park" } ?? places.first }
    private var storyCover: BackendActivityPlace? {
        places.first { $0.category == "bookshop" } ?? places.first { $0.id != cover?.id }
    }
    private var storySubtitle: String {
        let journey = MainlineCatalog.journey(starterRegionID: profile?.starterRegionID)
        guard let next = journey.stops.first(where: { !completedStories.contains($0.chapter.storyID) }) else { return "出发之后 · 已完成" }
        return "下一站 · \(deps.regionCatalog.region(id: next.regionID)?.nameZh ?? next.chapter.title)"
    }

    public var body: some View {
        GeometryReader { geometry in
            ScrollView {
                if let region = currentRegion {
                    VStack(spacing: 16) {
                        cityEntrance(region)
                            .frame(height: dynamicTypeSize.isAccessibilitySize ? 420 : min(340, max(260, geometry.size.height * 0.49)))
                        appointmentEntrance
                        secondaryEntrances
                    }
                    .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 24)
                } else if profileError {
                    ContentUnavailableView {
                        Label("旅程暂时无法读取", systemImage: "arrow.clockwise")
                    } actions: {
                        Button("重试") { Task { await reloadProfile() } }
                    }
                    .padding(24).dsSceneGlass(legibility: .frosted).padding(16)
                } else {
                    ProgressView("正在读取旅程").padding(24).dsSceneGlass(legibility: .frosted).padding(16)
                }
            }
            .scrollBounceBehavior(.basedOnSize)
            .refreshable { await reloadProfile(); await reloadOuting(); await reloadAppointment() }
        }
        .background {
            DSSceneBackdrop(imageName: DSCitySceneAssets.imageName(for: .activities, regionID: currentRegion?.id), tone: .cool)
                .accessibilityIdentifier("home.background.\(currentRegion?.id ?? "loading")")
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            DSHubHeader(title: "活动", symbol: "ellipsis", actionLabel: "背景照片与许可") { showsBackgroundCredits = true }
        }
        .foregroundStyle(Color.dsSceneTextPrimary)
        .toolbar(.hidden, for: .navigationBar).dsSceneTabBarBackground()
        .task(id: reloadKey) { if isVisible { await reloadProfile() } }
        .task(id: reloadKey) { if isVisible { await reloadOuting() } }
        .task(id: reloadKey) { if isVisible { await reloadAppointment() } }
        .sheet(isPresented: $showsBackgroundCredits) { DSHubPhotoCreditsView(cityID: currentRegion?.id ?? "london") }
        .sheet(item: $creditedPhoto) { ActivityPhotoCredits(photo: $0) }
    }

    private func cityEntrance(_ region: Region) -> some View {
        ZStack(alignment: .bottomLeading) {
            if let cover { ActivityPlacePhoto(photo: cover.photo) }
            LinearGradient(colors: [.black.opacity(0.08), .clear, .black.opacity(0.64)], startPoint: .top, endPoint: .bottom)
                .allowsHitTesting(false)
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text("城市活动").font(.subheadline.weight(.medium)).tracking(1)
                    Spacer()
                    if let cover {
                        Button { creditedPhoto = cover.photo } label: { Image(systemName: "ellipsis").frame(width: 44, height: 44) }
                            .accessibilityLabel("场景照片信息")
                    }
                }
                Spacer(minLength: 24)
                Text(region.nameZh).font(.system(.largeTitle, design: .serif, weight: .regular)).tracking(3)
                    .accessibilityLabel("当前驻地，\(region.countryNameZh)，\(region.nameZh)")
                if let resumableTitle {
                    Text("上次停留在\(resumableTitle)").font(.subheadline)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Button { onOpenDestination(.activities) } label: {
                    Text(resumableTitle == nil ? "去这里逛逛" : "继续上次外出")
                        .font(.body.weight(.medium)).tracking(1.5)
                        .padding(.horizontal, 24).padding(.vertical, 12)
                        .frame(minHeight: 48)
                        .overlay { Capsule().strokeBorder(.white, lineWidth: 1) }
                        .contentShape(Capsule())
                }
                .buttonStyle(DSSceneEntranceButtonStyle()).accessibilityLabel("城市活动")
                .accessibilityIdentifier("home.activities")
            }
            .padding(24).foregroundStyle(.white)
        }
        .background(Color.dsTravelNavy)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(.white.opacity(0.5), lineWidth: 0.8) }
    }

    private var appointmentEntrance: some View {
        Button {
            if let appointment, let onOpenAppointment { onOpenAppointment(appointment.id) }
            else { onOpenDestination(.appointments) }
        } label: {
            HStack(spacing: 14) {
                if let companion {
                    AvatarBadge(name: companion.displayName, size: 48, imageName: companion.card.avatarAssetName,
                                remoteURL: companion.card.avatarRemoteURL.flatMap(URL.init(string:)), usesPendingPlaceholder: true)
                } else {
                    Image(systemName: "calendar").font(.system(size: 25, weight: .regular)).frame(width: 48, height: 48)
                }
                VStack(alignment: .leading, spacing: 6) {
                    if let appointment {
                        Text(appointment.status == "in_progress" ? "继续赴约" : "赴约")
                            .font(.caption).foregroundStyle(Color.dsSceneTextTertiary)
                        Text(appointment.displayTitle(companionName: companion?.displayName ?? "旅伴"))
                            .font(.body.weight(.medium)).fixedSize(horizontal: false, vertical: true)
                        Text("\(AppointmentDisplayTime.beijing(appointment.startsAt)) 北京时间 · \(appointment.displayCityName) \(appointment.placeName)")
                            .font(.caption).foregroundStyle(Color.dsSceneTextSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        Text("赴约").font(.body.weight(.medium))
                    }
                    if appointmentError { Text("约定暂未更新，进入后可重试").font(.caption).foregroundStyle(Color.dsSceneTextSecondary) }
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.system(size: 12, weight: .medium)).foregroundStyle(Color.dsSceneTextTertiary)
            }
            .padding(18).frame(maxWidth: .infinity, alignment: .leading)
            .dsSceneGlass(radius: 22, interactive: true, legibility: .frosted)
            .contentShape(RoundedRectangle(cornerRadius: 22))
        }
        .buttonStyle(DSSceneEntranceButtonStyle()).accessibilityIdentifier("home.appointments")
    }

    @ViewBuilder private var secondaryEntrances: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(spacing: 16) {
                storyEntrance.frame(minHeight: 220)
                mapEntrance.frame(minHeight: 190)
            }
        } else {
            GeometryReader { geometry in
                HStack(spacing: 14) {
                    storyEntrance.frame(width: (geometry.size.width - 14) * 0.59)
                    mapEntrance
                }
            }.frame(height: 156)
        }
    }

    private var storyEntrance: some View {
        Button { onOpenDestination(.stories) } label: {
            ZStack(alignment: .bottomLeading) {
                if let storyCover { ActivityPlacePhoto(photo: storyCover.photo) }
                LinearGradient(colors: [.clear, .black.opacity(0.76)], startPoint: .top, endPoint: .bottom)
                VStack(alignment: .leading, spacing: 7) {
                    Text("剧情").font(.body.weight(.medium))
                    Text(storySubtitle).font(.caption).foregroundStyle(.white.opacity(0.85))
                        .fixedSize(horizontal: false, vertical: true)
                }.padding(18).foregroundStyle(.white)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity).background(Color.dsTravelNavy)
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
        .buttonStyle(DSSceneEntranceButtonStyle()).accessibilityLabel("剧情，\(storySubtitle)")
        .contextMenu { if let storyCover { Button("照片信息") { creditedPhoto = storyCover.photo } } }
    }

    private var mapEntrance: some View {
        Button { onOpenDestination(.map) } label: {
            ZStack(alignment: .topTrailing) {
                Image(systemName: "globe.europe.africa").font(.system(size: 76, weight: .ultraLight))
                    .foregroundStyle(Color.dsSceneTextTertiary.opacity(0.22)).padding(.top, 12).padding(.trailing, 12)
                VStack(alignment: .leading, spacing: 7) {
                    Spacer(minLength: 24)
                    Text("世界地图").font(.body.weight(.medium))
                    HStack {
                        Text("\(deps.regionCatalog.regions.count) 座城市").font(.caption)
                        Spacer(minLength: 0)
                        Image(systemName: "arrow.up.right").font(.system(size: 11))
                    }.foregroundStyle(Color.dsSceneTextSecondary)
                }.padding(18)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .dsSceneGlass(radius: 22, interactive: true, legibility: .frosted)
            .contentShape(RoundedRectangle(cornerRadius: 22))
        }
        .buttonStyle(DSSceneEntranceButtonStyle()).accessibilityLabel("世界地图")
    }

    private func reloadProfile() async {
        do {
            async let loadedProfile = deps.economyStore.profile()
            async let completed = deps.storyProgress.completedStoryIDs()
            let (newProfile, completedIDs) = try await (loadedProfile, completed)
            guard !Task.isCancelled else { return }
            profile = newProfile
            completedStories = DepartureStoryIdentity.catalogCompletionIDs(completedIDs)
            profileError = currentRegion == nil
        } catch is CancellationError {
        } catch { profileError = true }
        onInitialLoad()
    }

    private func reloadOuting() async {
        do {
            if !activityNamespace.isEmpty,
               let archive = try CityOutingArchive.load(namespace: activityNamespace), archive.needsContinuation {
                resumableTitle = archive.place.titleZh
                return
            }
            let active = try await deps.outingGateway?.activeOuting()
            guard !Task.isCancelled else { return }
            resumableTitle = active?.placeTitleZh
        } catch is CancellationError {
        } catch { /* The activity destination provides its progress recovery controls. */ }
    }

    private func reloadAppointment() async {
        guard let service = deps.appointments else { return }
        do {
            let list = try await service.appointments()
            let next = HomeHubPresentation.nextAppointment(in: list)
            var person: CharacterDTO?
            if let next { person = try? await deps.rosterStore.character(id: next.characterId) }
            guard !Task.isCancelled else { return }
            appointment = next
            companion = person
            appointmentError = false
        } catch is CancellationError {
        } catch { appointmentError = true }
    }
}
