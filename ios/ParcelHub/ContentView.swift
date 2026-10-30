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
            ("^已同步淘宝 · 新增 ([0-9]+) 件到站包裹$", "Taobao synced · $1 new pickups"),
            ("^已同步 ([0-9]+) 件待取包裹，可返回清单查看$", "$1 pickups synced. Return to the list to view them"),
            ("^官方暂无待取件，已从待取清单移除该来源的 ([0-9]+) 条旧记录$", "No official pickups. Removed $1 old entries from this source"),
            ("^已沿用上次(.+)的取件地点，请确认本次仍在此处$", "Using the last pickup location for $1. Check it is still correct"),
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
    @EnvironmentObject private var network: NetworkStatus
    @EnvironmentObject private var store: ParcelStore
    @EnvironmentObject private var clipboard: ClipboardImportController
    @State private var selectedTab = 0
    @State private var showingClipboardPrompt = false
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
            Text("剪贴板中有取件短信。确认后进入导入页核对，不会自动保存。")
        }
        .alert("本地数据提示", isPresented: Binding(get: { store.storageWarning != nil }, set: { _ in })) {
            Button("知道了", role: .cancel) { }
        } message: { Text(LocalizedStringKey(store.storageWarning ?? "")) }
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

    private var displayed: [Parcel] {
        let source = store.pending
        return source.filter { search.isEmpty || [$0.title, $0.station, $0.pickupCode, $0.trackingNumber, $0.carrier, store.provider($0.providerID)?.name ?? ""].joined(separator: " ").localizedCaseInsensitiveContains(search) }
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

                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .center, spacing: 18) {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("\(store.pending.count)").font(.system(size: 38, weight: .semibold, design: .rounded))
                                Text("件待取包裹").font(.subheadline.weight(.semibold))
                            }.frame(maxWidth: .infinity, alignment: .leading)
                            Rectangle().fill(.white.opacity(0.25)).frame(width: 1, height: 50)
                            VStack(alignment: .leading, spacing: 6) {
                                Text("\(store.watching.count)").font(.system(size: 38, weight: .semibold, design: .rounded))
                                Text("件在路上").font(.subheadline.weight(.semibold))
                            }.frame(maxWidth: .infinity, alignment: .leading)
                        }
                        Text("\(Set(store.pending.map(\.station)).count) 个取件地点").font(.caption).opacity(0.85)
                    }.foregroundStyle(.white).padding(22).frame(maxWidth: .infinity, minHeight: 114, alignment: .leading)
                        .background(Color(red: 0.10, green: 0.35, blue: 0.82).gradient, in: RoundedRectangle(cornerRadius: 23))
                    HStack(spacing: 12) {
                        Button { packageImportRequest = PackageImportRequest(kind: "sms") } label: {
                            Label("手动导入包裹", systemImage: "text.bubble").font(.subheadline.weight(.medium)).frame(maxWidth: .infinity, minHeight: 50)
                                .background(Palette.card, in: RoundedRectangle(cornerRadius: 15))
                        }
                    }.buttonStyle(PressFeedbackStyle())
                    if launching { ProgressView("正在打开小程序…").font(.caption) }
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 8) {
                            if sync.isRefreshing { ProgressView().controlSize(.small) }
                            else { Image(systemName: sync.needsLogin ? "person.crop.circle.badge.exclamationmark" : "arrow.triangle.2.circlepath") }
                            AppMessage(sync.status)
                        }
                        if sync.needsLogin { Button("重新登录淘宝") { showingOfficialLogin = true }.font(.caption.weight(.semibold)) }
                        if let updated = store.lastOfficialReadAt {
                            Text("上次同步 \(updated.formatted(date: .abbreviated, time: .shortened)) · 可下拉刷新")
                        }
                    }.font(.caption).foregroundStyle(.secondary)
                    Text("待取清单").font(.title2.bold())
                    if displayed.isEmpty {
                        ContentUnavailableView(LocalizedStringKey(search.isEmpty ? "暂无本地待取包裹" : "没有匹配的记录"), systemImage: "shippingbox", description: Text(LocalizedStringKey(search.isEmpty ? "登录淘宝后在前台自动检查；短信件可点“手动导入包裹”。" : "试试其他取件码、快递公司或地点。")))
                    }
                    ForEach(Array(Set(displayed.map(\.station))).sorted(), id: \.self) { station in
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Text(station).font(.title3.bold()).foregroundStyle(.primary)
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
    @State private var copied = false
    @State private var copiedTracking = false
    @State private var showingSMS = false
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                if let asset = CarrierBrand.asset(for: parcel.carrier) {
                    BrandMark(asset: asset, fallback: "shippingbox", label: parcel.carrier)
                } else if let provider = store.provider(parcel.providerID) { ProviderMark(provider: provider) }
                VStack(alignment: .leading, spacing: 4) {
                    Text(parcel.title).font(.headline)
                    HStack(spacing: 3) {
                        Text(parcel.carrier.isEmpty ? "快递" : parcel.carrier)
                        Text(verbatim: "·")
                        Text(LocalizedStringKey(parcel.source == "sms" ? "短信导入" : store.provider(parcel.providerID)?.name ?? "本地"))
                    }.font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button { store.toggleCollected(parcel) } label: {
                    Text(LocalizedStringKey(parcel.isCollected ? "恢复待取" : "我已取件"))
                        .font(.caption.weight(.medium)).padding(.horizontal, 12).frame(minHeight: 40)
                        .background(Palette.blue.opacity(0.10), in: Capsule())
                }.accessibilityLabel(parcel.isCollected ? "恢复待取" : "我已取件")
            }
            HStack {
                Text(parcel.pickupCode).font(.system(size: 28, weight: .semibold, design: .monospaced)).textSelection(.enabled)
                    .minimumScaleFactor(0.6).lineLimit(1)
                Spacer()
                if !parcel.isCollected {
                    Button(LocalizedStringKey(copied ? "已复制" : "复制")) {
                        UIPasteboard.general.string = parcel.pickupCode; clipboard.ignoreCurrentChange(); copied = true
                    }.font(.caption)
                }
            }
            let alternatives = parcel.pickupCredentials.filter { $0.isCurrent && !$0.pickupCode.isEmpty && $0.pickupCode != parcel.pickupCode }
            ForEach(Array(alternatives.enumerated()), id: \.offset) { _, credential in
                Text("\(store.provider(credential.providerID)?.name ?? "其他来源")取件码 · \(credential.pickupCode)")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if !parcel.trackingNumber.isEmpty {
                HStack(spacing: 5) {
                    Text("运单号").font(.caption2).foregroundStyle(.secondary)
                    Text(parcel.trackingNumber).font(.system(.caption2, design: .monospaced)).textSelection(.enabled)
                    Button {
                        UIPasteboard.general.string = parcel.trackingNumber; clipboard.ignoreCurrentChange(); copiedTracking = true
                    } label: {
                        Image(systemName: copiedTracking ? "checkmark" : "doc.on.doc").font(.caption)
                            .frame(minWidth: 36, minHeight: 36).contentShape(Rectangle())
                    }.accessibilityLabel("复制运单号")
                    Spacer(minLength: 0)
                }
            }
            if parcel.isCollected && parcel.hasSMS {
                Button { showingSMS = true } label: { Label("短信身份码", systemImage: "message").font(.caption.weight(.medium)) }
            }
            if let date = parcel.lastReadAt {
                Text("官方清单更新于 \(date.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }.padding(18).background(Palette.card, in: RoundedRectangle(cornerRadius: 22))
            .contentShape(Rectangle()).buttonStyle(PressFeedbackStyle())
            .fullScreenCover(isPresented: $showingSMS) { NavigationStack { SMSCredentialView(parcelID: parcel.id) } }
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
    @State private var sorting = false
    @State private var launching = false
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Group {
                        if let station { Text("为「\(station)」选择身份码，下次可直接打开。") }
                        else { Text("四个官方入口分别绑定；短信件可直接展示保存的通知原文。") }
                    }.font(.subheadline).foregroundStyle(.secondary)
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
                                    Text(LocalizedStringKey(provider.id == "sms" ? "查看本机保存的取件短信" : provider.identityURL != nil ? "App 内打开官方身份码" : store.identityBindings[provider.id]?.confirmed == true ? "已绑定 · 直接打开小程序" : provider.miniProgramURL != nil ? "首次试开并绑定小程序" : "入口待绑定"))
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                if let station, store.stationCredentials[station] == provider.id { Image(systemName: "checkmark.circle.fill") }
                                else if !sorting { Image(systemName: "chevron.right").font(.caption) }
                            }.padding(.vertical, 8).frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                        }.buttonStyle(PressFeedbackStyle()).disabled(launching)
                            .contextMenu {
                                if !["taobao", "sms"].contains(provider.id) { Button("管理小程序绑定") { launchError = nil; selected = provider } }
                            }
                    }.onMove { offsets, destination in store.moveProviders(from: offsets, to: destination) }
                        .deleteDisabled(true)
                        .moveDisabled(!sorting)
                }
                Section {
                    HStack {
                        Spacer()
                        Button(LocalizedStringKey(sorting ? "完成" : "排序")) { withAnimation { sorting.toggle() } }
                            .font(.subheadline).foregroundStyle(.secondary)
                    }.buttonStyle(PressFeedbackStyle())
                    if launching { ProgressView("正在打开小程序…").font(.caption) }
                }
            }.environment(\.editMode, .constant(sorting ? .active : .inactive))
                .navigationTitle("身份码").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    if showsDone { ToolbarItem(placement: .cancellationAction) { Button("关闭") { dismiss() } } }
                }
                .fullScreenCover(item: $selected) { PickupEntryView(provider: $0, initialError: launchError) }
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
                        Text("粘贴官方小程序的桌面链接，试开后确认。以后点击此平台或已绑定的取件地点，会直接尝试打开对应小程序。")
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
                                note = "已保存口令；这不表示可以直接唤起小程序。"
                            }.buttonStyle(.bordered)
                            Button("复制口令并打开微信") {
                                UIPasteboard.general.string = parsed?.value
                                if let url = URL(string: "weixin://") { openURL(url) { accepted in
                                    note = accepted ? "请在微信聊天输入框粘贴并发送口令，再点击进入。" : "未打开微信，请从桌面打开并粘贴口令。"
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
                        Text("仅粘贴入口链接，不要填写身份码或验证码。链接失效时请重新获取。")
                            .font(.caption).foregroundStyle(.secondary)
                        if provider.id == "fcbox" { Text("丰巢支持通知取件码和官方 App 开柜；这里绑定的是小程序入口。").font(.caption).foregroundStyle(.secondary) }
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
    private var records: [Parcel] {
        store.collected.filter { search.isEmpty || [$0.title, $0.station, $0.pickupCode, $0.carrier, $0.trackingNumber].joined(separator: " ").localizedCaseInsensitiveContains(search) }
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
                Section(day.formatted(date: .abbreviated, time: .omitted)) {
                    ForEach(Array(Set(daily.map(\.station))).sorted(), id: \.self) { station in
                        Text(station).font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                        ForEach(daily.filter { $0.station == station }) { parcel in
                            ParcelCard(parcel: parcel).listRowInsets(EdgeInsets(top: 5, leading: 0, bottom: 5, trailing: 0))
                                .listRowBackground(Color.clear).listRowSeparator(.hidden)
                                .swipeActions(edge: .leading, allowsFullSwipe: false) {
                                    Button(role: .destructive) { withAnimation { store.deleteCollected(parcel.id) } } label: {
                                        Image(systemName: "trash.fill")
                                    }.buttonStyle(.automatic).tint(.red).accessibilityLabel("删除已取记录")
                                }
                        }
                    }
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
                NavigationLink { LocalDataSettingsView() } label: { SettingsRowLabel("短信与本地记录", symbol: "message.fill", color: .green) }
            } header: { Text("数据与隐私") } footer: { Text("记录仅保存在本机，不读取短信收件箱。") }
            Section("关于涂涂取件") { Text("版本 0.7.4 · 本地开发版").foregroundStyle(.secondary) }
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
            Text("截图以兔喜生活为例，其他平台以实际菜单为准。").font(.caption).foregroundStyle(.secondary)
            HStack(alignment: .top, spacing: 12) {
                step("BindingGuideMenu", number: "1", title: "打开小程序右上角“…” → 添加到桌面")
                step("BindingGuideSafari", number: "2", title: "在 Safari 复制地址栏完整链接")
            }
            Text("复制地址栏链接后返回粘贴，无需继续添加到主屏幕。").font(.caption).foregroundStyle(.secondary)
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
    var body: some View {
        Form {
            Section("外观") {
                Picker("外观", selection: $appearance) {
                    Text("跟随系统").tag("system")
                    Text("浅色").tag("light")
                    Text("深色").tag("dark")
                }.pickerStyle(.inline).labelsHidden()
            }
            Section { Text("应用界面与短信凭证会随外观切换。官方身份码网页由平台控制，保留便于扫码的显示方式。")
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
            Section { Text("语言设置只改变应用界面，包裹名称、地点、短信原文及官方页面保持原样。")
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

    func fail(_ issue: AppServiceIssue) {
        failure = issue; status = issue.message; isLoading = false; hasError = true
    }

    func stop() {
        generation += 1
        authenticationDestination = nil
        webView.stopLoading()
        readResult = nil
        isLoading = false
    }

    func load(_ url: URL) {
        generation += 1
        authenticationDestination = nil
        pendingPage = url == Self.parcels
        readAttempt = 0
        readResult = nil
        failure = nil
        status = "正在加载官方页面…"
        isLoading = true
        hasError = false
        webView.load(URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30))
    }

    func reauthenticate(returningTo destination: URL) {
        guard let url = OfficialAuthenticationFlow.logoutURL(returningTo: destination) else { fail(.unavailable); return }
        stop()
        load(url)
        authenticationDestination = destination
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        generation += 1
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
                status = "请在此页重新登录淘宝，完成后将返回取件页面。"
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
        status = "正在读取最新待取清单…"
        let script = "JSON.stringify((\(reader))(document.body ? document.body.innerText : ''))"
        webView.evaluateJavaScript(script) { [weak self] value, error in
            guard let self, self.generation == requestGeneration else { return }
            guard error == nil, let json = value as? String, let data = json.data(using: .utf8),
                  let result = try? JSONDecoder().decode(OfficialPageRead.self, from: data) else {
                self.hasError = true; self.status = "未能读取官方页面，原有包裹保持不变"; return
            }
            // 页面应用异步加载，首次得到的占位零件不得清空已有记录。
            if result.state == "loading" {
                if attempt < 12 {
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

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        guard (error as NSError).code != NSURLErrorCancelled else { return }
        generation += 1
        isLoading = false
        fail(AppServiceIssue.from(error))
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
    @EnvironmentObject private var store: ParcelStore
    @EnvironmentObject private var sync: OfficialSyncController
    @StateObject private var session = OfficialPickupSession()
    @State private var page: Int
    @State private var confirmingAuthentication = false
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
                        Button("重新登录淘宝", systemImage: "person.crop.circle") { confirmingAuthentication = true }
                        Link("在浏览器打开", destination: pageURL)
                        Text("内容由淘宝官方提供，身份码由官方刷新")
                    } label: { Image(systemName: "ellipsis.circle") }
                }
            }
            .confirmationDialog("重新登录淘宝？", isPresented: $confirmingAuthentication, titleVisibility: .visible) {
                Button("退出当前网页登录并重新登录", role: .destructive) {
                    sync.beginAuthentication()
                    session.reauthenticate(returningTo: pageURL)
                }
                Button("取消", role: .cancel) { }
            } message: {
                Text("将通过淘宝官方页面退出当前网页登录，再在涂涂取件内重新登录。包裹与短信记录会保留。")
            }
            .onAppear { session.load(pageURL) }
            .onDisappear {
                session.stop()
                if sync.isAuthenticating { sync.endAuthentication() }
                else { NotificationCenter.default.post(name: Notification.Name("ParcelHub.official-session-changed"), object: nil) }
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
