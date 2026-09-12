import DesignSystem
import SwiftUI

public struct CityScenePhotoCreditsView: View {
    private struct Credit: Identifiable {
        let city: String
        let placement: String
        let author: String
        let license: String
        let sourceURL: URL

        var id: URL { sourceURL }
    }

    private static let cityOrder = [
        "伦敦", "伦敦", "墨尔本", "纽约", "开普敦", "新加坡", "都柏林", "爱丁堡", "温哥华",
        "奥克兰", "内罗毕", "多伦多", "悉尼", "新奥尔良", "曼彻斯特", "金斯敦",
    ]

    private static let credits: [Credit] = [
        credit("伦敦", "信息页", "Kuriakose John", "Pexels License", "https://www.pexels.com/photo/tower-bridge-in-the-united-kingdom-across-river-thames-13329893/"),
        credit("伦敦", "联系人页", "Colin", "CC BY-SA 4.0", "https://commons.wikimedia.org/wiki/File:Elizabeth_Tower_2014-09-21_151MP.jpg"),
        credit("墨尔本", "信息页", "Medelam", "CC BY-SA 4.0", "https://commons.wikimedia.org/wiki/File:Flinders_Street_Station_Main_Building,_May_2019.jpg"),
        credit("墨尔本", "联系人页", "Dietmar Rabich", "CC BY-SA 4.0", "https://commons.wikimedia.org/wiki/File:Melbourne_(AU),_City_Circle_Tram_--_2019_--_1547.jpg"),
        credit("纽约", "信息页", "Derek Jensen (Tysto)", "Public domain", "https://commons.wikimedia.org/wiki/File:Liberty-statue-from-front2.jpg"),
        credit("纽约", "联系人页", "Terabass", "CC BY-SA 3.0", "https://commons.wikimedia.org/wiki/File:New_york_times_square-terabass.jpg"),
        credit("开普敦", "信息页", "Schavda", "CC BY-SA 3.0", "https://commons.wikimedia.org/wiki/File:TMNP.jpg"),
        credit("开普敦", "联系人页", "Martinvl", "CC BY-SA 4.0", "https://commons.wikimedia.org/wiki/File:Dorp_Street,_Bo-Kaap,_Cape_Town.JPG"),
        credit("新加坡", "信息页", "Wenjie, Zhang  | A Certain Slant of Light", "CC BY 2.0", "https://www.flickr.com/photos/z_wenjie/6530128947/"),
        credit("新加坡", "联系人页", "Bjørn Christian Tørrissen", "CC BY-SA 3.0", "https://commons.wikimedia.org/wiki/File:Singapore_Merlion_BCT.jpg"),
        credit("都柏林", "信息页", "Finn Terman Frederiksen", "CC BY 2.0", "https://www.flickr.com/photos/141812453@N03/42153463580/"),
        credit("都柏林", "联系人页", "Alain Rouiller", "CC BY-SA 2.0", "https://www.flickr.com/photos/alainrouiller/30027952336/"),
        credit("爱丁堡", "信息页", "Scglossop1", "CC BY-SA 4.0", "https://commons.wikimedia.org/wiki/File:Castle_Rock_Edinburgh.jpg"),
        credit("爱丁堡", "联系人页", "rboed", "CC BY 2.0", "https://commons.wikimedia.org/wiki/File:The_Royal_Mile,_Edinburgh,_Scotland.jpg"),
        credit("温哥华", "信息页", "Dietmar Rabich", "CC BY-SA 4.0", "https://commons.wikimedia.org/wiki/File:Vancouver_(BC,_Canada),_Canada_Place_--_2022_--_1906.jpg"),
        credit("温哥华", "联系人页", "Dietmar Rabich", "CC BY-SA 4.0", "https://commons.wikimedia.org/wiki/File:Vancouver_(BC,_Canada),_Gastown_Steam_Clock_--_2022_--_1824.jpg"),
        credit("奥克兰", "信息页", "Jack189417", "CC BY-SA 4.0", "https://commons.wikimedia.org/wiki/File:Sky_Tower_Auckland_from_Federal_st.jpg"),
        credit("奥克兰", "联系人页", "Jorge Royan", "CC BY-SA 3.0", "https://commons.wikimedia.org/wiki/File:The_Westhaven_Bay_harbor,_sailboats_and_the_Skytower,_Auckland_-_0301.jpg"),
        credit("内罗毕", "信息页", "Bahnfrend", "CC BY-SA 4.0", "https://commons.wikimedia.org/wiki/File:Kenyatta_International_Convention_Centre,_2025_(01).jpg"),
        credit("内罗毕", "联系人页", "Alexmbogo", "CC BY-SA 4.0", "https://commons.wikimedia.org/wiki/File:A_Maasai_Giraffe_the_Tallest_Animal_in_Kenya_with_Britam_Tower_the_tallest_building_in_Kenya_in_the_background_at_Nairobi_National_Park.jpg"),
        credit("多伦多", "信息页", "Wladyslaw Sojka", "CC BY-SA 3.0", "https://commons.wikimedia.org/wiki/File:Toronto_-_ON_-_CN_Tower_bei_Nacht.jpg"),
        credit("多伦多", "联系人页", "Filipe Freitas", "Unsplash License", "https://unsplash.com/photos/a-view-of-a-city-with-a-fountain-in-the-middle-of-it-M5s3Vbxlri8"),
        credit("悉尼", "信息页", "Pexels · Photo 16872060", "Pexels License", "https://www.pexels.com/photo/clouds-over-the-sydney-opera-house-16872060/"),
        credit("悉尼", "联系人页", "Caspia Jackmanson", "CC BY 2.0", "https://www.flickr.com/photos/djackmanson/26451768205/"),
        credit("新奥尔良", "信息页", "Diego Delso", "CC BY-SA 3.0", "https://commons.wikimedia.org/wiki/File:Bourbon_St,_French_Quarter,_New_Orleans,_USA2.jpg"),
        credit("新奥尔良", "联系人页", "bvi4092", "CC BY 2.0", "https://www.flickr.com/photos/bvi4092/51817610871/"),
        credit("曼彻斯特", "信息页", "Julius (Juliux)", "CC BY-SA 3.0", "https://commons.wikimedia.org/wiki/File:Manchester_town_hall.jpg"),
        credit("曼彻斯特", "联系人页", "Parrot of Doom", "CC BY-SA 3.0", "https://commons.wikimedia.org/wiki/File:Old_trafford_february_2010.jpg"),
        credit("金斯敦", "信息页", "Christina Xu", "CC BY-SA 2.0", "https://www.flickr.com/photos/crimsonninjagirl/1258754977/"),
        credit("金斯敦", "联系人页", "Avda", "CC BY-SA 3.0", "https://commons.wikimedia.org/wiki/File:Bob_Marley_-_Statue_-_Kingston_-_Jamaica.jpg"),
    ]

