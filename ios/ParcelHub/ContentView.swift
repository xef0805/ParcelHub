import SwiftUI
import UIKit
import WebKit
import Combine

// 动态同步/识别提示也随应用语言切换，不改写保存的包裹与短信。
struct AppMessage: View {
    let text: String
    @Environment(\.locale) private var locale
    init(_ text: String) { self.text = text }
    private var translated: String {
        guard locale.identifier.hasPrefix("en"),
              let url = Bundle.main.url(forResource: "en", withExtension: "lproj"),
              let bundle = Bundle(url: url) else { return text }
        let exact = bundle.localizedString(forKey: text, value: text, table: nil)
        if exact != text { return exact }
        let patterns = [
            ("^已同步 · 新增 ([0-9]+) 件$", "Synced · $1 new pickups"),
            ("^已同步 ([0-9]+) 件待取包裹$", "$1 pickups synced"),
            ("^已归档 ([0-9]+) 件$", "$1 archived"),
            ("^已标记取件 · ([0-9]+) 件$", "$1 pickups marked collected"),
            ("^沿用(.+)上次地点，请核对$", "Using the last $1 location. Please check"),
            ("^返回后确认：刚才是否进入了(.+)？$", "After returning, confirm: did $1 open?")
        ]
        for (pattern, replacement) in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let range = NSRange(text.startIndex..., in: text)
            if regex.firstMatch(in: text, range: range) != nil {
                return regex.stringByReplacingMatches(in: text, range: range, withTemplate: replacement)
            }
        }
        return text
    }
    var body: some View { Text(verbatim: translated) }
}

struct ContentView: View {
    @Environment(\.locale) private var locale
    @EnvironmentObject private var network: NetworkStatus
    @EnvironmentObject private var store: ParcelStore
    @EnvironmentObject private var clipboard: ClipboardImportController
    @State private var selectedTab = 0
    @State private var showingClipboardPrompt = false
    @State private var copyToastID: UUID?
    @State private var showingCopyToast = false
    @State private var toastMessage = "已复制到剪贴板"
    var body: some View {
        TabView(selection: $selectedTab) {
            PackagesView().tabItem { Label("待取件", systemImage: "shippingbox") }.tag(0)
            ProvidersView().tabItem { Label("身份码", systemImage: "barcode.viewfinder") }.tag(1)
            MyView().tabItem { Label("我的", systemImage: "person.crop.circle") }.tag(2)
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            if network.isOffline {
                Label { AppMessage(AppServiceIssue.offline.message) } icon: { Image(systemName: "wifi.slash") }
                    .font(.caption).foregroundStyle(.orange).frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12).background(Palette.card)
            }
        }
        .onAppear { showingClipboardPrompt = clipboard.candidate != nil && !clipboard.isEditing }
        .onChange(of: clipboard.candidate?.text) { _, text in showingClipboardPrompt = text != nil && !clipboard.isEditing }
        .onChange(of: clipboard.isEditing) { _, editing in
            showingClipboardPrompt = !editing && clipboard.candidate != nil
        }
        .alert("检测到可导入内容", isPresented: $showingClipboardPrompt) {
            Button("去导入") {
                selectedTab = 0; clipboard.openImport()
            }
            Button("暂不处理", role: .cancel) { clipboard.dismissCandidate() }
        } message: {
            Text("发现取件短信，要去导入吗？")
        }
        .alert("本地数据提示", isPresented: Binding(get: { store.storageWarning != nil }, set: { _ in })) {
            Button("知道了", role: .cancel) { }
        } message: { Text(LocalizedStringKey(store.storageWarning ?? "")) }
        .overlay(alignment: .bottom) {
            VStack(spacing: 8) {
                if let undo = store.pendingUndo {
                    HStack {
                        AppMessage(undo.message).font(.subheadline)
                        Button("撤销") { store.undoLastAction() }.font(.subheadline.bold()).frame(minWidth: 44, minHeight: 44)
                    }.padding(.horizontal, 16).background(.regularMaterial, in: Capsule()).shadow(radius: 6, y: 2)
                }
                if showingCopyToast {
                AppMessage(toastMessage).font(.subheadline.weight(.medium))
                    .padding(.horizontal, 20).padding(.vertical, 12)
                    .background(.regularMaterial, in: Capsule()).shadow(radius: 6, y: 2)
                    .transition(.opacity).allowsHitTesting(false)
                }
            }.padding(.horizontal, 16).padding(.bottom, 76)
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("ParcelHub.copied"))) { _ in
            toastMessage = "已复制到剪贴板"
            AppFeedback.success()
            copyToastID = UUID()
            withAnimation(.easeInOut(duration: 0.2)) { showingCopyToast = true }
            UIAccessibility.post(notification: .announcement, argument: String(localized: "已复制到剪贴板", locale: locale))
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("ParcelHub.message"))) { message in
            toastMessage = message.object as? String ?? ""
            copyToastID = UUID()
            withAnimation(.easeInOut(duration: 0.2)) { showingCopyToast = true }
        }
        .task(id: copyToastID) {
            guard copyToastID != nil else { return }
            do { try await Task.sleep(for: .seconds(1.6)) } catch { return }
            withAnimation(.easeOut(duration: 0.3)) { showingCopyToast = false }
        }
    }
}

struct ProviderMark: View {
    let provider: PickupProvider
    var size: CGFloat = 44
    var body: some View {
        BrandMark(asset: "Brand-" + provider.id, fallback: provider.symbol, label: provider.name, size: size)
    }
}

struct BrandMark: View {
    let asset: String
    let fallback: String
    let label: String
    var size: CGFloat = 44
    var body: some View {
        Group {
            if UIImage(named: asset) != nil { Image(asset).resizable().scaledToFill() }
            else { Image(systemName: fallback).font(.title3).foregroundStyle(Palette.blue) }
        }.frame(width: size, height: size)
            .background(Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 13)).accessibilityLabel(label)
    }
}

struct UpdateStamp: View {
    let date: Date
    var label: LocalizedStringKey = "更新"
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "clock")
            Text(label)
            if !Calendar.current.isDateInToday(date) { Text(date, format: .dateTime.month().day()) }
            Text(date, format: .dateTime.hour().minute())
        }.font(.caption2).foregroundStyle(.secondary)
            .accessibilityElement(children: .combine)
            .accessibilityValue(Text(date, format: .dateTime.year().month().day().hour().minute()))
    }
}

private struct CredentialRequest: Identifiable {
    let id = UUID()
    var station: String?
}

struct PressFeedbackStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.7 : 1)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
            .animation(.easeOut(duration: 0.14), value: configuration.isPressed)
    }
}

@MainActor
private func launchCredential(_ provider: PickupProvider, store: ParcelStore, openURL: OpenURLAction,
                              fallback: @escaping (String?) -> Void) async {
    guard let binding = store.identityBindings[provider.id], binding.confirmed else { fallback(nil); return }
    guard let wechat = URL(string: "weixin://"), UIApplication.shared.canOpenURL(wechat) else { fallback(AppServiceIssue.wechatMissing.message); return }
    do {
        let url = try await IdentityLinkReader.resolve(binding.value, for: provider)
        openURL(url) { accepted in if !accepted { fallback(AppServiceIssue.openFailed.message) } }
    } catch { if !Task.isCancelled { fallback(AppServiceIssue.from(error).message) } }
}

