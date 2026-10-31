import SwiftUI

struct ArrivalMonitoringView: View {
    @EnvironmentObject private var store: ParcelStore
    @EnvironmentObject private var sync: OfficialSyncController
    var body: some View {
        List {
            Section("已接通") {
                Label("淘宝 · 前台自动检查", systemImage: "checkmark.circle.fill").foregroundStyle(Palette.blue)
                AppMessage(sync.status).font(.subheadline)
                if let date = store.lastOfficialReadAt { Text("上次成功读取 \(date.formatted(date: .abbreviated, time: .shortened))").font(.caption).foregroundStyle(.secondary) }
                Button("立即检查淘宝待取包裹") { sync.refresh(force: true) }.disabled(sync.isRefreshing)
                Text("打开或返回 App 时检查，前台每两分钟刷新。以官方清单为准。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("小程序入口已核实 · 清单尚未接通") {
                ForEach(["tuxi", "yishoufa", "fcbox"], id: \.self) { id in
                    if let provider = store.provider(id) {
                        HStack(spacing: 12) {
                            ProviderMark(provider: provider)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(provider.name)
                                Text("可绑定并打开首页；不能自动读取到站包裹").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                Text("当前仅支持打开小程序，尚未接通包裹同步。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("短信与后台") {
                Text("仅导入主动粘贴的短信，不读取短信或微信通知。")
                Text("锁屏或退出后暂停检查；其他平台可先导入短信。")
            }.font(.caption).foregroundStyle(.secondary)
        }.navigationTitle("到站监控").navigationBarTitleDisplayMode(.inline)
    }
}
