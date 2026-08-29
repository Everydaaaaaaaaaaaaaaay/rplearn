import DesignSystem
import DomainKit
import MapKit
import SwiftUI
import UIKit

struct MapViewportRequest {
    enum Target {
        case camera(center: CLLocationCoordinate2D, distance: CLLocationDistance)
        case rect(MKMapRect)
    }

    let revision: Int
    let target: Target
    let animated: Bool
}

/// Keeps MapKit's native recognizers in sole control of pan, zoom, annotation selection, and
/// momentum. SwiftUI receives only settled selections and travel actions, never per-frame camera
/// updates.
struct WorldMapCanvas: UIViewRepresentable {
    let regions: [Region]
    let presentations: [String: MapRegionPresentation]
    let selectedRegionID: String?
    let viewportRequest: MapViewportRequest?
    let viewportInsets: UIEdgeInsets
    let onSelect: (String?) -> Void
    let onTravel: (Region) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView(frame: .zero)
        mapView.delegate = context.coordinator
        mapView.isScrollEnabled = true
        mapView.isZoomEnabled = true
        mapView.isPitchEnabled = false
        mapView.isRotateEnabled = false
        mapView.showsCompass = false
        mapView.showsScale = false
        mapView.showsUserLocation = false
        mapView.pointOfInterestFilter = .excludingAll

        let configuration = MKStandardMapConfiguration(
            elevationStyle: .flat,
            emphasisStyle: .muted
        )
        configuration.pointOfInterestFilter = .excludingAll
        configuration.showsTraffic = false
        mapView.preferredConfiguration = configuration

        mapView.register(
            RegionAnnotationView.self,
            forAnnotationViewWithReuseIdentifier: RegionAnnotationView.reuseIdentifier
        )
        context.coordinator.installAnnotations(in: mapView)
        return mapView
    }

    func updateUIView(_ mapView: MKMapView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.installAnnotationsIfNeeded(in: mapView)
        context.coordinator.refreshVisibleAnnotations(in: mapView)
        context.coordinator.synchronizeSelection(in: mapView)
        context.coordinator.applyViewportIfNeeded(to: mapView)
    }

    @MainActor
    final class Coordinator: NSObject, MKMapViewDelegate {
        var parent: WorldMapCanvas

        private var annotationsByID: [String: RegionAnnotation] = [:]
        private var lastViewportRevision: Int?
        private var isSynchronizingSelection = false

        init(parent: WorldMapCanvas) {
            self.parent = parent
        }

        func installAnnotations(in mapView: MKMapView) {
            let annotations = parent.regions.map(RegionAnnotation.init)
            annotationsByID = Dictionary(uniqueKeysWithValues: annotations.map { ($0.region.id, $0) })
            mapView.addAnnotations(annotations)
        }

        func installAnnotationsIfNeeded(in mapView: MKMapView) {
            let expectedIDs = Set(parent.regions.map(\.id))
            guard Set(annotationsByID.keys) != expectedIDs else { return }

            mapView.removeAnnotations(Array(annotationsByID.values))
            installAnnotations(in: mapView)
        }

        func refreshVisibleAnnotations(in mapView: MKMapView) {
            for annotation in annotationsByID.values {
                guard let view = mapView.view(for: annotation) as? RegionAnnotationView else { continue }
                configure(view, for: annotation)
            }
        }

        func synchronizeSelection(in mapView: MKMapView) {
            let selected = mapView.selectedAnnotations.compactMap { $0 as? RegionAnnotation }.first
            let target = parent.selectedRegionID.flatMap { annotationsByID[$0] }
            guard selected !== target else { return }

            isSynchronizingSelection = true
            defer { isSynchronizingSelection = false }

            if let selected {
                mapView.deselectAnnotation(selected, animated: false)
            }
            if let target {
                mapView.selectAnnotation(target, animated: false)
            }
        }

        func applyViewportIfNeeded(to mapView: MKMapView) {
            guard let request = parent.viewportRequest,
                  request.revision != lastViewportRevision
            else { return }
            lastViewportRevision = request.revision

            switch request.target {
            case .camera(let center, let distance):
                let camera = MKMapCamera(
                    lookingAtCenter: center,
                    fromDistance: distance,
                    pitch: 0,
                    heading: 0
                )
                mapView.setCamera(camera, animated: request.animated)
            case .rect(let rect):
                mapView.setVisibleMapRect(
                    rect,
                    edgePadding: parent.viewportInsets,
                    animated: request.animated
                )
            }
        }

        func mapView(
            _ mapView: MKMapView,
            viewFor annotation: any MKAnnotation
        ) -> MKAnnotationView? {
            guard let annotation = annotation as? RegionAnnotation else { return nil }
            let view = mapView.dequeueReusableAnnotationView(
                withIdentifier: RegionAnnotationView.reuseIdentifier,
                for: annotation
            ) as! RegionAnnotationView
            configure(view, for: annotation)
            return view
        }

        func mapView(
            _ mapView: MKMapView,
            didSelect view: MKAnnotationView
        ) {
            view.superview?.bringSubviewToFront(view)
            guard !isSynchronizingSelection,
                  let annotation = view.annotation as? RegionAnnotation
            else { return }
            parent.onSelect(annotation.region.id)
        }

        func mapView(
            _ mapView: MKMapView,
            didDeselect view: MKAnnotationView
        ) {
            guard !isSynchronizingSelection else { return }
            DispatchQueue.main.async { [weak mapView, weak self] in
                guard let self, mapView?.selectedAnnotations.isEmpty == true else { return }
                self.parent.onSelect(nil)
            }
        }

        private func configure(
            _ view: RegionAnnotationView,
            for annotation: RegionAnnotation
        ) {
            let presentation = parent.presentations[annotation.region.id]
                ?? MapRegionPresentation(state: .locked, hasUsableTicket: false)
            view.configure(
                region: annotation.region,
                presentation: presentation,
                isSelected: parent.selectedRegionID == annotation.region.id,
                onSelect: { [weak self] in
                    self?.parent.onSelect(annotation.region.id)
                },
                onTravel: { [weak self] in
                    self?.parent.onTravel(annotation.region)
                }
            )
        }
    }
}

