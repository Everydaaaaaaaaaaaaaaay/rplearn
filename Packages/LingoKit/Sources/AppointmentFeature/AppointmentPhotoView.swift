import DesignSystem
import SwiftUI
import UIKit

struct AppointmentPhoto: Identifiable {
    let id: String
    let title: String
    let author: String
    let license: String
    let source: String
    let licenseURL: String

    static let london: [AppointmentPhoto] = [
        .init(id: "little-venice", title: "Little Venice", author: "Matthias v.d. Elbe", license: "CC BY-SA 4.0", source: "https://commons.wikimedia.org/wiki/File:Little_Venice_in_March.jpg", licenseURL: "https://creativecommons.org/licenses/by-sa/4.0"),
        .init(id: "primrose-hill", title: "Primrose Hill", author: "LatteKnowledge", license: "CC BY-SA 4.0", source: "https://commons.wikimedia.org/wiki/File:London%27s_Skyline_from_Primrose_Hill.jpg", licenseURL: "https://creativecommons.org/licenses/by-sa/4.0"),
        .init(id: "notting-hill", title: "Notting Hill", author: "Bex Walton", license: "CC BY 2.0", source: "https://commons.wikimedia.org/wiki/File:Colourful_houses_in_Lancaster_Road,_Notting_Hill_-_2020-07-05.jpg", licenseURL: "https://creativecommons.org/licenses/by/2.0")
    ]
}

private struct PreparedAppointmentPhoto: @unchecked Sendable { let image: UIImage? }

@MainActor
public enum AppointmentPhotoCache {
    private static let images: NSCache<NSString, UIImage> = {
        let value = NSCache<NSString, UIImage>()
        value.totalCostLimit = 24 * 1_024 * 1_024
        return value
    }()
    private static var loads: [String: Task<PreparedAppointmentPhoto, Never>] = [:]

    public static func cachedImage(id: String) -> UIImage? {
        images.object(forKey: id as NSString)
    }

    public static func load(id: String) async -> UIImage? {
        if let existing = images.object(forKey: id as NSString) { return existing }
        let task: Task<PreparedAppointmentPhoto, Never>
        if let inflight = loads[id] {
            task = inflight
        } else {
            task = Task.detached(priority: .userInitiated) {
                guard let url = Bundle.module.url(forResource: id, withExtension: "jpg", subdirectory: "Photos"),
                      let raw = UIImage(contentsOfFile: url.path) else {
                    return PreparedAppointmentPhoto(image: nil)
                }
                return PreparedAppointmentPhoto(image: raw.preparingForDisplay() ?? raw)
            }
            loads[id] = task
        }
        let value = await task.value
        loads[id] = nil
        if let image = value.image, let bitmap = image.cgImage {
            images.setObject(image, forKey: id as NSString, cost: bitmap.bytesPerRow * bitmap.height)
        }
        return value.image
    }

    public nonisolated static func preload(cityID: String, limit: Int = 1) async {
        guard cityID == "london" else { return }
        let missing = await MainActor.run {
            AppointmentPhoto.london.prefix(limit).map(\.id).filter { images.object(forKey: $0 as NSString) == nil }
        }
        guard !missing.isEmpty else { return }
        for id in missing {
            guard !Task.isCancelled else { return }
            let decoded: PreparedAppointmentPhoto
            if let url = Bundle.module.url(forResource: id, withExtension: "jpg", subdirectory: "Photos"),
               let raw = UIImage(contentsOfFile: url.path) {
                decoded = PreparedAppointmentPhoto(image: raw.preparingForDisplay() ?? raw)
            } else {
                decoded = PreparedAppointmentPhoto(image: nil)
            }
            await MainActor.run {
                if let image = decoded.image, let bitmap = image.cgImage,
                   images.object(forKey: id as NSString) == nil {
                    images.setObject(image, forKey: id as NSString, cost: bitmap.bytesPerRow * bitmap.height)
                }
            }
            await Task.yield()
        }
    }
}

