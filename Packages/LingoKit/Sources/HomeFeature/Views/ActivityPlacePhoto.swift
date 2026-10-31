import BackendKit
import CryptoKit
import DesignSystem
import SwiftUI
import UIKit

struct ActivityPlacePhoto: View {
    let photo: BackendActivityPhoto
    @State private var image: UIImage?
    @State private var failed = false
    @State private var attempt = 0
    var body: some View {
        GeometryReader { geometry in
            Group {
                if let image {
                    Image(uiImage: image).resizable().scaledToFill()
                        .frame(width: geometry.size.width, height: geometry.size.height).clipped()
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
        }.accessibilityLabel("地点实拍")
    }
}

struct ActivityPhotoCredits: View {
    let photo: BackendActivityPhoto
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            Form {
                LabeledContent("摄影", value: photo.author)
                LabeledContent("许可", value: photo.license)
                Link("查看照片来源", destination: photo.sourceUrl)
                Link("查看使用许可", destination: photo.licenseUrl).accessibilityIdentifier("activities.photo.license")
            }.navigationTitle("照片信息").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
        }.presentationDetents([.medium, .large])
    }
}
