import SwiftUI
import UIKit
import WebKit
import Combine

struct ContentView: View {
    @EnvironmentObject private var store: ParcelStore
    @State private var selectedTab = 0
    var body: some View {
        TabView(selection: $selectedTab) {
            PackagesView().tabItem { Label("待取件", systemImage: "shippingbox") }.tag(0)
            ProvidersView().tabItem { Label("取件凭证", systemImage: "qrcode.viewfinder") }.tag(1)
            AboutView().tabItem { Label("设置", systemImage: "slider.horizontal.3") }.tag(2)
        }
        .alert("本地数据提示", isPresented: Binding(get: { store.storageWarning != nil }, set: { _ in })) {
            Button("知道了", role: .cancel) { }
        } message: { Text(store.storageWarning ?? "") }
    }
}

struct ProviderMark: View {
    let provider: PickupProvider
    var body: some View {
        Text(provider.shortName).font(.headline).foregroundStyle(Palette.ink)
            .frame(width: 44, height: 44).background(provider.tint.opacity(0.24), in: RoundedRectangle(cornerRadius: 15))
    }
}

struct PackagesView: View {
    @EnvironmentObject private var store: ParcelStore
    @State private var search = ""
    @State private var showCollected = false
    @State private var adding = false
    @State private var selectedProvider: PickupProvider?
    @State private var copiedID: UUID?
    @State private var officialPortal = false

    private var displayed: [Parcel] {
        let source = showCollected ? store.collected : store.pending
        return source.filter { search.isEmpty || [$0.title, $0.station, $0.pickupCode, $0.trackingNumber, store.provider($0.providerID)?.name ?? ""].joined(separator: " ").localizedCaseInsensitiveContains(search) }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    HStack {
                        Label("拾件", systemImage: "shippingbox.fill").font(.title2.bold())
                        Spacer()
                        Text("初版预览").font(.caption).foregroundStyle(.secondary)
                    }
                    Text("包裹到齐了，\n顺路一起带回家。").font(.largeTitle.bold()).tracking(-1)
                    Button { officialPortal = true } label: {
                        Label("打开菜鸟官方身份码 / 待取件", systemImage: "barcode.viewfinder")
                            .frame(maxWidth: .infinity).padding(18)
                    }.buttonStyle(.borderedProminent)
                    Text("浏览器已验证身份码可在本人登录后显示；iPhone 与驿站扫码仍需实测。")
                        .font(.caption).foregroundStyle(.secondary)
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("\(store.pending.count)").font(.system(size: 52, weight: .semibold, design: .rounded))
                        Text("条本地待取记录 · \(Set(store.pending.map(\.station)).count) 个地点").font(.subheadline)
                    }
                    .foregroundStyle(.white).padding(24).frame(maxWidth: .infinity, alignment: .leading)
                    .background(Palette.green, in: RoundedRectangle(cornerRadius: 26))

