import DesignSystem
import DomainKit
import MapKit
import PersistenceKit
import SwiftUI

public struct MapDependencies: Sendable {
    public let economyStore: EconomyStore
    public let itemStore: ItemStore
    public let stubStore: TicketStubStore
    public let travelService: TravelService
    public let economyService: EconomyService
    public let regionCatalog: RegionCatalog

    public init(
        economyStore: EconomyStore,
        itemStore: ItemStore,
        stubStore: TicketStubStore,
        travelService: TravelService,
        economyService: EconomyService,
        regionCatalog: RegionCatalog
    ) {
        self.economyStore = economyStore
        self.itemStore = itemStore
        self.stubStore = stubStore
        self.travelService = travelService
        self.economyService = economyService
        self.regionCatalog = regionCatalog
    }
}

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
        .animation(DSAnimation.bouncy, value: selectedRegionID)
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
                        .background(.ultraThinMaterial, in: Capsule())
                }
                Spacer()
                Button {
                    toggleOverview()
                } label: {
                    Image(systemName: isOverview ? "location.fill" : "globe.americas.fill")
                        .font(.title3)
                        .frame(width: 42, height: 42)
                        .background(.ultraThinMaterial, in: Circle())
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
        withAnimation(DSAnimation.bouncy) {
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
        withAnimation(DSAnimation.bouncy) {
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

public enum MapDestination: Hashable {
    case ticketStubs
}

struct CityPinView: View {
    enum PinState {
        case current
        case unlocked
        case locked

        var accessibilityText: String {
            switch self {
            case .current: "当前城市"
            case .unlocked: "已解锁"
            case .locked: "未解锁"
            }
        }
    }

    let region: Region
    let state: PinState
    let isSelected: Bool

    @State private var pulse = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 2) {
            ZStack {
                if state == .current {
                    Circle()
                        .stroke(Color.dsSky.opacity(0.5), lineWidth: 5)
                        .frame(width: 58, height: 58)
                        .scaleEffect(pulse ? 1.25 : 0.85)
                        .opacity(pulse ? 0 : 0.9)
                }
                Image(systemName: state == .locked ? "mappin.slash.circle.fill" : "mappin.circle.fill")
                    .font(.system(size: state == .current ? 48 : 38))
                    .foregroundStyle(pinColor)
                    .background {
                        if state == .current {
                            Text(flag(region.countryCode))
                                .font(.system(size: 17))
                                .offset(y: -4)
                        }
                    }
                    .symbolEffect(.bounce, value: isSelected)
            }
            Text(region.nameZh)
                .font(.caption2.weight(.bold))
                .foregroundStyle(.primary)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(.regularMaterial, in: Capsule())
        }
        .scaleEffect(isSelected ? 1.08 : 1)
        .task {
            guard state == .current, !reduceMotion else { return }
            withAnimation(.easeOut(duration: 1.4).repeatForever(autoreverses: false)) {
                pulse = true
            }
        }
    }

    private var pinColor: Color {
        switch state {
        case .current: .dsSky
        case .unlocked: .dsCyan
        case .locked: .gray
        }
    }

    private func flag(_ code: String) -> String {
        code.uppercased().unicodeScalars.reduce(into: "") { result, scalar in
            if let value = Unicode.Scalar(0x1F1E6 + scalar.value - Unicode.Scalar("A").value) {
                result.unicodeScalars.append(value)
            }
        }
    }
}

private struct CityCard: View {
    let region: Region
    let state: CityPinView.PinState
    let ticketCount: Int
    let onTravel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: DSSpacing.sm) {
            HStack(alignment: .top, spacing: DSSpacing.sm) {
                ZStack {
                    RoundedRectangle(cornerRadius: DSRadius.inline, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    DSScenePalette.city(region.id).skyTop,
                                    DSScenePalette.city(region.id).silhouetteNear,
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                    Image(systemName: landmarkIcon)
                        .font(.system(size: 30, weight: .bold))
                        .foregroundStyle(.white.opacity(0.9))
                }
                .frame(width: 76, height: 76)

                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        Text(region.nameZh)
                            .font(.title2.bold())
                        DSChip(state.accessibilityText, tint: state == .current ? .dsSuccess : .dsSky)
                    }
                    Text("\(region.countryNameZh) · \(region.taglineZh)")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }

            HStack(spacing: DSSpacing.sm) {
                Label("可用机票 ×\(ticketCount)", systemImage: "ticket.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.dsSunset)
                Spacer()
                if state != .current {
                    Button {
                        onTravel()
                    } label: {
                        Label("前往", systemImage: "airplane")
                    }
                    .buttonStyle(.duo(.primary, fullWidth: false, compact: true))
                } else {
                    Label("你在这里", systemImage: "location.fill")
                        .font(.subheadline.bold())
                        .foregroundStyle(Color.dsSuccess)
                }
            }
        }
        .dsCard()
    }

    private var landmarkIcon: String {
        switch region.id {
        case "melbourne": "tram.fill"
        case "newyork": "building.2.fill"
        default: "clock.fill"
        }
    }
}

