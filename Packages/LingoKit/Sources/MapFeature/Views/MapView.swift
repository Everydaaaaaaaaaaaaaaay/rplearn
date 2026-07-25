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
            .safeAreaPadding(.top, 132)
            .safeAreaPadding(.bottom, selectedRegion == nil ? DSSpacing.md : 154)

            VStack(spacing: DSSpacing.sm) {
                topControls
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
            TravelSheet(region: region, deps: deps, tickets: tickets) { outcome in
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

    private var topControls: some View {
        VStack(alignment: .leading, spacing: DSSpacing.sm) {
            HStack(alignment: .center, spacing: DSSpacing.sm) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("选择目的地")
                        .font(.system(.title3, design: .rounded, weight: .bold))
                    Text("点按地图标记或城市名称")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    resetOverview()
                } label: {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.subheadline.weight(.semibold))
                        .frame(width: 36, height: 36)
                        .background(Color.dsSurface, in: Circle())
                }
                .buttonStyle(.pressableCard)
                .accessibilityLabel("显示全部目的地")

                NavigationLink(value: MapDestination.ticketStubs) {
                    Image(systemName: "ticket.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.dsSunset)
                        .frame(width: 36, height: 36)
                        .background(Color.dsSunset.opacity(0.13), in: Circle())
                }
                .buttonStyle(.pressableCard)
                .accessibilityLabel("票根夹")
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: DSSpacing.xs) {
                    ForEach(deps.regionCatalog.regions) { region in
                        Button {
                            select(region)
                        } label: {
                            HStack(spacing: 5) {
                                Text(region.flagEmoji)
                                Text(region.nameZh)
                            }
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(selectedRegionID == region.id ? .white : .primary)
                            .padding(.horizontal, 11)
                            .padding(.vertical, 8)
                            .background(
                                selectedRegionID == region.id ? Color.dsSky : Color.dsSurface,
                                in: Capsule()
                            )
                            .overlay {
                                Capsule().stroke(
                                    selectedRegionID == region.id ? Color.clear : Color.dsBorder,
                                    lineWidth: 1
                                )
                            }
                        }
                        .buttonStyle(.pressableCard)
                    }
                }
            }
        }
        .padding(DSSpacing.sm)
        .dsMaterial(
            .regularMaterial,
            in: RoundedRectangle(cornerRadius: DSRadius.card, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: DSRadius.card, style: .continuous)
                .stroke(Color.dsBorder, lineWidth: 1)
        }
        .padding(.horizontal, DSSpacing.md)
        .padding(.top, DSSpacing.xs)
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
        if profile?.unlockedRegionIDs.contains(region.id) == true { return .unlocked }
        return .locked
    }

    private func usableTickets(for region: Region) -> [ItemDTO] {
        tickets.filter { TravelService.isTicketUsable($0, for: region) }
    }

    private func coordinate(_ region: Region) -> CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: region.latitude, longitude: region.longitude)
    }
}
