import DesignSystem
import Testing
import UIKit

@Suite("活动与我的独立摄影资源")
struct HubScenePhotoTests {
    @Test @MainActor func allCitiesHaveTwoLoadableIndependentPhotos() throws {
        let photos = DSHubScenePhotos.photos
        #expect(photos.count == 30)
        #expect(Set(photos.map(\.sourceURL)).count == photos.count)
        #expect(Set(photos.map(\.outputSHA256)).count == photos.count)
        for city in DSCitySceneAssets.supportedRegionIDs {
            let pair = DSHubScenePhotos.photos(cityID: city)
            #expect(pair.count == 2)
            #expect(pair.contains { $0.role == .activities })
            #expect(pair.contains { $0.role == .profile })
            for photo in pair {
                #expect(photo.assetName == DSCitySceneAssets.imageName(for: photo.role, regionID: city))
                let image = try #require(UIImage(named: photo.assetName)?.cgImage)
                #expect(image.width == photo.width)
                #expect(image.height == photo.height)
                #expect(Double(photo.height) * 1.2 >= 2622)
                #expect(Double(photo.width) * 1.2 >= 1206)
                #expect(photo.sourceURL.scheme == "https")
                #expect(photo.licenseURL.scheme == "https")
                #expect(!photo.author.isEmpty && !photo.license.isEmpty)
            }
        }
    }
}
