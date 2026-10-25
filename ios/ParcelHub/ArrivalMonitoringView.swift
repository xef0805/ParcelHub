import SwiftUI

struct ArrivalMonitoringView: View {
    @EnvironmentObject private var store: ParcelStore
    @EnvironmentObject private var sync: OfficialSyncController
    var body: some View {
        List {
            Section("已接通") {
                Label("淘宝 · 前台自动检查", systemImage: "checkmark.circle.fill").foregroundStyle(Palette.blue)
                Text(sync.status).font(.subheadline)
                if let date = store.lastOfficialReadAt { Text("上次成功读取 \(date.formatted(date: .abbreviated, time: .shortened))").font(.caption).foregroundStyle(.secondary) }
                Button("立即检查淘宝待取包裹") { sync.refresh(force: true) }.disabled(sync.isRefreshing)
                Text("登录后打开或返回 App 时检查，前台每两分钟再检查。新件先要出现在官方清单中；网页成功读取后才加入主页，不承诺驿站入库后固定几分钟内显示。")
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
                Text("打开微信小程序不会把它的包裹数据交给本 App。接通自动监控仍需平台开放的消费者清单或本人可登录读取的官方网页，不能用其他平台身份码替代。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("短信与后台") {
                Text("短信只接收你手动粘贴的内容。本版不读取短信收件箱，不使用快捷指令，也不能读取微信通知。")
                Text("iOS 会挂起后台 App；本版不承诺锁屏、退出后仍持续监控。当前这三个小程序来源的包裹，仍需短信导入或先在官方服务中查看。")
            }.font(.caption).foregroundStyle(.secondary)
        }.navigationTitle("到站监控").navigationBarTitleDisplayMode(.inline)
    }
}
