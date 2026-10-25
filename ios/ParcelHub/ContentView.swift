import SwiftUI
import UIKit
import WebKit
import Combine

struct ContentView: View {
    @EnvironmentObject private var store: ParcelStore
    var body: some View {
        TabView {
            PackagesView().tabItem { Label("待取件", systemImage: "shippingbox") }
            ProvidersView().tabItem { Label("身份码", systemImage: "barcode.viewfinder") }
            MyView().tabItem { Label("我的", systemImage: "person.crop.circle") }
        }
        .alert("本地数据提示", isPresented: Binding(get: { store.storageWarning != nil }, set: { _ in })) {
            Button("知道了", role: .cancel) { }
        } message: { Text(store.storageWarning ?? "") }
    }
}

struct ProviderMark: View {
    let provider: PickupProvider
    var body: some View {
        BrandMark(asset: "Brand-" + provider.id, fallback: provider.symbol, label: provider.name)
    }
}

struct BrandMark: View {
    let asset: String
    let fallback: String
    let label: String
    var body: some View {
        Group {
            if UIImage(named: asset) != nil { Image(asset).resizable().scaledToFill() }
            else { Image(systemName: fallback).font(.title3).foregroundStyle(Palette.blue) }
        }.frame(width: 44, height: 44)
            .background(Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 13)).accessibilityLabel(label)
    }
}

private struct CredentialRequest: Identifiable {
    let id = UUID()
    var station: String?
}

struct PackagesView: View {
    @EnvironmentObject private var store: ParcelStore
    @State private var search = ""
    @State private var adding = false
    @State private var smsAdding = false
    @EnvironmentObject private var sync: OfficialSyncController
    @State private var credentialRequest: CredentialRequest?
    @State private var selectedProvider: PickupProvider?
    @State private var providerAfterBinding: PickupProvider?

    private var displayed: [Parcel] {
        let source = store.pending
        return source.filter { search.isEmpty || [$0.title, $0.station, $0.pickupCode, $0.trackingNumber, $0.carrier, store.provider($0.providerID)?.name ?? ""].joined(separator: " ").localizedCaseInsensitiveContains(search) }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    // 搜索框属于滚动内容，向下浏览包裹时自然移出屏幕。
                    HStack(spacing: 10) {
                        Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                        TextField("搜索包裹、取件码或地点", text: $search)
                            .textInputAutocapitalization(.never).autocorrectionDisabled()
                        if !search.isEmpty {
                            Button { search = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                                .accessibilityLabel("清除搜索")
                        }
                    }.padding(14).background(Palette.card, in: RoundedRectangle(cornerRadius: 16))

                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("\(store.pending.count)").font(.system(size: 52, weight: .semibold, design: .rounded))
                        VStack(alignment: .leading, spacing: 4) {
                            Text("件待取包裹").font(.headline)
                            Text("\(Set(store.pending.map(\.station)).count) 个取件地点").font(.caption)
                        }
                        Spacer()
                        Image(systemName: "shippingbox.fill").font(.largeTitle).opacity(0.6)
                    }
                    .foregroundStyle(.white).padding(24).frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(red: 0.10, green: 0.35, blue: 0.82).gradient, in: RoundedRectangle(cornerRadius: 26))

