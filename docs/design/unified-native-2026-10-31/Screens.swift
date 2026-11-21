import SwiftUI
import MapKit

struct Screens: View {
    @ObservedObject var navigation: Navigation
    @State private var draft = ""
    @State private var translation = true
    @State private var reminders = true
    @State private var autoReading = false
    @State private var showComposer = false
    @State private var showSources = false
    @State private var notice: String?

    var body: some View {
        content
            .onAppear {
                if ProcessInfo.processInfo.environment["DESIGN_COMPOSER"] == "1" { showComposer = true }
            }
            .sheet(isPresented: $showComposer) { composer }
            .sheet(isPresented: $showSources) { photoSources }
            .alert("界面展示", isPresented: Binding(get: { notice != nil }, set: { if !$0 { notice = nil } })) {
                Button("知道了", role: .cancel) { notice = nil }
            } message: { Text(notice ?? "") }
    }

    @ViewBuilder private var content: some View {
        switch navigation.page {
        case .gallery: gallery
        case .home: home
        case .map: worldMap
        case .activities: activities
        case .stories: stories
        case .story: narrative(meetup: false)
        case .appointment: appointment
        case .meetup: narrative(meetup: true)
        case .summary: summary
        case .messages: messages
        case .chat: chat
        case .contacts: contacts
        case .person: person
        case .me: me
        case .learning: learning
        case .settings: settings
        case .memories: memories
        }
    }

    private func bar(_ title: String, photo: Bool = false, back: Page? = .gallery,
                     subtitle: String? = nil, trailing: [(String,String,()->Void)] = []) -> some View {
        TopBar(title: title, subtitle: subtitle, onPhoto: photo,
               back: back.map { page in { navigation.open(page) } }, trailing: trailing)
    }

    private var gallery: some View {
        VStack(spacing: 0) {
            bar("界面实施基准", back: nil)
            List {
                Section("原生 SwiftUI · 本地展示数据") {
                    ForEach(Page.allCases.filter { $0 != .gallery }, id: \.self) { page in
                        Button { navigation.open(page) } label: {
                            HStack { Text(page.title); Spacer(); Image(systemName: "chevron.right").font(.caption) }
                        }.foregroundStyle(UIStyle.ink)
                    }
                }
                Section { Text("所有页面使用同一份原生组件。此程序不连接账号、聊天、模型、支付或后台服务。")
                        .font(.footnote).foregroundStyle(UIStyle.secondary) }
            }.scrollContentBackground(.hidden)
        }
    }

    private var home: some View {
        GeometryReader { p in
            ZStack {
                Backdrop(name: "home.png", darkness: 0)
                VStack {
                    HStack {
                        Button { navigation.open(.gallery) } label: {
                            Image(systemName: "square.grid.2x2").frame(width: 44, height: 44)
                        }.accessibilityLabel("全部界面")
                        Spacer()
                        HStack(spacing: 18) {
                            Label("680", systemImage: "circle")
                            Label("2", systemImage: "airplane")
                        }.font(.subheadline.weight(.medium)).padding(.horizontal, 14).padding(.vertical, 10)
                            .background(UIStyle.paper.opacity(0.95), in: Capsule())
                    }.foregroundStyle(UIStyle.ink).padding(.horizontal, 16)
                    Spacer()
                    Button { navigation.open(.appointment) } label: {
                        HStack(spacing: 11) {
                            Avatar(size: 36)
                            VStack(alignment: .leading, spacing: 3) {
                                Text("今天和 Oliver 有个约定").font(.subheadline.weight(.semibold))
                                Text("伦敦 15:00 · 河边坐一会").font(.caption).foregroundStyle(UIStyle.secondary)
                            }
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.right").font(.caption.weight(.semibold))
                        }.padding(14).background(UIStyle.paper.opacity(0.96), in: RoundedRectangle(cornerRadius: UIStyle.radius))
                    }.foregroundStyle(UIStyle.ink).buttonStyle(PressStyle())
                        .padding(.horizontal, 20).padding(.bottom, 16)
                }
                Button { navigation.open(.stories) } label: { Color.clear.contentShape(Rectangle()) }
                    .frame(width: p.size.width * 0.40, height: p.size.height * 0.19)
                    .position(x: p.size.width * 0.70, y: p.size.height * 0.43).accessibilityLabel("剧情")
                Button { navigation.open(.activities) } label: { Color.clear.contentShape(Rectangle()) }
                    .frame(width: p.size.width * 0.45, height: p.size.height * 0.14)
                    .position(x: p.size.width * 0.25, y: p.size.height * 0.76).accessibilityLabel("城市活动")
                Button { navigation.open(.map) } label: { Color.clear.contentShape(Rectangle()) }
                    .frame(width: p.size.width * 0.48, height: p.size.height * 0.20)
                    .position(x: p.size.width * 0.72, y: p.size.height * 0.24).accessibilityLabel("世界地图")
            }
        }
    }

