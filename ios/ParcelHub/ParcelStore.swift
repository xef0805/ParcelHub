import Foundation
import Combine
import SwiftUI

@MainActor
final class ParcelStore: ObservableObject {
    @Published private(set) var providers: [PickupProvider] = []
    @Published private(set) var parcels: [Parcel] = []
    @Published var storageWarning: String?
    @Published private(set) var stationCredentials: [String: String] = [:]
    @Published private(set) var lastOfficialReadAt: Date?
    @Published private(set) var preferredCredentialID: String?
    @Published private(set) var enabledProviderIDs: [String] = []
    @Published private(set) var identityBindings: [String: IdentityBinding] = [:]
    @Published var autoSyncEnabled = true {
        didSet { defaults.set(autoSyncEnabled, forKey: "parcelhub.auto-sync.v1") }
    }

    private let defaults = UserDefaults.standard
    private let parcelKey = "parcelhub.parcels.v1"
    private let providerKey = "parcelhub.providers.v1"
    private let stationCredentialKey = "parcelhub.station-credentials.v1"

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
                // 旧版以菜鸟命名的读取器实际使用淘宝网页，只迁移官方来源记录。
                for index in parcels.indices where parcels[index].source == "cainiao-web" {
                    parcels[index].providerID = "taobao"
                }
            } else {
                parcels = []
                persistParcels()
            }
            stationCredentials = defaults.dictionary(forKey: stationCredentialKey) as? [String: String] ?? [:]
            let savedOrder = defaults.stringArray(forKey: "parcelhub.provider-order.v1") ?? []
            var seen = Set<String>()
            let ordered = savedOrder.compactMap { id -> PickupProvider? in
                guard seen.insert(id).inserted else { return nil }
                return providers.first { $0.id == id }
            }
            providers = ordered + providers.filter { !seen.contains($0.id) }
            autoSyncEnabled = defaults.object(forKey: "parcelhub.auto-sync.v1") as? Bool ?? true
            lastOfficialReadAt = defaults.object(forKey: "parcelhub.last-official-read.v1") as? Date
            preferredCredentialID = defaults.string(forKey: "parcelhub.preferred-credential.v1")
            enabledProviderIDs = defaults.stringArray(forKey: "parcelhub.enabled-providers.v1")
                ?? ["taobao", "pdd", "tuxi"] + providers.filter { $0.id.hasPrefix("custom-") }.map(\.id)
                    + Array(stationCredentials.values) + (preferredCredentialID.map { [$0] } ?? [])
            if let data = defaults.data(forKey: "parcelhub.identity-bindings.v1") {
                identityBindings = try JSONDecoder().decode([String: IdentityBinding].self, from: data)
            }
        } catch {
            storageWarning = "本地数据读取失败，暂不覆盖原记录。请保留现有数据并反馈问题。"
        }
    }

    func provider(_ id: String) -> PickupProvider? { providers.first { $0.id == id } }
    // 隐藏旧演示记录，但保留存储，不删除用户原有数据。
    var pending: [Parcel] { parcels.filter { !$0.isDemo && !$0.isCollected && $0.inLatestOfficialSnapshot != false } }
    var collected: [Parcel] { parcels.filter { !$0.isDemo && $0.isCollected } }
    var credentialProviders: [PickupProvider] { providers.filter { $0.id != "manual" && enabledProviderIDs.contains($0.id) } }
    var availableProviders: [PickupProvider] { providers.filter { $0.id != "manual" && !$0.id.hasPrefix("custom-") && !enabledProviderIDs.contains($0.id) } }

    func enableProvider(_ id: String) {
        guard storageWarning == nil, provider(id) != nil, id != "manual", !enabledProviderIDs.contains(id) else { return }
        enabledProviderIDs.append(id)
        defaults.set(enabledProviderIDs, forKey: "parcelhub.enabled-providers.v1")
    }

    func removeProvider(_ id: String) {
        guard storageWarning == nil else { return }
        enabledProviderIDs.removeAll { $0 == id }
        defaults.set(enabledProviderIDs, forKey: "parcelhub.enabled-providers.v1")
        stationCredentials = stationCredentials.filter { $0.value != id }
        defaults.set(stationCredentials, forKey: stationCredentialKey)
        if preferredCredentialID == id {
            preferredCredentialID = nil
            defaults.removeObject(forKey: "parcelhub.preferred-credential.v1")
        }
        saveIdentityBinding(nil, for: id)
        // 只移除入口与绑定，不删除包裹、历史或平台元数据。
    }

    func saveIdentityBinding(_ binding: IdentityBinding?, for id: String) {
        guard storageWarning == nil, provider(id) != nil else { return }
        identityBindings[id] = binding
        do { defaults.set(try JSONEncoder().encode(identityBindings), forKey: "parcelhub.identity-bindings.v1") }
        catch { storageWarning = "身份码入口保存失败，请重试" }
    }

    var preferredCredential: PickupProvider? {
        if let id = preferredCredentialID, let provider = credentialProviders.first(where: { $0.id == id }) { return provider }
        let bound = Set(stationCredentials.values).compactMap { id in credentialProviders.first { $0.id == id } }
        return bound.count == 1 ? bound[0] : nil
    }

    func preferCredential(_ id: String) {
        guard credentialProviders.contains(where: { $0.id == id }) else { return }
        preferredCredentialID = id
        defaults.set(id, forKey: "parcelhub.preferred-credential.v1")
    }

    func moveProviders(from offsets: IndexSet, to destination: Int) {
        var ordered = credentialProviders
        ordered.move(fromOffsets: offsets, toOffset: destination)
        providers = ordered + providers.filter { !enabledProviderIDs.contains($0.id) || $0.id == "manual" }
        defaults.set(ordered.map(\.id), forKey: "parcelhub.provider-order.v1")
    }

    func rememberCredential(_ providerID: String, for station: String) {
        guard credentialProviders.contains(where: { $0.id == providerID }), !station.isEmpty else { return }
        stationCredentials[station] = providerID
        defaults.set(stationCredentials, forKey: stationCredentialKey)
    }

    func forgetCredential(for station: String) {
        stationCredentials.removeValue(forKey: station)
        defaults.set(stationCredentials, forKey: stationCredentialKey)
    }

    func importOfficial(_ snapshot: OfficialPageRead) -> String? {
        guard storageWarning == nil else { return "本地数据异常，暂不更新" }
        do {
            parcels = try OfficialSnapshotMerge.applying(snapshot, to: parcels)
            persistParcels()
            if storageWarning == nil {
                lastOfficialReadAt = Date()
                defaults.set(lastOfficialReadAt, forKey: "parcelhub.last-official-read.v1")
            }
            return storageWarning
        } catch {
            return error.localizedDescription
        }
    }

    func add(title: String, providerID: String, station: String, code: String, carrier: String, trackingNumber: String, source: String = "manual") -> String? {
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
                              carrier: company, trackingNumber: number, addedAt: Date(), isDemo: false, source: source), at: 0)
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
        providers.append(PickupProvider(id: "custom-\(UUID().uuidString)", name: clean, shortName: String(clean.prefix(1)), color: "#2867D8",
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
