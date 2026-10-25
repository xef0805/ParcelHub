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
                              fallback: @escaping () -> Void) async {
    guard let binding = store.identityBindings[provider.id], binding.confirmed,
          let url = await IdentityLinkReader.resolve(binding.value, for: provider) else { fallback(); return }
    openURL(url) { accepted in if !accepted { fallback() } }
}

struct PackagesView: View {
    @EnvironmentObject private var store: ParcelStore
    @State private var search = ""
    @State private var adding = false
    @Environment(\.openURL) private var openURL
    @State private var launching = false
    @EnvironmentObject private var sync: OfficialSyncController
    @State private var credentialRequest: CredentialRequest?
    @State private var selectedProvider: PickupProvider?
    @State private var providerAfterBinding: PickupProvider?

    private var displayed: [Parcel] {
        let source = store.pending
        return source.filter { search.isEmpty || [$0.title, $0.station, $0.pickupCode, $0.trackingNumber, $0.carrier, store.provider($0.providerID)?.name ?? ""].joined(separator: " ").localizedCaseInsensitiveContains(search) }
    }

    private func openCredential(_ provider: PickupProvider) {
        guard !launching else { return }
        launching = true
        Task { @MainActor in
            await launchCredential(provider, store: store, openURL: openURL) { selectedProvider = provider }
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

                    HStack(spacing: 10) {
                        Button { adding = true } label: {
                            Label("手动导入包裹", systemImage: "text.bubble")
                                .font(.subheadline.weight(.medium)).frame(maxWidth: .infinity, minHeight: 50)
                                .background(Palette.blue.opacity(0.1), in: RoundedRectangle(cornerRadius: 14))
                        }
                        Button {
                            if let provider = store.preferredCredential { openCredential(provider) }
                            else { credentialRequest = CredentialRequest() }
                        } label: {
                            Label("打开身份码", systemImage: "barcode.viewfinder")
                                .font(.subheadline.weight(.medium)).frame(maxWidth: .infinity, minHeight: 50)
                                .foregroundStyle(.white).background(Color.accentColor, in: RoundedRectangle(cornerRadius: 14))
                        }.disabled(launching)
                    }
                    if launching { ProgressView("正在打开小程序…").font(.caption) }
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
                        ContentUnavailableView(search.isEmpty ? "暂无本地待取包裹" : "没有匹配的记录", systemImage: "shippingbox", description: Text(search.isEmpty ? "登录淘宝后在前台自动检查；短信件可点“手动导入包裹”。" : "试试其他取件码、快递公司或地点。"))
                    }
                    ForEach(Array(Set(displayed.map(\.station))).sorted(), id: \.self) { station in
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Text(station).font(.title3.bold()).foregroundStyle(.primary)
                                Spacer(minLength: 12)
                                Button {
                                    if let id = store.stationCredentials[station], let provider = store.provider(id) { openCredential(provider) }
                                    else { credentialRequest = CredentialRequest(station: station) }
                                } label: {
                                    Text(store.stationCredentials[station].flatMap { store.provider($0)?.name }.map { "\($0)身份码" } ?? "选择身份码")
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
                }.padding(20)
            }
            .refreshable { await sync.refreshAndWait() }
            .scrollDismissesKeyboard(.interactively)
            .background(Palette.paper).foregroundStyle(Palette.ink)
            .navigationTitle("涂涂取件").navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $adding) { AddParcelView() }
            .sheet(item: $credentialRequest, onDismiss: {
                if let providerAfterBinding {
                    openCredential(providerAfterBinding)
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
    @Environment(\.openURL) private var openURL
    @State private var selected: PickupProvider?
    @State private var adding = false
    @State private var sorting = false
    @State private var launching = false
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
                            else {
                                guard !launching else { return }
                                launching = true
                                Task { @MainActor in
                                    await launchCredential(provider, store: store, openURL: openURL) { selected = provider }
                                    launching = false
                                }
                            }
                        } label: {
                            HStack(spacing: 14) {
                                ProviderMark(provider: provider)
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(provider.id == "fcbox" ? "丰巢取件" : "\(provider.name)身份码").font(.headline).foregroundStyle(.primary)
                                    Text(provider.identityURL != nil ? "App 内打开官方身份码" : store.identityBindings[provider.id]?.confirmed == true ? "已绑定 · 直接打开小程序" : provider.miniProgramURL != nil ? "首次试开并绑定小程序" : "入口待绑定")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                if let station, store.stationCredentials[station] == provider.id { Image(systemName: "checkmark.circle.fill") }
                                else if !sorting { Image(systemName: "chevron.right").font(.caption) }
                            }.padding(.vertical, 8).frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                        }.buttonStyle(PressFeedbackStyle()).disabled(launching)
                            .swipeActions(edge: .leading, allowsFullSwipe: false) {
                                if !sorting { Button("删除", role: .destructive) { withAnimation { store.removeProvider(provider.id) } } }
                            }
                            .contextMenu {
                                if provider.id != "taobao" { Button("管理小程序绑定") { selected = provider } }
                            }
                    }.onMove { offsets, destination in store.moveProviders(from: offsets, to: destination) }
                        .deleteDisabled(true)
                        .moveDisabled(!sorting)
                }
                Section {
                    HStack {
                        Button { adding = true } label: { Label("添加其他平台", systemImage: "plus.circle") }.disabled(sorting)
                        Spacer()
                        Button(sorting ? "完成" : "排序") { withAnimation { sorting.toggle() } }
                            .font(.subheadline).foregroundStyle(.secondary)
                    }.buttonStyle(PressFeedbackStyle())
                    if launching { ProgressView("正在打开小程序…").font(.caption) }
                }
            }.environment(\.editMode, .constant(sorting ? .active : .inactive))
                .navigationTitle("身份码").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    if showsDone { ToolbarItem(placement: .cancellationAction) { Button("关闭") { dismiss() } } }
                }
                .fullScreenCover(item: $selected) { PickupEntryView(provider: $0) }
                .sheet(isPresented: $adding) { AddProviderView() }
        }
    }
}

