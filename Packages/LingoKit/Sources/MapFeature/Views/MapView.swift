import DesignSystem
import DomainKit
import MapKit
import PersistenceKit
import SwiftUI

public struct MapView: View {
    private let deps: MapDependencies
    private let onOpenMainline: @MainActor () -> Void

    @State private var profile: UserProfileDTO?
    @State private var tickets: [ItemDTO] = []
    @State private var completedStories: Set<String> = []
    @State private var position: MapCameraPosition = .automatic
    @State private var selectedRegionID: String?
    @State private var travelTarget: Region?
    @State private var flight: FlightPresentation?
    @State private var feedback: String?
    @State private var showsTicketStubsPreview = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(
        deps: MapDependencies,
        onOpenMainline: @escaping @MainActor () -> Void = {}
    ) {
        self.deps = deps
        self.onOpenMainline = onOpenMainline
    }

    private var selectedRegion: Region? {
        selectedRegionID.flatMap(deps.regionCatalog.region(id:))
    }

    private var currentRegion: Region? {
        profile.flatMap { deps.regionCatalog.region(id: $0.currentRegionID) }
    }

    private var guidance: JourneyMapGuidance? {
        #if DEBUG
        switch ProcessInfo.processInfo.environment["UI_TEST_MAP_GUIDE"] {
        case "single":
            return .travel(
                eyebrow: "主线下一站",
                title: MainlineCatalog.capeTown.title,
                detail: "前往信号山追踪跨洋广播，确认这不是一场巧合。",
                regionIDs: ["capetown"]
            )
        case "two":
            return .travel(
                eyebrow: "分支目标",
                title: "选择下一段城市回声",
                detail: "两个目的地都会推进当前阶段。",
                regionIDs: ["capetown", "singapore"]
            )
        case "multiple":
            return .travel(
                eyebrow: "主线之外",
                title: "把旅程写成自己的故事",
                detail: "选择一座尚未到访的城市继续探索。",
                regionIDs: ["dublin", "edinburgh", "vancouver", "auckland"]
            )
        case "complete":
            return .complete(
                title: "世界地图已经点亮",
                detail: "返回主线重温旅途，或等待下一段城市故事。"
            )
        default:
            break
        }
        #endif
        guard let profile else { return nil }
        return MainlineCatalog.mapGuidance(
            starterRegionID: profile.starterRegionID,
            currentRegionID: profile.currentRegionID,
            completedStoryIDs: completedStories,
            unlockedRegionIDs: Set(profile.unlockedRegionIDs),
            availableSideRegionIDs: deps.regionCatalog.sideRegions.map(\.id)
        )
    }