    private var activities: some View {
        ZStack {
            Backdrop(name: "park.jpg", darkness: 0.08)
            VStack(spacing: 0) {
                bar("伦敦 · 城市活动", photo: true, back: .home,
                    trailing: [("book.closed", "相遇与足迹", { navigation.open(.memories) })])
                HStack(spacing: 26) {
                    ForEach(["公园小憩", "池畔观察", "雨天咖啡馆"], id: \.self) { title in
                        VStack(spacing: 9) {
                            Text(title).font(.subheadline.weight(title == "公园小憩" ? .semibold : .regular))
                            Rectangle().fill(title == "公园小憩" ? UIStyle.gold : .clear).frame(height: 2)
                        }
                    }
                }.foregroundStyle(.white).padding(.horizontal, 20).padding(.top, 18)
                Spacer(minLength: 28)
                VStack(alignment: .leading, spacing: 18) {
                    Paper(floating: true) {
                        VStack(spacing: 0) {
                            Text("给这一刻，留一点时间。")
                                .font(.system(size: 23, weight: .regular, design: .serif))
                                .foregroundStyle(UIStyle.ink).frame(maxWidth: .infinity, alignment: .leading).padding(.bottom, 16)
                            Button { navigation.open(.meetup) } label: { SettingRow(symbol: "map", title: "问问路线", value: "一起探索") }
                            FineDivider()
                            Button { navigation.open(.meetup) } label: { SettingRow(symbol: "cup.and.saucer", title: "喝口咖啡", value: "慢下来") }
                            FineDivider()
                            Button { navigation.open(.meetup) } label: { SettingRow(symbol: "book", title: "交换见闻", value: "聊聊发现") }
                        }
                    }
                    Button { navigation.open(.appointment) } label: {
                        Paper(floating: true, padding: 15) {
                            HStack(spacing: 12) {
                                Avatar(size: 38)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("赴约").font(.subheadline.weight(.semibold))
                                    Text("Oliver · 今天 15:00").font(.caption).foregroundStyle(UIStyle.secondary)
                                }
                                Spacer(); Text("可赴约").font(.caption).foregroundStyle(UIStyle.tint)
                                Image(systemName: "chevron.right").font(.caption)
                            }.foregroundStyle(UIStyle.ink)
                        }
                    }.buttonStyle(PressStyle())
                }.padding(20).padding(.bottom, 12)
            }
        }
    }

    private var stories: some View {
        ZStack {
            Backdrop(name: "story-room.jpg", darkness: 0.22)
            VStack(spacing: 0) {
                bar("剧情", photo: true, back: .home)
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("五座城市，一路同行").font(.caption).tracking(1).foregroundStyle(.white.opacity(0.8))
                            Text("出发之后").font(.system(size: 34, weight: .regular, design: .serif)).foregroundStyle(.white)
                        }.padding(.top, 28).padding(.bottom, 12)
                        Button { navigation.open(.story) } label: {
                            VStack(alignment: .leading, spacing: 0) {
                                Asset(name: "story-exterior.jpg").frame(height: 154).clipped()
                                VStack(alignment: .leading, spacing: 10) {
                                    HStack { Text("主线 · 第一站").font(.caption).foregroundStyle(UIStyle.secondary); Spacer(); Text("继续阅读").font(.caption).foregroundStyle(UIStyle.tint) }
                                    Text("空着的那把椅子").font(.title2.weight(.medium)).foregroundStyle(UIStyle.ink)
                                    Text("伦敦 · Oliver").font(.subheadline).foregroundStyle(UIStyle.secondary)
                                }.padding(18).frame(maxWidth: .infinity, alignment: .leading).background(UIStyle.paper)
                            }.clipShape(RoundedRectangle(cornerRadius: UIStyle.radius))
                        }.buttonStyle(PressStyle())
                        Paper {
                            VStack(alignment: .leading, spacing: 8) {
                                SectionTitle(title: "城市故事", detail: "15 座城市")
                                Text("走进街区，也走进别人的一天。")
                                    .font(.subheadline).foregroundStyle(UIStyle.secondary).padding(.bottom, 8)
                                Button { navigation.open(.story) } label: { SettingRow(symbol: "book.closed", title: "伦敦的另一页", value: "已开放") }
                                FineDivider()
                                SettingRow(symbol: "book.closed", title: "海风里的墨尔本", value: "已开放")
                            }
                        }
                    }.padding(20)
                }.scrollIndicators(.hidden)
            }
        }
    }

    private func narrative(meetup: Bool) -> some View {
        ZStack {
            Backdrop(name: meetup ? "notting-hill.jpg" : "story-room.jpg", darkness: meetup ? 0.18 : 0.12)
            if !meetup {
                GeometryReader { p in
                    Asset(name: "oliver-manuscript.png", contentMode: .fit)
                        .frame(height: p.size.height * 0.72)
                        .position(x: p.size.width * 0.52, y: p.size.height * 0.40)
                }.allowsHitTesting(false)
            }
            VStack(spacing: 0) {
                bar(meetup ? "河边坐一会" : "先问一句", photo: true,
                    back: meetup ? .appointment : .stories,
                    subtitle: meetup ? "与 Oliver 赴约 · 伦敦" : "出发之后 · 空着的那把椅子",
                    trailing: [("speaker.wave.2", "声音", { autoReading.toggle() }),
                               ("text.book.closed", "回看", { navigation.open(.memories) })])
                if meetup {
                    HStack {
                        Text("伦敦风景").font(.caption2)
                        Button { showSources = true } label: { Image(systemName: "info.circle").frame(width: 44, height: 44) }
                        Spacer()
                    }.foregroundStyle(.white.opacity(0.85)).padding(.leading, 20)
                }
                Spacer(minLength: 20)
                Paper(floating: true, padding: 18) {
                    VStack(alignment: .leading, spacing: 13) {
                        HStack {
                            Text(meetup ? "Oliver" : "你的选择").font(.subheadline.weight(.semibold))
                            Spacer()
                            Button { translation.toggle() } label: { Text(translation ? "中 / EN" : "EN").font(.caption).frame(minWidth: 48, minHeight: 32) }
                        }.foregroundStyle(UIStyle.ink)
                        Rectangle().fill(UIStyle.gold.opacity(0.55)).frame(height: 0.7)
                        if meetup {
                            Text("Oliver 看向沿岸的小路，又回头等你的意思。")
                                .font(.footnote).foregroundStyle(UIStyle.secondary).lineSpacing(3)
                        }
                        Text(meetup ? "We could keep walking, or find somewhere to sit. What would you like?" : "How would you like to help?")
                            .font(.body).lineSpacing(4).foregroundStyle(UIStyle.ink).fixedSize(horizontal: false, vertical: true)
                        if translation {
                            Text(meetup ? "我们可以继续走，也可以找个地方坐坐。你想怎么来？" : "你打算怎么帮他？")
                                .font(.subheadline).foregroundStyle(UIStyle.secondary).lineSpacing(3)
                        }
                        VStack(spacing: 9) {
                            Choice(english: meetup ? "Let’s walk a little further." : "Ask Oliver privately what he wants.",
                                   chinese: meetup ? "再沿河走一小段吧。" : "先私下问 Oliver 的想法。") { navigation.open(.summary) }
                            Choice(english: meetup ? "Could we sit for a while?" : "Ask Nora about the format, without naming Oliver.",
                                   chinese: meetup ? "我们先坐一会，好吗？" : "先问 Nora 活动形式，不提 Oliver 的名字。") { navigation.open(.summary) }
                        }.padding(.top, 3)
                        if meetup {
                            Button { showComposer = true } label: {
                                Label("自己说一句，或做点别的", systemImage: "square.and.pencil")
                                    .font(.subheadline).frame(maxWidth: .infinity, minHeight: 44).foregroundStyle(UIStyle.tint)
                            }.buttonStyle(PressStyle())
                        } else {
                            HStack { Text("轻点英文可查词").font(.caption2).foregroundStyle(UIStyle.secondary); Spacer(); Label("回看", systemImage: "text.book.closed").font(.caption).foregroundStyle(UIStyle.ink) }
                        }
                    }
                }.padding(.horizontal, 18).padding(.bottom, 14)
            }
        }
    }

    private var appointment: some View {
        ZStack {
            Backdrop(name: "primrose-hill.jpg", darkness: 0.18)
            VStack(spacing: 0) {
                bar("这次约定", photo: true, back: .activities,
                    trailing: [("ellipsis", "更多", { notice = "改期需要回到聊天，与 Oliver 重新说定。" })])
                HStack {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("伦敦 · 和 Oliver").font(.caption).foregroundStyle(.white.opacity(0.8))
                        Text("河边坐一会").font(.system(size: 31, weight: .regular, design: .serif)).foregroundStyle(.white)
                    }; Spacer()
                }.padding(.horizontal, 22).padding(.top, 28)
                Spacer(minLength: 24)
                Paper(floating: true) {
                    VStack(alignment: .leading, spacing: 18) {
                        HStack(spacing: 11) {
                            Avatar(size: 44)
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Oliver").font(.headline).foregroundStyle(UIStyle.ink)
                                Text("你的伦敦旅伴").font(.caption).foregroundStyle(UIStyle.secondary)
                            }
                            Spacer(); Text("可赴约").font(.caption.weight(.medium)).foregroundStyle(UIStyle.tint)
                        }
                        FineDivider()
                        HStack(alignment: .firstTextBaseline, spacing: 13) {
                            Text("15:00").font(.system(size: 40, weight: .regular)).monospacedDigit().foregroundStyle(UIStyle.ink)
                            VStack(alignment: .leading, spacing: 4) {
                                Text("今天 · 10 月 31 日，周六").font(.subheadline)
                                Text("伦敦当地时间").font(.caption).foregroundStyle(UIStyle.secondary)
                            }
                        }
                        Text("你的时间 · 北京时间 23:00").font(.caption).foregroundStyle(UIStyle.secondary).padding(.top, -10)
                        VStack(spacing: 0) {
                            SettingRow(symbol: "mappin.and.ellipse", title: "南岸 · 滑铁卢桥附近", chevron: false)
                            SettingRow(symbol: "clock", title: "留出一小时左右", chevron: false)
                        }
                        Text("“See you by the river at three.”").font(.subheadline.italic()).foregroundStyle(UIStyle.secondary)
                        MainAction(title: "去赴约") { navigation.open(.meetup) }
                        Text("今天 14:30—17:00 可进入").font(.caption2).foregroundStyle(UIStyle.secondary).frame(maxWidth: .infinity)
                        HStack {
                            Button("商量改期") { navigation.open(.chat) }
                            Spacer()
                            Button("取消约定") { notice = "这里只展示界面，不会取消真实约定。" }
                        }.font(.footnote).foregroundStyle(UIStyle.secondary).padding(.top, 2)
                    }
                }.padding(20).padding(.bottom, 5)
            }
        }
    }

    private var summary: some View {
        ZStack(alignment: .top) {
            UIStyle.canvas.ignoresSafeArea()
            Asset(name: "little-venice.jpg").frame(height: 252).clipped().ignoresSafeArea(edges: .top)
                .overlay(alignment: .top) { Color.black.opacity(0.22).frame(height: 252).ignoresSafeArea(edges: .top) }
            VStack(spacing: 0) {
                bar("这次约定", photo: true, back: .activities, trailing: [("text.book.closed", "完整经历", { navigation.open(.memories) })])
                VStack(alignment: .leading, spacing: 7) {
                    Text("没有赶路的一个下午").font(.system(size: 28, weight: .regular, design: .serif))
                    Text("Oliver · 伦敦 · 2026.10.31").font(.caption).opacity(0.85)
                }.foregroundStyle(.white).frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 22).padding(.top, 18).padding(.bottom, 24)
                ScrollView {
                    Paper {
                        VStack(alignment: .leading, spacing: 17) {
                            HStack(alignment: .top, spacing: 11) {
                                Avatar(size: 36)
                                VStack(alignment: .leading, spacing: 5) {
                                    Text("“It was nice just being there with you.”").font(.subheadline).lineSpacing(2)
                                    Text("能这样一起待一会儿，挺好的。").font(.caption).foregroundStyle(UIStyle.secondary)
                                }
                            }
                            FineDivider()
                            HStack(alignment: .firstTextBaseline) {
                                Text("这次的好感变化").font(.subheadline.weight(.semibold)); Spacer()
                                Text("+1.2").font(.system(size: 28, weight: .regular)).foregroundStyle(UIStyle.tint)
                            }
                            HStack { Text("认真回应，也尊重彼此的选择。"); Spacer(); Text("42.6 → 43.8") }
                                .font(.caption).foregroundStyle(UIStyle.secondary).padding(.top, -10)
                            FineDivider()
                            SectionTitle(title: "你留下的选择")
                            decision("他问你想继续走，还是坐一会。", choice: "我们先坐一会，好吗？", result: "你们决定先停下来。")
                            decision("这次，你自己说了：", choice: "今天不用安排什么，我想听你随便聊聊。", result: "你们把节奏留给了彼此。")
                            FineDivider()
                            HStack(spacing: 8) { Image(systemName: "leaf").foregroundStyle(UIStyle.tint); Text("留在他的记忆里").font(.subheadline.weight(.semibold)) }
                            Text("这次在伦敦，你们放慢脚步，留了一段没有安排满的时间。")
                                .font(.subheadline).foregroundStyle(UIStyle.secondary).lineSpacing(3)
                            Button("管理这条记忆") { navigation.open(.memories) }.font(.caption).foregroundStyle(UIStyle.tint)
                        }.foregroundStyle(UIStyle.ink)
                    }.padding(.horizontal, 20)
                }.scrollIndicators(.hidden)
                MainAction(title: "回到与 Oliver 的聊天", symbol: "bubble.left") { navigation.open(.chat) }
                    .padding(.horizontal, 20).padding(.top, 12).padding(.bottom, 10)
            }
        }
    }

    private func decision(_ context: String, choice: String, result: String) -> some View {
        HStack(alignment: .top, spacing: 11) {
            Circle().fill(UIStyle.gold).frame(width: 5, height: 5).padding(.top, 7)
            VStack(alignment: .leading, spacing: 5) {
                Text(context).font(.caption).foregroundStyle(UIStyle.secondary)
                Text(choice).font(.subheadline).foregroundStyle(UIStyle.ink)
                Text(result).font(.caption).foregroundStyle(UIStyle.secondary)
            }
        }
    }

    private var messages: some View {
        ZStack {
            Backdrop(name: "messages.jpg", darkness: 0.22)
            VStack(spacing: 0) {
                bar("信息", photo: true, back: nil, trailing: [("square.grid.2x2", "全部界面", { navigation.open(.gallery) })])
                SearchField(prompt: "搜索信息").padding(.horizontal, 20).padding(.top, 8)
                ScrollView {
                    VStack(alignment: .leading, spacing: 15) {
                        HStack { Text("最近聊天").font(.caption.weight(.medium)); Spacer(); Text("3 位旅伴").font(.caption) }
                            .foregroundStyle(.white.opacity(0.9)).padding(.top, 28)
                        Paper(padding: 16) {
                            VStack(spacing: 0) {
                                conversationRow("oliver", name: "Oliver", text: "See you by the river at three.", time: "14:32", unread: true)
                                FineDivider().padding(.leading, 61)
                                conversationRow("ruby", name: "Ruby", text: "That sounds like a proper day off.", time: "昨天")
                                FineDivider().padding(.leading, 61)
                                conversationRow("marcus", name: "Marcus", text: "Found a new little place today.", time: "周四")
                            }
                        }
                        Paper(floating: true, padding: 15) {
                            Button { navigation.open(.appointment) } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: "calendar").foregroundStyle(UIStyle.tint)
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("今天的约定").font(.subheadline.weight(.medium))
                                        Text("Oliver · 伦敦 15:00").font(.caption).foregroundStyle(UIStyle.secondary)
                                    }; Spacer(); Image(systemName: "chevron.right").font(.caption)
                                }.foregroundStyle(UIStyle.ink)
                            }.buttonStyle(PressStyle())
                        }
                    }.padding(20)
                }.scrollIndicators(.hidden)
            }
        }
    }

    private func conversationRow(_ avatar: String, name: String, text: String, time: String, unread: Bool = false) -> some View {
        Button { navigation.open(.chat) } label: {
            HStack(alignment: .top, spacing: 13) {
                Avatar(name: avatar, size: 48)
                VStack(alignment: .leading, spacing: 7) {
                    HStack { Text(name).font(.body.weight(.semibold)); Spacer(); Text(time).font(.caption2).foregroundStyle(UIStyle.secondary) }
                    Text(text).font(.subheadline).foregroundStyle(UIStyle.secondary).lineLimit(2)
                }
                if unread { Circle().fill(UIStyle.tint).frame(width: 6, height: 6).padding(.top, 32) }
            }.foregroundStyle(UIStyle.ink).padding(.vertical, 17)
        }.buttonStyle(PressStyle())
    }

    private var chat: some View {
        VStack(spacing: 0) {
            bar("Oliver", back: .messages, subtitle: "伦敦 · 在线",
                trailing: [("phone", "语音通话", { notice = "原生界面展示不拨打电话。" }),
                           ("person.crop.circle", "角色详情", { navigation.open(.person) })])
            FineDivider()
            ScrollViewReader { reader in
            ScrollView {
                VStack(spacing: 18) {
                    Text("今天 14:32").font(.caption2).foregroundStyle(UIStyle.secondary).padding(.top, 10)
                    bubble("I’ve got an hour free this afternoon.", translation: "今天下午我有一个小时空闲。")
                    bubble("Shall we take a walk by the river?", translation: "要不要去河边走走？")
                    bubble("That sounds lovely. Shall we meet at three?", outgoing: true)
                    bubble("Three works. Near Waterloo Bridge?", translation: "三点可以。在滑铁卢桥附近见？")
                    bubble("See you there!", outgoing: true)
                    Button { navigation.open(.appointment) } label: {
                        Paper(padding: 16) {
                            VStack(alignment: .leading, spacing: 12) {
                                Label("你们约好了", systemImage: "calendar").font(.caption).foregroundStyle(UIStyle.secondary)
                                Text("河边坐一会").font(.headline).foregroundStyle(UIStyle.ink)
                                Text("今天 15:00 · 伦敦当地时间").font(.subheadline).foregroundStyle(UIStyle.ink)
                                Text("南岸 · 滑铁卢桥附近").font(.caption).foregroundStyle(UIStyle.secondary)
                                FineDivider()
                                HStack { Text("查看约定"); Spacer(); Image(systemName: "arrow.right") }
                                    .font(.subheadline.weight(.medium)).foregroundStyle(UIStyle.tint)
                            }
                        }.padding(.leading, 48)
                    }.buttonStyle(PressStyle()).id("conversation-end")
                }.padding(.horizontal, 20).padding(.bottom, 20)
            }.scrollIndicators(.hidden)
                .onAppear { DispatchQueue.main.async { reader.scrollTo("conversation-end", anchor: .bottom) } }
            }
            HStack(spacing: 12) {
                Button { notice = "此展示程序不录音。" } label: { Image(systemName: "waveform").font(.system(size: 22)).frame(width: 36, height: 44) }
                TextField("用英语说点什么…", text: $draft).font(.body).padding(.horizontal, 14).frame(minHeight: 44)
                    .background(UIStyle.canvas, in: RoundedRectangle(cornerRadius: 22))
                Button { draft = "" } label: {
                    Image(systemName: "arrow.up").font(.system(size: 17, weight: .semibold)).frame(width: 42, height: 42)
                        .foregroundStyle(UIStyle.onPrimary).background(UIStyle.primary, in: Circle())
                }.accessibilityLabel("发送")
            }.foregroundStyle(UIStyle.tint).padding(.horizontal, 14).padding(.vertical, 10)
                .background(UIStyle.paper.ignoresSafeArea(edges: .bottom))
                .overlay(alignment: .top) { FineDivider() }
        }
    }

    private func bubble(_ text: String, translation: String? = nil, outgoing: Bool = false) -> some View {
        HStack(alignment: .top, spacing: 9) {
            if outgoing { Spacer(minLength: 42) } else { Avatar(size: 34) }
            VStack(alignment: .leading, spacing: 8) {
                Text(text).font(.body).lineSpacing(3)
                if let translation { Text(translation).font(.caption).foregroundStyle(UIStyle.secondary).lineSpacing(2) }
            }.foregroundStyle(outgoing ? UIStyle.onPrimary : UIStyle.ink)
                .padding(.horizontal, 15).padding(.vertical, 12)
                .background(outgoing ? UIStyle.primary : UIStyle.paper, in: RoundedRectangle(cornerRadius: 16))
            if !outgoing { Spacer(minLength: 35) }
        }
    }

    private var contacts: some View {
        ZStack {
            Backdrop(name: "contacts.jpg", darkness: 0.16)
            VStack(spacing: 0) {
                bar("联系人", photo: true, back: nil,
                    trailing: [("person.badge.plus", "添加旅伴", { notice = "旅伴号搜索将在正式功能中沿用现有流程。" })])
                SearchField(prompt: "姓名、备注或旅伴号").padding(.horizontal, 20).padding(.top, 8)
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        HStack { Text("我的旅伴"); Spacer(); Text("3 / 6 好友位") }.font(.caption).foregroundStyle(.white).padding(.top, 26)
                        Paper(padding: 18) {
                            VStack(alignment: .leading, spacing: 0) {
                                Text("特别关心").font(.caption).foregroundStyle(UIStyle.secondary).padding(.bottom, 8)
                                contactRow("oliver", name: "Oliver", detail: "伦敦 · 喜欢书页之间的停顿", favorite: true)
                                FineDivider().padding(.vertical, 10)
                                Text("好友").font(.caption).foregroundStyle(UIStyle.secondary).padding(.bottom, 8)
                                contactRow("ruby", name: "Ruby", detail: "墨尔本 · 把日常画进速写本")
                                FineDivider().padding(.leading, 60)
                                contactRow("marcus", name: "Marcus", detail: "纽约 · 街头总有新发现")
                            }
                        }
                    }.padding(20)
                }.scrollIndicators(.hidden)
            }
        }
    }

    private func contactRow(_ avatar: String, name: String, detail: String, favorite: Bool = false) -> some View {
        Button { navigation.open(.person) } label: {
            HStack(spacing: 13) {
                Avatar(name: avatar, size: 48)
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 7) { Text(name).font(.body.weight(.semibold)); if favorite { Image(systemName: "star.fill").font(.caption2).foregroundStyle(UIStyle.gold) } }
                    Text(detail).font(.caption).foregroundStyle(UIStyle.secondary).lineLimit(2)
                }; Spacer(minLength: 0); Image(systemName: "chevron.right").font(.caption).foregroundStyle(UIStyle.secondary)
            }.foregroundStyle(UIStyle.ink).padding(.vertical, 14)
        }.buttonStyle(PressStyle())
    }

    private var person: some View {
        ZStack(alignment: .top) {
            UIStyle.canvas.ignoresSafeArea()
            Asset(name: "contacts.jpg").frame(height: 270).clipped().ignoresSafeArea(edges: .top)
                .overlay(alignment: .top) { Color.black.opacity(0.18).frame(height: 270).ignoresSafeArea(edges: .top) }
            VStack(spacing: 0) {
                bar("旅伴资料", photo: true, back: .contacts, trailing: [("ellipsis", "更多", { notice = "角色备注、特别关心与联系人管理沿用现有功能。" })])
                ScrollView {
                    VStack(spacing: 20) {
                        Avatar(size: 88).padding(.top, 20)
                        Paper {
                            VStack(alignment: .leading, spacing: 16) {
                                HStack { Text("Oliver").font(.title2.weight(.semibold)); Spacer(); Image(systemName: "star.fill").foregroundStyle(UIStyle.gold) }
                                Text("伦敦 · 写作与旧书").font(.subheadline).foregroundStyle(UIStyle.secondary)
                                Text("慢热，有一点干幽默。喜欢认真听人把一句话说完。")
                                    .font(.body).lineSpacing(4)
                                FineDivider()
                                HStack { Text("好感度").font(.subheadline); Spacer(); Text("43.8").font(.title2).foregroundStyle(UIStyle.tint) }
                                Text("最近：一起留了一段不赶路的时间。")
                                    .font(.caption).foregroundStyle(UIStyle.secondary)
                                FineDivider()
                                Button { navigation.open(.memories) } label: { SettingRow(symbol: "book.closed", title: "共同记忆", value: "查看") }
                                Button { navigation.open(.appointment) } label: { SettingRow(symbol: "calendar", title: "我们的约定", value: "1 项") }
                                MainAction(title: "和 Oliver 聊聊", symbol: "bubble.left") { navigation.open(.chat) }
                            }.foregroundStyle(UIStyle.ink)
                        }
                    }.padding(20)
                }.scrollIndicators(.hidden)
            }
        }
    }

    private var me: some View {
        VStack(spacing: 0) {
            bar("我的", back: nil, trailing: [("gearshape", "设置", { navigation.open(.settings) })])
            ScrollView {
                VStack(spacing: 22) {
                    Paper {
                        HStack(spacing: 15) {
                            ZStack { Circle().fill(UIStyle.canvas); Image(systemName: "person.crop.circle").font(.system(size: 42, weight: .ultraLight)).foregroundStyle(UIStyle.tint) }.frame(width: 66, height: 66)
                            VStack(alignment: .leading, spacing: 6) {
                                Text("旅行者").font(.title2.weight(.semibold))
                                Text("把每次开口，留在旅途中。")
                                    .font(.subheadline).foregroundStyle(UIStyle.secondary)
                            }; Spacer(minLength: 0)
                        }.foregroundStyle(UIStyle.ink)
                    }
                    Paper {
                        VStack(spacing: 16) {
                            HStack { SectionTitle(title: "这段旅程"); Spacer() }
                            HStack {
                                metric("3", label: "同行旅伴"); Spacer(); metric("5", label: "到访城市"); Spacer(); metric("12", label: "共同经历")
                            }
                        }
                    }
                    Paper(padding: 18) {
                        VStack(spacing: 0) {
                            Button { navigation.open(.learning) } label: { SettingRow(symbol: "text.book.closed", title: "我的英语旅程", value: "继续") }
                            FineDivider()
                            Button { navigation.open(.memories) } label: { SettingRow(symbol: "bookmark", title: "收藏与记忆") }
                            FineDivider()
                            Button { navigation.open(.summary) } label: { SettingRow(symbol: "ticket", title: "旅程与经历") }
                            FineDivider()
                            SettingRow(symbol: "creditcard", title: "积分与会员", value: "680 积分")
                        }
                    }
                    Button { navigation.open(.settings) } label: {
                        Paper(padding: 18) { SettingRow(symbol: "gearshape", title: "设置", value: "语音、提醒与账号") }
                    }.buttonStyle(PressStyle())
                }.padding(20)
            }.scrollIndicators(.hidden)
        }
    }

    private func metric(_ value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(value).font(.system(size: 28, weight: .regular)).monospacedDigit().foregroundStyle(UIStyle.ink)
            Text(label).font(.caption).foregroundStyle(UIStyle.secondary)
        }
    }

    private var learning: some View {
        VStack(spacing: 0) {
            bar("我的英语旅程", back: .me)
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    Asset(name: "learning.jpg").frame(height: 156).clipped().clipShape(RoundedRectangle(cornerRadius: UIStyle.radius))
                    Paper {
                        VStack(alignment: .leading, spacing: 15) {
                            HStack { Text("当前学习").font(.caption).foregroundStyle(UIStyle.secondary); Spacer(); Text("初中三年级").font(.caption).foregroundStyle(UIStyle.tint) }
                            Text("把想法说得更完整").font(.title2.weight(.medium))
                            Text("在熟悉的对话里，练习表达理由与选择。")
                                .font(.subheadline).foregroundStyle(UIStyle.secondary).lineSpacing(3)
                            HStack(spacing: 5) { ForEach(0..<8) { i in Capsule().fill(i < 3 ? UIStyle.tint : UIStyle.line).frame(height: 4) } }.padding(.vertical, 6)
                            Text("已完成 3 / 8 个单元").font(.caption).foregroundStyle(UIStyle.secondary)
                            MainAction(title: "继续当前单元") { notice = "本程序只展示视觉基准，不提交真实学习成绩。" }
                        }.foregroundStyle(UIStyle.ink)
                    }
                    Paper(padding: 18) {
                        VStack(spacing: 0) {
                            SettingRow(symbol: "checkmark.circle", title: "最近完成", value: "谈谈你的周末")
                            FineDivider()
                            SettingRow(symbol: "clock", title: "学习记录", value: "查看全部")
                            FineDivider()
                            SettingRow(symbol: "slider.horizontal.3", title: "学习水平", value: "调整")
                        }
                    }
                }.padding(20)
            }.scrollIndicators(.hidden)
        }
    }

    private var settings: some View {
        VStack(spacing: 0) {
            bar("设置", back: .me)
            ScrollView {
                VStack(alignment: .leading, spacing: 23) {
                    VStack(alignment: .leading, spacing: 10) {
                        SectionTitle(title: "提醒与相处")
                        Paper(padding: 18) {
                            VStack(spacing: 0) {
                                Toggle(isOn: $reminders) {
                                    VStack(alignment: .leading, spacing: 5) {
                                        Text("角色主动联系").font(.body)
                                        Text("允许旅伴自然地发来问候")
                                            .font(.caption).foregroundStyle(UIStyle.secondary)
                                    }
                                }.tint(UIStyle.tint).padding(.vertical, 10)
                                FineDivider()
                                SettingRow(symbol: "bell", title: "系统通知", value: "已开启")
                            }.foregroundStyle(UIStyle.ink)
                        }
                    }
                    VStack(alignment: .leading, spacing: 10) {
                        SectionTitle(title: "语音与阅读")
                        Paper(padding: 18) {
                            VStack(spacing: 0) {
                                Toggle(isOn: $autoReading) { Text("自动朗读角色消息").font(.body) }
                                    .tint(UIStyle.tint).padding(.vertical, 16)
                                FineDivider()
                                SettingRow(symbol: "waveform", title: "朗读声音", value: "跟随角色")
                                FineDivider()
                                SettingRow(symbol: "arrow.down.circle", title: "离线语音", value: "已就绪")
                                FineDivider()
                                SettingRow(symbol: "textformat.size", title: "文字大小", value: "跟随系统")
                            }.foregroundStyle(UIStyle.ink)
                        }
                    }
                    VStack(alignment: .leading, spacing: 10) {
                        SectionTitle(title: "账号与数据")
                        Paper(padding: 18) {
                            VStack(spacing: 0) {
                                SettingRow(symbol: "person.crop.circle", title: "账号与同步")
                                FineDivider()
                                Button { navigation.open(.memories) } label: { SettingRow(symbol: "book.closed", title: "记忆管理") }
                                FineDivider()
                                SettingRow(symbol: "info.circle", title: "关于咕游记")
                            }
                        }
                    }
                }.padding(20).padding(.bottom, 12)
            }.scrollIndicators(.hidden)
        }
    }

    private var memories: some View {
        VStack(spacing: 0) {
            bar("共同记忆", back: .person, trailing: [("ellipsis", "管理", { notice = "记忆编辑与遗忘在正式程序中保留现有功能。" })])
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    HStack(spacing: 10) { Avatar(size: 36); Text("与 Oliver").font(.subheadline); Spacer(); Text("3 条记忆").font(.caption).foregroundStyle(UIStyle.secondary) }
                    memoryItem("今天 · 一段共同经历", "没有赶路的一个下午", "你们在伦敦放慢脚步，留了一段没有安排满的时间。", source: "来自赴约 · 查看经历")
                    memoryItem("10 月 28 日 · 聊天", "你偏爱安静的地方", "你说过，比起很热闹的聚会，你更喜欢能好好说话的小地方。", source: "来自你的表达 · 查看原文")
                    memoryItem("10 月 24 日 · 剧情", "先问他的想法", "在书店里，你先私下问 Oliver 想不想参加朗读，没有替他报名。", source: "来自剧情 · 查看经历")
                    Text("记忆可以编辑，也可以不再用于后续聊天。")
                        .font(.caption).foregroundStyle(UIStyle.secondary).lineSpacing(3)
                }.padding(20)
            }.scrollIndicators(.hidden)
        }
    }

    private func memoryItem(_ date: String, _ title: String, _ text: String, source: String) -> some View {
        Paper {
            VStack(alignment: .leading, spacing: 12) {
                Text(date).font(.caption).foregroundStyle(UIStyle.secondary)
                Text(title).font(.headline).foregroundStyle(UIStyle.ink)
                Text(text).font(.body).foregroundStyle(UIStyle.ink).lineSpacing(4)
                FineDivider()
                HStack { Text(source); Spacer(); Image(systemName: "chevron.right") }.font(.caption).foregroundStyle(UIStyle.tint)
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack { Text("你想怎样继续？").font(.title3.weight(.semibold)); Spacer(); Button { showComposer = false } label: { Image(systemName: "xmark").frame(width: 44, height: 44) } }
            Text("可以说一句话，也可以描述你想做的事。")
                .font(.subheadline).foregroundStyle(UIStyle.secondary)
            TextField("比如：我们坐着画过往的船吧。", text: $draft, axis: .vertical)
                .lineLimit(4...7).padding(15).background(UIStyle.canvas, in: RoundedRectangle(cornerRadius: 10))
            MainAction(title: "就这样回应", symbol: "arrow.up") { showComposer = false; navigation.open(.summary) }.disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }.foregroundStyle(UIStyle.ink).padding(22).frame(maxHeight: .infinity, alignment: .top)
            .presentationDetents([.medium, .large]).presentationDragIndicator(.visible)
            .presentationBackground(UIStyle.paper)
    }

    private var photoSources: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("伦敦风景").font(.title2.weight(.semibold))
            Text("照片用于城市氛围，不对应故事中每一刻的具体地点。")
                .font(.subheadline).foregroundStyle(UIStyle.secondary)
            Text("小威尼斯运河 · Matthias v.d. Elbe · CC BY-SA 4.0\n樱草山 · LatteKnowledge · CC BY-SA 4.0\n诺丁山街区 · Bex Walton · CC BY 2.0")
                .font(.footnote).lineSpacing(12)
            Button("关闭") { showSources = false }.font(.body.weight(.medium))
        }.padding(24).frame(maxHeight: .infinity, alignment: .top).foregroundStyle(UIStyle.ink)
            .presentationDetents([.medium]).presentationDragIndicator(.visible).presentationBackground(UIStyle.paper)
    }

    private var worldMap: some View {
        ZStack {
            NativeWorldMap().ignoresSafeArea()
            VStack {
                LinearGradient(colors: [.black.opacity(0.55), .clear], startPoint: .top, endPoint: .bottom)
                    .frame(height: 160).ignoresSafeArea(edges: .top)
                Spacer()
            }.allowsHitTesting(false)
            VStack(spacing: 0) {
                bar("世界地图", photo: true, back: .home,
                    trailing: [("ticket", "旅行票根", { notice = "此展示程序不会消耗机票或发起旅行。" })])
                HStack(spacing: 7) {
                    Image(systemName: "location.fill").font(.caption2)
                    Text("当前驻地 · 伦敦").font(.subheadline)
                    Spacer()
                }.foregroundStyle(.white).padding(.horizontal, 22).padding(.top, 8)
                Spacer()
                Paper(floating: true) {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack { Text("下一站").font(.caption).foregroundStyle(UIStyle.secondary); Spacer(); Label("2 张机票", systemImage: "airplane").font(.caption).foregroundStyle(UIStyle.tint) }
                        Text("去开普敦，听另一种回声。").font(.title3.weight(.medium)).foregroundStyle(UIStyle.ink)
                        Text("信号山、旧街区，还有等待拼起的线索。")
                            .font(.subheadline).foregroundStyle(UIStyle.secondary).lineSpacing(3)
                        MainAction(title: "查看这座城市", symbol: "globe.europe.africa") { navigation.open(.stories) }
                    }
                }.padding(20).padding(.bottom, 10)
            }
        }
    }

}