struct PackagesView: View {
    @EnvironmentObject private var store: ParcelStore
    @State private var search = ""
    @EnvironmentObject private var clipboard: ClipboardImportController
    @State private var packageImportRequest: PackageImportRequest?
    @Environment(\.openURL) private var openURL
    @State private var launching = false
    @State private var smsStation: String?
    @State private var showingSMS = false
    @EnvironmentObject private var sync: OfficialSyncController
    @State private var credentialRequest: CredentialRequest?
    @State private var selectedProvider: PickupProvider?
    @State private var launchError: String?
    @State private var showingOfficialLogin = false
    @State private var providerAfterBinding: PickupProvider?
    @State private var editingStation: StationSelection?
    @State private var batchStation: StationSelection?
    @AppStorage("parcelhub.large-text.v1") private var largeText = false
    @ScaledMetric(relativeTo: .body) private var summaryHeight: CGFloat = 140
    @ScaledMetric(relativeTo: .body) private var importHeight: CGFloat = 96

    private var displayed: [Parcel] {
        let source = store.pending
        return source.filter { search.isEmpty || [$0.title, $0.note ?? "", $0.station, store.stationName($0.station), $0.pickupCode, $0.trackingNumber, $0.carrier, store.provider($0.providerID)?.name ?? ""].joined(separator: " ").localizedCaseInsensitiveContains(search) }
    }

    private var displayedWatching: [Parcel] {
        store.watching.filter { search.isEmpty || [$0.title, $0.trackingNumber, $0.carrier].joined(separator: " ").localizedCaseInsensitiveContains(search) }
    }

    private func openCredential(_ provider: PickupProvider) {
        if provider.id == "sms" { showingSMS = true; return }
        guard !launching else { return }
        launching = true
        Task { @MainActor in
            await launchCredential(provider, store: store, openURL: openURL) { message in launchError = message; selectedProvider = provider }
            launching = false
        }
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

                    VStack(alignment: .leading, spacing: 6) {
                        GeometryReader { geometry in
                            let availableWidth = max(0, geometry.size.width - 12)
                            HStack(alignment: .bottom, spacing: 12) {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text("\(store.pending.count)").font(.system(size: 44, weight: .semibold, design: .rounded))
                                    Text("件待取包裹").font(.system(size: 18, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.75)
                                    Text("\(Set(store.pending.map(\.station)).count) 个取件地点").font(.subheadline).opacity(0.85)
                                }.foregroundStyle(.white).padding(16)
                                    .frame(width: availableWidth * 0.6, height: summaryHeight, alignment: .leading)
                                    .background(Color(red: 0.10, green: 0.35, blue: 0.82).gradient, in: RoundedRectangle(cornerRadius: 23))
                                Button { packageImportRequest = PackageImportRequest(kind: "sms") } label: {
                                    VStack(spacing: 6) {
                                        Image(systemName: "text.bubble").font(.system(size: 26))
                                        Text("手动导入包裹").font(.system(size: 14, weight: .medium)).multilineTextAlignment(.center)
                                    }.foregroundStyle(Palette.blue).padding(10).frame(width: availableWidth * 0.4, height: importHeight)
                                        .background(Palette.card, in: RoundedRectangle(cornerRadius: 20))
                                }.buttonStyle(PressFeedbackStyle())
                            }
                        }.frame(height: summaryHeight)
                        if launching { ProgressView("正在打开小程序…").font(.caption) }
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 8) {
                                if sync.isRefreshing { ProgressView().controlSize(.small) }
                                else { Image(systemName: sync.needsLogin ? "person.crop.circle.badge.exclamationmark" : "arrow.triangle.2.circlepath") }
                                AppMessage(sync.needsLogin ? "同步已暂停，清单可能未更新" : sync.status).lineLimit(2)
                                Spacer(minLength: 8)
                                Button { sync.refresh(force: true) } label: {
                                    Image(systemName: "arrow.clockwise").frame(width: 44, height: 44)
                                }.disabled(sync.isRefreshing).accessibilityLabel("刷新待取清单")
                            }
                            LastSuccessfulSyncView(date: store.lastOfficialReadAt)
                            if sync.needsLogin { Button("重新登录淘宝") { showingOfficialLogin = true }.font(.caption.weight(.semibold)) }
                        }.font(.caption).foregroundStyle(.secondary)
                    }
                    Text("待取清单").font(.title2.bold())
                    if displayed.isEmpty {
                        ContentUnavailableView(LocalizedStringKey(search.isEmpty ? "暂无本地待取包裹" : "没有匹配的记录"), systemImage: "shippingbox", description: Text(LocalizedStringKey(search.isEmpty ? "登录淘宝后在前台自动检查；短信件可点“手动导入包裹”。" : "试试其他取件码、快递公司或地点。")))
                    }
                    ForEach(store.sortedStations(displayed.map(\.station)), id: \.self) { station in
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Menu {
                                    Button("地点管理", systemImage: "pencil") { editingStation = StationSelection(id: station) }
                                    Button("批量取件", systemImage: "checkmark.circle") { batchStation = StationSelection(id: station) }
                                } label: {
                                    HStack(spacing: 5) {
                                        if store.stationPreferences[station]?.pinned == true { Image(systemName: "pin.fill").font(.caption) }
                                        Text(store.stationName(station)).font(largeText ? .title2.bold() : .title3.bold())
                                        Image(systemName: "chevron.down").font(.caption2)
                                    }.frame(minHeight: 44).contentShape(Rectangle()).foregroundStyle(.primary)
                                }.accessibilityHint("地点管理与批量取件")
                                Spacer(minLength: 12)
                                Button {
                                    if let id = store.stationCredentials[station], let provider = store.provider(id) { smsStation = station; openCredential(provider) }
                                    else { credentialRequest = CredentialRequest(station: station) }
                                } label: {
                                    Text(LocalizedStringKey(store.stationCredentials[station].flatMap { store.provider($0)?.name }.map { $0.hasSuffix("身份码") ? $0 : "\($0)身份码" } ?? "选择身份码"))
                                        .font(.caption).padding(.horizontal, 10).padding(.vertical, 7)
                                        .background(Palette.blue.opacity(0.09), in: Capsule())
                                        .overlay(Capsule().stroke(Palette.blue.opacity(0.2), lineWidth: 0.7))
                                        .frame(minHeight: 44).contentShape(Rectangle())
                                }
                                .fixedSize(horizontal: true, vertical: false).disabled(launching)
                            }.foregroundStyle(Palette.blue)
                            ForEach(displayed.filter { $0.station == station }) { parcel in
                                ParcelCard(parcel: parcel)
                            }
                        }
                    }
                    if !displayedWatching.isEmpty {
                        Text("在路上 · \(displayedWatching.count)").font(.title3.bold())
                        Text("仅为已保存的单号记录，可补充取件短信。").font(.caption).foregroundStyle(.secondary)
                        ForEach(displayedWatching) { TrackingParcelCard(parcel: $0) }
                    }
                }.padding(20)
            }
            .refreshable { await sync.refreshAndWait() }
            .scrollDismissesKeyboard(.interactively)
            .background(Palette.paper).foregroundStyle(Palette.ink)
            .navigationTitle("涂涂取件").navigationBarTitleDisplayMode(.inline)
            .sheet(item: $packageImportRequest, onDismiss: receiveClipboardRequest) { request in
                AddParcelView(initialSMS: request.text)
            }
            .onAppear { receiveClipboardRequest() }
            .onChange(of: clipboard.request?.id) { _, _ in receiveClipboardRequest() }
            .fullScreenCover(isPresented: $showingSMS) { SMSCredentialListView(station: smsStation) }
            .sheet(item: $credentialRequest, onDismiss: {
                if let providerAfterBinding {
                    openCredential(providerAfterBinding)
                    self.providerAfterBinding = nil
                }
            }) { request in
                CredentialPickerView(station: request.station, onChoose: { provider in
                    smsStation = request.station
                    providerAfterBinding = provider
                    credentialRequest = nil
                })
            }
            .fullScreenCover(item: $selectedProvider) { PickupEntryView(provider: $0, initialError: launchError) }
            .fullScreenCover(isPresented: $showingOfficialLogin) { OfficialPickupView(initialPage: 0) }
            .sheet(item: $editingStation) { StationEditorView(station: $0.id) }
            .sheet(item: $batchStation) { BatchCollectionView(station: $0.id) }
        }
    }
    private func receiveClipboardRequest() {
        guard packageImportRequest == nil, let request = clipboard.request else { return }
        guard request.kind == "sms" else { clipboard.request = nil; return }
        packageImportRequest = request
        clipboard.request = nil
    }

}