    public var body: some View {
        ZStack {
            Color.dsBackground.ignoresSafeArea()

            Map(position: $position, interactionModes: [.pan, .zoom]) {
                ForEach(deps.regionCatalog.regions) { region in
                    Annotation(
                        "",
                        coordinate: coordinate(region),
                        anchor: CityPinAnnotationView.mapAnchor
                    ) {
                        CityPinAnnotationView(
                            region: region,
                            state: pinState(region),
                            isSelected: selectedRegionID == region.id,
                            hasUsableTicket: !usableTickets(for: region).isEmpty,
                            onSelect: { select(region) },
                            onAction: { travelTarget = region }
                        )
                    }
                }
            }
            .mapStyle(
                .standard(
                    elevation: .flat,
                    emphasis: .muted,
                    pointsOfInterest: .excludingAll,
                    showsTraffic: false
                )
            )
            .safeAreaPadding(.top, 76)
            .safeAreaPadding(.bottom, guidance == nil ? DSSpacing.md : 172)

            VStack(spacing: 0) {
                mapHUD
                Spacer()
                if let guidance {
                    JourneyGuideView(
                        guidance: guidance,
                        regionCatalog: deps.regionCatalog,
                        state: pinState,
                        ticketCount: { usableTickets(for: $0).count },
                        onTravel: { travelTarget = $0 },
                        onOpenMainline: onOpenMainline
                    )
                    .dynamicTypeSize(...DynamicTypeSize.large)
                    .id(guidance)
                    .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .bottom)))
                    .padding(.horizontal, DSSpacing.md)
                    .padding(.bottom, DSSpacing.md)
                }
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .navigationDestination(for: MapDestination.self) { destination in
            switch destination {
            case .ticketStubs:
                TicketStubsView(stubStore: deps.stubStore, regionCatalog: deps.regionCatalog)
                    .dsTabBarHidden()
            }
        }
        .navigationDestination(isPresented: $showsTicketStubsPreview) {
            TicketStubsView(stubStore: deps.stubStore, regionCatalog: deps.regionCatalog)
                .dsTabBarHidden()
        }
        .sheet(item: $travelTarget) { region in
            TravelSheet(
                region: region,
                requiresTicket: requiresTicket(for: region),
                deps: deps,
                tickets: tickets
            ) { outcome in
                travelTarget = nil
                handle(outcome)
            }
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
        }
        .fullScreenCover(item: $flight) { presentation in
            FlightTransitionOverlay(
                presentation: presentation,
                regionCatalog: deps.regionCatalog
            ) {
                flight = nil
                Task {
                    await reload()
                    if let destination = deps.regionCatalog.region(id: presentation.toRegionID) {
                        selectedRegionID = destination.id
                        resetOverview()
                    }
                }
            }
        }
        .alert(
            feedback ?? "",
            isPresented: Binding(
                get: { feedback != nil },
                set: { if !$0 { feedback = nil } }
            )
        ) {
            Button("好", role: .cancel) {}
        }
        .task {
            await reload()
            #if DEBUG
            let environment = ProcessInfo.processInfo.environment
            showsTicketStubsPreview = environment["UI_TEST_TICKET_STUBS"] == "1"
            if environment["UI_TEST_FLIGHT_ARRIVAL"] != nil
                || environment["UI_TEST_FLIGHT_REVISIT"] != nil
            {
                // 首帧事务结束后再呈现 cover，避免 SwiftUI 丢弃冷启动时的测试状态。
                try? await Task.sleep(for: .milliseconds(250))
            }
            #endif
            presentDebugFlightIfRequested()
        }
        .animation(reduceMotion ? nil : DSAnimation.snappy, value: selectedRegionID)
        .dsTabBarHidden(flight != nil)
    }

    private var mapHUD: some View {
        ZStack(alignment: .topTrailing) {
            MapStatusHUD(
                currentRegion: currentRegion,
                ticketCount: tickets.count,
                coins: profile?.coins
            )
            .padding(.horizontal, DSSpacing.md)
            .padding(.top, DSSpacing.xs)

            HStack(spacing: 8) {
                Button {
                    resetOverview()
                } label: {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.primary)
                        .frame(width: 38, height: 38)
                        .background(.regularMaterial, in: Circle())
                        .overlay {
                            Circle().stroke(.white.opacity(0.72), lineWidth: 1)
                        }
                        .shadow(color: .black.opacity(0.11), radius: 6, y: 2)
                }
                .buttonStyle(.pressableCard)
                .accessibilityLabel("显示全部目的地")

                NavigationLink(value: MapDestination.ticketStubs) {
                    Image(systemName: "ticket.fill")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Color.dsSunset)
                        .frame(width: 38, height: 38)
                        .background(.regularMaterial, in: Circle())
                        .overlay {
                            Circle().stroke(.white.opacity(0.72), lineWidth: 1)
                        }
                        .shadow(color: .black.opacity(0.11), radius: 6, y: 2)
                }
                .buttonStyle(.pressableCard)
                .accessibilityLabel("票根夹")
            }
            .padding(.trailing, DSSpacing.md)
            .padding(.top, 58)
        }
        .dynamicTypeSize(...DynamicTypeSize.large)
        .frame(height: 104)
        .background(alignment: .top) {
            LinearGradient(
                colors: [
                    Color.dsBackground.opacity(0.68),
                    Color.dsBackground.opacity(0.24),
                    .clear,
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 116)
            .ignoresSafeArea(edges: .top)
            .allowsHitTesting(false)
        }
    }

    private func select(_ region: Region) {
        selectedRegionID = region.id
        show(region)
        Haptics.selection()
    }

    private func resetOverview() {
        let guidedRegions = guidance?.destinationRegionIDs.compactMap(
            deps.regionCatalog.region(id:)
        ) ?? []
        let regions = ([currentRegion].compactMap { $0 } + guidedRegions)
        if regions.count > 1 {
            show(regions)
        } else if let region = regions.first ?? selectedRegion ?? deps.regionCatalog.regions.first {
            show(region)
        }
    }

    private func show(_ region: Region, animated: Bool = true) {
        withAnimation(animated && !reduceMotion ? .easeInOut(duration: 0.35) : nil) {
            position = Self.overviewPosition(for: region)
        }
    }

    private func show(_ regions: [Region], animated: Bool = true) {
        guard !regions.isEmpty else { return }
        let points = regions.map { MKMapPoint(coordinate($0)) }
        var rect = points.reduce(MKMapRect.null) { partial, point in
            partial.union(MKMapRect(x: point.x, y: point.y, width: 1, height: 1))
        }
        let minimumPadding = 1_800_000.0
        rect = rect.insetBy(
            dx: -max(rect.width * 0.28, minimumPadding),
            dy: -max(rect.height * 0.28, minimumPadding)
        )
        withAnimation(animated && !reduceMotion ? .easeInOut(duration: 0.35) : nil) {
            position = .rect(rect)
        }
    }

    private static func overviewPosition(for region: Region) -> MapCameraPosition {
        .camera(
            MapCamera(
                centerCoordinate: CLLocationCoordinate2D(
                    latitude: region.latitude,
                    longitude: region.longitude
                ),
                distance: 5_800_000,
                heading: 0,
                pitch: 0
            )
        )
    }

    private func handle(_ outcome: TravelOutcome) {
        switch outcome {
        case .success(let destination, let result):
            let from = result.fromRegionID
            flight = FlightPresentation(
                fromRegionID: from,
                toRegionID: destination.id,
                fromName: deps.regionCatalog.region(id: from)?.nameZh ?? from,
                toName: destination.nameZh,
                ticketStub: result.ticketStub
            )
        case .failure(let message):
            feedback = message
        }
    }

    private func reload() async {
        async let loadedProfile = try? deps.economyStore.profile()
        async let loadedTickets = try? deps.itemStore.unconsumedTickets()
        async let loadedStories = try? deps.storyProgress.completedStoryIDs()
        profile = await loadedProfile
        tickets = await loadedTickets ?? []
        completedStories = await loadedStories ?? []
        if selectedRegionID == nil {
            #if DEBUG
            if let regionID = ProcessInfo.processInfo.environment["UI_TEST_MAP_SELECTED"],
               let region = deps.regionCatalog.region(id: regionID) {
                selectedRegionID = region.id
                show(region, animated: false)
                return
            }
            #endif
            resetOverview()
        }
    }

    private func pinState(_ region: Region) -> CityPinView.PinState {
        if profile?.currentRegionID == region.id { return .current }
        if !requiresTicket(for: region) { return .unlocked }
        return .locked
    }

    private func requiresTicket(for region: Region) -> Bool {
        guard let profile else { return true }
        return TravelService.requiresTicket(to: region, profile: profile)
    }

    private func usableTickets(for region: Region) -> [ItemDTO] {
        tickets.filter { TravelService.isTicketUsable($0, for: region) }
    }

    private func coordinate(_ region: Region) -> CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: region.latitude, longitude: region.longitude)
    }

    private func presentDebugFlightIfRequested() {
        #if DEBUG
        let environment = ProcessInfo.processInfo.environment
        let firstArrivalID = environment["UI_TEST_FLIGHT_ARRIVAL"]
        let revisitID = environment["UI_TEST_FLIGHT_REVISIT"]
        guard let destinationID = firstArrivalID ?? revisitID,
              let destination = deps.regionCatalog.region(id: destinationID)
        else { return }

        let from = currentRegion ?? deps.regionCatalog.region(id: "london")
        let stub = firstArrivalID.map { _ in
            TicketStubDTO(
                id: UUID(uuidString: "019c0123-4567-789a-8bcd-ef0123456799")!,
                fromRegionID: from?.id ?? "london",
                toRegionID: destination.id,
                usedAt: .now,
                serialNumber: "LT-FIRST",
                artSeed: 4
            )
        }
        flight = FlightPresentation(
            fromRegionID: from?.id ?? "london",
            toRegionID: destination.id,
            fromName: from?.nameZh ?? "伦敦",
            toName: destination.nameZh,
            ticketStub: stub
        )
        #endif
    }
}