private final class RegionAnnotation: NSObject, MKAnnotation {
    let region: Region
    let coordinate: CLLocationCoordinate2D

    init(region: Region) {
        self.region = region
        coordinate = CLLocationCoordinate2D(latitude: region.latitude, longitude: region.longitude)
        super.init()
    }
}

@MainActor
private final class RegionAnnotationView: MKAnnotationView {
    static let reuseIdentifier = "lingotrip.region"

    private static let viewSize = CGSize(width: 132, height: 112)
    private static let photoFrame = CGRect(x: 42, y: 0, width: 48, height: 48)

    private let photoShadowView = UIView()
    private let photoView = UIImageView()
    private let lockedOverlay = UIView()
    private let flagLabel = UILabel()
    private let badgeView = UIImageView()
    private let titleLabel = UILabel()
    private let markerAccessibilityView = AccessibleMarkerView()
    private let actionButton = UIButton(type: .system)

    private var region: Region?
    private var presentation = MapRegionPresentation(state: .locked, hasUsableTicket: false)
    private var onTravel: (() -> Void)?

    override init(annotation: (any MKAnnotation)?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        bounds = CGRect(origin: .zero, size: Self.viewSize)
        centerOffset = CGPoint(x: 0, y: 32)
        backgroundColor = .clear
        canShowCallout = false
        collisionMode = .rectangle
        displayPriority = .required
        zPriority = .defaultUnselected
        selectedZPriority = .max
        isAccessibilityElement = false

        configureSubviews()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        region = nil
        onTravel = nil
        markerAccessibilityView.onActivate = nil
        actionButton.isHidden = true
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        photoShadowView.frame = Self.photoFrame
        photoView.frame = photoShadowView.bounds
        lockedOverlay.frame = photoView.bounds

        flagLabel.frame = CGRect(x: 34, y: 32, width: 18, height: 18)
        badgeView.frame = CGRect(x: 80, y: 32, width: 18, height: 18)

        let titleWidth = min(124, max(52, titleLabel.intrinsicContentSize.width + 16))
        titleLabel.frame = CGRect(
            x: (bounds.width - titleWidth) / 2,
            y: 52,
            width: titleWidth,
            height: 24
        )
        markerAccessibilityView.frame = CGRect(x: 28, y: 0, width: 76, height: 76)

        let actionWidth = min(122, max(82, actionButton.intrinsicContentSize.width + 18))
        actionButton.frame = CGRect(
            x: (bounds.width - actionWidth) / 2,
            y: 80,
            width: actionWidth,
            height: 30
        )
    }

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        markerAccessibilityView.frame.insetBy(dx: -8, dy: -6).contains(point)
            || (!actionButton.isHidden && actionButton.frame.insetBy(dx: -4, dy: -4).contains(point))
    }

    override func setSelected(_ selected: Bool, animated: Bool) {
        super.setSelected(selected, animated: false)
        if selected {
            superview?.bringSubviewToFront(self)
        }
        applySelection(selected)
    }

    func configure(
        region: Region,
        presentation: MapRegionPresentation,
        isSelected: Bool,
        onSelect: @escaping () -> Void,
        onTravel: @escaping () -> Void
    ) {
        self.region = region
        self.presentation = presentation
        self.onTravel = onTravel

        photoView.image = UIImage(named: "city_pin_\(region.id)")
        flagLabel.text = region.flagEmoji
        titleLabel.text = region.nameZh
        lockedOverlay.isHidden = presentation.state != .locked

        markerAccessibilityView.accessibilityLabel = "\(region.nameZh)，\(presentation.state.accessibilityText)"
        markerAccessibilityView.accessibilityHint = "轻点选择城市，拖动可继续移动地图"
        markerAccessibilityView.onActivate = onSelect

        updateBadge()
        updateActionConfiguration()
        applySelection(isSelected)
        setNeedsLayout()
    }

    private func configureSubviews() {
        photoShadowView.backgroundColor = .clear
        photoShadowView.layer.shadowColor = UIColor.black.cgColor
        photoShadowView.layer.shadowOffset = CGSize(width: 0, height: 2)
        addSubview(photoShadowView)

        photoView.contentMode = .scaleAspectFill
        photoView.clipsToBounds = true
        photoView.layer.cornerRadius = 24
        photoShadowView.addSubview(photoView)

        lockedOverlay.backgroundColor = UIColor.black.withAlphaComponent(0.14)
        lockedOverlay.layer.cornerRadius = 24
        lockedOverlay.isUserInteractionEnabled = false
        photoView.addSubview(lockedOverlay)

        flagLabel.font = .systemFont(ofSize: 10)
        flagLabel.textAlignment = .center
        flagLabel.isAccessibilityElement = false
        flagLabel.backgroundColor = UIColor.systemBackground.withAlphaComponent(0.96)
        flagLabel.layer.cornerRadius = 9
        flagLabel.clipsToBounds = true
        addSubview(flagLabel)

        badgeView.contentMode = .center
        badgeView.tintColor = .white
        badgeView.isAccessibilityElement = false
        badgeView.layer.cornerRadius = 9
        badgeView.clipsToBounds = true
        badgeView.layer.borderWidth = 2
        badgeView.layer.borderColor = UIColor.systemBackground.cgColor
        addSubview(badgeView)

        titleLabel.font = .systemFont(ofSize: 11, weight: .bold)
        titleLabel.textAlignment = .center
        titleLabel.textColor = .label
        titleLabel.isAccessibilityElement = false
        titleLabel.backgroundColor = UIColor.systemBackground.withAlphaComponent(0.96)
        titleLabel.layer.cornerRadius = 12
        titleLabel.clipsToBounds = true
        addSubview(titleLabel)

        markerAccessibilityView.backgroundColor = .clear
        markerAccessibilityView.isUserInteractionEnabled = false
        addSubview(markerAccessibilityView)

        actionButton.configuration = .filled()
        actionButton.configuration?.cornerStyle = .capsule
        actionButton.configuration?.imagePadding = 5
        actionButton.configuration?.contentInsets = NSDirectionalEdgeInsets(
            top: 0,
            leading: 9,
            bottom: 0,
            trailing: 9
        )
        actionButton.addAction(
            UIAction { [weak self] _ in
                guard let self, self.presentation.state != .current else { return }
                self.onTravel?()
            },
            for: .primaryActionTriggered
        )
        actionButton.isHidden = true
        addSubview(actionButton)
    }

    private func updateBadge() {
        let symbolName: String
        let backgroundColor: UIColor
        switch presentation.state {
        case .current:
            symbolName = "location.fill"
            backgroundColor = UIColor(Color.dsSuccess)
        case .unlocked:
            symbolName = "checkmark"
            backgroundColor = UIColor(Color.dsSky)
        case .locked:
            symbolName = "lock.fill"
            backgroundColor = .systemGray
        }

        let configuration = UIImage.SymbolConfiguration(pointSize: 8, weight: .bold)
        badgeView.image = UIImage(systemName: symbolName, withConfiguration: configuration)
        badgeView.backgroundColor = backgroundColor
    }

    private func updateActionConfiguration() {
        let title: String
        let symbol: String
        let background: UIColor
        let foreground: UIColor
        switch presentation.state {
        case .current:
            title = "已在这里"
            symbol = "location.fill"
            background = UIColor.secondarySystemBackground.withAlphaComponent(0.96)
            foreground = .secondaryLabel
        case .unlocked:
            title = "前往"
            symbol = "airplane"
            background = UIColor(Color.dsSky)
            foreground = .white
        case .locked:
            title = presentation.hasUsableTicket ? "使用机票" : "购买机票"
            symbol = "ticket.fill"
            background = UIColor(Color.dsSunset)
            foreground = .white
        }

        var configuration = actionButton.configuration ?? .filled()
        configuration.title = title
        configuration.image = UIImage(
            systemName: symbol,
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 10, weight: .black)
        )
        configuration.baseBackgroundColor = background
        configuration.baseForegroundColor = foreground
        configuration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer {
            var attributes = $0
            attributes.font = .systemFont(ofSize: 10, weight: .black)
            return attributes
        }
        actionButton.configuration = configuration
        actionButton.subviews.forEach { $0.isAccessibilityElement = false }
        actionButton.isEnabled = presentation.state != .current
        actionButton.accessibilityLabel = "\(title)：\(region?.nameZh ?? "")"
        actionButton.accessibilityHint = actionAccessibilityHint
    }

    private func applySelection(_ selected: Bool) {
        actionButton.isHidden = !selected
        actionButton.accessibilityElementsHidden = !selected
        layer.zPosition = selected ? 10 : 0
        if selected {
            superview?.bringSubviewToFront(self)
        }

        let ringColor: UIColor
        if selected {
            ringColor = UIColor(Color.dsSky)
        } else {
            switch presentation.state {
            case .current: ringColor = UIColor(Color.dsSuccess)
            case .unlocked: ringColor = UIColor.white.withAlphaComponent(0.92)
            case .locked: ringColor = .separator
            }
        }
        photoView.layer.borderColor = ringColor.cgColor
        photoView.layer.borderWidth = selected ? 3 : (presentation.state == .current ? 2 : 1)
        photoShadowView.layer.shadowOpacity = selected ? 0.2 : 0.08
        photoShadowView.layer.shadowRadius = selected ? 6 : 3
        titleLabel.layer.borderColor = ringColor.withAlphaComponent(selected ? 0.7 : 0.28).cgColor
        titleLabel.layer.borderWidth = 1
        setNeedsLayout()
    }

    private var actionAccessibilityHint: String {
        switch presentation.state {
        case .current: "当前已经在这个城市"
        case .unlocked: "打开出发确认"
        case .locked:
            presentation.hasUsableTicket
                ? "使用已有机票解锁并前往"
                : "购买机票并解锁这个城市"
        }
    }
}

@MainActor
private final class AccessibleMarkerView: UIView {
    var onActivate: (() -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        isAccessibilityElement = true
        accessibilityTraits = .button
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func accessibilityActivate() -> Bool {
        onActivate?()
        return true
    }
}
