import SwiftUI

public struct DSHubScenePhoto: Codable, Sendable, Identifiable {
    public let cityID: String
    public let cityName: String
    public let role: DSCitySceneRole
    public let title: String
    public let assetName: String
    public let author: String
    public let license: String
    public let sourceURL: URL
    public let licenseURL: URL
    public let width: Int
    public let height: Int
    public let outputSHA256: String
    public var id: String { assetName }
    public var placement: String { role == .activities ? "活动首页" : "我的页" }
}

public enum DSHubScenePhotos {
    public static let photos: [DSHubScenePhoto] = {
        struct Manifest: Decodable { let photos: [DSHubScenePhoto] }
        guard let url = Bundle.main.url(forResource: "hub-scene-photos", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let manifest = try? JSONDecoder().decode(Manifest.self, from: data) else { return [] }
        return manifest.photos
    }()

    public static func photos(cityID: String) -> [DSHubScenePhoto] {
        photos.filter { $0.cityID == cityID }
    }
}

public struct DSHubPhotoCreditsView: View {
    private let cityID: String
    @Environment(\.dismiss) private var dismiss

    public init(cityID: String) { self.cityID = cityID }

    public var body: some View {
        NavigationStack {
            List {
                ForEach(DSHubScenePhotos.photos(cityID: cityID)) { photo in
                    Section(photo.placement) {
                        Text(photo.title)
                        Text("\(photo.author) · \(photo.license)").font(.subheadline)
                        Link("查看照片来源", destination: photo.sourceURL)
                        Link("查看使用许可", destination: photo.licenseURL)
                    }
                }
                Text("照片经过竖屏裁切、等比缩小和 JPEG 编码。各衍生图沿用来源许可。")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            .navigationTitle("背景照片").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
        }
    }
}