private enum TravelOutcome {
    case success(region: Region, serial: String)
    case failure(String)
}

private struct TravelSheet: View {
    let region: Region
    let deps: MapDependencies
    let tickets: [ItemDTO]
    let onDone: (TravelOutcome) -> Void

    @State private var isWorking = false

    private var usable: [ItemDTO] {
        tickets.filter { TravelService.isTicketUsable($0, for: region) }
    }

    var body: some View {
        VStack(spacing: DSSpacing.lg) {
            Capsule().fill(.tertiary).frame(width: 38, height: 5).padding(.top, 8)
            ZStack {
                Circle().fill(Color.dsSky.opacity(0.12))
                Image(systemName: "airplane.departure")
                    .font(.system(size: 34, weight: .bold))
                    .foregroundStyle(Color.dsSky)
            }
            .frame(width: 76, height: 76)
            Text("前往 \(region.nameZh)")
                .font(.title2.bold())
            Text(region.taglineZh)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            if let ticket = usable.first {
                Label(
                    ticket.type == .ticketUniversal ? "使用通用机票" : "使用 \(ticket.countryCode ?? "") 国家机票",
                    systemImage: "ticket.fill"
                )
                .foregroundStyle(Color.dsSunset)
                Button {
                    travel(with: ticket)
                } label: {
                    workingLabel("确认出发")
                }
                .buttonStyle(.duoPrimary)
                .disabled(isWorking)
            } else {
                Text("没有可用的机票")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Button {
                    buyAndTravel()
                } label: {
                    workingLabel("花 \(EconomyService.Price.universalTicket) 金币购票并出发")
                }
                .buttonStyle(.duoPrimary)
                .disabled(isWorking)
            }
            Spacer()
        }
        .padding(.horizontal, DSSpacing.xl)
    }

    private func workingLabel(_ title: String) -> some View {
        HStack {
            if isWorking { ProgressView().tint(.white) }
            Text(title).frame(maxWidth: .infinity)
        }
    }

    private func travel(with ticket: ItemDTO) {
        isWorking = true
        Task {
            do {
                let stub = try await deps.travelService.travel(to: region, using: ticket)
                Haptics.notify(.success)
                onDone(.success(region: region, serial: stub.serialNumber))
            } catch {
                onDone(.failure("出发失败：\(errorText(error))"))
            }
        }
    }

    private func buyAndTravel() {
        isWorking = true
        Task {
            do {
                let ticket = try await deps.economyService.buyTicket(type: .ticketUniversal)
                let stub = try await deps.travelService.travel(to: region, using: ticket)
                Haptics.notify(.success)
                onDone(.success(region: region, serial: stub.serialNumber))
            } catch {
                onDone(.failure("购票失败：\(errorText(error))"))
            }
        }
    }

    private func errorText(_ error: Error) -> String {
        if case EconomyStore.EconomyError.insufficientCoins = error { return "金币不足" }
        return error.localizedDescription
    }
}
