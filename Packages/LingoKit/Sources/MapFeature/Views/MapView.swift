import CoreKit
import DesignSystem
import DomainKit
import MapKit
import PersistenceKit
import SwiftUI

public struct MapView: View {
    private let deps: MapDependencies
    private let reloadToken: Int
    private let onBack: (@MainActor () -> Void)?

    @State private var profile: UserProfileDTO?
    @State private var tickets: [ItemDTO] = []
    @State private var selectedRegionID: String?
    @State private var travelTarget: Region?
    @State private var pendingTravelOutcome: TravelOutcome?
    @State private var flight: FlightPresentation?
    @State private var feedback: String?
    @State private var showsTicketStubsPreview = false
    @State private var viewportRevision = 0
    @State private var viewportRequest: MapViewportRequest?
    @Namespace private var zoomNamespace
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(
        deps: MapDependencies,
        reloadToken: Int = 0,
        onBack: (@MainActor () -> Void)? = nil
    ) {
        self.deps = deps
        _profile = State(initialValue: deps.presentationCache?.profile)
        _tickets = State(initialValue: deps.presentationCache?.tickets ?? [])
        _selectedRegionID = State(initialValue: deps.mapCache?.selectedRegionID)
        self.reloadToken = reloadToken
        self.onBack = onBack
    }

    private var selectedRegion: Region? {
        selectedRegionID.flatMap(deps.regionCatalog.region(id:))
    }

    private var currentRegion: Region? {
        profile.flatMap { deps.regionCatalog.region(id: $0.currentRegionID) }
    }