                    Label("官方网页读取的包裹会标明来源；未读取时不能视为没有包裹。", systemImage: "info.circle")
                        .font(.caption).foregroundStyle(.secondary)
                    HStack {
                        Text(showCollected ? "已取记录" : "待取清单").font(.title3.bold())
                        Spacer()
                        Button(showCollected ? "查看待取" : "已取 \(store.collected.count)") { showCollected.toggle() }.font(.subheadline)
                    }
                    if displayed.isEmpty {
                        ContentUnavailableView(search.isEmpty ? "官方待取件尚未读取" : "没有匹配的本地记录", systemImage: "shippingbox", description: Text("请先打开上方官方页面。没有本地记录不代表没有包裹。"))
                    }
                    ForEach(Array(Set(displayed.map(\.station))).sorted(), id: \.self) { station in
                        VStack(alignment: .leading, spacing: 12) {
                            Label(station, systemImage: "mappin.circle").font(.subheadline.bold())
                            ForEach(displayed.filter { $0.station == station }) { parcel in
                                VStack(alignment: .leading, spacing: 16) {
                                    HStack(spacing: 12) {
                                        if let provider = store.provider(parcel.providerID) { ProviderMark(provider: provider) }
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(parcel.title).font(.headline)
                                            Text("\(parcel.carrier.isEmpty ? "快递" : parcel.carrier) · \(parcel.source == "cainiao-web" ? "官方页面读取" : "手动添加")").font(.caption).foregroundStyle(.secondary)
                                        }
                                        Spacer()
                                        Button { store.toggleCollected(parcel) } label: {
                                            Image(systemName: parcel.isCollected ? "arrow.uturn.backward.circle" : "checkmark.circle")
                                                .font(.title2).frame(width: 44, height: 44)
                                        }.accessibilityLabel(parcel.isCollected ? "恢复待取" : "标记已取")
                                    }
                                    HStack {
                                        Text(parcel.pickupCode).font(.system(size: 29, weight: .semibold, design: .monospaced))
                                        Spacer()
                                        Button(copiedID == parcel.id ? "已复制" : "复制") {
                                            UIPasteboard.general.string = parcel.pickupCode
                                            copiedID = parcel.id
                                        }.font(.caption)
                                    }
                                    if let provider = store.provider(parcel.providerID) {
                                        Button { selectedProvider = provider } label: {
                                            Label("查看取件入口", systemImage: "arrow.up.forward.app").font(.subheadline)
                                        }
                                    }
                                }.padding(18).background(.background, in: RoundedRectangle(cornerRadius: 22))
                            }
                        }
                    }
                }.padding(22)
            }
            .background(Palette.paper).foregroundStyle(Palette.ink)
            .searchable(text: $search, prompt: "搜索包裹、取件码或地点")
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button { adding = true } label: { Image(systemName: "plus") }.accessibilityLabel("添加包裹") } }
            .sheet(isPresented: $adding) { AddParcelView() }
            .sheet(item: $selectedProvider) { PickupEntryView(provider: $0) }
            .sheet(isPresented: $officialPortal) { OfficialPickupView() }
        }
    }
}

struct ProvidersView: View {
    @EnvironmentObject private var store: ParcelStore
    @State private var selected: PickupProvider?
    @State private var adding = false
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("取件凭证").font(.largeTitle.bold())
                    Text("菜鸟使用官方网页展示身份码；其余平台继续验证。\n包裹自动汇总尚未打通。")
                        .font(.subheadline).foregroundStyle(.secondary)
                    ForEach(store.providers) { provider in
                        Button { selected = provider } label: {
                            HStack(spacing: 14) {
                                ProviderMark(provider: provider)
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(provider.name).font(.headline)
                                    Text("\(provider.kind) · \(provider.identityURL == nil ? "尚未打通" : "官方网页入口")").font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right").font(.caption)
                            }.padding(18).background(.background, in: RoundedRectangle(cornerRadius: 22))
                        }.buttonStyle(.plain)
                    }
                    Button { adding = true } label: { Label("添加取件平台", systemImage: "plus.circle").frame(maxWidth: .infinity).padding(20) }
                    Text("自定义入口只保存平台名称和微信搜索词，不会自动获得包裹数据或身份码。")
                        .font(.caption).foregroundStyle(.secondary)
                }.padding(22)
            }.background(Palette.paper).foregroundStyle(Palette.ink)
            .sheet(item: $selected) { PickupEntryView(provider: $0) }
            .sheet(isPresented: $adding) { AddProviderView() }
        }
    }
}

