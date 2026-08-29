import SwiftUI

struct CityScenePhotoCreditsView: View {
    private struct Credit: Identifiable {
        let city: String
        let placement: String
        let author: String
        let license: String
        let sourceURL: URL

        var id: URL { sourceURL }
    }

    private static let cityOrder = [
        "墨尔本", "纽约", "开普敦", "新加坡", "都柏林", "爱丁堡", "温哥华",
        "奥克兰", "内罗毕", "多伦多", "悉尼", "新奥尔良", "曼彻斯特", "金斯敦",
    ]

    private static let credits: [Credit] = [
        credit("墨尔本", "信息页", "Medelam", "CC BY-SA 4.0", "https://commons.wikimedia.org/wiki/File:Flinders_Street_Station_Main_Building,_May_2019.jpg"),
        credit("墨尔本", "联系人页", "Dietmar Rabich", "CC BY-SA 4.0", "https://commons.wikimedia.org/wiki/File:Melbourne_(AU),_City_Circle_Tram_--_2019_--_1547.jpg"),
        credit("纽约", "信息页", "Daniel Schwen", "Public domain", "https://commons.wikimedia.org/wiki/File:Statue_of_Liberty_frontal_2.jpg"),
        credit("纽约", "联系人页", "Terabass", "CC BY-SA 3.0", "https://commons.wikimedia.org/wiki/File:New_york_times_square-terabass.jpg"),
        credit("开普敦", "信息页", "Matti Blume", "CC BY-SA 4.0", "https://commons.wikimedia.org/wiki/File:Table_Mountain,_Cape_Town_(P1050222).jpg"),
        credit("开普敦", "联系人页", "Martinvl", "CC BY-SA 4.0", "https://commons.wikimedia.org/wiki/File:Dorp_Street,_Bo-Kaap,_Cape_Town.JPG"),
        credit("新加坡", "信息页", "Supanut Arunoprayote", "CC BY 4.0", "https://commons.wikimedia.org/wiki/File:Marina_Bay_Sands_(I).jpg"),
        credit("新加坡", "联系人页", "Bjørn Christian Tørrissen", "CC BY-SA 3.0", "https://commons.wikimedia.org/wiki/File:Singapore_Merlion_BCT.jpg"),
        credit("都柏林", "信息页", "Robert Linsdell", "CC BY 2.0", "https://commons.wikimedia.org/wiki/File:Ha%27penny_Bridge_%26_River_Liffey,_Dublin_(507189)_(32897146055).jpg"),
        credit("都柏林", "联系人页", "David Kernan", "CC BY 4.0", "https://commons.wikimedia.org/wiki/File:Rainy_day_at_Merchant%27s_Arch,_Temple_Bar,_Dublin.jpg"),
        credit("爱丁堡", "信息页", "Saffron Blaze", "CC BY-SA 3.0", "https://commons.wikimedia.org/wiki/File:Edinburgh_Castle_Rock.jpg"),
        credit("爱丁堡", "联系人页", "Andrew Abbott", "CC BY-SA 2.0", "https://commons.wikimedia.org/wiki/File:Victoria_Street,_Edinburgh_-_geograph.org.uk_-_5093825.jpg"),
        credit("温哥华", "信息页", "Murray Foubister", "CC BY-SA 2.0", "https://commons.wikimedia.org/wiki/File:Vancouver_skyline_(49108102623).jpg"),
        credit("温哥华", "联系人页", "Dietmar Rabich", "CC BY-SA 4.0", "https://commons.wikimedia.org/wiki/File:Vancouver_(BC,_Canada),_Gastown_Steam_Clock_--_2022_--_1824.jpg"),
        credit("奥克兰", "信息页", "Jack189417", "CC BY-SA 4.0", "https://commons.wikimedia.org/wiki/File:Sky_Tower_Auckland_from_Federal_st.jpg"),
        credit("奥克兰", "联系人页", "Jorge Royan", "CC BY-SA 3.0", "https://commons.wikimedia.org/wiki/File:The_Westhaven_Bay_harbor,_sailboats_and_the_Skytower,_Auckland_-_0301.jpg"),
        credit("内罗毕", "信息页", "Lebu Ayiga", "CC BY-SA 4.0", "https://commons.wikimedia.org/wiki/File:Aerial_view_of_the_Nairobi_skyline_from_the_KICC_rooftop_at_golden_hour.jpg"),
        credit("内罗毕", "联系人页", "Alexmbogo", "CC BY-SA 4.0", "https://commons.wikimedia.org/wiki/File:A_Maasai_Giraffe_the_Tallest_Animal_in_Kenya_with_Britam_Tower_the_tallest_building_in_Kenya_in_the_background_at_Nairobi_National_Park.jpg"),
        credit("多伦多", "信息页", "Wladyslaw Sojka", "CC BY-SA 3.0", "https://commons.wikimedia.org/wiki/File:Toronto_-_ON_-_CN_Tower_bei_Nacht.jpg"),
        credit("多伦多", "联系人页", "shankar s.", "CC BY 2.0", "https://commons.wikimedia.org/wiki/File:Toronto_tram_(streetcar)_at_night_(27900584565).jpg"),
        credit("悉尼", "信息页", "Benh LIEU SONG", "CC BY-SA 4.0", "https://commons.wikimedia.org/wiki/File:Sydney_Opera_House_and_Harbour_Bridge_Dusk_(2)_2019-06-21.jpg"),
        credit("悉尼", "联系人页", "Dietmar Rabich", "CC BY-SA 4.0", "https://commons.wikimedia.org/wiki/File:Sydney_(AU),_View_from_Opera_House,_Harbour_Bridge_--_2019_--_3070.jpg"),
        credit("新奥尔良", "信息页", "Diego Delso", "CC BY-SA 3.0", "https://commons.wikimedia.org/wiki/File:Bourbon_St,_French_Quarter,_New_Orleans,_USA2.jpg"),
        credit("新奥尔良", "联系人页", "Infrogmation of New Orleans", "CC BY-SA 4.0", "https://commons.wikimedia.org/wiki/File:Streetcar_947_at_St_Charles_and_Burdette,_New_Orleans,_September_2022.jpg"),
        credit("曼彻斯特", "信息页", "Dai O'Nysius", "CC BY-SA 3.0", "https://commons.wikimedia.org/wiki/File:Albert_Square_and_Manchester_Town_Hall_-_panoramio.jpg"),
        credit("曼彻斯特", "联系人页", "G-13114", "CC BY-SA 4.0", "https://commons.wikimedia.org/wiki/File:Tram_entering_Manchester_Victoria.JPG"),
        credit("金斯敦", "信息页", "Caidrro", "Unsplash License", "https://unsplash.com/photos/_52iqVQKEsU"),
        credit("金斯敦", "联系人页", "Avda", "CC BY-SA 3.0", "https://commons.wikimedia.org/wiki/File:Bob_Marley_-_Statue_-_Kingston_-_Jamaica.jpg"),
    ]

