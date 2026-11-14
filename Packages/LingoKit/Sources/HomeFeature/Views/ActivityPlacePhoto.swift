import BackendKit
import CryptoKit
import DesignSystem
import SwiftUI
import UIKit

public struct ActivityPlacePhoto: View {
    let photo: BackendActivityPhoto
    let contentMode: ContentMode
    @State private var image: UIImage?
    @State private var failed = false
    @State private var attempt = 0
    private static let framing: [String: String] = {
        guard let url = Bundle.main.url(forResource: "activity-photo-framing", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let values = try? JSONDecoder().decode([String: String].self, from: data) else { return [:] }
        return values
    }()
    private var alignment: Alignment {
        switch Self.framing[photo.assetName] {
        case "leading": .leading
        case "trailing": .trailing
        default: .center
        }
    }
    public init(photo: BackendActivityPhoto, contentMode: ContentMode = .fill) {
        self.photo = photo
        self.contentMode = contentMode
    }
    public var body: some View {
        GeometryReader { geometry in
            Group {
                if let image {
                    Image(uiImage: image).resizable().aspectRatio(contentMode: contentMode)
                        .frame(width: geometry.size.width, height: geometry.size.height,
                               alignment: contentMode == .fit ? .center : alignment).clipped()
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
        }
        .task(id: "\(photo.id):\(attempt)") {
            image = nil
            failed = false
            let bytes = await Task.detached(priority: .utility) { () -> Data? in
                guard !photo.assetName.contains("/"), !photo.assetName.contains(".."),
                      let url = Bundle.main.url(forResource: photo.assetName, withExtension: nil, subdirectory: "ActivityPlaces")
                        ?? Bundle.main.url(forResource: photo.assetName, withExtension: nil),
                      let data = try? Data(contentsOf: url),
                      SHA256.hash(data: data).map({ String(format: "%02x", $0) }).joined() == photo.outputSHA256 else { return nil }
                return data
            }.value
            guard !Task.isCancelled else { return }
            image = bytes.flatMap { UIImage(data: $0) }; failed = image == nil
        }.contentShape(Rectangle()).accessibilityLabel("地点实拍")
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