                    Button {
                        if let provider = store.preferredCredential { selectedProvider = provider }
                        else { credentialRequest = CredentialRequest() }
                    } label: {
                        Label("打开身份码", systemImage: "barcode.viewfinder")
                            .frame(maxWidth: .infinity).padding(.vertical, 15)
                    }.buttonStyle(.borderedProminent).buttonBorderShape(.roundedRectangle(radius: 14))
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 8) {
                            if sync.isRefreshing { ProgressView().controlSize(.small) }
                            else { Image(systemName: sync.needsLogin ? "person.crop.circle.badge.exclamationmark" : "arrow.triangle.2.circlepath") }
                            Text(sync.status)
                        }
                        if let updated = store.lastOfficialReadAt {
                            Text("上次同步 \(updated.formatted(date: .abbreviated, time: .shortened)) · 可下拉刷新")
                        }
                    }.font(.caption).foregroundStyle(.secondary)
                    Text("待取清单").font(.title2.bold())
                    if displayed.isEmpty {
                        ContentUnavailableView(search.isEmpty ? "暂无本地待取包裹" : "没有匹配的记录", systemImage: "shippingbox", description: Text(search.isEmpty ? "登录淘宝后在前台自动检查；短信件可点右上角添加。" : "试试其他取件码、快递公司或地点。"))
                    }
                    ForEach(Array(Set(displayed.map(\.station))).sorted(), id: \.self) { station in
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Text(station).font(.title3.bold()).foregroundStyle(.primary)
                                Spacer(minLength: 12)
                                Button {
                                    if let id = store.stationCredentials[station], let provider = store.provider(id) { selectedProvider = provider }
                                    else { credentialRequest = CredentialRequest(station: station) }
                                } label: {
                                    Text(store.stationCredentials[station].flatMap { store.provider($0)?.name }.map { "\($0)身份码" } ?? "选择身份码")
                                }
                                .font(.subheadline).fixedSize(horizontal: true, vertical: false)
                            }.foregroundStyle(Palette.blue)
                            ForEach(displayed.filter { $0.station == station }) { parcel in
                                ParcelCard(parcel: parcel)
                            }
                        }
                    }
                }.padding(20)
            }
            .refreshable { await sync.refreshAndWait() }
            .scrollDismissesKeyboard(.interactively)
            .background(Palette.paper).foregroundStyle(Palette.ink)
            .navigationTitle("涂涂取件").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("粘贴短信智能导入", systemImage: "text.bubble") { smsAdding = true; adding = true }
                        Button("手动添加包裹", systemImage: "square.and.pencil") { smsAdding = false; adding = true }
                    } label: { Image(systemName: "plus") }.accessibilityLabel("添加包裹")
                }
            }
            .sheet(isPresented: $adding) { AddParcelView(fromSMS: smsAdding) }
            .sheet(item: $credentialRequest, onDismiss: {
                if let providerAfterBinding {
                    selectedProvider = providerAfterBinding
                    self.providerAfterBinding = nil
                }
            }) { request in
                CredentialPickerView(station: request.station, onChoose: { provider in
                    providerAfterBinding = provider
                    credentialRequest = nil
                })
            }
            .fullScreenCover(item: $selectedProvider) { PickupEntryView(provider: $0) }
        }
    }
}

