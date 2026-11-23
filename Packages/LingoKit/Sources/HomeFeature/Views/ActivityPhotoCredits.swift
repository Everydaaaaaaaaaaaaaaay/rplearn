import BackendKit
import DesignSystem
import SwiftUI

/// 地点场景所用实拍的署名与许可。场景是照片经裁切、调色与风格化处理后的版本，天空为绘制。
struct ActivityPhotoCredits: View {
    let photo: BackendActivityPhoto
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: Puff.Space.m) {
            HStack {
                Text("照片信息")
                    .font(.puff(.title3, Puff.Weight.display))
                Spacer()
                Button("完成") { dismiss() }
                    .font(.puff(.body, Puff.Weight.emphasis))
                    .frame(minHeight: 44)
            }
            VStack(spacing: 0) {
                row("摄影", photo.author)
                Rectangle().fill(Puff.Palette.line).frame(height: 1)
                row("许可", photo.license)
            }
            .puffCard(radius: Puff.Radius.medium)
            HStack(spacing: Puff.Space.s) {
                Link(destination: photo.sourceUrl) {
                    Label("照片来源", systemImage: "photo").frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(PuffCardButtonStyle(radius: 22, lipHeight: 3))
                Link(destination: photo.licenseUrl) {
                    Label("使用许可", systemImage: "doc.text").frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(PuffCardButtonStyle(radius: 22, lipHeight: 3))
                .accessibilityIdentifier("activities.photo.license")
            }
            .font(.puff(.subheadline, Puff.Weight.emphasis))
            Text("画面由实拍裁切、调色并风格化，天空为绘制。")
                .font(.puff(.footnote, Puff.Weight.body))
                .foregroundStyle(Puff.Palette.inkSoft)
            Spacer(minLength: 0)
        }
        .foregroundStyle(Puff.Palette.ink)
        .tint(PuffCandy.sky.deep)
        .padding(Puff.Space.l)
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
        .presentationBackground(Puff.Palette.page)
    }

    private func row(_ title: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Puff.Space.m) {
            Text(title)
                .font(.puff(.subheadline, Puff.Weight.emphasis))
                .foregroundStyle(Puff.Palette.inkSoft)
            Spacer(minLength: Puff.Space.s)
            Text(value)
                .font(.puff(.body, Puff.Weight.body))
                .multilineTextAlignment(.trailing)
        }
        .padding(.horizontal, Puff.Space.m)
        .frame(minHeight: 48)
        .accessibilityElement(children: .combine)
    }
}