struct ParcelCard: View {
    let parcel: Parcel
    @EnvironmentObject private var store: ParcelStore
    @EnvironmentObject private var clipboard: ClipboardImportController
    @State private var showingSMS = false
    @State private var showingNote = false
    @AppStorage("parcelhub.large-text.v1") private var largeText = false
    @AppStorage("parcelhub.density.v1") private var density = "compact"
    @ScaledMetric(relativeTo: .title2) private var codeSize: CGFloat = 28
    private func copy(_ value: String) {
        UIPasteboard.general.string = value
        clipboard.ignoreCurrentChange()
        NotificationCenter.default.post(name: Notification.Name("ParcelHub.copied"), object: nil)
    }
    private var trackingLabel: some View {
        HStack(spacing: 2) {
            Text(parcel.trackingNumber).font(.system(.caption2, design: .monospaced))
                .lineLimit(1).minimumScaleFactor(0.65).textSelection(.enabled)
            Button { copy(parcel.trackingNumber) } label: {
                Image(systemName: "doc.on.doc").font(.caption2)
                    .frame(width: 44, height: 44).contentShape(Rectangle())
            }.accessibilityLabel("复制运单号")
        }
    }
    private var metadata: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 3) {
                Text(parcel.carrier.isEmpty ? "快递" : parcel.carrier)
                if !parcel.trackingNumber.isEmpty { Text(verbatim: "·"); trackingLabel }
            }.fixedSize(horizontal: true, vertical: false)
            VStack(alignment: .leading, spacing: 0) {
                Text(parcel.carrier.isEmpty ? "快递" : parcel.carrier).lineLimit(1)
                if !parcel.trackingNumber.isEmpty { trackingLabel }
            }
        }.font(.caption).foregroundStyle(.secondary)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                if let asset = CarrierBrand.asset(for: parcel.carrier) {
                    BrandMark(asset: asset, fallback: "shippingbox", label: parcel.carrier, size: 40)
                } else if let provider = store.provider(parcel.providerID) { ProviderMark(provider: provider, size: 40) }
                VStack(alignment: .leading, spacing: 3) {
                    Text(parcel.title).font(largeText ? .headline : .subheadline.weight(.semibold)).lineLimit(2)
                        .onTapGesture { showingNote = true }.accessibilityAddTraits(.isButton).accessibilityHint("编辑备注")
                    metadata
                }.frame(maxWidth: .infinity, alignment: .leading)
                Button { store.toggleCollected(parcel) } label: {
                    Text(LocalizedStringKey(parcel.isCollected ? "恢复待取" : "我已取件"))
                        .font(.caption.weight(.medium)).padding(.horizontal, 12).frame(minHeight: 40)
                        .background(Palette.blue.opacity(0.10), in: Capsule())
                }.accessibilityLabel(parcel.isCollected ? "恢复待取" : "我已取件")
            }
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(parcel.pickupCode).font(.system(size: largeText ? codeSize * 1.22 : codeSize, weight: .semibold, design: .monospaced)).textSelection(.enabled)
                        .minimumScaleFactor(0.75).lineLimit(largeText ? 2 : 1)
                    if !parcel.isCollected && ParcelArrival.daysAgo(on: parcel.arrivedOn) != nil { ArrivalStamp(day: parcel.arrivedOn) }
                }.frame(maxWidth: .infinity, alignment: .leading).layoutPriority(1)
                VStack(alignment: .trailing, spacing: 3) {
                    if !parcel.isCollected {
                        Button("复制") { copy(parcel.pickupCode) }
                            .font(.caption).frame(minWidth: 44, minHeight: 44).contentShape(Rectangle())
                    } else if parcel.hasSMS {
                        Button { showingSMS = true } label: {
                            Image(systemName: "message").font(.caption).frame(width: 28, height: 24)
                        }.accessibilityLabel("短信身份码")
                    }
                }.fixedSize().padding(.top, 4)
            }
            if let note = parcel.note, !note.isEmpty {
                Button { showingNote = true } label: {
                    Label(note, systemImage: "note.text").font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }.accessibilityLabel("编辑备注")
            }
            let alternatives = parcel.pickupCredentials.filter { $0.isCurrent && !$0.pickupCode.isEmpty && $0.pickupCode != parcel.pickupCode }
            ForEach(Array(alternatives.enumerated()), id: \.offset) { _, credential in
                Text("\(store.provider(credential.providerID)?.name ?? "其他来源")取件码 · \(credential.pickupCode)")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }.padding(density == "comfortable" ? 20 : 12).background(Palette.card, in: RoundedRectangle(cornerRadius: 18))
            .contentShape(Rectangle()).buttonStyle(PressFeedbackStyle())
            .contextMenu { Button("编辑备注", systemImage: "note.text") { showingNote = true } }
            .accessibilityAction(named: Text("编辑备注")) { showingNote = true }
            .sheet(isPresented: $showingNote) { ParcelNoteView(parcel: parcel) }
            .fullScreenCover(isPresented: $showingSMS) { NavigationStack { SMSCredentialView(parcelID: parcel.id) } }
    }
}

