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
    @State private var isOverview = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(deps: MapDependencies) {
        self.deps = deps
    }

    private var selectedRegion: Region? {
        selectedRegionID.flatMap(deps.regionCatalog.region(id:))
    }

    public var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color.dsSkyDeep, Color.dsBackground],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            Map(position: $position) {
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
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(region.nameZh)，\(pinState(region).accessibilityText)")
                    }
                }
            }
            .mapStyle(.standard(elevation: .realistic, pointsOfInterest: .excludingAll))
            .mapControls {
                MapCompass()
                MapScaleView()
            }
            .safeAreaPadding(.bottom, selectedRegion == nil ? DSSpacing.md : 250)

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
                    .transition(.move(edge: .bottom).combined(with: .opacity))
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
            .presentationDetents([.medium, .large])
        }
        .fullScreenCover(item: $flight) { presentation in
            FlightTransitionOverlay(presentation: presentation) {
                flight = nil
                Task {
                    await reload()
                    if let destination = deps.regionCatalog.region(id: presentation.toRegionID) {
                        focus(on: destination)
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
        .animation(reduceMotion ? nil : DSAnimation.bouncy, value: selectedRegionID)
        .dsTabBarHidden(flight != nil)
    }

    private var topControls: some View {
        VStack(spacing: DSSpacing.sm) {
            HStack(spacing: DSSpacing.xs) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: DSSpacing.xs) {
                        ForEach(deps.regionCatalog.regions) { region in
                            Button {
                                select(region)
                            } label: {
                                HStack(spacing: 5) {
                                    Text(flag(region.countryCode))
                                    Text(region.nameZh)
                                }
                                .font(.caption.weight(.bold))
                                .foregroundStyle(selectedRegionID == region.id ? .white : .primary)
                                .padding(.horizontal, 11)
                                .padding(.vertical, 8)
                                .background(
                                    selectedRegionID == region.id ? Color.dsSky : Color.dsSurface,
                                    in: Capsule()
                                )
                                .overlay {
                                    Capsule().stroke(Color.dsBorder, lineWidth: 1)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                if let profile {
                    Label("\(profile.coins)", systemImage: "circle.grid.2x1.fill")
                        .font(.caption.bold().monospacedDigit())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(Color.dsSunset, in: Capsule())
                }
            }

            HStack {
                NavigationLink(value: MapDestination.ticketStubs) {
                    Label("票根夹", systemImage: "ticket.fill")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Color.dsSunset)
                        .padding(.horizontal, 11)
                        .padding(.vertical, 9)
                        .dsMaterial(.ultraThinMaterial, in: Capsule())
                }
                Spacer()
                Button {
                    toggleOverview()
                } label: {
                    Image(systemName: isOverview ? "location.fill" : "globe.americas.fill")
                        .font(.title3)
                        .frame(width: 42, height: 42)
                        .dsMaterial(.ultraThinMaterial, in: Circle())
                        .overlay { Circle().stroke(Color.dsBorder, lineWidth: 1) }
                }
                .accessibilityLabel(isOverview ? "聚焦当前城市" : "查看地球")
            }
        }
        .padding(.horizontal, DSSpacing.md)
        .padding(.top, DSSpacing.xs)
    }

    private func select(_ region: Region) {
        selectedRegionID = region.id
        isOverview = false
        focus(on: region)
    }

    private func focus(on region: Region) {
        withAnimation(reduceMotion ? nil : DSAnimation.bouncy) {
            position = .camera(
                MapCamera(
                    centerCoordinate: coordinate(region),
                    distance: 6_000,
                    heading: 30,
                    pitch: 55
                )
            )
        }
    }

    private func toggleOverview() {
        isOverview.toggle()
        withAnimation(reduceMotion ? nil : DSAnimation.bouncy) {
            if isOverview {
                position = .camera(
                    MapCamera(
                        centerCoordinate: CLLocationCoordinate2D(latitude: 18, longitude: 25),
                        distance: 20_000_000,
                        heading: 0,
                        pitch: 0
                    )
                )
            } else if let current = profile.flatMap({ deps.regionCatalog.region(id: $0.currentRegionID) }) {
                selectedRegionID = current.id
                focus(on: current)
            }
        }
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
            focus(on: region)
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

    private func flag(_ code: String) -> String {
        code.uppercased().unicodeScalars.reduce(into: "") { result, scalar in
            if let value = Unicode.Scalar(0x1F1E6 + scalar.value - Unicode.Scalar("A").value) {
                result.unicodeScalars.append(value)
            }
        }
    }
}