// The same native MapKit approach as the app's WorldMapCanvas, isolated from domain data.
struct NativeWorldMap: UIViewRepresentable {
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeUIView(context: Context) -> MKMapView {
        let map = LabeledMapView()
        map.delegate = context.coordinator
        map.preferredConfiguration = MKImageryMapConfiguration(elevationStyle: .flat)
        map.showsCompass = false
        map.pointOfInterestFilter = .excludingAll
        map.setCamera(MKMapCamera(lookingAtCenter: CLLocationCoordinate2D(latitude: 28, longitude: -18),
                                 fromDistance: 24_000_000, pitch: 0, heading: 0), animated: false)
        return map
    }
    func updateUIView(_ map: MKMapView, context: Context) {}
    final class Coordinator: NSObject, MKMapViewDelegate {
        func mapViewDidChangeVisibleRegion(_ mapView: MKMapView) {
            (mapView as? LabeledMapView)?.positionLabels()
        }
    }
}

// Native city labels stay tied to MapKit's coordinate projection and update
// during real pan/zoom, with the same paper and gold visual tokens.
final class LabeledMapView: MKMapView {
    private var cities: [(UILabel, CLLocationCoordinate2D)] = []
    override init(frame: CGRect) {
        super.init(frame: frame)
        for (title, lat, lon) in [("伦敦 · 当前", 51.5074, -0.1278), ("开普敦", -33.9249, 18.4241), ("纽约", 40.7128, -74.006)] {
            let label = UILabel()
            label.text = title
            label.font = .systemFont(ofSize: 14, weight: .semibold)
            label.textColor = UIColor(red: 0.15, green: 0.21, blue: 0.18, alpha: 1)
            label.backgroundColor = UIColor(red: 0.98, green: 0.96, blue: 0.92, alpha: 1)
            label.textAlignment = .center
            label.layer.cornerRadius = 15
            label.layer.borderWidth = 1
            label.layer.borderColor = UIColor(red: 0.74, green: 0.61, blue: 0.38, alpha: 1).cgColor
            label.clipsToBounds = true
            label.frame = CGRect(x: 0, y: 0, width: title == "伦敦 · 当前" ? 106 : 70, height: 32)
            label.accessibilityLabel = title
            addSubview(label)
            cities.append((label, CLLocationCoordinate2D(latitude: lat, longitude: lon)))
        }
    }
    required init?(coder: NSCoder) { fatalError("Not used") }
    override func layoutSubviews() { super.layoutSubviews(); positionLabels() }
    func positionLabels() {
        for (label, coordinate) in cities {
            label.center = convert(coordinate, toPointTo: self)
            let difference = abs((coordinate.longitude - centerCoordinate.longitude + 540).truncatingRemainder(dividingBy: 360) - 180)
            label.isHidden = !bounds.insetBy(dx: 0, dy: 70).contains(label.center) || difference > 85
            bringSubviewToFront(label)
        }
    }
}