private struct ArrivalStamp: View {
    let day: String?
    @Environment(\.scenePhase) private var scenePhase
    @State private var now = Date()
    var body: some View {
        Group {
            if let days = ParcelArrival.daysAgo(on: day, now: now) {
                if days == 0 { Text("今日到站") }
                else if days == 1 { Text("昨天到站") }
                else if days == 2 { Text("前天到站") }
                else { Text("已到站\(days)天") }
            }
        }.font(.caption2).foregroundStyle(.secondary).fixedSize()
            .onAppear { now = Date() }
            .onChange(of: scenePhase) { _, phase in if phase == .active { now = Date() } }
            .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in now = Date() }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)) { _ in now = Date() }
            .onReceive(NotificationCenter.default.publisher(for: .NSSystemTimeZoneDidChange)) { _ in now = Date() }
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
    @Environment(\.openURL) private var openURL
    @State private var selected: PickupProvider?
    @State private var launchError: String?
    @State private var launching = false
    @State private var sorting = false
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Group {
                        if let station { Text("为「\(station)」选择身份码") }
                        else { Label("按驿站要求选码，短信件用短信码", systemImage: "info.circle") }
                    }.font(.caption).foregroundStyle(.secondary)
                        .listRowBackground(Color.clear).listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 0, leading: 4, bottom: 0, trailing: 4))
                }
                Section {
                    ForEach(store.credentialProviders) { provider in
                        Button {
                            guard !sorting else { return }
                            if let station { store.rememberCredential(provider.id, for: station) }
                            store.preferCredential(provider.id)
                            if let onChoose { onChoose(provider) }
                            else {
                                guard !launching else { return }
                                launching = true
                                Task { @MainActor in
                                    await launchCredential(provider, store: store, openURL: openURL) { message in launchError = message; selected = provider }
                                    launching = false
                                }
                            }
                        } label: {
                            HStack(spacing: 14) {
                                ProviderMark(provider: provider, size: 62)
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(LocalizedStringKey(provider.id == "sms" ? provider.name : provider.id == "fcbox" ? "丰巢取件" : "\(provider.name)身份码")).font(.headline).foregroundStyle(.primary)
                                    Text(LocalizedStringKey(provider.id == "sms" ? "查看取件短信" : provider.identityURL != nil ? "官方身份码" : store.identityBindings[provider.id]?.confirmed == true ? "已绑定 · 点击打开" : provider.miniProgramURL != nil ? "首次打开需绑定" : "入口待绑定"))
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                if let station, store.stationCredentials[station] == provider.id { Image(systemName: "checkmark.circle.fill") }
                                else { Image(systemName: "chevron.right").font(.caption) }
                            }.padding(.vertical, 8).frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                        }.buttonStyle(PressFeedbackStyle()).disabled(launching)
                            .contextMenu {
                                if !["taobao", "sms"].contains(provider.id) { Button("管理小程序绑定") { launchError = nil; selected = provider } }
                            }
                    }.onMove(perform: store.moveProviders).moveDisabled(!sorting)
                }
                if launching {
                    Section { ProgressView("正在打开小程序…").font(.caption) }
                }
                if station == nil {
                    HStack {
                        Spacer()
                        Button {
                            withAnimation { sorting.toggle() }
                        } label: {
                            Label(LocalizedStringKey(sorting ? "完成" : "排序"), systemImage: sorting ? "checkmark" : "arrow.up.arrow.down")
                                .font(.caption).foregroundStyle(.secondary).padding(12)
                        }.buttonStyle(PressFeedbackStyle()).disabled(launching)
                    }.listRowBackground(Color.clear).listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                }
            }.listStyle(.insetGrouped).listSectionSpacing(16)
                .environment(\.editMode, .constant(sorting ? .active : .inactive))
                .navigationTitle("身份码").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    if showsDone { ToolbarItem(placement: .cancellationAction) { Button("关闭") { dismiss() } } }
                }
                .fullScreenCover(item: $selected) { PickupEntryView(provider: $0, initialError: launchError) }
                .onDisappear { sorting = false }
        }
    }
}

struct PickupEntryView: View {
    let provider: PickupProvider
    var initialError: String? = nil
    @EnvironmentObject private var store: ParcelStore
    @EnvironmentObject private var clipboard: ClipboardImportController
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var link = ""
    @State private var prefilledLink = ""
    @State private var note: String?
    @State private var testedValue: String?
    @State private var trying = false
    @State private var error: String?
    @State private var openTask: Task<Void, Never>?

    private var parsed: IdentityLinkResult? { IdentityLinkReader.parse(link, for: provider) }