struct PickupEntryView: View {
    let provider: PickupProvider
    @Environment(\.dismiss) private var dismiss
    @State private var copied = false
    var body: some View {
        if provider.id == "cainiao" {
            OfficialPickupView()
        } else {
          NavigationStack {
            VStack(alignment: .leading, spacing: 24) {
                ProviderMark(provider: provider)
                Text("\(provider.name)取件入口").font(.title.bold())
                Text("当前尚未接通身份码和小程序自动跳转。").font(.subheadline).foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 14) {
                    Text("1  打开微信，搜索「\(provider.miniProgramName)」。")
                    Text("2  核对运营主体后，进入官方服务并登录。")
                    Text("3  查看其提供的取件码、身份码或开柜入口。")
                }.font(.body)
                Text("这里保存的是搜索词，尚未核验具体小程序标识及身份码页面。")
                    .font(.caption).foregroundStyle(.secondary)
                Button(copied ? "已复制搜索词" : "复制微信搜索词") {
                    UIPasteboard.general.string = provider.miniProgramName
                    copied = true
                }.buttonStyle(.borderedProminent).controlSize(.large)
                if !provider.website.isEmpty, let url = URL(string: provider.website) {
                    Link("查看平台官网", destination: url).font(.subheadline)
                    Text("官网是备用信息入口，不保证能在网页取件。").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
            }.padding(26)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
          }
        }
    }
}

struct AboutView: View {
    var body: some View {
        NavigationStack {
            List {
                Section("拾件 · 官方入口验证版") {
                    Label("本地保存，无需注册", systemImage: "iphone")
                    Label("本地包裹记录不上传；登录在官方网页完成", systemImage: "lock.shield")
                    Label("不读取短信", systemImage: "message")
                }
                Section("当前能力") {
                    Text("已接入官方身份码网页，页面内容由淘宝官方提供。浏览器登录后显示已验证；iOS 工程未编译实测。")
                    Text("原生工程已加入官方页面读取及合并逻辑；编译、iPhone 实测和其他平台接入仍待完成。")
                }
                Section("数据说明") {
                    Text("不再自动添加演示记录。旧演示记录已隐藏，手动添加的内容仍保存在本机。")
                    Text("iOS 工程与 Windows 浏览器预览的本地数据分别保存，不会互相同步。")
                }
            }.navigationTitle("设置")
        }
    }
}

/// 同一个持久 WebKit 会话承载官方登录、身份码和待取件页，不读取 Cookie 或复制条形码。
@MainActor
final class OfficialPickupSession: NSObject, ObservableObject, WKNavigationDelegate, WKUIDelegate {
    static let identity = URL(string: "https://pages-fast.m.taobao.com/wow/z/uniapp/1100410/last-mile-fe/m-end-identity-code/home?x-ssr=true&skeleton=true&forceThemis=true")!
    static let parcels = URL(string: "https://pages-fast.m.taobao.com/wow/z/uniapp/1100333/last-mile-fe/m-end-school-tab/home")!
    let webView: WKWebView
    @Published var status = "正在加载官方页面…"
    @Published var host = "pages-fast.m.taobao.com"
    @Published var hasError = false
    @Published var readResult: OfficialPageRead?
    private var pendingPage = false

    override init() {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        webView = WKWebView(frame: .zero, configuration: configuration)
        super.init()
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.allowsBackForwardNavigationGestures = true
        load(Self.identity)
    }

