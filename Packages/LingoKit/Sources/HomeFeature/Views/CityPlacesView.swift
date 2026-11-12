import BackendKit
import DesignSystem
import SwiftUI

struct CityPlacesView: View {
    let cityName: String
    let catalog: BackendActivityCatalog
    let onBack: () -> Void
    let onJournal: () -> Void
    let onSelect: (BackendActivityPlace) -> Void
    let resumeTitle: String?
    let onResume: () -> Void
    @State private var credits: BackendActivityPhoto?
    private let ink = Color.dsTravelNavy
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 10) {
                    Text(cityName).font(.subheadline.weight(.medium)).foregroundStyle(ink.opacity(0.6))
                    Text("今天想去哪里").font(.system(.largeTitle, design: .serif, weight: .medium))
                    Text("走进这座城市的日常。").font(.subheadline).foregroundStyle(ink.opacity(0.7))
                }.padding(.vertical, 10)
                if let resumeTitle {
                    Button(action: onResume) {
                        Label(resumeTitle, systemImage: "arrow.clockwise")
                            .frame(maxWidth: .infinity, alignment: .leading).padding(18)
                            .background(.white, in: RoundedRectangle(cornerRadius: 18))
                    }.buttonStyle(DSSceneEntranceButtonStyle()).accessibilityIdentifier("activities.resumePlaceOuting")
                }
                ForEach(catalog.places) { place in
                    Button { onSelect(place) } label: {
                        VStack(alignment: .leading, spacing: 0) {
                            ActivityPlacePhoto(photo: place.photo).accessibilityHidden(true).frame(height: 178).clipped()
                            HStack(spacing: 14) {
                                Text(place.titleZh).font(.headline).fixedSize(horizontal: false, vertical: true)
                                Spacer(minLength: 4)
                                Image(systemName: "arrow.up.right").font(.subheadline)
                            }.padding(20).frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
                        }.background(.white).clipShape(RoundedRectangle(cornerRadius: 24))
                            .contentShape(RoundedRectangle(cornerRadius: 24))
                    }.buttonStyle(DSSceneEntranceButtonStyle())
                        .disabled(resumeTitle != nil)
                        .accessibilityIdentifier("activities.place.\(place.id)")
                        .overlay(alignment: .topTrailing) {
                            Button { credits = place.photo } label: {
                                Image(systemName: "info.circle").frame(width: 44, height: 44)
                                    .background(.regularMaterial, in: Circle())
                            }.accessibilityLabel("\(place.titleZh)的照片信息").padding(10)
                        }
                }
            }.padding(.horizontal, 24).padding(.bottom, 30)
                .frame(maxWidth: 620).frame(maxWidth: .infinity)
        }.scrollBounceBehavior(.basedOnSize)
            .safeAreaInset(edge: .top, spacing: 0) {
                HStack {
                    Button(action: onBack) { Image(systemName: "chevron.left").frame(width: 44, height: 44).contentShape(Rectangle()) }.accessibilityLabel("返回首页")
                    Spacer()
                    Button(action: onJournal) { Label("足迹", systemImage: "book.closed").frame(minHeight: 44) }
                }.padding(.leading, 28).padding(.trailing, 14).padding(.vertical, 4).background(Self.paper)
            }
            .foregroundStyle(ink).background(Self.paper)
            .sheet(item: $credits) { ActivityPhotoCredits(photo: $0) }
    }
    static let paper = Color(red: 0.975, green: 0.965, blue: 0.945)
}
