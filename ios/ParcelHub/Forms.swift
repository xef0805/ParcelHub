import SwiftUI
import JavaScriptCore

private struct SMSDraft: Decodable {
    let state: String
    let message: String
    let title: String
    let carrier: String
    let providerID: String
    let station: String
    let stationSource: String
    let pickupCode: String
    let codeCandidates: [String]
    let trackingNumber: String
}

private enum SMSDraftReader {
    static func read(_ message: String, history: [Parcel]) -> SMSDraft? {
        guard let url = Bundle.main.url(forResource: "sms-reader", withExtension: "js"),
              let source = try? String(contentsOf: url, encoding: .utf8), let context = JSContext() else { return nil }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyy-MM-dd"
        guard let textData = try? encoder.encode(message), let text = String(data: textData, encoding: .utf8),
              let historyData = try? encoder.encode(history), let records = String(data: historyData, encoding: .utf8),
              let dayData = try? encoder.encode(formatter.string(from: Date())), let day = String(data: dayData, encoding: .utf8),
              let json = context.evaluateScript("JSON.stringify((\(source))(\(text), \(records), \(day)))")?.toString(),
              context.exception == nil, let data = json.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(SMSDraft.self, from: data)
    }
}

struct AddParcelView: View {
    @EnvironmentObject private var store: ParcelStore
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var station = ""
    @State private var code = ""
    @State private var carrier = ""
    @State private var number = ""
    @State private var providerID = "manual"
    @State private var sms = ""
    @State private var candidates: [String] = []
    @State private var recognitionNote: String?
    @State private var error: String?
    private enum Field: Hashable { case title, station, code }
    @FocusState private var focused: Field?
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ZStack(alignment: .topLeading) {
                        if sms.isEmpty { Text("在此粘贴完整取件短信，自动识别取件码与物流公司")
                            .font(.subheadline).foregroundStyle(.tertiary).padding(.top, 8).padding(.leading, 5).allowsHitTesting(false) }
                        TextEditor(text: $sms).frame(minHeight: 130).accessibilityLabel("完整取件短信")
                            .scrollContentBackground(.hidden)
                    }
                    PasteButton(payloadType: String.self) { texts in sms = texts.first ?? "" }
                    if let recognitionNote { Label(recognitionNote, systemImage: "sparkles").font(.caption).foregroundStyle(.secondary) }
                    if candidates.count > 1 {
                        Picker("本次添加的取件码", selection: $code) {
                            Text("请选择").tag("")
                            ForEach(candidates, id: \.self) { Text($0).tag($0) }
                        }
                    }
                } footer: {
                    Text("只在本机识别你主动粘贴的短信。未写地点时沿用该物流公司最近一次的地点；保存前可修改。短信原文不会保存。")
                }
                Section("核对包裹信息") {
                    TextField("包裹名称", text: $title).focused($focused, equals: .title)
                    Picker("取件平台", selection: $providerID) { ForEach(store.providers) { Text($0.name).tag($0.id) } }
                    TextField("取件地点（必填）", text: $station).focused($focused, equals: .station)
                    TextField("取件码（必填）", text: $code).textInputAutocapitalization(.never).autocorrectionDisabled().focused($focused, equals: .code)
                }
                Section("物流信息") {
                    TextField("快递公司", text: $carrier)
                    TextField("运单号（选填）", text: $number).textInputAutocapitalization(.never).autocorrectionDisabled()
                }
                Section { Text("短信记录加入同一待取清单。尚未连接对应平台时，取件后需手动标记已取。").font(.caption) }
            }.safeAreaInset(edge: .top, spacing: 0) {
                if let error {
                    Label(error, systemImage: "exclamationmark.circle.fill")
                        .font(.caption.weight(.medium)).foregroundStyle(.orange)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(12)
                        .background(Color.orange.opacity(0.12)).accessibilityAddTraits(.updatesFrequently)
                }
            }.navigationTitle("手动导入包裹").navigationBarTitleDisplayMode(.inline)
                .scrollDismissesKeyboard(.interactively)
                .onAppear { if title.isEmpty { title = SMSDraftReader.read("", history: store.parcels)?.title ?? "" } }
                .onChange(of: title) { _, _ in error = nil }
                .onChange(of: station) { _, _ in error = nil }
                .onChange(of: code) { _, _ in error = nil }
                .onChange(of: sms) { _, text in
                    guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
                    guard let draft = SMSDraftReader.read(text, history: store.parcels) else {
                        recognitionNote = "暂时无法识别，请手动核对填写"; return
                    }
                    title = draft.title
                    station = draft.station
                    code = draft.pickupCode
                    carrier = draft.carrier
                    number = draft.trackingNumber
                    providerID = store.provider(draft.providerID) == nil ? "manual" : draft.providerID
                    candidates = draft.codeCandidates
                    recognitionNote = draft.message
                    error = nil
                }
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("保存") {
                            error = store.add(title: title, providerID: providerID, station: station, code: code, carrier: carrier, trackingNumber: number,
                                              source: sms.isEmpty ? "manual" : "sms")
                            if error == nil { dismiss() }
                            else if title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { focused = .title }
                            else if station.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { focused = .station }
                            else if code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { focused = .code }
                        }
                    }
                }
        }
    }
}

struct AddProviderView: View {
    @EnvironmentObject private var store: ParcelStore
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("选择平台即可添加入口。部分小程序仍需绑定官方跳转链接，不同平台的身份码不能互换。")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                Section("可添加平台") {
                    if store.availableProviders.isEmpty { Text("已添加全部现有平台，更多入口会逐步更新。").font(.subheadline).foregroundStyle(.secondary) }
                    ForEach(store.availableProviders) { provider in
                        Button {
                            store.enableProvider(provider.id)
                        } label: {
                            HStack(spacing: 14) {
                                ProviderMark(provider: provider)
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(provider.name).foregroundStyle(.primary)
                                    Text(provider.identityURL != nil ? "官方身份码网页" : provider.miniProgramURL != nil ? "已核实小程序首页链接" : "小程序入口待绑定")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "plus.circle.fill")
                            }.frame(maxWidth: .infinity).contentShape(Rectangle())
                        }.buttonStyle(PressFeedbackStyle())
                    }
                }
            }.navigationTitle("添加其他平台").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } }
                }
        }
    }
}
