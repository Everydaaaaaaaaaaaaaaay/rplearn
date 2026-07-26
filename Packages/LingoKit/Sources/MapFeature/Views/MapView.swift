import DesignSystem
import DomainKit
import MapKit
import PersistenceKit
import SwiftUI

public struct MapView: View {
    private let deps: MapDependencies

    @State private var profile: UserProfileDTO?
    @State private var tickets: [ItemDTO] = []
    @State private var position: MapCameraPosition = .automatic
    @State private var selectedRegionID: String?
    @State private var travelTarget: Region?
    @State private var flight: FlightPresentation?
    @State private var feedback: String?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(deps: MapDependencies) {
        self.deps = deps
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

            Map(position: $position, interactionModes: [.pan, .zoom]) {
                ForEach(deps.regionCatalog.regions) { region in
                    Annotation("", coordinate: coordinate(region), anchor: .bottom) {
                        Button {
                            select(region)
                        } label: {
                            CityPinView(
                                region: region,
                                state: pinState(region),
                                isSelected: selectedRegionID == region.id
                            )
                        }
                        .buttonStyle(.pressableCard)
                        .accessibilityLabel("\(region.nameZh)，\(pinState(region).accessibilityText)")
                        .accessibilityHint("选择这个目的地")
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
            .safeAreaPadding(.bottom, selectedRegion == nil ? DSSpacing.md : 154)

            VStack(spacing: 0) {
                mapHUD
                Spacer()
                if let selectedRegion {
                    CityCard(
                        region: selectedRegion,
                        state: pinState(selectedRegion),
                        ticketCount: usableTickets(for: selectedRegion).count,
                        onTravel: { travelTarget = selectedRegion }
                    )
                    .id(selectedRegion.id)
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
            FlightTransitionOverlay(presentation: presentation) {
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
        .task { await reload() }
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
        guard let region = selectedRegion
            ?? profile.flatMap({ deps.regionCatalog.region(id: $0.currentRegionID) })
            ?? deps.regionCatalog.regions.first
        else { return }

        show(region)
    }

    private func show(_ region: Region, animated: Bool = true) {
        withAnimation(animated && !reduceMotion ? .easeInOut(duration: 0.35) : nil) {
            position = Self.overviewPosition(for: region)
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
        case .success(let destination, let serial):
            let from = profile?.currentRegionID ?? destination.id
            flight = FlightPresentation(
                fromRegionID: from,
                toRegionID: destination.id,
                fromName: deps.regionCatalog.region(id: from)?.nameZh ?? from,
                toName: destination.nameZh,
                serialNumber: serial
            )
        case .failure(let message):
            feedback = message
        }
    }

    private func reload() async {
        profile = try? await deps.economyStore.profile()
        tickets = (try? await deps.itemStore.unconsumedTickets()) ?? []
        if selectedRegionID == nil,
           let region = profile.flatMap({ deps.regionCatalog.region(id: $0.currentRegionID) }) {
            selectedRegionID = region.id
            show(region, animated: false)
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
}