    var body: some View {
        if provider.id == "taobao" {
            OfficialPickupView(initialPage: 1)
        } else if provider.id == "sms" {
            SMSCredentialListView()
        } else {
            NavigationStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        if let error { Label(LocalizedStringKey(error), systemImage: "exclamationmark.circle.fill").font(.subheadline).foregroundStyle(.orange) }

                        HStack(spacing: 14) {
                            ProviderMark(provider: provider)
                            VStack(alignment: .leading, spacing: 5) {
                                Text(provider.name).font(.title2.bold())
                                Text(store.identityBindings[provider.id]?.confirmed == true ? "已绑定小程序入口" : "首次绑定小程序")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        Text("粘贴小程序链接，试开后保存绑定。")
                            .font(.subheadline).foregroundStyle(.secondary)
                        if store.identityBindings[provider.id]?.confirmed != true || error != nil { BindingGuideView() }
                        if provider.miniProgramURL != nil {
                            Label("已找到官方入口，请先试开", systemImage: "link.circle.fill").font(.subheadline).foregroundStyle(Palette.blue)
                        }
                        VStack(alignment: .leading, spacing: 12) {
                            Text("小程序口令或官方跳转链接").font(.caption).foregroundStyle(.secondary)
                            TextField("粘贴链接或 #小程序://…", text: $link, axis: .vertical)
                                .lineLimit(2...5).textInputAutocapitalization(.never).autocorrectionDisabled()
                            PasteButton(payloadType: String.self) { values in link = values.first ?? "" }
                            if let message = parsed?.message { Text(message).font(.caption).foregroundStyle(.secondary) }
                        }.padding(18).background(Palette.card, in: RoundedRectangle(cornerRadius: 18))
                        if parsed?.kind == "launchURL" {
                            Button {
                                trying = true; error = nil; testedValue = nil
                                let candidate = link.trimmingCharacters(in: .whitespacesAndNewlines)
                                openTask = Task { @MainActor in
                                    guard let wechat = URL(string: "weixin://"), UIApplication.shared.canOpenURL(wechat) else {
                                        trying = false; error = AppServiceIssue.wechatMissing.message; return
                                    }
                                    let url: URL
                                    do { url = try await IdentityLinkReader.resolve(candidate, for: provider) }
                                    catch { trying = false; if !Task.isCancelled { self.error = AppServiceIssue.from(error).message }; return }
                                    guard !Task.isCancelled, candidate == link.trimmingCharacters(in: .whitespacesAndNewlines) else { trying = false; return }
                                    openURL(url) { accepted in
                                        trying = false
                                        if accepted { testedValue = candidate; note = "返回后确认：刚才是否进入了\(provider.miniProgramName)？" }
                                        else { error = AppServiceIssue.openFailed.message }
                                    }
                                }
                            } label: {
                                HStack { if trying { ProgressView().tint(.white) }; Text(trying ? "正在打开…" : "试开\(provider.name)") }.frame(maxWidth: .infinity)
                            }.buttonStyle(.borderedProminent).controlSize(.large).disabled(trying)
                            if testedValue == link.trimmingCharacters(in: .whitespacesAndNewlines) {
                                Text(note ?? "请确认进入了正确小程序。").font(.caption).foregroundStyle(.secondary)
                                Button("确认已打开，保存绑定") {
                                    guard let testedValue else { return }
                                    store.saveIdentityBinding(IdentityBinding(kind: "launchURL", value: testedValue, confirmed: true), for: provider.id)
                                    if store.storageWarning == nil { dismiss() }
                                }.buttonStyle(.borderedProminent).controlSize(.large)
                            }
                        } else if parsed?.kind == "shareCode" {
                            Button("保存口令（仍需在微信内打开）") {
                                guard let value = parsed?.value else { return }
                                store.saveIdentityBinding(IdentityBinding(kind: "shareCode", value: value, confirmed: false), for: provider.id)
                                note = "口令已保存，需在微信内打开"
                            }.buttonStyle(.bordered)
                            Button("复制口令并打开微信") {
                                UIPasteboard.general.string = parsed?.value
                                if let url = URL(string: "weixin://") { openURL(url) { accepted in
                                    note = accepted ? "在微信粘贴并发送口令，再点击打开" : "请打开微信并粘贴口令"
                                } }
                            }.buttonStyle(.bordered)
                        } else if !link.isEmpty { Text(parsed?.error ?? "无法识别链接").font(.caption).foregroundStyle(.orange) }
                        if let error, !error.isEmpty, parsed?.kind == "launchURL", let url = URL(string: link), url.scheme == "https" {
                            Link("在 Safari 打开官方入口重试", destination: url).font(.subheadline)
                        }
                        if let note, testedValue == nil { AppMessage(note).font(.caption).foregroundStyle(.secondary) }
                        if store.identityBindings[provider.id] != nil {
                            Button("解除此平台的入口绑定", role: .destructive) {
                                store.saveIdentityBinding(nil, for: provider.id); testedValue = nil; note = "已解除入口绑定"
                            }.font(.subheadline)
                        }
                        Text("只粘贴链接，勿填身份码或验证码。")
                            .font(.caption).foregroundStyle(.secondary)
                        if provider.id == "fcbox" { Text("此处绑定丰巢小程序入口。").font(.caption).foregroundStyle(.secondary) }
                        if provider.id == "fcbox",
                           let link = provider.appStoreURL, let url = URL(string: link) {
                            Link("官方 App（App Store）", destination: url).font(.subheadline)
                        }
                    }.padding(24)
                }.background(Palette.paper)
                    .navigationTitle("小程序绑定").navigationBarTitleDisplayMode(.inline)
                    .toolbar { ToolbarItem(placement: .cancellationAction) { Button("返回") { dismiss() } } }
                    .onAppear {
                        clipboard.isEditing = true
                        prefilledLink = store.identityBindings[provider.id]?.value ?? provider.miniProgramURL ?? ""
                        link = prefilledLink; error = initialError
                    }
                    .onChange(of: link) { _, value in testedValue = nil; note = nil; if value != prefilledLink { error = nil } }
                    .onDisappear { clipboard.isEditing = false; openTask?.cancel() }
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
    @State private var search = ""
    @State private var openDeletionID: UUID?
    private var records: [Parcel] {
        store.collected.filter { search.isEmpty || [$0.title, $0.note ?? "", $0.station, store.stationName($0.station), $0.pickupCode, $0.carrier, $0.trackingNumber].joined(separator: " ").localizedCaseInsensitiveContains(search) }
            .sorted { ($0.collectedAt ?? .distantPast) > ($1.collectedAt ?? .distantPast) }
    }
    private var days: [Date] {
        Array(Set(records.compactMap(\.collectedAt).map { Calendar.current.startOfDay(for: $0) })).sorted(by: >)
    }
    var body: some View {
        List {
            if records.isEmpty { ContentUnavailableView(LocalizedStringKey(search.isEmpty ? "暂无已取记录" : "没有匹配的记录"), systemImage: "checkmark.circle") }
            ForEach(days, id: \.self) { day in
                let daily = records.filter { Calendar.current.isDate($0.collectedAt ?? .distantPast, inSameDayAs: day) }
                Section {
                    ForEach(Array(Set(daily.map(\.station))).sorted(), id: \.self) { station in
                        Text(store.stationName(station)).font(.headline).foregroundStyle(Palette.blue)
                            .listRowInsets(EdgeInsets(top: 20, leading: 12, bottom: 10, trailing: 12))
                            .listRowBackground(Color.clear).listRowSeparator(.hidden)
                        ForEach(daily.filter { $0.station == station }) { parcel in
                            CollectedParcelRow(parcel: parcel, openDeletionID: $openDeletionID)
                                .listRowInsets(EdgeInsets(top: 5, leading: 0, bottom: 5, trailing: 0))
                                .listRowBackground(Color.clear).listRowSeparator(.hidden)
                        }
                    }
                } header: {
                    Text(day, format: .dateTime.year().month().day())
                        .font(.title3.weight(.bold)).foregroundStyle(Palette.blue).textCase(nil)
                        .padding(.top, 10).padding(.bottom, 4)
                }
            }
        }.buttonStyle(.automatic).safeAreaInset(edge: .top, spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("搜索包裹、取件码或地点", text: $search).textInputAutocapitalization(.never).autocorrectionDisabled()
                if !search.isEmpty { Button { search = "" } label: { Image(systemName: "xmark.circle.fill") }.accessibilityLabel("清除搜索") }
            }.padding(14).background(Palette.card, in: RoundedRectangle(cornerRadius: 16)).padding(.horizontal, 20).padding(.vertical, 10).background(Palette.paper)
        }.background(Palette.paper).navigationTitle("已取记录").navigationBarTitleDisplayMode(.inline)
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: search) { _, _ in openDeletionID = nil }
    }
}

private struct CollectedParcelRow: View {
    let parcel: Parcel
    @Binding var openDeletionID: UUID?
    @EnvironmentObject private var store: ParcelStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @GestureState private var dragOffset: CGFloat = 0
    private var isOpen: Bool { openDeletionID == parcel.id }
    private var offset: CGFloat { min(0, max(-60, (isOpen ? -60 : 0) + dragOffset)) }

    var body: some View {
        ZStack(alignment: .trailing) {
            if offset < 0 {
                Button(role: .destructive) { remove() } label: {
                    Image(systemName: "trash.fill").font(.system(size: 17))
                        .foregroundStyle(.white).frame(width: 44, height: 44)
                        .background(Color.red, in: RoundedRectangle(cornerRadius: 13))
                }.buttonStyle(PressFeedbackStyle()).padding(.trailing, 6)
                    .accessibilityLabel("删除已取记录").accessibilityHidden(!isOpen)
            }
            ParcelCard(parcel: parcel)
                .overlay {
                    if isOpen {
                        Color.clear.contentShape(Rectangle()).onTapGesture { openDeletionID = nil }
                    }
                }
                .offset(x: offset)
        }.contentShape(Rectangle()).clipped()
            // 只响应横向拖动，让纵向滚动及卡片中的按钮继续正常工作。
            .simultaneousGesture(DragGesture(minimumDistance: 12)
                .updating($dragOffset) { value, state, _ in
                    if abs(value.translation.width) > abs(value.translation.height) * 1.25 {
                        state = value.translation.width
                    }
                }
                .onEnded { value in
                    guard abs(value.translation.width) > abs(value.translation.height) * 1.25 else { return }
                    let finalOffset = (isOpen ? -60.0 : 0.0) + value.translation.width
                    openDeletionID = finalOffset < -28 ? parcel.id : nil
                })
            .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: isOpen)
            .accessibilityAction(named: Text("删除已取记录")) { remove() }
    }
    private func remove() {
        openDeletionID = nil
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.18)) { store.deleteCollected(parcel.id) }
    }
}

