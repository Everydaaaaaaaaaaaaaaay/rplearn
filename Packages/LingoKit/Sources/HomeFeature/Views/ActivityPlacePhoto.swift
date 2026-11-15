import BackendKit
import CryptoKit
import DesignSystem
import ImageIO
import SwiftUI
import UIKit

private final class PreparedActivityPhoto: @unchecked Sendable {
    let image: UIImage
    init(_ image: UIImage) { self.image = image }
}

public struct ActivityPlacePhoto: View {
    let photo: BackendActivityPhoto
    let contentMode: ContentMode
    @State private var image: UIImage?
    @State private var failed = false
    @State private var attempt = 0
    @Environment(\.displayScale) private var displayScale
    private static let framing: [String: String] = {
        guard let url = Bundle.main.url(forResource: "activity-photo-framing", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let values = try? JSONDecoder().decode([String: String].self, from: data) else { return [:] }
        return values
    }()
    public init(photo: BackendActivityPhoto, contentMode: ContentMode = .fill) {
        self.photo = photo
        self.contentMode = contentMode
    }
    public var body: some View {
        GeometryReader { geometry in
            let pixelSize = CGSize(width: ceil(geometry.size.width * displayScale),
                                   height: ceil(geometry.size.height * displayScale))
            Group {
                if let image {
                    Image(uiImage: image).resizable().aspectRatio(contentMode: contentMode)
                        .frame(width: geometry.size.width, height: geometry.size.height,
                               alignment: .center).clipped()
                        .accessibilityIdentifier("activities.photo.loaded.\(photo.placeId)")
                } else if failed {
                    VStack(spacing: 8) {
                        Image(systemName: "photo")
                        Text("照片暂时未能打开").font(.caption)
                        Button("重试") { attempt += 1 }.font(.caption.weight(.semibold))
                    }.frame(maxWidth: .infinity, maxHeight: .infinity)
                } else { ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity) }
            }.frame(width: geometry.size.width, height: geometry.size.height)
                .background(Color.dsTravelNavy.opacity(0.06))
                .task(id: "\(photo.outputSHA256):\(attempt):\(pixelSize):\(contentMode)") {
                    image = nil
                    failed = false
                    let fit = contentMode == .fit
                    let horizontalAlignment = Self.framing[photo.assetName] ?? "center"
                    let prepared = await Task.detached(priority: .utility) {
                        Self.prepare(photo, pixelSize: pixelSize, fit: fit, alignment: horizontalAlignment)
                    }.value
                    guard !Task.isCancelled else { return }
                    image = prepared?.image
                    failed = image == nil
                }
        }.contentShape(Rectangle()).accessibilityLabel("地点实拍")
    }

    private nonisolated static func prepare(_ photo: BackendActivityPhoto, pixelSize: CGSize,
                                           fit: Bool, alignment: String) -> PreparedActivityPhoto? {
        guard pixelSize.width > 0, pixelSize.height > 0, photo.width > 0, photo.height > 0 else { return nil }
        return autoreleasepool {
            guard !photo.assetName.contains("/"), !photo.assetName.contains(".."),
                  let url = Bundle.main.url(forResource: photo.assetName, withExtension: nil, subdirectory: "ActivityPlaces")
                    ?? Bundle.main.url(forResource: photo.assetName, withExtension: nil),
                  let data = try? Data(contentsOf: url),
                  SHA256.hash(data: data).map({ String(format: "%02x", $0) }).joined() == photo.outputSHA256,
                  let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
            let widthScale = pixelSize.width / CGFloat(photo.width)
            let heightScale = pixelSize.height / CGFloat(photo.height)
            let scale = min(1, fit ? min(widthScale, heightScale) : max(widthScale, heightScale))
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceShouldCacheImmediately: true,
                kCGImageSourceThumbnailMaxPixelSize: ceil(CGFloat(max(photo.width, photo.height)) * scale),
            ]
            guard let decoded = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
            else { return nil }
            if fit { return PreparedActivityPhoto(UIImage(cgImage: decoded)) }

            // Store only the visible screen-sized bitmap after decoding a landscape source.
            let decodedImage = UIImage(cgImage: decoded)
            let fillScale = max(pixelSize.width / decodedImage.size.width,
                                pixelSize.height / decodedImage.size.height)
            let drawSize = CGSize(width: decodedImage.size.width * fillScale,
                                  height: decodedImage.size.height * fillScale)
            let horizontalFraction: CGFloat
            switch alignment {
            case "leading": horizontalFraction = 0
            case "trailing": horizontalFraction = 1
            default: horizontalFraction = CGFloat(min(1, max(0, Double(alignment) ?? 0.5)))
            }
            let origin = CGPoint(x: (pixelSize.width - drawSize.width) * horizontalFraction,
                                 y: (pixelSize.height - drawSize.height) / 2)
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            format.opaque = true
            let rendered = UIGraphicsImageRenderer(size: pixelSize, format: format).image { _ in
                decodedImage.draw(in: CGRect(origin: origin, size: drawSize))
            }
            return PreparedActivityPhoto(rendered)
        }
    }
}

public struct ActivityPhotoCredits: View {
    let photo: BackendActivityPhoto
    @Environment(\.dismiss) private var dismiss
    private let ivory = Color(red: 0.975, green: 0.965, blue: 0.945)
    public init(photo: BackendActivityPhoto) { self.photo = photo }
    public var body: some View {
        NavigationStack {
            Form {
                LabeledContent("摄影", value: photo.author)
                LabeledContent("许可", value: photo.license)
                Link("查看照片来源", destination: photo.sourceUrl)
                Link("查看使用许可", destination: photo.licenseUrl).accessibilityIdentifier("activities.photo.license")
                Text("照片经过尺寸缩放与 JPEG 转码，页面中可能裁切显示。").font(.footnote).foregroundStyle(.secondary)
            }
            .scrollContentBackground(.hidden).background(ivory)
            .foregroundStyle(Color.dsPaperInk).tint(Color.dsPaperInk)
            .navigationTitle("照片信息").navigationBarTitleDisplayMode(.inline)
                .toolbarBackground(ivory, for: .navigationBar)
                .toolbarBackground(.visible, for: .navigationBar)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
        }.preferredColorScheme(.light).presentationBackground(ivory)
            .presentationDetents([.medium, .large])
    }
}
