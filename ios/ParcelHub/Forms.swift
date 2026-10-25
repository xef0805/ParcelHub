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
    var fromSMS = false
    @EnvironmentObject private var store: ParcelStore
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var station = ""
    @State private var code = ""
    @State private var carrier = ""
    @State private var number = ""
    @State private var providerID = "manual"
    @State private var sms = ""
    @State private var smsExpanded = false
    @State private var candidates: [String] = []
    @State private var recognitionNote: String?
    @State private var error: String?
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DisclosureGroup("粘贴取件短信，自动填写", isExpanded: $smsExpanded) {
                        TextEditor(text: $sms).frame(minHeight: 115)
                            .accessibilityLabel("完整取件短信")
                        PasteButton(payloadType: String.self) { texts in sms = texts.first ?? "" }
                        if let recognitionNote { Text(recognitionNote).font(.caption).foregroundStyle(.secondary) }
                        if candidates.count > 1 {
                            Picker("本次添加的取件码", selection: $code) {
                                Text("请选择").tag("")
                                ForEach(candidates, id: \.self) { Text($0).tag($0) }
                            }
                        }
                    }
                } footer: {
                    Text("只在本机识别你主动粘贴的短信。未写地点时沿用该物流公司最近一次的地点；保存前可修改。短信原文不会保存。")
                }
                Section("核对包裹信息") {
                    TextField("包裹名称", text: $title)
                    Picker("取件平台", selection: $providerID) { ForEach(store.providers) { Text($0.name).tag($0.id) } }
                    TextField("取件地点", text: $station)
                    TextField("取件码", text: $code).textInputAutocapitalization(.never).autocorrectionDisabled()
                }
                Section("物流信息") {
                    TextField("快递公司", text: $carrier)
                    TextField("运单号（选填）", text: $number).textInputAutocapitalization(.never).autocorrectionDisabled()
                }
                if let error { Section { Text(error).foregroundStyle(.red) } }
                Section { Text("短信记录加入同一待取清单。尚未连接对应平台时，取件后需手动标记已取。").font(.caption) }
            }.navigationTitle(fromSMS ? "短信智能导入" : "添加包裹").navigationBarTitleDisplayMode(.inline)
                .onAppear { smsExpanded = fromSMS }
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
                        }
                    }
                }
        }
    }
}

struct AddProviderView: View {
    @EnvironmentObject private var store: ParcelStore
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var search = ""
    @State private var error: String?
    var body: some View {
        NavigationStack {
            Form {
                Section("新平台") {
                    TextField("平台名称", text: $name)
                    TextField("微信搜索词", text: $search)
                }
                Section { Text("添加后可保存手动取件记录、查看打开指引。自动同步和身份码需要后续单独接入。") }
                if let error { Section { Text(error).foregroundStyle(.red) } }
            }.navigationTitle("添加取件平台").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("保存") {
                            error = store.addProvider(name: name, miniProgramName: search)
                            if error == nil { dismiss() }
                        }
                    }
                }
        }
    }
}
