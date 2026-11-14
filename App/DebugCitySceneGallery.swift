#if DEBUG
import BackendKit
import DesignSystem
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
    private let currentCityID: (() async throws -> String)?
    private let onClose: (() -> Void)?
    @Environment(\.dismiss) private var dismiss
    @State private var cities: [City] = []
    @State private var selectedCityID = ProcessInfo.processInfo.environment["UI_TEST_SCENE_CITY"] ?? "london"
    @State private var showsCities = false
    @State private var visit: BackendActivityPlace?
    @State private var error: String?
    private var city: City? { cities.first { $0.id == selectedCityID } }
    private let ivory = Color(red: 0.975, green: 0.965, blue: 0.945)

    init(currentCityID: (() async throws -> String)? = nil, onClose: (() -> Void)? = nil) {
        self.currentCityID = currentCityID
        self.onClose = onClose
    }

    var body: some View {
        Group {
            if let city {
                ActivitySceneBrowser(cityName: city.nameZh, places: city.places,
                                     onBack: onClose ?? { dismiss() },
                                     onChooseCity: currentCityID == nil ? { showsCities = true } : nil,
                                     onSelect: { visit = $0 })
                    .id(city.id)
            } else if let error {
                ContentUnavailableView {
                    Label("场景清单未能打开", systemImage: "photo")
                } description: {
                    Text(error)
                } actions: {
                    Button("返回", action: onClose ?? { dismiss() })
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
                            Text(item.nameZh).font(.title3.weight(.regular)).tracking(1)
                            Spacer()
                            if item.id == selectedCityID {
                                Image(systemName: "checkmark").font(.system(size: 12, weight: .medium))
                            }
                        }.frame(minHeight: 52).foregroundStyle(Color.dsPaperInk)
                    }.accessibilityIdentifier("sceneGallery.city.\(item.id)")
                        .listRowBackground(Color.clear).listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 6, leading: 32, bottom: 6, trailing: 32))
                }
                .listStyle(.plain).scrollContentBackground(.hidden).background(ivory)
                .navigationTitle("选择城市").navigationBarTitleDisplayMode(.inline)
                .toolbarBackground(ivory, for: .navigationBar)
                .toolbarBackground(.visible, for: .navigationBar)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("取消") { showsCities = false } }
                }
            }.tint(Color.dsPaperInk).preferredColorScheme(.light)
                .presentationBackground(ivory)
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
                let manifest = try JSONDecoder().decode(Manifest.self, from: Data(contentsOf: url))
                if let currentCityID {
                    let identifier = try await currentCityID()
                    guard manifest.cities.contains(where: { $0.id == identifier }) else {
                        throw CocoaError(.fileReadCorruptFile)
                    }
                    selectedCityID = identifier
                }
                guard !Task.isCancelled else { return }
                cities = manifest.cities
                if city == nil { selectedCityID = cities.first?.id ?? "london" }
            } catch { self.error = "暂时无法读取场景，请返回后重试。" }
        }
    }
}
#endif
