#if DEBUG
import BackendKit
import DesignSystem
import HomeFeature
import SwiftUI

/// Local photographic review surface. It never starts an outing or changes the account's city.
struct DebugCitySceneGallery: View {
    private struct Manifest: Decodable {
        let cities: [City]
    }
    private struct City: Decodable, Identifiable {
        let id: String
        let nameZh: String
        let places: [Place]
    }
    private struct Place: Decodable, Identifiable {
        let id: String
        let titleZh: String
        let descriptionZh: String
        let photo: BackendActivityPhoto
    }
    @Environment(\.dismiss) private var dismiss
    @State private var cities: [City] = []
    @State private var selectedCityID = ProcessInfo.processInfo.environment["UI_TEST_SCENE_CITY"] ?? "london"
    @State private var showsCities = false
    @State private var selectedPlace: Place?
    @State private var error: String?
    private let ink = Color.dsTravelNavy
    private let paper = Color(red: 0.975, green: 0.965, blue: 0.945)
    private var city: City? { cities.first { $0.id == selectedCityID } }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    Text("今天想去哪里").font(.system(.largeTitle, design: .serif, weight: .medium))
                    if let error { Text(error) }
                    ForEach(city?.places ?? []) { place in
                        Button { selectedPlace = place } label: {
                            ZStack(alignment: .bottomLeading) {
                                ActivityPlacePhoto(photo: place.photo).accessibilityHidden(true)
                                LinearGradient(colors: [.clear, .black.opacity(0.75)], startPoint: .center, endPoint: .bottom)
                                Text(place.titleZh).font(.title3.weight(.semibold)).foregroundStyle(.white)
                                    .padding(22).fixedSize(horizontal: false, vertical: true)
                            }.frame(height: 230).clipShape(RoundedRectangle(cornerRadius: 24))
                                .contentShape(RoundedRectangle(cornerRadius: 24))
                        }.buttonStyle(DSSceneEntranceButtonStyle())
                            .accessibilityLabel(place.titleZh)
                            .accessibilityIdentifier("sceneGallery.place.\(place.id)")
                    }
                }.padding(24).frame(maxWidth: 620).frame(maxWidth: .infinity)
            }.id(selectedCityID).background(paper).foregroundStyle(ink)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button { showsCities = true } label: {
                            HStack { Text(city?.nameZh ?? "选择城市"); Image(systemName: "chevron.down").font(.caption) }
                                .frame(minHeight: 44)
                        }.accessibilityIdentifier("sceneGallery.cities")
                    }
                    ToolbarItem(placement: .topBarTrailing) { Button("完成") { dismiss() }.frame(minHeight: 44) }
                }
                .navigationTitle("场景预览").navigationBarTitleDisplayMode(.inline)
                .sheet(isPresented: $showsCities) {
                    NavigationStack {
                        List(cities) { item in
                            Button { selectedCityID = item.id; showsCities = false } label: {
                                HStack {
                                    Text(item.nameZh)
                                    Spacer()
                                    if item.id == selectedCityID { Image(systemName: "checkmark") }
                                }.frame(minHeight: 44)
                            }.accessibilityIdentifier("sceneGallery.city.\(item.id)")
                        }.navigationTitle("选择城市").navigationBarTitleDisplayMode(.inline)
                            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { showsCities = false } } }
                    }
                }
                .fullScreenCover(item: $selectedPlace) { place in
                    SceneDetail(place: place, cityName: city?.nameZh ?? "")
                }
        }.tint(ink)
            .task {
                do {
                    guard let url = Bundle.main.url(forResource: "city-scene-gallery", withExtension: "json") else {
                        throw CocoaError(.fileNoSuchFile)
                    }
                    cities = try JSONDecoder().decode(Manifest.self, from: Data(contentsOf: url)).cities
                    if city == nil { selectedCityID = cities.first?.id ?? "london" }
                } catch { self.error = "场景清单未能打开，请重新安装最新预览。" }
            }
    }

    private struct SceneDetail: View {
        let place: Place
        let cityName: String
        @Environment(\.dismiss) private var dismiss
        @Environment(\.dynamicTypeSize) private var dynamicTypeSize
        @State private var showsOriginal = false
        @State private var showsCredits = false
        private let paper = Color(red: 0.975, green: 0.965, blue: 0.945)
        var body: some View {
            ZStack(alignment: .bottom) {
                ActivityPlacePhoto(photo: place.photo).ignoresSafeArea()
                Group {
                    if dynamicTypeSize.isAccessibilitySize {
                        ScrollView { details }.frame(height: 350)
                    } else {
                        details
                    }
                }.background(paper, in: RoundedRectangle(cornerRadius: 28))
                    .clipShape(RoundedRectangle(cornerRadius: 28))
                    .padding(16)
            }.safeAreaInset(edge: .top) {
                HStack {
                    Button { dismiss() } label: {
                        Image(systemName: "chevron.left").frame(width: 44, height: 44)
                            .background(paper, in: Circle())
                    }.accessibilityLabel("返回地点").accessibilityIdentifier("sceneGallery.back")
                    Spacer()
                }.padding(.horizontal, 24).padding(.top, 8)
            }.foregroundStyle(Color.dsTravelNavy).tint(Color.dsTravelNavy)
                .sheet(isPresented: $showsCredits) { ActivityPhotoCredits(photo: place.photo) }
                .fullScreenCover(isPresented: $showsOriginal) {
                    ZStack(alignment: .topTrailing) {
                        Color.black.ignoresSafeArea()
                        ActivityPlacePhoto(photo: place.photo, contentMode: .fit).ignoresSafeArea()
                        Button("完成") { showsOriginal = false }.padding(16)
                            .background(paper, in: Capsule()).padding(20)
                            .accessibilityIdentifier("sceneGallery.original.close")
                    }
                }
        }
        private var details: some View {
            VStack(alignment: .leading, spacing: 14) {
                Text(cityName).font(.subheadline).foregroundStyle(.secondary)
                Text(place.titleZh).font(.system(.title, design: .serif, weight: .medium))
                Text(place.descriptionZh).font(.body).fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 20) {
                    Button("查看全图") { showsOriginal = true }.frame(minHeight: 44)
                        .accessibilityIdentifier("sceneGallery.original")
                    Button("摄影与许可") { showsCredits = true }.frame(minHeight: 44)
                        .accessibilityIdentifier("sceneGallery.credits")
                }
            }.padding(24).frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
#endif