    public var body: some View {
        ZStack {
            Puff.Palette.page.ignoresSafeArea()
            interactiveMap
        }
        .overlay(alignment: .top) {
            mapHUD
        }
        .overlay(alignment: .bottomTrailing) {
            Button { resetOverview() } label: {
                Image(systemName: "globe.europe.africa.fill")
                    .font(.system(size: 22, weight: .regular))
                    .foregroundStyle(PuffCandy.sky.base, PuffCandy.mint.base)
                    .symbolRenderingMode(.palette)
                    .frame(width: 52, height: 52)
            }
            .buttonStyle(PuffCardButtonStyle(radius: 26, lipHeight: 3))
            .accessibilityLabel("回到地球全景")
            .padding(.trailing, 18)
            .padding(.bottom, 18)
        }
        .toolbar(.hidden, for: .navigationBar)
        .navigationDestination(for: MapDestination.self) { destination in
            switch destination {
            case .ticketStubs:
                TicketStubsView(stubStore: deps.stubStore, regionCatalog: deps.regionCatalog)
                    .dsTabBarHidden()
                    .navigationTransition(.zoom(sourceID: MapDestination.ticketStubs, in: zoomNamespace))
            }
        }
        .navigationDestination(isPresented: $showsTicketStubsPreview) {
            TicketStubsView(stubStore: deps.stubStore, regionCatalog: deps.regionCatalog)
                .dsTabBarHidden()
        }
        .sheet(item: $travelTarget, onDismiss: finishPendingTravel) { region in
            TravelSheet(
                region: region,
                requiresTicket: requiresTicket(for: region),
                deps: deps,
                tickets: tickets
            ) { outcome in
                pendingTravelOutcome = outcome
                travelTarget = nil
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
        .dsModalDialog(
            isPresented: Binding(
                get: { feedback != nil },
                set: { if !$0 { feedback = nil } }
            ),
            configuration: feedbackDialog,
            onPrimary: {}
        )
        .task(id: reloadToken) {
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
        .dsTabBarHidden(flight != nil)
        .onChange(of: selectedRegionID) { _, value in deps.mapCache?.selectedRegionID = value }
        .task(id: selectedRegionID, priority: .utility) {
            if let selectedRegionID { await DownloadableContent.prefetchCity(selectedRegionID) }
        }
    }

    private var interactiveMap: some View {
        WorldMapCanvas(
            cache: deps.mapCache,
            initialRegion: currentRegion,
            regions: deps.regionCatalog.regions,
            presentations: mapRegionPresentations,
            selectedRegionID: selectedRegionID,
            viewportRequest: viewportRequest,
            viewportInsets: UIEdgeInsets(
                top: 140,
                left: 30,
                bottom: 104,
                right: 30
            ),
            onSelect: selectRegion,
            onTravel: { travelTarget = $0 }
        )
        .ignoresSafeArea()
    }

    /// 地图页头：返回、标题与当前所在城市、票根夹入口；下一行是机票和金币。浮在地图上方，底下一层白色渐隐保证可读。
    private var mapHUD: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: Puff.Space.s) {
                if let onBack {
                    PuffBackButton(label: "返回首页", action: onBack)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text("世界地图")
                        .font(.puff(.title, Puff.Weight.display))
                        .foregroundStyle(Puff.Palette.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .accessibilityAddTraits(.isHeader)
                    MapStatusHUD(currentRegion: currentRegion)
                }
                Spacer(minLength: 0)
                ticketStubsEntry
            }
            MapResourceHUD(ticketCount: tickets.count, coins: profile?.coins)
        }
        .dynamicTypeSize(...DynamicTypeSize.xLarge)
        .padding(.horizontal, Puff.Space.m)
        .padding(.top, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(alignment: .top) {
            LinearGradient(
                stops: [
                    .init(color: Puff.Palette.page.opacity(0.94), location: 0),
                    .init(color: Puff.Palette.page.opacity(0.7), location: 0.55),
                    .init(color: Puff.Palette.page.opacity(0), location: 1),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .padding(.bottom, -36)
            .ignoresSafeArea(edges: .top)
            .allowsHitTesting(false)
        }
    }

    private var ticketStubsEntry: some View {
        NavigationLink(value: MapDestination.ticketStubs) {
            HStack(spacing: 6) {
                Image(systemName: "ticket.fill")
                    .font(.system(size: 15, weight: Puff.Weight.icon))
                    .foregroundStyle(PuffCandy.bubblegum.base)
                Text("票根夹")
                    .font(.puff(.subheadline, Puff.Weight.emphasis))
                    .foregroundStyle(Puff.Palette.ink)
                    .lineLimit(1)
            }
            .padding(.horizontal, 14)
            .frame(height: 44)
            .background(Puff.Palette.card, in: Capsule())
            .overlay { Capsule().strokeBorder(Puff.Palette.line, lineWidth: 1) }
            .shadow(color: Puff.Palette.ink.opacity(0.06), radius: 6, y: 2)
            .contentShape(Capsule())
        }
        .buttonStyle(.puffSquish)
        .puffZoomSource(id: MapDestination.ticketStubs, in: zoomNamespace, cornerRadius: 22)
        .accessibilityLabel("票根夹")
    }

    private var mapRegionPresentations: [String: MapRegionPresentation] {
        Dictionary(uniqueKeysWithValues: deps.regionCatalog.regions.map { region in
            (
                region.id,
                MapRegionPresentation(
                    state: pinState(region),
                    hasUsableTicket: !usableTickets(for: region).isEmpty
                )
            )
        })
    }

    private func selectRegion(_ regionID: String?) {
        guard selectedRegionID != regionID else { return }
        selectedRegionID = regionID
        if regionID != nil {
            Haptics.selection()
        }
    }

    private func resetOverview() {
        if let region = currentRegion ?? selectedRegion ?? deps.regionCatalog.regions.first {
            show(region)
        }
    }

    private func show(_ region: Region, animated: Bool = true) {
        viewportRevision &+= 1
        viewportRequest = MapViewportRequest(
            revision: viewportRevision,
            target: .camera(
                center: coordinate(region),
                distance: 22_000_000
            ),
            animated: animated && !reduceMotion
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

    private func finishPendingTravel() {
        guard let outcome = pendingTravelOutcome else { return }
        pendingTravelOutcome = nil
        handle(outcome)
    }

    private var feedbackDialog: DSModalDialogConfiguration {
        let message = feedback ?? ""
        let isFailure = ["失败", "不足", "不能", "需要"].contains {
            message.localizedStandardContains($0)
        }
        return DSModalDialogConfiguration(
            eyebrow: "旅行提示",
            title: isFailure ? "暂时无法出发" : "旅程提示",
            message: message,
            icon: isFailure ? "exclamationmark.triangle.fill" : "airplane",
            tone: isFailure ? .danger : .info,
            primaryTitle: "知道了",
            primaryIcon: "checkmark",
            primaryRole: .cancel,
            secondaryTitle: nil
        )
    }

    private func reload() async {
        async let loadedProfile = try? deps.economyStore.profile()
        async let loadedTickets = try? deps.itemStore.unconsumedTickets()
        if let value = await loadedProfile { profile = value }
        if let value = await loadedTickets { tickets = value }
        if selectedRegionID == nil {
            #if DEBUG
            if let regionID = ProcessInfo.processInfo.environment["UI_TEST_MAP_SELECTED"],
               let region = deps.regionCatalog.region(id: regionID) {
                selectedRegionID = region.id
                show(region, animated: false)
                return
            }
            #endif
            if deps.mapCache?.hasCamera != true { resetOverview() }
        }
    }

    private func pinState(_ region: Region) -> CityPinState {
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
