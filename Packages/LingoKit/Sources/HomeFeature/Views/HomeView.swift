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
    private let transitionNamespace: Namespace.ID?
    private let onInitialLoad: @MainActor () -> Void
    private let onOpenDestination: @MainActor (HomeDestination) -> Void
    private let onOpenAppointment: (@MainActor (UUID) -> Void)?

    @State private var loadedProfile: UserProfileDTO?
    @State private var completedStories: Set<String> = []
    @State private var profileError = false
    @State private var resumableTitle: String?
    @State private var appointments = HomeAppointmentPresentation()
    @State private var hasEntered = false
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(deps: HomeDependencies, reloadToken: Int = 0, isVisible: Bool = true,
                activityNamespace: String = "", transitionNamespace: Namespace.ID? = nil,
                onInitialLoad: @escaping @MainActor () -> Void = {},
                onOpenDestination: @escaping @MainActor (HomeDestination) -> Void = { _ in },
                onOpenAppointment: (@MainActor (UUID) -> Void)? = nil) {
        self.deps = deps
        _loadedProfile = State(initialValue: deps.presentationCache?.profile)
        _completedStories = State(initialValue: deps.presentationCache?.completed ?? [])
        self.reloadToken = reloadToken
        self.isVisible = isVisible
        self.activityNamespace = activityNamespace
        self.transitionNamespace = transitionNamespace
        self.onInitialLoad = onInitialLoad
        self.onOpenDestination = onOpenDestination
        self.onOpenAppointment = onOpenAppointment
    }

    private var profile: UserProfileDTO? { deps.presentationCache?.profile ?? loadedProfile }

    private var currentRegion: Region? {
        #if DEBUG
        if let requested = ProcessInfo.processInfo.environment["UI_TEST_REGION"],
           let region = deps.regionCatalog.region(id: requested) { return region }
        #endif
        return profile.flatMap { deps.regionCatalog.region(id: $0.currentRegionID) }
    }
    private var reloadKey: String { "\(reloadToken)-\(isVisible)" }
    private var places: [BackendActivityPlace] { CityActivityRelease.bundled()?.places(in: currentRegion?.id ?? "") ?? [] }
    private var nextStoryRegionID: String? {
        MainlineCatalog.journey(starterRegionID: profile?.starterRegionID).stops
            .first(where: { !completedStories.contains($0.chapter.storyID) })?.regionID
    }
    private var storySubtitle: String {
        let journey = MainlineCatalog.journey(starterRegionID: profile?.starterRegionID)
        guard let next = journey.stops.first(where: { !completedStories.contains($0.chapter.storyID) }) else { return "出发之后 · 已完成" }
        return "下一站 · \(deps.regionCatalog.region(id: next.regionID)?.nameZh ?? next.chapter.title)"
    }

    public var body: some View {
        ScrollView {
            if let region = currentRegion {
                VStack(spacing: Puff.Space.m) {
                    cityEntrance(region)
                        .puffEntrance(index: 0, isShown: hasEntered)
                    appointmentEntrance
                        .puffEntrance(index: 1, isShown: hasEntered)
                    secondaryEntrances
                        .puffEntrance(index: 2, isShown: hasEntered)
                }
                .padding(.horizontal, Puff.Space.m).padding(.top, 2).padding(.bottom, Puff.Space.xl)
            } else if profileError {
                PuffEmptyState("旅程暂时无法读取", mood: .curious) {
                    Button("重试") { Task { await reloadProfile() } }
                        .buttonStyle(PuffCandyButtonStyle(.sky))
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 60)
            } else {
                PuffLoadingDots()
                    .frame(maxWidth: .infinity)
                    .padding(.top, 120)
            }
        }
        .scrollBounceBehavior(.basedOnSize)
        .refreshable { await reloadProfile(); await reloadOuting(); await appointments.reload(using: deps) }
        .background(Puff.Palette.page.ignoresSafeArea())
        .puffPageHeader(title: "活动")
        .onChange(of: currentRegion?.id) { startEntranceIfNeeded() }
        .onAppear { if currentRegion != nil { startEntranceIfNeeded() } }
        .task(id: reloadKey) { if isVisible { await reloadProfile() } }
        .task(id: reloadKey) { if isVisible { await reloadOuting() } }
        .task(id: reloadKey) { if isVisible { await appointments.reload(using: deps) } }
        .task(id: currentRegion?.id, priority: .utility) {
            guard let region = currentRegion else { return }
            // Wait for the hub's first frame to settle before starting speculative background work.
            do { try await Task.sleep(for: .milliseconds(350)) } catch { return }
            guard !Task.isCancelled else { return }
            let windowSize = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
                .flatMap(\.windows).first(where: \.isKeyWindow)
                .map { ($0.bounds.size, $0.screen.scale) }
            let placePhotos = places.map(\.photo)
            let main = MainlineCatalog.journey(starterRegionID: profile?.starterRegionID).stops.prefix(2)
                .map { DSCitySceneAssets.imageName(for: .messages, regionID: $0.regionID) }
            let cities = CityStoryCatalog.chapters.prefix(2)
                .map { DSCitySceneAssets.imageName(for: .contacts, regionID: $0.regionID) }
            let allStoryStrips = MainlineCatalog.chapters.map {
                DSCitySceneAssets.imageName(for: .messages, regionID: $0.regionID)
            } + CityStoryCatalog.chapters.map {
                DSCitySceneAssets.imageName(for: .contacts, regionID: $0.regionID)
            }
            let bgTask = Task.detached(priority: .utility) {
                if let (size, scale) = windowSize {
                    await ActivityPlacePhoto.preload(placePhotos, size: size, scale: scale, limit: 2)
                }
                guard !Task.isCancelled else { return }
                await DSSceneImageCache.preloadThumbnails(allStoryStrips, maxPixelSize: 200)
                guard !Task.isCancelled else { return }
                await DSSceneImageCache.preloadThumbnails(main + cities, maxPixelSize: 720)
            }
            if let cache = deps.presentationCache, let releaseID = deps.activityReleaseID, let gateway = deps.outingGateway {
                _ = try? await cache.refreshCatalog(releaseID: releaseID, cityID: region.id, gateway: gateway)
            }
            await withTaskCancellationHandler {
                await bgTask.value
            } onCancel: {
                bgTask.cancel()
            }
        }
    }

    private func startEntranceIfNeeded() {
        guard !hasEntered else { return }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(40))
            hasEntered = true
        }
    }

    /// 城市卡通全景 + 城市名 + “出去走走”。
    private func cityEntrance(_ region: Region) -> some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: Puff.Space.s))
            : AnyLayout(HStackLayout(alignment: .center, spacing: Puff.Space.s))
        return PuffSceneCard(
            regionID: region.id,
            viewport: .center,
            sceneHeight: dynamicTypeSize.isAccessibilitySize ? 160 : 196,
            isActive: isVisible
        ) {
            layout {
                VStack(alignment: .leading, spacing: 4) {
                    Text(region.nameZh)
                        .font(.puff(.largeTitle, .heavy))
                        .foregroundStyle(Puff.Palette.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .accessibilityLabel("当前驻地，\(region.countryNameZh)，\(region.nameZh)")
                        .accessibilityIdentifier("home.cityName")
                    if let resumableTitle {
                        PuffTag(resumableTitle, systemImage: "clock.arrow.circlepath", candy: .tangerine)
                            .accessibilityLabel("上次停留在\(resumableTitle)")
                    }
                }
                if !dynamicTypeSize.isAccessibilitySize { Spacer(minLength: 0) }
                Button { onOpenDestination(.activities) } label: {
                    Label("出去走走", systemImage: "figure.walk")
                        .labelStyle(.titleAndIcon)
                }
                .buttonStyle(PuffCandyButtonStyle(.sky))
                .accessibilityLabel("出去走走")
                .accessibilityIdentifier("home.activities")
            }
        }
        .matchedHomeTransitionSource(id: .activities, in: transitionNamespace, cornerRadius: Puff.Radius.huge)
    }

    private var appointmentEntrance: some View {
        HomeAppointmentEntrance(model: appointments, onOpenAppointment: onOpenAppointment,
            onOpenDestination: onOpenDestination)
            .matchedHomeTransitionSource(id: .appointments, in: transitionNamespace, cornerRadius: Puff.Radius.large)
    }

    @ViewBuilder private var secondaryEntrances: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(spacing: Puff.Space.m) {
                storyEntrance
                mapEntrance
            }
        } else {
            HStack(alignment: .top, spacing: Puff.Space.s) {
                storyEntrance
                mapEntrance
            }
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// 剧情：下一站城市的小卡通画。
    private var storyEntrance: some View {
        Button { onOpenDestination(.stories) } label: {
            VStack(alignment: .leading, spacing: 0) {
                PuffCityScene(regionID: nextStoryRegionID ?? currentRegion?.id, viewport: .east, isActive: isVisible)
                    .frame(height: 92)
                    .clipShape(RoundedRectangle(cornerRadius: Puff.Radius.large - 6, style: .continuous))
                    .padding([.horizontal, .top], 6)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Image(systemName: "book.fill")
                            .font(.system(size: 14, weight: .heavy))
                            .foregroundStyle(PuffCandy.grape.deep)
                        Text("剧情")
                            .font(.puff(.headline, .heavy))
                            .foregroundStyle(Puff.Palette.ink)
                    }
                    Text(storySubtitle)
                        .font(.puff(.caption, .bold))
                        .foregroundStyle(Puff.Palette.inkSoft)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, Puff.Space.s)
                .padding(.vertical, Puff.Space.s)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .buttonStyle(PuffCardButtonStyle(radius: Puff.Radius.large))
        .accessibilityLabel("剧情，\(storySubtitle)")
        .matchedHomeTransitionSource(id: .stories, in: transitionNamespace, cornerRadius: Puff.Radius.large)
    }

    private var mapEntrance: some View {
        Button { onOpenDestination(.map) } label: {
            VStack(alignment: .leading, spacing: 0) {
                ZStack {
                    RoundedRectangle(cornerRadius: Puff.Radius.large - 6, style: .continuous)
                        .fill(PuffCandy.sky.wash)
                    Image(systemName: "globe.europe.africa.fill")
                        .font(.system(size: 52, weight: .regular))
                        .foregroundStyle(PuffCandy.sky.base, PuffCandy.mint.base)
                        .symbolRenderingMode(.palette)
                        .symbolEffect(.bounce, value: hasEntered)
                }
                .frame(height: 92)
                .padding([.horizontal, .top], 6)
                HStack(spacing: 6) {
                    Image(systemName: "map.fill")
                        .font(.system(size: 14, weight: .heavy))
                        .foregroundStyle(PuffCandy.sky.deep)
                    Text("世界地图")
                        .font(.puff(.headline, .heavy))
                        .foregroundStyle(Puff.Palette.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                .padding(Puff.Space.s)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .buttonStyle(PuffCardButtonStyle(radius: Puff.Radius.large))
        .accessibilityLabel("世界地图")
        .matchedHomeTransitionSource(id: .map, in: transitionNamespace, cornerRadius: Puff.Radius.large)
    }

    private func reloadProfile() async {
        do {
            async let loadedProfile = deps.economyStore.profile()
            async let completed = deps.storyProgress.completedStoryIDs()
            let (newProfile, completedIDs) = try await (loadedProfile, completed)
            guard !Task.isCancelled else { return }
            self.loadedProfile = newProfile
            if let cache = deps.presentationCache {
                await cache.refreshLocal(economy: deps.economyStore, items: deps.itemStore,
                    progress: deps.storyProgress, ticketStubs: deps.ticketStubStore)
            }
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
                resumableTitle = archive.hasEnded ? nil : archive.place.titleZh
                return
            }
            let active = try await deps.outingGateway?.activeOuting()
            guard !Task.isCancelled else { return }
            resumableTitle = active?.placeTitleZh
        } catch is CancellationError {
        } catch { /* The activity destination provides its progress recovery controls. */ }
    }

}

private extension View {
    @ViewBuilder
    func matchedHomeTransitionSource(
        id: HomeDestination,
        in namespace: Namespace.ID?,
        cornerRadius: CGFloat
    ) -> some View {
        if let namespace {
            matchedTransitionSource(id: id, in: namespace) { configuration in
                configuration
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            }
        } else {
            self
        }
    }
}