struct ParcelCard: View {
    let parcel: Parcel
    @EnvironmentObject private var store: ParcelStore
    @State private var copied = false
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                if let asset = CarrierBrand.asset(for: parcel.carrier) {
                    BrandMark(asset: asset, fallback: "shippingbox", label: parcel.carrier)
                } else if let provider = store.provider(parcel.providerID) { ProviderMark(provider: provider) }
                VStack(alignment: .leading, spacing: 4) {
                    Text(parcel.title).font(.headline)
                    Text("\(parcel.carrier.isEmpty ? "快递" : parcel.carrier) · \(parcel.source == "sms" ? "短信导入" : store.provider(parcel.providerID)?.name ?? "本地")")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button { store.toggleCollected(parcel) } label: {
                    Text(parcel.isCollected ? "恢复待取" : "我已取件")
                        .font(.caption.weight(.medium)).padding(.horizontal, 12).frame(minHeight: 40)
                        .background(Palette.blue.opacity(0.10), in: Capsule())
                }.accessibilityLabel(parcel.isCollected ? "恢复待取" : "我已取件")
            }
            HStack {
                Text(parcel.pickupCode).font(.system(size: 28, weight: .semibold, design: .monospaced)).textSelection(.enabled)
                    .minimumScaleFactor(0.6).lineLimit(1)
                Spacer()
                Button(copied ? "已复制" : "复制") { UIPasteboard.general.string = parcel.pickupCode; copied = true }.font(.caption)
            }
            if let date = parcel.lastReadAt {
                Text("官方清单更新于 \(date.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }.padding(18).background(Palette.card, in: RoundedRectangle(cornerRadius: 22))
    }
}

struct ProvidersView: View {
    var body: some View { CredentialPickerView(station: nil, showsDone: false) }
}

struct CredentialPickerView: View {
    var station: String?
    var showsDone = true
    var onChoose: ((PickupProvider) -> Void)? = nil
    @EnvironmentObject private var store: ParcelStore
    @Environment(\.dismiss) private var dismiss
    @State private var selected: PickupProvider?
    @State private var adding = false
    @State private var sorting = false
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text(station.map { "为「\($0)」选择身份码，下次可直接打开。" } ?? "按驿站要求选择平台。点击排序后，按住右侧把手上下拖动。")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                Section {
                    ForEach(store.credentialProviders) { provider in
                        Button {
                            guard !sorting else { return }
                            if let station { store.rememberCredential(provider.id, for: station) }
                            store.preferCredential(provider.id)
                            if let onChoose { onChoose(provider) }
                            else { selected = provider }
                        } label: {
                            HStack(spacing: 14) {
                                ProviderMark(provider: provider)
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(provider.id == "fcbox" ? "丰巢取件" : "\(provider.name)身份码").font(.headline).foregroundStyle(.primary)
                                    Text(provider.identityURL == nil ? "打开官方服务获取凭证" : "App 内打开官方身份码")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                if let station, store.stationCredentials[station] == provider.id { Image(systemName: "checkmark.circle.fill") }
                                else if !sorting { Image(systemName: "chevron.right").font(.caption) }
                            }.padding(.vertical, 5)
                        }.buttonStyle(.plain)
                    }.onMove { offsets, destination in store.moveProviders(from: offsets, to: destination) }
                        .deleteDisabled(true)
                        .moveDisabled(!sorting)
                }
                if !sorting { Section { Button { adding = true } label: { Label("添加其他平台", systemImage: "plus.circle") } } }
            }.environment(\.editMode, .constant(sorting ? .active : .inactive))
                .navigationTitle("身份码").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(sorting ? "完成" : "排序") { withAnimation { sorting.toggle() } }
                            .font(.subheadline).foregroundStyle(.secondary).buttonStyle(.plain)
                    }
                    if showsDone { ToolbarItem(placement: .cancellationAction) { Button("关闭") { dismiss() } } }
                }
                .fullScreenCover(item: $selected) { PickupEntryView(provider: $0) }
                .sheet(isPresented: $adding) { AddProviderView() }
        }
    }
}

struct PickupEntryView: View {
    let provider: PickupProvider
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var copied = false
    @State private var openFailed = false
    var body: some View {
        if provider.id == "taobao" {
            OfficialPickupView(initialPage: 1)
        } else {
            NavigationStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        ProviderMark(provider: provider)
                        Text(provider.id == "fcbox" ? "丰巢取件" : "\(provider.name)身份码").font(.largeTitle.bold())
                        Text("请使用本站要求的平台身份码。能查到同一包裹，不代表身份码可以通用。")
                            .font(.subheadline).foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 18) {
                            Label("打开微信，搜索「\(provider.miniProgramName)」", systemImage: "1.circle")
                            Label("进入官方小程序并登录", systemImage: "2.circle")
                            Label("找到身份码或取件入口，出示动态码", systemImage: "3.circle")
                        }.padding(20).frame(maxWidth: .infinity, alignment: .leading)
                            .background(Palette.card, in: RoundedRectangle(cornerRadius: 20))
                        if provider.id == "jd" {
                            Text("若驿站要求扫描现场的京东快递小程序码，请先用微信扫一扫进入，再找到「身份码」。现场入口可能带站点信息，应优先使用现场指引。")
                                .font(.subheadline)
                        }
                        if provider.id == "fcbox" {
                            Text("丰巢官方支持通知取件码及 App 一键开柜，目前未确认可供本 App 使用的统一身份码接口。")
                                .font(.subheadline)
                        }
                        Button(copied ? "已复制名称，再打开微信" : "复制名称并打开微信") {
                            UIPasteboard.general.string = provider.miniProgramName
                            copied = true
                            if let url = URL(string: "weixin://") { openURL(url) { accepted in openFailed = !accepted } }
                        }.buttonStyle(.borderedProminent).controlSize(.large)
                        if openFailed { Text("无法打开微信，请从手机桌面打开并搜索。已复制小程序名称。") .font(.caption).foregroundStyle(.orange) }
                        if let link = provider.appStoreURL, let url = URL(string: link) {
                            Link("官方 App（App Store）", destination: url).font(.subheadline)
                        }
                        Text("当前可打开微信，尚不能直达这个小程序的身份码页面；不会用淘宝码替代。")
                            .font(.caption).foregroundStyle(.secondary)
                    }.padding(24)
                }.background(Palette.paper)
                    .navigationTitle("取件身份码").navigationBarTitleDisplayMode(.inline)
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
            }
        }
    }
}

