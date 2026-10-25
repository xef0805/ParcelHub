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

    var tint: Color {
        let value = UInt64(color.trimmingCharacters(in: CharacterSet(charactersIn: "#")), radix: 16) ?? 0x479981
        return Color(red: Double((value >> 16) & 255) / 255,
                     green: Double((value >> 8) & 255) / 255,
                     blue: Double(value & 255) / 255)
    }
}

struct Parcel: Codable, Identifiable {
    var id: UUID
    var title: String
    var providerID: String
    var station: String
    var pickupCode: String
    var carrier: String
    var trackingNumber: String
    var addedAt: Date
    var collectedAt: Date? = nil
    var isDemo: Bool
    var source: String? = nil
    var inLatestOfficialSnapshot: Bool? = nil
    var lastReadAt: Date? = nil

    var isCollected: Bool { collectedAt != nil }

    static var examples: [Parcel] {
        let now = Date()
        return [
            Parcel(id: UUID(), title: "日常用品", providerID: "cainiao", station: "梧桐里 · 菜鸟驿站", pickupCode: "2-06-218", carrier: "中通", trackingNumber: "DEMO-CN-001", addedAt: now, isDemo: true),
            Parcel(id: UUID(), title: "书与文具", providerID: "cainiao", station: "梧桐里 · 菜鸟驿站", pickupCode: "3-02-086", carrier: "圆通", trackingNumber: "DEMO-CN-002", addedAt: now, isDemo: true),
            Parcel(id: UUID(), title: "一份小惊喜", providerID: "yishoufa", station: "梧桐里 · 驿收发", pickupCode: "A-12-039", carrier: "顺丰", trackingNumber: "DEMO-YSF-001", addedAt: now, isDemo: true),
            Parcel(id: UUID(), title: "生活小物", providerID: "fcbox", station: "梧桐里 · 东门丰巢柜", pickupCode: "008 426", carrier: "申通", trackingNumber: "DEMO-FC-001", addedAt: now, isDemo: true)
        ]
    }
}

struct OfficialParcelRead: Codable, Equatable {
    var providerID: String
    var title: String
    var station: String
    var pickupCode: String
    var carrier: String
    var trackingNumber: String
}

struct OfficialPageRead: Codable, Equatable {
    var state: String
    var message: String
    var parcels: [OfficialParcelRead]
    var expectedCount: Int?
    var readAt: String
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
