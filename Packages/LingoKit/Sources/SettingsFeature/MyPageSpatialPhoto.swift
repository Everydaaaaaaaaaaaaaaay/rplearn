import DesignSystem
import SwiftUI

struct MyPageSpatialPhoto: View {
    let assetName: String
    let camera: CGSize
    let onReady: (Bool) -> Void

    var body: some View {
        DSSceneLayeredPhoto(assetName: assetName, camera: camera,
                         size: MyPageSpatialGeometry.size,
                         backgroundDepth: MyPageSpatialGeometry.backgroundDepth,
                         layers: MyPageSpatialGeometry.layers, onReady: onReady)
    }
}
