import Foundation
import SwiftUI

struct PickupProvider: Codable, Identifiable, Hashable {
    var id: String
    var name: String
    var shortName: String
    var color: String
    var symbol: String
    var miniProgramName: String
    var website: String
    var kind: String
    var featured: Bool
    var identityURL: String? = nil
    var parcelsURL: String? = nil
    var appStoreURL: String? = nil

    var tint: Color {
        let value = UInt64(color.trimmingCharacters(in: CharacterSet(charactersIn: "#")), radix: 16) ?? 0x479981
        return Color(red: Double((value >> 16) & 255) / 255,
                     green: Double((value >> 8) & 255) / 255,
                     blue: Double(value & 255) / 255)
    }
}

enum CarrierBrand {
    static func asset(for carrier: String) -> String? {
        let values = [("韵达", "yunda"), ("中通", "zto"), ("申通", "sto"), ("圆通", "yto"),
                      ("顺丰", "sf"), ("京东", "jd"), ("极兔", "jtexpress"), ("德邦", "deppon"),
                      ("EMS", "ems"), ("邮政", "post"), ("菜鸟", "cainiao")]
        return values.first { carrier.localizedCaseInsensitiveContains($0.0) }.map { "Brand-" + $0.1 }
    }
}

enum ParcelDraftValidator {
    static func validate(title: String, station: String, code: String, providerID: String, providers: [PickupProvider]) -> String? {
        if title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "请填写包裹名称" }
        if station.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "请填写取件地点" }
        if code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "请填写取件码" }
        if !providers.contains(where: { $0.id == providerID }) { return "请选择取件平台" }
        if title.count > 60 || station.count > 100 || code.count > 40 { return "填写内容过长，请缩短后重试" }
        return nil
    }
}
