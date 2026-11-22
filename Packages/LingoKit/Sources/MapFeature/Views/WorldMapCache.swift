import DesignSystem
import DomainKit
import MapKit
import SwiftUI

/// Retains one native renderer per account, including MapKit's camera, tile cache and pins.
@MainActor
public final class WorldMapCache {
    private var map: MKMapView?
    private weak var warmupHost: UIView?
    private var isInUse = false
    private var warmupTask: Task<Void, Never>?
    private var initialRegionID: String?
    private var hasBeenDisplayed = false
    var selectedRegionID: String?
    var hasCamera: Bool { map != nil }

    public init() {}

    private func prepared(region: Region?) -> MKMapView {
        if let map { return map }
        let value = WorldMapCanvas.preparedMapView()
        value.setCamera(MKMapCamera(lookingAtCenter: CLLocationCoordinate2D(
            latitude: region?.latitude ?? 51.5074, longitude: region?.longitude ?? -0.1278),
            fromDistance: 22_000_000, pitch: 0, heading: 0), animated: false)
        initialRegionID = region?.id
        map = value
        return value
    }

    func warmUp(in host: UIView, region: Region?, regions: [Region] = []) {
        warmupHost = host
        // 城市图钉改为程序化卡通小图（PuffCitySnapshot），不再预解码图钉照片。
        guard !isInUse else { return }
        guard map != nil else {
            guard warmupTask == nil else { return }
            warmupTask = Task { @MainActor [weak self, weak host] in
                try? await Task.sleep(for: .milliseconds(250))
                guard let self, !Task.isCancelled else { return }
                warmupTask = nil
                guard let host, !isInUse else { return }
                _ = prepared(region: region)
                warmUp(in: host, region: region, regions: regions)
            }
            return
        }
        let map = prepared(region: region)
        if !regions.isEmpty, map.annotations.isEmpty {
            map.addAnnotations(regions.map(RegionAnnotation.init))
        }
        if !hasBeenDisplayed, let region, initialRegionID != region.id {
            map.setCamera(MKMapCamera(lookingAtCenter: CLLocationCoordinate2D(
                latitude: region.latitude, longitude: region.longitude),
                fromDistance: 22_000_000, pitch: 0, heading: 0), animated: false)
            initialRegionID = region.id
        }
        guard map.superview !== host else { return }
        map.frame = host.bounds
        map.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        host.addSubview(map)
    }

    func acquire(region: Region?) -> MKMapView {
        isInUse = true
        let value = prepared(region: region)
        hasBeenDisplayed = true
        value.removeFromSuperview()
        return value
    }

    func release(_ map: MKMapView) {
        guard self.map === map else { return }
        isInUse = false
        // Let SwiftUI finish removing its host before returning the renderer to warm-up.
        Task { @MainActor [weak self] in
            await Task.yield()
            guard let self, !isInUse, let warmupHost else { return }
            warmUp(in: warmupHost, region: nil)
        }
    }
}

/// Mounted behind the app so the initial globe and shaders warm up before first presentation.
public struct WorldMapWarmupView: UIViewRepresentable {
    private let cache: WorldMapCache
    private let region: Region?
    private let regions: [Region]
    public init(cache: WorldMapCache, region: Region?, regions: [Region] = []) {
        self.cache = cache
        self.region = region
        self.regions = regions
    }
    public func makeUIView(context: Context) -> UIView { UIView() }
    public func updateUIView(_ host: UIView, context: Context) {
        cache.warmUp(in: host, region: region, regions: regions)
    }
}
