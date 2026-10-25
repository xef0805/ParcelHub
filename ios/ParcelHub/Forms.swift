import SwiftUI

struct AddParcelView: View {
    @EnvironmentObject private var store: ParcelStore
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var station = ""
    @State private var code = ""
    @State private var carrier = ""
    @State private var number = ""
    @State private var providerID = "cainiao"
    @State private var error: String?
    var body: some View {
        NavigationStack {
            Form {
                Section("包裹信息") {
                    TextField("包裹名称", text: $title)
                    Picker("取件平台", selection: $providerID) { ForEach(store.providers) { Text($0.name).tag($0.id) } }
                    TextField("取件地点", text: $station)
                    TextField("取件码", text: $code).textInputAutocapitalization(.never)
                }
                Section("可选信息") {
                    TextField("快递公司", text: $carrier)
                    TextField("运单号", text: $number).textInputAutocapitalization(.never).autocorrectionDisabled()
                }
                if let error { Section { Text(error).foregroundStyle(.red) } }
                Section { Text("仅保存在本机；不会因此连接平台或自动更新取件状态。").font(.caption) }
            }.navigationTitle("添加包裹").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("保存") {
                            error = store.add(title: title, providerID: providerID, station: station, code: code, carrier: carrier, trackingNumber: number)
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