    private static let journeyCredits: [Credit] = [
        credit("伦敦", "十五城相遇影片", "Anh Nguyen", "Pexels License", "https://www.pexels.com/video/35286695/"),
        credit("墨尔本", "十五城相遇影片", "Camilo Rodriguez", "Pexels License", "https://www.pexels.com/video/30331414/"),
        credit("纽约", "十五城相遇影片", "Emre Yurttakalın", "Pexels License", "https://www.pexels.com/video/28608250/"),
        credit("开普敦", "十五城相遇影片", "Benjamin Sprankle", "Pexels License", "https://www.pexels.com/video/29801279/"),
        credit("新加坡", "十五城相遇影片", "Vasilis Karkalas", "Pexels License", "https://www.pexels.com/video/37147087/"),
        credit("都柏林", "十五城相遇影片", "Flávio Nascimento", "Pexels License", "https://www.pexels.com/video/29478528/"),
        credit("爱丁堡", "十五城相遇影片", "Mateusz Max Maksiak", "Pexels License", "https://www.pexels.com/video/38682240/"),
        credit("温哥华", "十五城相遇影片", "The Six", "Pexels License", "https://www.pexels.com/video/33290794/"),
        credit("奥克兰", "Piha Beach Walkthrough Music Video 4K60", "Beautiful New Zealand Scenery", "CC Attribution (YouTube)", "https://www.youtube.com/watch?v=gi_vNfIpXKU"),
        credit("内罗毕", "十五城相遇影片", "Ken Mwaura", "Pexels License", "https://www.pexels.com/video/29069413/"),
        credit("多伦多", "十五城相遇影片", "Numan Gilgil", "Pexels License", "https://www.pexels.com/video/29904667/"),
        credit("悉尼", "十五城相遇影片", "Ben Prater", "Pexels License", "https://www.pexels.com/video/36427881/"),
        credit("新奥尔良", "十五城相遇影片", "Ahmed Ari", "Pexels License", "https://www.pexels.com/video/13107072/"),
        credit("曼彻斯特", "十五城相遇影片", "Declan Conor", "Pexels License", "https://www.pexels.com/video/25839532/"),
        credit("金斯敦", "UWI (Mona) gardens and Ruins", "Spicy_FPV_Jamaica", "CC Attribution (YouTube)", "https://www.youtube.com/watch?v=OtiXjWrmNvo"),
    ]

    public init() {}

    public var body: some View {
        List {
            Section("十五城 · 相遇影片") {
                Text("各城真实摄影，经选段、竖屏裁切、缩放及无声编码。每城一秒；并非实时画面。")
                    .font(.footnote).foregroundStyle(.secondary)
                ForEach(Self.journeyCredits) { credit in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(credit.city).font(.caption).foregroundStyle(.secondary)
                        creditRow(credit)
                    }
                }
                Link("Pexels License", destination: URL(string: "https://www.pexels.com/license/")!)
                Link("YouTube 知识共享署名许可说明", destination: URL(string: "https://support.google.com/youtube/answer/2797468")!)
            }
            Section("城市活动 · 街角咖啡馆") {
                Text("室内为 AI 情景美术，窗外为加工后的素材画面；并非当前城市实拍或实时影像。视频路人不代表可互动角色。")
                    .font(.footnote).foregroundStyle(.secondary)
                Link("窗外街景 · Davide Giordani / Pixabay（素材 27023）",
                     destination: URL(string: "https://pixabay.com/videos/london-building-people-walking-27023/")!)
                Link("Pixabay Content License",
                     destination: URL(string: "https://pixabay.com/service/license-summary/")!)
            }
            Section("城市活动 · 街边旧书摊 / 街角花摊") {
                Text("摊位前景均为一次性 AI 情景美术，背景为经过稳定、裁切、柔焦和接缝处理的真实素材。不是当前城市的实拍或实时影像，真实路人不作为 NPC 身份。")
                    .font(.footnote).foregroundStyle(.secondary)
                Link("旧书摊街景 · BreakDownPictures / Pixabay（素材 67850，锡比乌）",
                     destination: URL(string: "https://pixabay.com/videos/building-houses-square-street-67850/")!)
                Link("花摊街景 · Liemedia / Pixabay（素材 18027，旧金山）",
                     destination: URL(string: "https://pixabay.com/videos/san-francisco-crowd-usa-city-18027/")!)
                Link("Pixabay Content License",
                     destination: URL(string: "https://pixabay.com/service/license-summary/")!)
            }
            citySections
            licenseSection
        }
        .navigationTitle("影像来源与许可")
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