    var body: some View {
        List {
            citySections
            licenseSection
        }
        .navigationTitle("城市背景照片")
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private var citySections: some View {
        ForEach(Self.cityOrder, id: \.self) { city in
            Section(city) {
                ForEach(Self.credits.filter { $0.city == city }) { credit in
                    creditRow(credit)
                }
            }
        }
    }

    private func creditRow(_ credit: Credit) -> some View {
        Link(destination: credit.sourceURL) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(credit.placement)
                        .foregroundStyle(.primary)
                    Text("\(credit.author) · \(credit.license)")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                Image(systemName: "arrow.up.right.square")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var licenseSection: some View {
        Section {
            Link(
                "Wikimedia Commons 重用说明",
                destination: URL(string: "https://commons.wikimedia.org/wiki/Commons:Reusing_content_outside_Wikimedia")!
            )
            Link(
                "Unsplash License",
                destination: URL(string: "https://unsplash.com/license")!
            )
        } header: {
            Text("许可说明")
        } footer: {
            Text("照片均为真实摄影，并为移动端背景做了裁切、缩放和 JPEG 压缩；各衍生图沿用上方标注的许可。")
        }
    }

    private static func credit(
        _ city: String,
        _ placement: String,
        _ author: String,
        _ license: String,
        _ source: String
    ) -> Credit {
        Credit(
            city: city,
            placement: placement,
            author: author,
            license: license,
            sourceURL: URL(string: source)!
        )
    }
}
