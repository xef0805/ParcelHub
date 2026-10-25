import Foundation

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