struct AppointmentPhotoView: View {
    let cityID: String
    let cityName: String
    let paused: Bool
    var showsControls = true
    var showsPlaceholder = true
    @State private var index = 0
    @State private var credits = false
    @State private var loadedImage: UIImage?
    @State private var loadedPhotoID: String?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    private var photos: [AppointmentPhoto] { cityID == "london" ? AppointmentPhoto.london : [] }
    private var currentPhoto: AppointmentPhoto? { photos.isEmpty ? nil : photos[index % photos.count] }
    private var running: Bool { !paused && !reduceMotion && !credits && scenePhase == .active && photos.count > 1 }

    var body: some View {
        GeometryReader { geometry in
            let activePhoto = currentPhoto
            let activeImage = activePhoto.flatMap { photo in
                (loadedPhotoID == photo.id ? loadedImage : nil) ?? AppointmentPhotoCache.cachedImage(id: photo.id)
            }
            ZStack(alignment: .bottomTrailing) {
                AppointmentStyle.ink
                if let activePhoto, let image = activeImage {
                    Image(uiImage: image).resizable().scaledToFill()
                        .frame(width: geometry.size.width, height: geometry.size.height).clipped()
                        .id(activePhoto.id).transition(.opacity).accessibilityHidden(true)
                    LinearGradient(colors: [.black.opacity(0.28), .clear, .black.opacity(0.30)], startPoint: .top, endPoint: .bottom).accessibilityHidden(true)
                    if showsControls {
                        Button { credits = true } label: { Label("照片信息", systemImage: "info.circle").font(.caption).padding(12).frame(minHeight: 44) }
                            .foregroundStyle(.white).background(.black.opacity(0.4), in: Capsule()).padding(12)
                    }
                } else if activePhoto == nil && showsPlaceholder {
                    VStack(spacing: 10) { Image(systemName: "photo"); Text("\(cityName)城市实拍素材待准备").font(.subheadline) }.foregroundStyle(.white.opacity(0.85)).frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }.frame(width: geometry.size.width, height: geometry.size.height).clipped()
        }
        .task(id: currentPhoto?.id) {
            guard let photo = currentPhoto else { return }
            if let cached = AppointmentPhotoCache.cachedImage(id: photo.id) {
                loadedImage = cached
                loadedPhotoID = photo.id
                return
            }
            let decoded = await AppointmentPhotoCache.load(id: photo.id)
            guard !Task.isCancelled else { return }
            loadedImage = decoded
            loadedPhotoID = photo.id
        }
        .task(id: running) {
            guard running else { return }
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(18)) } catch { return }
                guard !Task.isCancelled else { return }
                withAnimation(.easeInOut(duration: 0.7)) { index = (index + 1) % photos.count }
            }
        }
        .sheet(isPresented: $credits) { AppointmentPhotoCreditsView(cityID: cityID, cityName: cityName) }
    }
}

struct AppointmentPhotoCreditsView: View {
    let cityID: String
    let cityName: String

    var body: some View {
        NavigationStack {
            AppointmentPage(cityID: cityID, cityName: cityName, title: "照片来源", backLabel: "返回约定") {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("照片取景于\(cityName)，用于呈现城市氛围。故事地点以约定为准。")
                            .font(.subheadline).foregroundStyle(AppointmentStyle.ink.opacity(0.7))
                        AppointmentSectionDivider()
                        ForEach(cityID == "london" ? AppointmentPhoto.london : []) { photo in
                            VStack(alignment: .leading, spacing: 14) {
                                Text(photo.title).font(.headline)
                                Text("\(photo.author) · \(photo.license)").font(.footnote)
                                    .foregroundStyle(AppointmentStyle.ink.opacity(0.65))
                                if let url = URL(string: photo.source) {
                                    Link(destination: url) { Label("Wikimedia Commons", systemImage: "arrow.up.right").frame(minHeight: 44) }
                                }
                                if let url = URL(string: photo.licenseURL) { Link("查看许可", destination: url).frame(minHeight: 44) }
                            }
                            AppointmentSectionDivider()
                        }
                    }.padding(.horizontal, 24).padding(.top, 22).padding(.bottom, 24)
                        .frame(maxWidth: 640).frame(maxWidth: .infinity)
                }.scrollBounceBehavior(.basedOnSize)
            }
        }.tint(AppointmentStyle.ink)
    }
}
