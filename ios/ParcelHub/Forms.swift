import SwiftUI
import JavaScriptCore

private struct SMSDraft: Decodable {
    let state: String
    let message: String
    let title: String
    let sender: String?
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
    @State private var sender = ""
    @State private var candidates: [String] = []
    @State private var recognitionNote: String?
    @State private var error: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack {
                            Label("粘贴取件短信", systemImage: "text.bubble.fill").font(.headline)
                            Spacer()
                            Text("本机识别").font(.caption2).foregroundStyle(Palette.blue)
                        }
                        ZStack(alignment: .topLeading) {
                            if sms.isEmpty { Text("粘贴完整通知，自动填写取件码、物流和地点")
                                .font(.subheadline).foregroundStyle(.tertiary).padding(.top, 9).padding(.leading, 5).allowsHitTesting(false) }
                            TextEditor(text: $sms).frame(minHeight: 135).scrollContentBackground(.hidden).accessibilityLabel("完整取件短信")
                        }.padding(6).background(Palette.paper, in: RoundedRectangle(cornerRadius: 14))
                        HStack { PasteButton(payloadType: String.self) { texts in sms = texts.first ?? "" }; Spacer() }
                        if let recognitionNote { Label(recognitionNote, systemImage: "sparkles").font(.caption).foregroundStyle(.secondary) }
                    }.padding(18).background(Palette.card, in: RoundedRectangle(cornerRadius: 22))
                    VStack(alignment: .leading, spacing: 15) {
                        Label("核对取件信息", systemImage: "shippingbox").font(.headline)
                        if candidates.count > 1 {
                            Picker("选择本次取件码", selection: $code) {
                                Text("请选择").tag("")
                                ForEach(candidates, id: \.self) { Text($0).tag($0) }
                            }
                        }
                        field("取件码", placeholder: "必填", value: $code, monospaced: true)
                        field("取件地点", placeholder: "必填，请核对本次地点", value: $station)
                        field("包裹名称", placeholder: "按日期自动编号", value: $title)
                        Picker("取件平台", selection: $providerID) {
                            ForEach(store.providers.filter { $0.id != "sms" }) { Text($0.name).tag($0.id) }
                        }.font(.subheadline)
                    }.padding(18).background(Palette.card, in: RoundedRectangle(cornerRadius: 22))
                    VStack(alignment: .leading, spacing: 15) {
                        Label("物流与去重", systemImage: "number").font(.headline)
                        field("快递公司", placeholder: "例如：中通、韵达", value: $carrier)
                        field("完整快递单号", placeholder: "建议补全，尾号不能跨平台去重", value: $number, monospaced: true)
                        Text("相同完整单号和物流公司会合并为一个包裹，各平台取件码分别保留。短信没有完整单号时，只能保守核对原文、地点和取件码。").font(.caption).foregroundStyle(.secondary)
                    }.padding(18).background(Palette.card, in: RoundedRectangle(cornerRadius: 22))
                    Text("保存后，短信原文及导入时间仅保留在本机，可用“短信身份码”展示。不会自动读取短信收件箱。").font(.caption).foregroundStyle(.secondary)
                }.padding(20)
            }.background(Palette.paper).scrollDismissesKeyboard(.interactively)
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    Button { save() } label: { Text("保存包裹").font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity).padding(.vertical, 9) }
                        .buttonStyle(.borderedProminent).padding(.horizontal, 20).padding(.vertical, 12).background(Palette.paper)
                }
                .safeAreaInset(edge: .top, spacing: 0) {
                    if let error { Label(error, systemImage: "exclamationmark.circle.fill").font(.caption.weight(.medium))
                        .foregroundStyle(.orange).frame(maxWidth: .infinity, alignment: .leading).padding(12).background(Palette.card) }
                }
                .navigationTitle("手动导入包裹").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } } }
                .onAppear { if title.isEmpty { title = SMSDraftReader.read("", history: store.parcels)?.title ?? "" } }
                .onChange(of: sms) { _, text in
                    guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
                    guard let draft = SMSDraftReader.read(text, history: store.parcels) else { recognitionNote = "识别失败，请核对填写"; return }
                    title = draft.title; station = draft.station; code = draft.pickupCode; carrier = draft.carrier
                    number = draft.trackingNumber; sender = draft.sender ?? draft.carrier
                    providerID = store.provider(draft.providerID) == nil ? "manual" : draft.providerID
                    candidates = draft.codeCandidates; recognitionNote = draft.message; error = nil
                }
        }
    }
    private func field(_ label: String, placeholder: String, value: Binding<String>, monospaced: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            TextField(placeholder, text: value).font(monospaced ? .system(.body, design: .monospaced) : .body)
                .textInputAutocapitalization(.never).autocorrectionDisabled().padding(12)
                .background(Palette.paper, in: RoundedRectangle(cornerRadius: 12))
                .onChange(of: value.wrappedValue) { _, _ in error = nil }
        }
    }
    private func save() {
        error = store.add(title: title, providerID: providerID, station: station, code: code, carrier: carrier, trackingNumber: number,
                          source: sms.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "manual" : "sms", smsOriginal: sms, smsSender: sender)
        if error == nil {
            if !sms.isEmpty && providerID == "manual" && store.stationCredentials[station] == nil { store.rememberCredential("sms", for: station) }
            dismiss()
        }
    }
}
