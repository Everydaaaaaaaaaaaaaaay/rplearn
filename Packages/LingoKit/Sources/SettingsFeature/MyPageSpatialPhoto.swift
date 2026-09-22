import DesignSystem
import SwiftUI

struct MyPageSpatialPhoto: View {
    let assetName: String
    let camera: CGSize
    let onReady: (Bool) -> Void

    var body: some View {
        DSSceneDepthPhoto(assetName: assetName, camera: camera,
                         size: MyPageSpatialGeometry.size,
                         depth: MyPageSpatialGeometry.depth, onReady: onReady)
    }
}