struct MyView: View {
    @EnvironmentObject private var store: ParcelStore
    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 16) {
                        Image("TutuLogo").resizable().scaledToFit().frame(width: 64, height: 64).clipShape(RoundedRectangle(cornerRadius: 16))
                        VStack(alignment: .leading, spacing: 5) {
                            Text("涂涂取件").font(.title2.bold())
                            Text("把每一次取件整理好").font(.caption).foregroundStyle(.secondary)
                        }
                    }.padding(.vertical, 12)
                }
                Section {
                    NavigationLink { CollectedParcelsView() } label: {
                        HStack { Label("已取记录", systemImage: "checkmark.circle"); Spacer(); Text("\(store.collected.count)").foregroundStyle(.secondary) }
                    }
                    NavigationLink { SettingsView() } label: { Label("设置", systemImage: "gearshape") }
                }
                Section { Text("更多个人功能会逐步加入。").font(.caption).foregroundStyle(.secondary) }
            }.navigationTitle("我的")
        }
    }
}

struct CollectedParcelsView: View {
    @EnvironmentObject private var store: ParcelStore
    var body: some View {
        ScrollView {
            LazyVStack(spacing: 14) {
                if store.collected.isEmpty { ContentUnavailableView("暂无已取记录", systemImage: "checkmark.circle", description: Text("待取清单中标记已取的包裹会保存在这里。")) }
                ForEach(store.collected.sorted { ($0.collectedAt ?? .distantPast) > ($1.collectedAt ?? .distantPast) }) { parcel in
                    VStack(alignment: .leading, spacing: 8) { Text(parcel.station).font(.caption).foregroundStyle(.secondary); ParcelCard(parcel: parcel) }
                }
            }.padding(20)
        }.background(Palette.paper).navigationTitle("已取记录").navigationBarTitleDisplayMode(.inline)
    }
}

struct SettingsView: View {
    @EnvironmentObject private var store: ParcelStore
    @State private var officialLogin = false
    var body: some View {
        List {
            Section("同步与账号") {
                Toggle("前台自动刷新待取清单", isOn: $store.autoSyncEnabled)
                Button("淘宝登录与官方清单") { officialLogin = true }
                Text("打开或返回 App 时自动检查，前台每两分钟检查一次；登录失效或读取异常时保留原记录。下拉待取清单可手动重试。") .font(.caption).foregroundStyle(.secondary)
                Text("当前仅淘宝清单支持同步。iOS 后台运行由系统调度，本版不承诺锁屏后持续更新。") .font(.caption).foregroundStyle(.secondary)
            }
            Section("短信与本地记录") {
                Text("朋友寄件也可添加：在短信中复制完整通知，到右上角 + 选择短信智能导入。自动识别取件码，沿用该物流公司最近一次地点，按日期编号。确认后只保存包裹字段。")
                Text("不会自动读取短信收件箱，也不保存短信原文。短信件和未接通平台的包裹，取完后需手动标记。")
            }
            Section("身份码") {
                NavigationLink("地点身份码绑定") { StationCredentialSettingsView() }
                Text("淘宝、菜鸟、京东等来源分别保留；身份码页可手动排序，地点可记住常用入口。除淘宝官方网页外，其余动态码仍在逐项验证。")
            }
            Section("关于涂涂取件") {
                Label("蓝白配色，跟随系统深色模式", systemImage: "circle.lefthalf.filled")
                Text("版本 0.4.0 · 本地开发版")
            }
        }.navigationTitle("设置").navigationBarTitleDisplayMode(.inline)
            .fullScreenCover(isPresented: $officialLogin) { OfficialPickupView(initialPage: 0) }
    }
}