struct SettingsRowLabel: View {
    let title: LocalizedStringKey
    let symbol: String
    let color: Color
    init(_ title: LocalizedStringKey, symbol: String, color: Color = .blue) {
        self.title = title; self.symbol = symbol; self.color = color
    }
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol).font(.system(size: 16, weight: .medium)).foregroundStyle(.white)
                .frame(width: 28, height: 28).background(color, in: RoundedRectangle(cornerRadius: 7))
            Text(title).foregroundStyle(.primary)
        }
    }
}

struct SettingsView: View {
    @EnvironmentObject private var store: ParcelStore
    @EnvironmentObject private var clipboard: ClipboardImportController
    @AppStorage("parcelhub.appearance.v1") private var appearance = "system"
    @AppStorage("parcelhub.language.v1") private var language = "zh-Hans"
    @State private var officialLogin = false
    @AppStorage("parcelhub.haptics.v1") private var haptics = true
    @AppStorage("parcelhub.privacy-shield.v1") private var privacyShield = true
    var body: some View {
        List {
            Section("通用") {
                NavigationLink { AppearanceSettingsView() } label: {
                    HStack {
                        SettingsRowLabel("界面与显示", symbol: "circle.lefthalf.filled", color: .gray)
                        Spacer()
                        Text(LocalizedStringKey(appearance == "light" ? "浅色" : appearance == "dark" ? "深色" : "跟随系统"))
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                }
                NavigationLink { LanguageSettingsView() } label: {
                    HStack { SettingsRowLabel("语言", symbol: "globe"); Spacer(); Text(verbatim: language == "en" ? "English" : "简体中文").font(.subheadline).foregroundStyle(.secondary) }
                }
                NavigationLink { StationManagementView() } label: { SettingsRowLabel("地点管理", symbol: "mappin.and.ellipse", color: .orange) }
                Toggle(isOn: $haptics) { SettingsRowLabel("轻触反馈", symbol: "hand.tap", color: .purple) }.tint(.green)
            }
            Section {
                Toggle(isOn: $store.autoSyncEnabled) { SettingsRowLabel("前台自动刷新", symbol: "arrow.triangle.2.circlepath", color: .green) }
                    .tint(.green)
                Toggle(isOn: $clipboard.enabled) { SettingsRowLabel("剪贴板智能识别", symbol: "doc.on.clipboard", color: .orange) }
                    .tint(.green)
                Button { officialLogin = true } label: { SettingsRowLabel("淘宝登录与官方清单", symbol: "person.crop.circle", color: .orange) }
            } header: { Text("自动检查") } footer: { Text("自动刷新仅支持淘宝，剪贴板导入需确认。") }
            Section("身份码") {
                NavigationLink { StationCredentialSettingsView() } label: { SettingsRowLabel("地点身份码绑定", symbol: "barcode.viewfinder", color: .purple) }
                NavigationLink { MiniProgramSettingsView() } label: { SettingsRowLabel("小程序入口绑定", symbol: "link") }
                NavigationLink { ArrivalMonitoringView() } label: { SettingsRowLabel("到站监控与接入状态", symbol: "shippingbox", color: .green) }
            }
            Section {
                Toggle(isOn: $privacyShield) { SettingsRowLabel("后台隐私遮罩", symbol: "eye.slash", color: .purple) }.tint(.green)
                NavigationLink { LocalDataSettingsView() } label: { SettingsRowLabel("短信与本地记录", symbol: "message.fill", color: .green) }
            } header: { Text("数据与隐私") } footer: { Text("后台遮罩隐藏多任务预览中的包裹和短信。记录仅保存在本机。") }
            Section("关于涂涂取件") { Text("版本 0.7.13 · 本地开发版").foregroundStyle(.secondary) }
        }.listStyle(.insetGrouped).navigationTitle("设置").navigationBarTitleDisplayMode(.inline)
            .fullScreenCover(isPresented: $officialLogin) { OfficialPickupView(initialPage: 0) }
    }
}

struct LocalDataSettingsView: View {
    var body: some View {
        List {
            Section {
                Text("短信原文仅保存在本机，删除已取记录时会清除。")
                Text("不会自动读取短信收件箱，导入前可核对内容。")
            }
        }.listStyle(.insetGrouped).navigationTitle("短信与本地记录").navigationBarTitleDisplayMode(.inline)
    }
}

private struct BindingGuideImage: Identifiable { let id: String }
struct BindingGuideView: View {
    @State private var selectedImage: BindingGuideImage?
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("如何获取小程序链接").font(.headline)
            Text("以兔喜为例，其他平台菜单可能不同。").font(.caption).foregroundStyle(.secondary)
            HStack(alignment: .top, spacing: 12) {
                step("BindingGuideMenu", number: "1", title: "打开小程序右上角“…” → 添加到桌面")
                step("BindingGuideSafari", number: "2", title: "在 Safari 复制地址栏完整链接")
            }
            Text("复制网址后返回粘贴，无需添加到主屏幕。").font(.caption).foregroundStyle(.secondary)
        }.padding(14).background(Palette.card, in: RoundedRectangle(cornerRadius: 18))
            .sheet(item: $selectedImage) { selected in
                NavigationStack {
                    ScrollView { Image(selected.id).resizable().scaledToFit().frame(maxWidth: .infinity) }
                        .background(Color.black).navigationTitle("截图指引").navigationBarTitleDisplayMode(.inline)
                        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("关闭") { selectedImage = nil } } }
                }
            }
    }
    private func step(_ asset: String, number: String, title: LocalizedStringKey) -> some View {
        Button { selectedImage = BindingGuideImage(id: asset) } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top, spacing: 5) {
                    Text(verbatim: number).font(.caption2).foregroundStyle(.white).frame(width: 18, height: 18).background(Palette.blue, in: Circle())
                    Text(title).font(.caption2).foregroundStyle(.primary)
                }.frame(minHeight: 54, alignment: .topLeading)
                Image(asset).resizable().scaledToFit().frame(maxWidth: .infinity).clipShape(RoundedRectangle(cornerRadius: 9))
                Text("点击截图可放大").font(.caption2).foregroundStyle(Palette.blue)
            }.frame(maxWidth: .infinity, alignment: .topLeading)
        }.buttonStyle(PressFeedbackStyle())
    }
}

