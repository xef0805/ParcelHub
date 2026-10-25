import SwiftUI

struct SMSCredentialListView: View {
    var station: String? = nil
    @EnvironmentObject private var store: ParcelStore
    @Environment(\.dismiss) private var dismiss
    private var records: [Parcel] {
        store.smsParcels.filter { $0.isPending && (station == nil || $0.station == station || $0.pickupCredentials.contains { $0.station == station }) }
    }
    var body: some View {
        NavigationStack {
            Group {
                if records.isEmpty {
                    ContentUnavailableView("暂无待取短信凭证", systemImage: "message", description: Text("从主页导入取件短信后，会在这里保存原文。已取包裹的短信可在已取记录查看。"))
                } else if records.count == 1 {
                    SMSCredentialView(parcelID: records[0].id)
                } else {
                    List(records) { parcel in
                        NavigationLink { SMSCredentialView(parcelID: parcel.id) } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(parcel.title).font(.headline)
                                Text(parcel.station).font(.caption).foregroundStyle(.secondary)
                                Text(parcel.pickupCode).font(.system(.body, design: .monospaced))
                            }.padding(.vertical, 6)
                        }
                    }
                }
            }.navigationTitle("短信身份码").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
        }
    }
}

struct SMSCredentialView: View {
    let parcelID: UUID
    @EnvironmentObject private var store: ParcelStore
    private var parcel: Parcel? { store.parcels.first { $0.id == parcelID && $0.deletedAt == nil } }
    var body: some View {
        ScrollView {
            if let parcel, let original = parcel.smsOriginal {
                VStack(spacing: 24) {
                    VStack(spacing: 10) {
                        BrandMark(asset: CarrierBrand.asset(for: parcel.carrier) ?? "", fallback: "message.fill", label: parcel.smsSender ?? "取件通知", size: 68)
                        Text(parcel.smsSender ?? (parcel.carrier.isEmpty ? "取件通知" : parcel.carrier)).font(.title2.bold())
                    }.padding(.top, 12)
                    VStack(spacing: 5) {
                        Text("短信凭证 · 本机保存")
                        Text("导入于 \((parcel.smsImportedAt ?? parcel.addedAt).formatted(date: .abbreviated, time: .shortened))")
                    }.font(.caption).foregroundStyle(.secondary)
                    HStack {
                        Text(original).font(.system(size: 19)).lineSpacing(5).textSelection(.enabled)
                            .padding(18).background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 23))
                            .overlay(alignment: .bottomLeading) {
                                SMSBubbleTail().fill(Color(uiColor: .secondarySystemBackground)).frame(width: 16, height: 14).offset(x: 12, y: 6)
                            }
                        Spacer(minLength: 24)
                    }
                    Text("内容为你导入的短信原文，显示时间为导入时间。")
                        .font(.caption2).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
                }.padding(20)
            } else {
                ContentUnavailableView("未保存短信原文", systemImage: "message", description: Text("旧版本不会保存原文，可重新粘贴原短信并补全运单号；识别为同一包裹时会合并。"))
            }
        }.background(Color(uiColor: .systemBackground)).navigationTitle("短信身份码").navigationBarTitleDisplayMode(.inline)
    }
}

private struct SMSBubbleTail: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: .zero); path.addLine(to: CGPoint(x: rect.maxX, y: 0)); path.addLine(to: CGPoint(x: 0, y: rect.maxY)); path.closeSubpath()
        return path
    }
}