struct StationCredentialSettingsView: View {
    @EnvironmentObject private var store: ParcelStore
    private var stations: [String] {
        Array(Set(store.parcels.filter { !$0.isDemo }.map(\.station)).union(store.stationCredentials.keys)).sorted()
    }
    var body: some View {
        List {
            if stations.isEmpty { Text("有包裹地点后，可在这里设置身份码来源。").foregroundStyle(.secondary) }
            ForEach(stations, id: \.self) { station in
                Section(station) {
                    Picker("身份码来源", selection: Binding(get: { store.stationCredentials[station] ?? "" }, set: { id in
                        if id.isEmpty { store.forgetCredential(for: station) }
                        else { store.rememberCredential(id, for: station) }
                    })) {
                        Text("未绑定").tag("")
                        ForEach(store.credentialProviders) { Text($0.name).tag($0.id) }
                    }
                }
            }
        }.navigationTitle("地点身份码绑定").navigationBarTitleDisplayMode(.inline)
    }
}

/// 保留官方条形码的生成与刷新，不提取登录凭证，也不重画身份码。
@MainActor
final class OfficialPickupSession: NSObject, ObservableObject, WKNavigationDelegate, WKUIDelegate {
    static let identity = URL(string: "https://pages-fast.m.taobao.com/wow/z/uniapp/1100410/last-mile-fe/m-end-identity-code/home?x-ssr=true&skeleton=true&forceThemis=true")!
    static let parcels = URL(string: "https://pages-fast.m.taobao.com/wow/z/uniapp/1100333/last-mile-fe/m-end-school-tab/home")!
    let webView: WKWebView
    @Published var status = "正在加载官方页面…"
    @Published var hasError = false
    @Published var isLoading = true
    @Published var readResult: OfficialPageRead?
    private var pendingPage = false
    private var generation = 0
    private var readAttempt = 0

    override init() {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        // 只适配淘宝取件页面的视口；不隐藏页面内容，不影响官方登录和验证码。
        let viewport = """
        (() => {
          if (location.hostname !== 'pages-fast.m.taobao.com' || !location.pathname.includes('/last-mile-fe/')) return;
          let meta = document.querySelector('meta[name="viewport"]');
          if (!meta) { meta = document.createElement('meta'); meta.name = 'viewport'; document.head.appendChild(meta); }
          meta.content = 'width=device-width, initial-scale=1, viewport-fit=cover';
        })();
        """
        configuration.userContentController.addUserScript(WKUserScript(source: viewport, injectionTime: .atDocumentEnd, forMainFrameOnly: true))
        webView = WKWebView(frame: .zero, configuration: configuration)
        super.init()
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.allowsBackForwardNavigationGestures = true
        webView.backgroundColor = .white
        webView.scrollView.backgroundColor = .white
        webView.overrideUserInterfaceStyle = .light
    }

    func stop() {
        generation += 1
        webView.stopLoading()
        readResult = nil
        isLoading = false
    }