struct PickupEntryView: View {
    let provider: PickupProvider
    @EnvironmentObject private var store: ParcelStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var link = ""
    @State private var note: String?
    @State private var testedValue: String?
    @State private var trying = false
    @State private var error: String?
    @State private var openTask: Task<Void, Never>?

    private var parsed: IdentityLinkResult? { IdentityLinkReader.parse(link, for: provider) }

    var body: some View {
        if provider.id == "taobao" {
            OfficialPickupView(initialPage: 1)
        } else {
            NavigationStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
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
                        if let error { Label(error, systemImage: "exclamationmark.circle.fill").font(.caption).foregroundStyle(.orange) }
                        if parsed?.kind == "launchURL" {
                            Button {
                                trying = true; error = nil; testedValue = nil
                                let candidate = link.trimmingCharacters(in: .whitespacesAndNewlines)
                                openTask = Task { @MainActor in
                                    guard let url = await IdentityLinkReader.resolve(candidate, for: provider) else {
                                        trying = false; error = "链接未能解析到对应小程序，请重新获取完整链接。"; return
                                    }
                                    guard !Task.isCancelled, candidate == link.trimmingCharacters(in: .whitespacesAndNewlines) else { trying = false; return }
                                    openURL(url) { accepted in
                                        trying = false
                                        if accepted { testedValue = candidate; note = "返回后确认：刚才是否进入了\(provider.miniProgramName)？" }
                                        else { error = "无法打开微信，请确认已安装微信；也可以重新获取官方链接。" }
                                    }
                                }
                            } label: {
                                HStack { if trying { ProgressView().tint(.white) }; Text(trying ? "正在打开…" : "试开\(provider.miniProgramName)") }.frame(maxWidth: .infinity)
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
                        if let note, testedValue == nil { Text(note).font(.caption).foregroundStyle(.secondary) }
                        if store.identityBindings[provider.id] != nil {
                            Button("解除此平台的入口绑定", role: .destructive) {
                                store.saveIdentityBinding(nil, for: provider.id); testedValue = nil; note = "已解除入口绑定"
                            }.font(.subheadline)
                        }
                        Text("获取方式：微信打开「\(provider.miniProgramName)」→ … → 添加到桌面；若进入 Safari，复制地址栏链接。只有“复制链接”时得到的可能是口令。不要粘贴身份码、密码或验证码。")
                            .font(.caption).foregroundStyle(.secondary)
                        if provider.id == "jd" { Text("京东现场扫码入口可能带站点信息，应优先使用本站提供的入口。").font(.caption).foregroundStyle(.secondary) }
                        if provider.id == "pdd" { Text("拼多多与兔喜单独保留。本平台的通用身份码入口尚未核实，不能用兔喜码替代。").font(.caption).foregroundStyle(.secondary) }
                        if provider.id == "fcbox" { Text("丰巢支持通知取件码和官方 App 开柜；这里绑定的是小程序入口。").font(.caption).foregroundStyle(.secondary) }
                        if ["cainiao", "jd", "fcbox", "pdd"].contains(provider.id),
                           let link = provider.appStoreURL, let url = URL(string: link) {
                            Link("官方 App（App Store）", destination: url).font(.subheadline)
                        }
                    }.padding(24)
                }.background(Palette.paper)
                    .navigationTitle("小程序绑定").navigationBarTitleDisplayMode(.inline)
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
                    .onAppear { link = store.identityBindings[provider.id]?.value ?? provider.miniProgramURL ?? "" }
                    .onChange(of: link) { _, _ in testedValue = nil; note = nil; error = nil }
                    .onDisappear { openTask?.cancel() }
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
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 18) {
                if records.isEmpty { ContentUnavailableView(search.isEmpty ? "暂无已取记录" : "没有匹配的记录", systemImage: "checkmark.circle") }
                ForEach(days, id: \.self) { day in
                    let daily = records.filter { Calendar.current.isDate($0.collectedAt ?? .distantPast, inSameDayAs: day) }
                    VStack(alignment: .leading, spacing: 14) {
                        Text(day.formatted(date: .abbreviated, time: .omitted)).font(.title3.bold())
                        ForEach(Array(Set(daily.map(\.station))).sorted(), id: \.self) { station in
                            Text(station).font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                            ForEach(daily.filter { $0.station == station }) { ParcelCard(parcel: $0) }
                        }
                    }
                }
            }.padding(20)
        }.safeAreaInset(edge: .top, spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("搜索包裹、取件码或地点", text: $search).textInputAutocapitalization(.never).autocorrectionDisabled()
                if !search.isEmpty { Button { search = "" } label: { Image(systemName: "xmark.circle.fill") }.accessibilityLabel("清除搜索") }
            }.padding(14).background(Palette.card, in: RoundedRectangle(cornerRadius: 16)).padding(.horizontal, 20).padding(.vertical, 10).background(Palette.paper)
        }.background(Palette.paper).navigationTitle("已取记录").navigationBarTitleDisplayMode(.inline)
            .scrollDismissesKeyboard(.interactively)
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
                Text("朋友寄件也可添加：在短信中复制完整通知，点击主页的“手动导入包裹”。自动识别取件码，沿用该物流公司最近一次地点，按日期编号。确认后只保存包裹字段。")
                Text("不会自动读取短信收件箱，也不保存短信原文。短信件和未接通平台的包裹，取完后需手动标记。")
            }
            Section("身份码") {
                NavigationLink("地点身份码绑定") { StationCredentialSettingsView() }
                NavigationLink("小程序入口绑定") { MiniProgramSettingsView() }
                Text("不同平台凭证单独保留。身份码页右滑删除入口，长按可管理绑定。兔喜已核实官方首页跳转链接，仍需首次试开确认；其他平台逐项适配。")
            }
            Section("关于涂涂取件") {
                Label("蓝白配色，跟随系统深色模式", systemImage: "circle.lefthalf.filled")
                Text("版本 0.5.0 · 本地开发版")
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

struct MiniProgramSettingsView: View {
    @EnvironmentObject private var store: ParcelStore
    @State private var selected: PickupProvider?
    var body: some View {
        List {
            ForEach(store.credentialProviders.filter { $0.id != "taobao" }) { provider in
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
