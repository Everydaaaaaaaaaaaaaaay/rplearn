#if DEBUG
import BackendKit
import HomeFeature
import SwiftUI

/// Local scene review. The visit button explains the draft content state.
struct DebugCitySceneGallery: View {
    private struct Manifest: Decodable {
        let cities: [City]
    }
    private struct City: Decodable, Identifiable {
        let id: String
        let nameZh: String
        let places: [BackendActivityPlace]
    }
    @Environment(\.dismiss) private var dismiss
    @State private var cities: [City] = []
    @State private var selectedCityID = ProcessInfo.processInfo.environment["UI_TEST_SCENE_CITY"] ?? "london"
    @State private var showsCities = false
    @State private var visit: BackendActivityPlace?
    @State private var error: String?
    private var city: City? { cities.first { $0.id == selectedCityID } }

    var body: some View {
        Group {
            if let city {
                ActivitySceneBrowser(cityName: city.nameZh, places: city.places,
                                     onBack: { dismiss() }, onChooseCity: { showsCities = true },
                                     onSelect: { visit = $0 })
                    .id(city.id)
            } else if let error {
                ContentUnavailableView {
                    Label("场景清单未能打开", systemImage: "photo")
                } description: {
                    Text(error)
                } actions: {
                    Button("返回") { dismiss() }
                }
            } else {
                ProgressView()
            }
        }
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
                }
                .navigationTitle("选择城市").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("取消") { showsCities = false } }
                }
            }.tint(Color.primary)
        }
        .alert("人物剧情正在接入", isPresented: Binding(
            get: { visit != nil }, set: { if !$0 { visit = nil } }
        )) {
            Button("知道了", role: .cancel) { visit = nil }
        } message: {
            Text("已选定\(visit?.titleZh ?? "这个地点")。当前为场景预览，完整相遇内容完成后将从这里进入活动。")
        }
        .task {
            do {
                guard let url = Bundle.main.url(forResource: "city-scene-gallery", withExtension: "json") else {
                    throw CocoaError(.fileNoSuchFile)
                }
                cities = try JSONDecoder().decode(Manifest.self, from: Data(contentsOf: url)).cities
                if city == nil { selectedCityID = cities.first?.id ?? "london" }
            } catch { self.error = "请重新安装最新预览。" }
        }
    }
}
#endif