    func load(_ url: URL) {
        generation += 1
        pendingPage = url == Self.parcels
        readAttempt = 0
        readResult = nil
        status = "正在加载官方页面…"
        isLoading = true
        hasError = false
        webView.load(URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30))
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        generation += 1
        readAttempt = 0
        readResult = nil
        isLoading = true
        hasError = false
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        isLoading = false
        status = "官方页面已加载"
        if pendingPage { readPending(); return }
        webView.evaluateJavaScript("(() => { const t = document.body ? document.body.innerText : ''; return /接口超时|网络异常/.test(t); })()") { [weak self] result, _ in
            if let failed = result as? Bool, failed {
                self?.status = "官方页面暂时无法加载，请重试"
                self?.hasError = true
            }
        }
    }

    func readPending() {
        guard pendingPage, !isLoading else { return }
        guard let currentURL = webView.url,
              currentURL.host == Self.parcels.host,
              currentURL.path == Self.parcels.path else {
            status = "请先完成官方登录，再打开待取记录刷新"
            hasError = true
            return
        }
        guard let url = Bundle.main.url(forResource: "cainiao-reader", withExtension: "js"),
              let reader = try? String(contentsOf: url, encoding: .utf8) else {
            status = "读取组件缺失，无法同步"; hasError = true; return
        }
        let requestGeneration = generation
        readAttempt += 1
        let attempt = readAttempt
        status = "正在读取最新待取清单…"
        let script = "JSON.stringify((\(reader))(document.body ? document.body.innerText : ''))"
        webView.evaluateJavaScript(script) { [weak self] value, error in
            guard let self, self.generation == requestGeneration else { return }
            guard error == nil, let json = value as? String, let data = json.data(using: .utf8),
                  let result = try? JSONDecoder().decode(OfficialPageRead.self, from: data) else {
                self.hasError = true; self.status = "未能读取官方页面，原有包裹保持不变"; return
            }
            // 页面应用异步加载，首次得到的占位零件不得清空已有记录。
            if result.state == "loading", attempt < 12 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.75) { [weak self] in
                    guard let self, self.generation == requestGeneration else { return }
                    self.readPending()
                }
                return
            }
            self.status = result.state == "ready" ? "正在同步清单…" : result.message
            self.hasError = result.state != "ready"
            self.readResult = result
        }
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        guard (error as NSError).code != NSURLErrorCancelled else { return }
        generation += 1
        isLoading = false
        status = "官方页面加载失败，原有包裹保持不变，请重试"
        hasError = true
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
            status = "此步骤需要外部应用，请从右上角菜单打开官方页面继续"
            hasError = true
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
    @State private var page: Int
    init(initialPage: Int = 1) { _page = State(initialValue: initialPage) }
    private var pageURL: URL { page == 1 ? OfficialPickupSession.identity : OfficialPickupSession.parcels }
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("官方页面", selection: $page) {
                    Text("待取记录").tag(0)
                    Text("身份码").tag(1)
                }.pickerStyle(.segmented).padding(12)
                if session.isLoading { ProgressView().frame(maxWidth: .infinity).padding(8) }
                OfficialPickupWebView(session: session)
            }
            .background(Palette.paper)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                VStack(spacing: 10) {
                    if page == 0 {
                        Button { session.load(OfficialPickupSession.parcels) } label: {
                            Label("读取当前待取件到涂涂取件", systemImage: "arrow.triangle.2.circlepath")
                                .frame(maxWidth: .infinity).padding(.vertical, 6)
                        }.buttonStyle(.borderedProminent).disabled(session.isLoading)
                    }
                    if page == 0 || session.hasError {
                        Text(session.status).font(.caption)
                            .foregroundStyle(session.hasError ? Color.orange : Color.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }.padding(page == 0 || session.hasError ? 14 : 0).background(.bar)
            }
            .navigationTitle(page == 1 ? "淘宝身份码" : "淘宝待取记录").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("完成") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("刷新官方页面", systemImage: "arrow.clockwise") { session.load(pageURL) }
                        Link("在浏览器打开", destination: pageURL)
                        Text("内容由淘宝官方提供，身份码由官方刷新")
                    } label: { Image(systemName: "ellipsis.circle") }
                }
            }
            .onAppear { session.load(pageURL) }
            .onDisappear {
                session.stop()
                NotificationCenter.default.post(name: Notification.Name("ParcelHub.official-session-changed"), object: nil)
            }
            .onChange(of: page) { _, _ in session.load(pageURL) }
            .onChange(of: session.readResult) { _, result in
                guard let result, result.state == "ready" else { return }
                let previousCount = store.pending.filter { ["cainiao-web", "taobao-web"].contains($0.source ?? "") }.count
                if let error = store.importOfficial(result) {
                    session.status = error; session.hasError = true
                } else if result.parcels.isEmpty {
                    session.status = "官方暂无待取件，已从待取清单移除该来源的 \(previousCount) 条旧记录"
                } else {
                    session.status = "已同步 \(result.parcels.count) 件待取包裹，可返回清单查看"
                }
            }
        }
    }
}
