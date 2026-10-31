import BackendKit
import DesignSystem
import SwiftUI

/// The rebuilt activity system chooses real places, with story decisions inside an outing.
struct CityPlacesView: View {
    let cityName: String
    let catalog: BackendActivityCatalog
    let onBack: () -> Void
    let onJournal: () -> Void
    let onSelect: (BackendActivityPlace) -> Void
    let resumeTitle: String?
    let onResume: () -> Void
    @State private var credits: BackendActivityPhoto?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(cityName + " · 城市地点").font(.caption).foregroundStyle(DSReadingPalette.secondary)
                    Text("今天想去哪里").font(.system(.largeTitle, design: .serif, weight: .regular))
                    Text("走进这座城市的日常。").font(.subheadline).foregroundStyle(DSReadingPalette.secondary)
                }.padding(.vertical, 8)
                if let resumeTitle {
                    Button(action: onResume) {
                        DSPaper {
                            DSReadingRow(resumeTitle, symbol: "arrow.clockwise", value: "继续外出")
                        }
                    }.buttonStyle(DSReadingPressStyle()).accessibilityIdentifier("activities.resumePlaceOuting")
                }
                ForEach(catalog.places) { place in
                    Button { onSelect(place) } label: {
                        VStack(alignment: .leading, spacing: 0) {
                            ActivityPlacePhoto(photo: place.photo).frame(height: 178).clipped()
                            HStack(spacing: 14) {
                                Text(place.titleZh).font(.headline).fixedSize(horizontal: false, vertical: true)
                                Spacer(minLength: 4)
                                Image(systemName: "arrow.up.right").font(.subheadline).foregroundStyle(DSReadingPalette.tint)
                            }.padding(20).frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
                        }.background(DSReadingPalette.paper).clipShape(RoundedRectangle(cornerRadius: 12))
                            .overlay { RoundedRectangle(cornerRadius: 12).stroke(DSReadingPalette.line, lineWidth: 0.5) }
                            .contentShape(RoundedRectangle(cornerRadius: 12))
                    }.buttonStyle(DSReadingPressStyle()).disabled(resumeTitle != nil)
                        .accessibilityIdentifier("activities.place.\(place.id)")
                        .overlay(alignment: .topTrailing) {
                            Button { credits = place.photo } label: {
                                Image(systemName: "info.circle").font(.system(size: 18))
                                    .frame(width: 44, height: 44)
                                    .background(DSReadingPalette.paper, in: Circle())
                            }.buttonStyle(DSReadingPressStyle())
                                .accessibilityLabel("\(place.titleZh)的照片信息").padding(10)
                        }
                }
            }.padding(.horizontal, 20).padding(.bottom, 24)
                .frame(maxWidth: 620).frame(maxWidth: .infinity)
        }.scrollBounceBehavior(.basedOnSize)
            .safeAreaInset(edge: .top, spacing: 0) {
                HStack {
                    Button(action: onBack) { Image(systemName: "chevron.left").frame(width: 44, height: 44).contentShape(Rectangle()) }
                        .accessibilityLabel("返回首页")
                    Text("城市活动").font(.system(size: 18, weight: .semibold))
                    Spacer()
                    Button(action: onJournal) { Label("足迹", systemImage: "book.closed").frame(minHeight: 44) }
                }.padding(.leading, 28).padding(.trailing, 20).padding(.vertical, 4).background(DSReadingPalette.canvas)
            }
            .foregroundStyle(DSReadingPalette.ink).tint(DSReadingPalette.tint)
            .background(DSReadingPalette.canvas.ignoresSafeArea())
            .sheet(item: $credits) { ActivityPhotoCredits(photo: $0) }
    }
    static var paper: Color { DSReadingPalette.canvas }
}