struct AppearanceSettingsView: View {
    @AppStorage("parcelhub.appearance.v1") private var appearance = "system"
    @AppStorage("parcelhub.large-text.v1") private var largeText = false
    @AppStorage("parcelhub.density.v1") private var density = "compact"
    var body: some View {
        Form {
            Section("外观") {
                Picker("外观", selection: $appearance) {
                    Text("跟随系统").tag("system")
                    Text("浅色").tag("light")
                    Text("深色").tag("dark")
                }.pickerStyle(.inline).labelsHidden()
            }
            Section("包裹显示") {
                Picker("字号", selection: $largeText) { Text("标准").tag(false); Text("大字").tag(true) }.pickerStyle(.segmented)
                Picker("显示密度", selection: $density) { Text("紧凑").tag("compact"); Text("舒适").tag("comfortable") }.pickerStyle(.segmented)
            }
            Section { Text("外观影响应用和短信页，官方网页保持原样。")
                    .font(.caption).foregroundStyle(.secondary) }
        }.navigationTitle("界面与显示").navigationBarTitleDisplayMode(.inline)
    }
}

struct LanguageSettingsView: View {
    @AppStorage("parcelhub.language.v1") private var language = "zh-Hans"
    var body: some View {
        Form {
            Section("应用语言") {
                Picker("语言", selection: $language) {
                    Text(verbatim: "简体中文").tag("zh-Hans")
                    Text(verbatim: "English").tag("en")
                }.pickerStyle(.inline).labelsHidden()
            }
            Section { Text("仅切换界面语言，不修改包裹和短信。")
                    .font(.caption).foregroundStyle(.secondary) }
        }.navigationTitle("语言").navigationBarTitleDisplayMode(.inline)
    }
}