    func load(_ url: URL) {
        pendingPage = url == Self.parcels
        status = "正在加载官方页面…"
        hasError = false
        webView.load(URLRequest(url: url, timeoutInterval: 30))
    }

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        host = webView.url?.host ?? "官方网页"
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        status = "官方页面已加载；是否登录及身份码以页面内容为准"
        if pendingPage {
            readPending()
            return
        }
        // 只检测页面可见错误文字，不采集身份码、账号或浏览器凭证。
        webView.evaluateJavaScript("(() => { const t = document.body ? document.body.innerText : ''; return t.includes('接口超时') || t.includes('网络异常'); })()") { [weak self] result, _ in
            if let failed = result as? Bool, failed {
                self?.status = "官方接口超时，未读取到包裹；请重试，不能视为零件"
                self?.hasError = true
            }
        }
    }

    func readPending() {
        guard pendingPage else { return }
        guard let url = Bundle.main.url(forResource: "cainiao-reader", withExtension: "js"),
              let reader = try? String(contentsOf: url, encoding: .utf8) else {
            status = "读取组件缺失，无法同步"
            hasError = true
            return
        }
        status = "正在读取官方页面当前显示的待取件…"
        // 只读取页面可见包裹信息，不访问 Cookie、网络令牌或隐藏业务状态。
        let script = "JSON.stringify((\(reader))(document.body ? document.body.innerText : ''))"
        webView.evaluateJavaScript(script) { [weak self] value, error in
            guard error == nil, let json = value as? String, let data = json.data(using: .utf8),
                  let result = try? JSONDecoder().decode(OfficialPageRead.self, from: data) else {
                self?.hasError = true
                self?.status = "未能读取官方页面，原有包裹保持不变"
                return
            }
            self?.readResult = result
            self?.hasError = result.state == "error"
            self?.status = result.state == "ready" ? "已读取 \(result.parcels.count) 件，正在保存" : result.message
        }
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        guard (error as NSError).code != NSURLErrorCancelled else { return }
        hasError = true
        status = "官方页面加载失败，请重试或在浏览器打开"
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        self.webView(webView, didFailProvisionalNavigation: navigation, withError: error)
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url else { decisionHandler(.cancel); return }
        if url.absoluteString == "about:blank" { decisionHandler(.allow); return }
        let host = url.host?.lowercased() ?? ""
        let official = ["taobao.com", "tmall.com", "alipay.com", "alipay.cn", "cainiao.com"]
            .contains { host == $0 || host.hasSuffix("." + $0) }
        if url.scheme == "https" && official { decisionHandler(.allow) }
        else {
            status = "页面请求跳转外部应用或其他站点；请使用下方浏览器入口继续"
            decisionHandler(.cancel)
        }
    }

    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if navigationAction.targetFrame == nil { webView.load(navigationAction.request) }
        return nil
    }
}

struct OfficialPickupWebView: UIViewRepresentable {
    let session: OfficialPickupSession
    func makeUIView(context: Context) -> WKWebView { session.webView }
    func updateUIView(_ uiView: WKWebView, context: Context) { }
}

struct OfficialPickupView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: ParcelStore
    @StateObject private var session = OfficialPickupSession()
    @State private var page = 0
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("官方页面", selection: $page) {
                    Text("身份码").tag(0)
                    Text("待取件").tag(1)
                }.pickerStyle(.segmented).padding(12)
                HStack {
                    Image(systemName: "lock.fill")
                    Text(session.host).lineLimit(1)
                    Spacer()
                    Button("重试") { session.load(page == 0 ? OfficialPickupSession.identity : OfficialPickupSession.parcels) }
                }.font(.caption).padding(.horizontal, 14).padding(.bottom, 10)
                OfficialPickupWebView(session: session)
                if page == 1 {
                    Button("读取当前待取件到拾件") { session.readPending() }
                        .buttonStyle(.borderedProminent).padding(.top, 10)
                }
                Text(session.status).font(.caption).foregroundStyle(session.hasError ? Color.orange : Color.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(12)
                Link("在浏览器打开此官方页面", destination: page == 0 ? OfficialPickupSession.identity : OfficialPickupSession.parcels)
                    .font(.caption).padding(.bottom, 12)
            }
            .navigationTitle("菜鸟官方取件").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
            .onChange(of: page) { _, newPage in
                session.load(newPage == 0 ? OfficialPickupSession.identity : OfficialPickupSession.parcels)
            }
            .onChange(of: session.readResult) { _, result in
                guard let result, result.state == "ready" else { return }
                if let error = store.importOfficial(result) {
                    session.status = error
                    session.hasError = true
                } else {
                    session.status = "已保存 \(result.parcels.count) 件真实待取件；可返回清单查看"
                }
            }
        }
    }
}
