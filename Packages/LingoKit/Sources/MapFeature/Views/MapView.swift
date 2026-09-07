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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(
        deps: MapDependencies,
        reloadToken: Int = 0,
        onBack: (@MainActor () -> Void)? = nil
    ) {
        self.deps = deps
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
            Color.dsBackground.ignoresSafeArea()
            interactiveMap
        }
        .overlay(alignment: .top) {
            mapHUD
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
    }

    private var interactiveMap: some View {
        WorldMapCanvas(
            regions: deps.regionCatalog.regions,
            presentations: mapRegionPresentations,
            selectedRegionID: selectedRegionID,
            viewportRequest: viewportRequest,
            viewportInsets: UIEdgeInsets(
                top: 92,
                left: 30,
                bottom: 104,
                right: 30
            ),
            onSelect: selectRegion,
            onTravel: { travelTarget = $0 }
        )
        .ignoresSafeArea()
    }

    private var mapHUD: some View {
        HStack(spacing: 0) {
            if let onBack {
                Button(action: onBack) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.96))
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.pressableCard)
                .accessibilityLabel("返回首页")

                mapHUDDivider
            }

            MapStatusHUD(currentRegion: currentRegion)
                .padding(.horizontal, 7)
                .layoutPriority(2)

            mapHUDDivider

            MapResourceHUD(
                ticketCount: tickets.count,
                coins: profile?.coins
            )
            .padding(.horizontal, 7)
            .layoutPriority(1)

            mapHUDDivider

            NavigationLink(value: MapDestination.ticketStubs) {
                HStack(spacing: 4) {
                    Image(systemName: "ticket.fill")
                        .font(.system(size: 14, weight: .semibold))
                    Text("票根夹")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                }
                .foregroundStyle(.white.opacity(0.94))
                .lineLimit(1)
                .frame(minHeight: 44)
                .padding(.horizontal, 7)
                .contentShape(Rectangle())
            }
            .buttonStyle(.pressableCard)
            .accessibilityLabel("票根夹")
        }
        .frame(height: 54)
        .padding(.horizontal, 4)
        .background(
            Color.dsTravelNavy.opacity(0.34),
            in: RoundedRectangle(cornerRadius: 18, style: .continuous)
        )
        .dsSceneGlass(
            radius: 18,
            tint: .dsTravelNavy,
            legibility: .enhanced
        )
        .dynamicTypeSize(...DynamicTypeSize.large)
        .padding(.horizontal, 14)
        .padding(.top, 8)
        .frame(maxWidth: .infinity, alignment: .top)
        .background(alignment: .top) {
            LinearGradient(
                colors: [
                    Color.dsBackground.opacity(0.44),
                    Color.dsBackground.opacity(0.1),
                    .clear,
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 84)
            .ignoresSafeArea(edges: .top)
            .allowsHitTesting(false)
        }
    }

    private var mapHUDDivider: some View {
        Rectangle()
            .fill(.white.opacity(0.16))
            .frame(width: 0.5, height: 22)
            .accessibilityHidden(true)
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
                distance: 5_800_000
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
        profile = await loadedProfile
        tickets = await loadedTickets ?? []
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