struct StationCredentialSettingsView: View {
    @EnvironmentObject private var store: ParcelStore
    private var stations: [String] {
        Array(Set(store.parcels.filter { !$0.isDemo && !$0.station.isEmpty }.map(\.station)).union(store.stationCredentials.keys)).sorted()
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
    @Published var failure: AppServiceIssue?
    @Published private(set) var authenticationDestination: URL?
    private var pendingPage = false
    private var generation = 0
    private var readAttempt = 0
    private var emptyConfirmation = OfficialEmptyConfirmation()

    override init() {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        if let url = Bundle.main.url(forResource: "taobao-refresh", withExtension: "js"),
           let source = try? String(contentsOf: url, encoding: .utf8) {
            configuration.userContentController.addUserScript(WKUserScript(source: source, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        }
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

    func fail(_ issue: AppServiceIssue) {
        emptyConfirmation.reset()
        failure = issue; status = issue.message; isLoading = false; hasError = true
    }

    func stop() {
        generation += 1
        emptyConfirmation.reset()
        authenticationDestination = nil
        webView.stopLoading()
        readResult = nil
        isLoading = false
    }

    func load(_ url: URL) {
        generation += 1
        emptyConfirmation.reset()
        authenticationDestination = nil
        pendingPage = url == Self.parcels
        readAttempt = 0
        readResult = nil
        failure = nil
        status = "正在加载官方页面…"
        isLoading = true
        hasError = false
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30)
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        request.setValue("no-cache", forHTTPHeaderField: "Pragma")
        webView.load(request)
    }

    func reauthenticate(returningTo destination: URL) {
        guard let url = OfficialAuthenticationFlow.logoutURL(returningTo: destination) else { fail(.unavailable); return }
        stop()
        load(url)
        authenticationDestination = destination
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        generation += 1
        emptyConfirmation.reset()
        readAttempt = 0
        readResult = nil
        failure = nil
        status = "正在加载官方页面…"
        isLoading = true
        hasError = false
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        isLoading = false
        if let destination = authenticationDestination {
            guard webView.url?.host == destination.host, webView.url?.path == destination.path else {
                status = "请在此页登录，完成后自动返回"
                return
            }
            authenticationDestination = nil
            pendingPage = destination == Self.parcels
        }
        status = "官方页面已加载"
        if pendingPage { readPending(); return }
        let currentGeneration = generation
        let script = "(() => { const t = document.body ? document.body.innerText : ''; if (/login/.test(location.hostname) || /登录已失效|登录过期|请重新登录|账号密码登录|请先登录/.test(t)) return 'login'; return /接口超时|网络异常|网络错误|请求超时/.test(t) ? 'error' : 'ready'; })()"
        webView.evaluateJavaScript(script) { [weak self] result, _ in
            guard let self, self.generation == currentGeneration else { return }
            if result as? String == "login" { self.fail(.login) }
            else if result as? String == "error" { self.fail(.unavailable) }
        }
    }

    func readPending() {
        guard pendingPage, !isLoading else { return }
        guard let currentURL = webView.url,
              currentURL.host == Self.parcels.host,
              currentURL.path == Self.parcels.path else {
            let current = webView.url?.absoluteString.lowercased() ?? ""
            fail(current.contains("login") ? .login : .unavailable)
            return
        }
        guard let url = Bundle.main.url(forResource: "cainiao-reader", withExtension: "js"),
              let reader = try? String(contentsOf: url, encoding: .utf8) else {
            status = "读取组件缺失，无法同步"; hasError = true; return
        }
        let requestGeneration = generation
        readAttempt += 1
        let attempt = readAttempt
        status = "正在读取…"
        let script = """
        (() => {
          const freshness = window.__tutuTaobaoFreshness;
          const text = freshness ? freshness.pageText() : (document.body ? document.body.innerText : '');
          const snapshot = (\(reader))(text);
          if (freshness) return JSON.stringify(freshness.verify(snapshot));
          if (snapshot.state === 'login_required' || snapshot.state === 'error') return JSON.stringify(snapshot);
          return JSON.stringify({state: 'loading', message: '正在确认最新清单…',
            parcels: [], expectedCount: null, readAt: snapshot.readAt});
        })()
        """
        webView.evaluateJavaScript(script) { [weak self] value, error in
            guard let self, self.generation == requestGeneration else { return }
            guard error == nil, let json = value as? String, let data = json.data(using: .utf8),
                  let snapshot = try? JSONDecoder().decode(OfficialPageRead.self, from: data) else {
                self.emptyConfirmation.reset()
                self.hasError = true; self.status = "读取失败，记录已保留"; return
            }
            let result = self.emptyConfirmation.accepting(snapshot)
            if result.state == "filtered_empty" {
                guard attempt < 40 else { self.fail(.incomplete); return }
                self.status = "正在确认空清单…"
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.75) { [weak self] in
                    guard let self, self.generation == requestGeneration else { return }
                    self.readPending()
                }
                return
            }
            // 页面应用异步加载，首次得到的占位零件不得清空已有记录。
            if result.state == "loading" {
                if attempt < 40 {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.75) { [weak self] in
                        guard let self, self.generation == requestGeneration else { return }
                        self.readPending()
                    }
                } else {
                    // 本轮重试已结束，不能继续显示仍在加载；失败不覆盖本地快照。
                    self.fail(.incomplete)
                }
                return
            }
            self.failure = result.state == "login_required" ? .login : result.state == "filtered_empty" ? .phoneFilter : nil
            self.status = result.state == "ready" ? "正在同步清单…" : result.state == "login_required" ? AppServiceIssue.login.message : result.message
            self.hasError = result.state != "ready"
            self.readResult = result
        }
    }

    func copyDiagnostics() {
        guard webView.url?.host == Self.parcels.host, webView.url?.path == Self.parcels.path,
              let url = Bundle.main.url(forResource: "cainiao-reader", withExtension: "js"),
              let reader = try? String(contentsOf: url, encoding: .utf8) else {
            status = "请先打开淘宝待取记录"
            return
        }
        let requestGeneration = generation
        let script = """
        (() => {
          const freshness = window.__tutuTaobaoFreshness;
          const text = freshness ? freshness.pageText() : (document.body ? document.body.innerText : '');
          const snapshot = (\(reader))(text);
          return JSON.stringify({query: freshness?.read() ?? {state: 'missing'},
            page: snapshot.diagnostics, parsedState: snapshot.state,
            verifiedState: freshness?.verify(snapshot).state ?? 'missing', message: snapshot.message});
        })()
        """
        webView.evaluateJavaScript(script) { [weak self] value, error in
            guard let self, self.generation == requestGeneration else { return }
            guard error == nil, let report = value as? String else {
                self.status = "诊断读取失败，请重试"
                return
            }
            let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
            let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
            // 只复制请求状态、标签和数量，不包含手机号、运单、取件码或 Cookie。
            UIPasteboard.general.string = "涂涂取件 \(version)/\(build)\n\(report)"
            self.status = "诊断已复制"
        }
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        guard (error as NSError).code != NSURLErrorCancelled else { return }
        generation += 1
        isLoading = false
        fail(AppServiceIssue.from(error))
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        self.webView(webView, didFailProvisionalNavigation: navigation, withError: error)
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        stop()
        fail(.unavailable)
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url else { decisionHandler(.cancel); return }
        if url.absoluteString == "about:blank" { decisionHandler(.allow); return }
        let host = url.host?.lowercased() ?? ""
        let official = ["taobao.com", "tmall.com", "alipay.com", "alipay.cn", "cainiao.com"]
            .contains { host == $0 || host.hasSuffix("." + $0) }
        if url.scheme == "https" && official { decisionHandler(.allow) }
        else {
            status = "请从右上角菜单打开官方页面"
            hasError = true
            decisionHandler(.cancel)
        }
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse, decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
        if let response = navigationResponse.response as? HTTPURLResponse, response.statusCode >= 400 {
            fail(response.statusCode == 401 ? .login : .unavailable); decisionHandler(.cancel)
        } else { decisionHandler(.allow) }
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
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var store: ParcelStore
    @EnvironmentObject private var sync: OfficialSyncController
    @StateObject private var session = OfficialPickupSession()
    @State private var page: Int
    @State private var confirmingAuthentication = false
    @State private var refreshAfterBackground = false
    init(initialPage: Int = 1) { _page = State(initialValue: initialPage) }
    private var pageURL: URL { page == 1 ? OfficialPickupSession.identity : OfficialPickupSession.parcels }
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("官方页面", selection: $page) {
                    Text("待取记录").tag(0)
                    Text("身份码").tag(1)
                }.pickerStyle(.segmented).padding(12).disabled(session.authenticationDestination != nil)
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
                        }.buttonStyle(.borderedProminent).disabled(session.isLoading || session.authenticationDestination != nil)
                    }
                    if session.hasError {
                        Button("重试") { session.load(pageURL) }
                            .font(.subheadline.weight(.semibold))
                        if let failure = session.failure, [.login, .phoneFilter, .incomplete].contains(failure) {
                            Button("重新登录淘宝") { confirmingAuthentication = true }
                                .font(.subheadline.weight(.semibold))
                        }
                    }
                    if page == 0 || session.hasError || session.authenticationDestination != nil {
                        AppMessage(session.status).font(.caption)
                            .foregroundStyle(session.hasError ? Color.orange : Color.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }.padding(page == 0 || session.hasError || session.authenticationDestination != nil ? 14 : 0).background(.bar)
            }
            .navigationTitle(page == 1 ? "淘宝身份码" : "淘宝待取记录").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("返回") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("刷新官方页面", systemImage: "arrow.clockwise") { session.load(pageURL) }
                            .disabled(session.authenticationDestination != nil)
                        Button("复制同步诊断", systemImage: "doc.on.doc") { session.copyDiagnostics() }
                            .disabled(page != 0 || session.isLoading || session.authenticationDestination != nil)
                        Button("重新登录淘宝", systemImage: "person.crop.circle") { confirmingAuthentication = true }
                        Link("在浏览器打开", destination: pageURL)
                        Text("内容由淘宝官方提供，身份码由官方刷新")
                    } label: { Image(systemName: "ellipsis.circle") }
                }
            }
            .confirmationDialog("重新登录淘宝？", isPresented: $confirmingAuthentication, titleVisibility: .visible) {
                Button("退出并重新登录", role: .destructive) {
                    sync.beginAuthentication()
                    session.reauthenticate(returningTo: pageURL)
                }
                Button("取消", role: .cancel) { }
            } message: {
                Text("退出当前网页登录后重登，包裹和短信会保留。")
            }
            .onAppear { session.load(pageURL) }
            .onDisappear {
                session.stop()
                if sync.isAuthenticating { sync.endAuthentication() }
                else { NotificationCenter.default.post(name: Notification.Name("ParcelHub.official-session-changed"), object: nil) }
            }
            .onChange(of: page) { _, _ in session.load(pageURL) }
            .onChange(of: scenePhase) { _, phase in
                guard session.authenticationDestination == nil && !sync.isAuthenticating else { return }
                if phase == .background {
                    refreshAfterBackground = true
                    session.stop()
                } else if phase == .active && refreshAfterBackground {
                    refreshAfterBackground = false
                    session.load(pageURL)
                }
            }
            .onChange(of: session.readResult) { _, result in
                guard let result, result.state == "ready" else { return }
                let previousCount = store.collected.count
                if let error = store.importOfficial(result) {
                    session.status = error; session.hasError = true
                } else if result.parcels.isEmpty {
                    let archivedCount = max(0, store.collected.count - previousCount)
                    session.status = archivedCount > 0 ? "已归档 \(archivedCount) 件" : "已同步淘宝"
                } else {
                    session.status = "已同步 \(result.parcels.count) 件待取包裹"
                }
            }
        }
    }
}

struct MiniProgramSettingsView: View {
    @EnvironmentObject private var store: ParcelStore
    @State private var selected: PickupProvider?
    var body: some View {
        List {
            ForEach(store.credentialProviders.filter { !["taobao", "sms"].contains($0.id) }) { provider in
                Button { selected = provider } label: {
                    HStack {
                        ProviderMark(provider: provider)
                        VStack(alignment: .leading, spacing: 5) {
                            Text(provider.name).foregroundStyle(.primary)
                            Text(store.identityBindings[provider.id]?.confirmed == true ? "已确认跳转链接" : store.identityBindings[provider.id]?.kind == "shareCode" ? "已保存口令 · 不能直达" : "未绑定")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").font(.caption)
                    }.frame(maxWidth: .infinity).contentShape(Rectangle())
                }.buttonStyle(PressFeedbackStyle())
            }
        }.navigationTitle("小程序入口绑定").navigationBarTitleDisplayMode(.inline)
            .fullScreenCover(item: $selected) { PickupEntryView(provider: $0) }
    }
}
