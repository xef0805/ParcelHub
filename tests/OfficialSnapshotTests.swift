import Foundation

@main
struct OfficialSnapshotTests {
    static func main() throws {
        let now = Date(timeIntervalSince1970: 1_000)
        let row = OfficialParcelRead(providerID: "cainiao", title: "测试包裹", station: "测试驿站", pickupCode: "01-02-0003", carrier: "中通", trackingNumber: "TEST00001")
        let snapshot = OfficialPageRead(state: "ready", message: "", parcels: [row], expectedCount: 1, readAt: "test")
        let first = try OfficialSnapshotMerge.applying(snapshot, to: [], now: now)
        precondition(first.count == 1 && first[0].providerID == "taobao" && first[0].pickupCode == "01-02-0003")
        var legacy = first[0]
        legacy.source = "cainiao-web"
        legacy.providerID = "cainiao"
        var manual = first[0]
        manual.id = UUID(); manual.source = nil; manual.providerID = "fcbox"
        var other = first[0]
        other.id = UUID(); other.source = "jd-web"; other.providerID = "jd"
        var collected = first[0]
        collected.id = UUID(); collected.collectedAt = now
        let original = [legacy, manual, other, collected]
        let empty = OfficialPageRead(state: "ready", message: "", parcels: [], expectedCount: 0, readAt: "test")
        let cleared = try OfficialSnapshotMerge.applying(empty, to: original)
        precondition(cleared.count == 4 && cleared[0].inLatestOfficialSnapshot == false)
        precondition(cleared[1].inLatestOfficialSnapshot == true && cleared[2].inLatestOfficialSnapshot == true)
        precondition(cleared[3].collectedAt == now && cleared[3].inLatestOfficialSnapshot == false)
        precondition(original[0].inLatestOfficialSnapshot == true)
        let updated = try OfficialSnapshotMerge.applying(snapshot, to: [legacy, other])
        precondition(updated.count == 2 && updated[0].id == legacy.id && updated[0].providerID == "taobao")
        precondition(updated[1].source == "jd-web")
        for invalid in [
            OfficialPageRead(state: "error", message: "请求超时", parcels: [], expectedCount: 0, readAt: "test"),
            OfficialPageRead(state: "ready", message: "", parcels: [], expectedCount: nil, readAt: "test"),
            OfficialPageRead(state: "ready", message: "", parcels: [row], expectedCount: 2, readAt: "test"),
            OfficialPageRead(state: "ready", message: "", parcels: [row, row], expectedCount: 2, readAt: "test")
        ] {
            do {
                _ = try OfficialSnapshotMerge.applying(invalid, to: original)
                fatalError("Invalid snapshot must not overwrite records")
            } catch is OfficialSnapshotMerge.InvalidSnapshot { }
        }
        print("Native snapshot checks passed: empty, legacy migration, source isolation, history, leading zeros, errors and duplicate guards")
    }
}
