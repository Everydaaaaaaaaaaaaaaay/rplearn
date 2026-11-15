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

struct AppointmentPhotoView: View {
    let cityID: String
    let cityName: String
    let paused: Bool
    var showsControls = true
    @State private var index = 0
    @State private var credits = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    private var photos: [AppointmentPhoto] { cityID == "london" ? AppointmentPhoto.london : [] }
    private var running: Bool { !paused && !reduceMotion && !credits && scenePhase == .active && photos.count > 1 }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .bottomTrailing) {
                AppointmentStyle.ink
                if !photos.isEmpty,
                   let url = Bundle.module.url(forResource: photos[index % photos.count].id, withExtension: "jpg", subdirectory: "Photos"),
                   let image = UIImage(contentsOfFile: url.path) {
                    Image(uiImage: image).resizable().scaledToFill()
                        .frame(width: geometry.size.width, height: geometry.size.height).clipped()
                        .id(photos[index % photos.count].id).transition(.opacity).accessibilityHidden(true)
                    LinearGradient(colors: [.black.opacity(0.28), .clear, .black.opacity(0.30)], startPoint: .top, endPoint: .bottom).accessibilityHidden(true)
                    if showsControls {
                        Button { credits = true } label: { Label("照片信息", systemImage: "info.circle").font(.caption).padding(12).frame(minHeight: 44) }
                            .foregroundStyle(.white).background(.black.opacity(0.4), in: Capsule()).padding(12)
                    }
                } else {
                    VStack(spacing: 10) { Image(systemName: "photo"); Text("\(cityName)城市实拍素材待准备").font(.subheadline) }.foregroundStyle(.white.opacity(0.85)).frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }.frame(width: geometry.size.width, height: geometry.size.height).clipped()
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
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("照片取景于\(cityName)，用于呈现城市氛围。故事地点以约定为准。")
                        .font(.subheadline).foregroundStyle(AppointmentStyle.ink.opacity(0.7))
                        .padding(24).frame(maxWidth: .infinity, alignment: .leading).appointmentSurface()
                    ForEach(cityID == "london" ? AppointmentPhoto.london : []) { photo in
                        VStack(alignment: .leading, spacing: 14) {
                            Text(photo.title).font(.title3.weight(.semibold))
                            Text("\(photo.author) · \(photo.license)").font(.subheadline)
                                .foregroundStyle(AppointmentStyle.ink.opacity(0.7))
                            if let url = URL(string: photo.source) {
                                Link(destination: url) { Label("Wikimedia Commons", systemImage: "arrow.up.right").frame(minHeight: 44) }
                            }
                            if let url = URL(string: photo.licenseURL) {
                                Link("查看许可", destination: url).frame(minHeight: 44)
                            }
                        }.padding(24).frame(maxWidth: .infinity, alignment: .leading).appointmentSurface()
                    }
                }.padding(22).frame(maxWidth: 640).frame(maxWidth: .infinity)
            }
            .appointmentChrome(cityID: cityID, cityName: cityName)
            .appointmentNavigation("照片来源", backLabel: "返回约定")
        }
        .tint(AppointmentStyle.ink)
    }
}
