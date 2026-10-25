import Foundation
import Combine

@MainActor
final class ParcelStore: ObservableObject {
    @Published private(set) var providers: [PickupProvider] = []
    @Published private(set) var parcels: [Parcel] = []
    @Published var storageWarning: String?

    private let defaults = UserDefaults.standard
    private let parcelKey = "parcelhub.parcels.v1"
    private let providerKey = "parcelhub.providers.v1"

    init() {
        do {
            guard let url = Bundle.main.url(forResource: "catalog", withExtension: "json") else {
                throw CocoaError(.fileNoSuchFile)
            }
            providers = try JSONDecoder().decode([PickupProvider].self, from: Data(contentsOf: url))
            if let saved = defaults.data(forKey: providerKey) {
                providers += try JSONDecoder().decode([PickupProvider].self, from: saved)
            }
            if let saved = defaults.data(forKey: parcelKey) {
                parcels = try JSONDecoder().decode([Parcel].self, from: saved)
            } else {
                parcels = []
                persistParcels()
            }
        } catch {
            storageWarning = "本地数据读取失败，暂不覆盖原记录。请保留现有数据并反馈问题。"
        }
    }

    func provider(_ id: String) -> PickupProvider? { providers.first { $0.id == id } }
    // 隐藏旧演示记录，但保留存储，不删除用户原有数据。
    var pending: [Parcel] { parcels.filter { !$0.isDemo && !$0.isCollected && $0.inLatestOfficialSnapshot != false } }
    var collected: [Parcel] { parcels.filter { !$0.isDemo && $0.isCollected && $0.inLatestOfficialSnapshot != false } }

    func importOfficial(_ snapshot: OfficialPageRead) -> String? {
        guard storageWarning == nil else { return "本地数据异常，暂不更新" }
        guard snapshot.state == "ready", snapshot.expectedCount == snapshot.parcels.count else { return snapshot.message }
        let now = Date()
        for index in parcels.indices where parcels[index].source == "cainiao-web" {
            parcels[index].inLatestOfficialSnapshot = false
        }
        for row in snapshot.parcels {
            let index = parcels.firstIndex {
                !$0.isDemo && $0.carrier == row.carrier && $0.trackingNumber.caseInsensitiveCompare(row.trackingNumber) == .orderedSame
            }
            var parcel = index.map { parcels[$0] } ?? Parcel(id: UUID(), title: row.title, providerID: "cainiao", station: row.station,
                                                           pickupCode: row.pickupCode, carrier: row.carrier, trackingNumber: row.trackingNumber,
                                                           addedAt: now, isDemo: false)
            parcel.providerID = "cainiao"
            parcel.station = row.station
            parcel.pickupCode = row.pickupCode
            parcel.collectedAt = nil
            parcel.source = "cainiao-web"
            parcel.inLatestOfficialSnapshot = true
            parcel.lastReadAt = now
            if let index { parcels[index] = parcel } else { parcels.insert(parcel, at: 0) }
        }
        persistParcels()
        return nil
    }

    func add(title: String, providerID: String, station: String, code: String, carrier: String, trackingNumber: String) -> String? {
        if storageWarning != nil { return "本地数据异常，暂时无法保存新记录" }
        if let error = ParcelDraftValidator.validate(title: title, station: station, code: code, providerID: providerID, providers: providers) { return error }
        let number = trackingNumber.trimmingCharacters(in: .whitespacesAndNewlines)
        let company = carrier.trimmingCharacters(in: .whitespacesAndNewlines)
        // 运单号和取件码都保持字符串，避免丢失前导零。
        if !number.isEmpty && parcels.contains(where: {
            !$0.isDemo && $0.trackingNumber.caseInsensitiveCompare(number) == .orderedSame &&
            $0.carrier.caseInsensitiveCompare(company) == .orderedSame
        }) { return "已存在相同快递公司和运单号的记录" }
        parcels.insert(Parcel(id: UUID(), title: title.trimmingCharacters(in: .whitespacesAndNewlines), providerID: providerID,
                              station: station.trimmingCharacters(in: .whitespacesAndNewlines), pickupCode: code.trimmingCharacters(in: .whitespacesAndNewlines),
                              carrier: company, trackingNumber: number, addedAt: Date(), isDemo: false), at: 0)
        persistParcels()
        return nil
    }

    func toggleCollected(_ parcel: Parcel) {
        guard storageWarning == nil, let index = parcels.firstIndex(where: { $0.id == parcel.id }) else { return }
        parcels[index].collectedAt = parcel.isCollected ? nil : Date()
        persistParcels()
    }

    func addProvider(name: String, miniProgramName: String) -> String? {
        if storageWarning != nil { return "本地数据异常，暂时无法保存" }
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let search = miniProgramName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty, !search.isEmpty else { return "请填写平台名称和微信搜索词" }
        guard clean.count <= 20, search.count <= 40 else { return "平台名称或搜索词过长" }
        guard !providers.contains(where: { $0.name.caseInsensitiveCompare(clean) == .orderedSame }) else { return "这个平台已经存在" }
        providers.append(PickupProvider(id: "custom-\(UUID().uuidString)", name: clean, shortName: String(clean.prefix(1)), color: "#479981",
                                        symbol: "square.stack.3d.up.fill", miniProgramName: search, website: "", kind: "自定义平台", featured: false))
        do {
            let custom = providers.filter { $0.id.hasPrefix("custom-") }
            defaults.set(try JSONEncoder().encode(custom), forKey: providerKey)
        } catch { storageWarning = "平台配置保存失败，请重试" }
        return nil
    }

    private func persistParcels() {
        do { defaults.set(try JSONEncoder().encode(parcels), forKey: parcelKey) }
        catch { storageWarning = "本地记录保存失败，请重试" }
    }
}
