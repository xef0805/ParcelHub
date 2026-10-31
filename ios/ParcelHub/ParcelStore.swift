import Foundation
import Combine
import SwiftUI

@MainActor
final class ParcelStore: ObservableObject {
    @Published private(set) var providers: [PickupProvider] = []
    @Published private(set) var parcels: [Parcel] = []
    @Published var storageWarning: String?
    @Published private(set) var lastImportWasDuplicate = false
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
    private let stationCredentialKey = "parcelhub.station-credentials.v1"

    init() {
        do {
            guard let url = Bundle.main.url(forResource: "catalog", withExtension: "json") else {
                throw CocoaError(.fileNoSuchFile)
            }
            providers = try JSONDecoder().decode([PickupProvider].self, from: Data(contentsOf: url))
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
            parcels = ParcelIdentity.coalescing(parcels)
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
            enabledProviderIDs = ["taobao", "tuxi", "yishoufa", "fcbox", "sms"]
            stationCredentials = stationCredentials.filter { enabledProviderIDs.contains($0.value) }
            for index in parcels.indices where provider(parcels[index].providerID) == nil { parcels[index].providerID = "manual" }
            if let data = defaults.data(forKey: "parcelhub.identity-bindings.v1") {
                identityBindings = try JSONDecoder().decode([String: IdentityBinding].self, from: data).filter { enabledProviderIDs.contains($0.key) }
            }
        } catch {
            storageWarning = "本地记录读取失败，原数据未改动"
        }
    }

    func provider(_ id: String) -> PickupProvider? { providers.first { $0.id == id } }
    // 隐藏旧演示记录，但保留存储，不删除用户原有数据。
    var pending: [Parcel] { parcels.filter { $0.isPending } }
    var collected: [Parcel] { parcels.filter { !$0.isDemo && $0.isCollected && $0.deletedAt == nil } }
    var watching: [Parcel] { parcels.filter { !$0.isDemo && !$0.isCollected && $0.deletedAt == nil && $0.awaitingArrival == true } }
    var smsParcels: [Parcel] { parcels.filter { !$0.isDemo && $0.deletedAt == nil && $0.hasSMS }.sorted { ($0.smsImportedAt ?? $0.addedAt) > ($1.smsImportedAt ?? $1.addedAt) } }
    var credentialProviders: [PickupProvider] { providers.filter { $0.id != "manual" && enabledProviderIDs.contains($0.id) } }
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
        guard storageWarning == nil else { return }
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

    func add(title: String, providerID: String, station: String, code: String, carrier: String, trackingNumber: String,
             source: String = "manual", smsOriginal: String? = nil, smsSender: String? = nil, arrivalDate: Date? = nil) -> String? {
        lastImportWasDuplicate = false
        if storageWarning != nil { return "本地数据异常，暂时无法保存新记录" }
        if let error = ParcelDraftValidator.validate(title: title, station: station, code: code, providerID: providerID, providers: providers) { return error }
        let now = Date()
        var incoming = Parcel(id: UUID(), title: title.trimmingCharacters(in: .whitespacesAndNewlines), providerID: providerID,
            station: station.trimmingCharacters(in: .whitespacesAndNewlines), pickupCode: code.trimmingCharacters(in: .whitespacesAndNewlines),
            carrier: carrier.trimmingCharacters(in: .whitespacesAndNewlines), trackingNumber: ParcelIdentity.text(trackingNumber), addedAt: now, isDemo: false, source: source)
        if let date = arrivalDate ?? (source == "sms" ? now : nil) {
            let day = ParcelArrival.day(for: date)
            guard ParcelArrival.isSelectable(day, now: now) else { return "到站日期仅支持今天及前7天" }
            incoming.arrivedOn = day
        }
        if let smsOriginal, !smsOriginal.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            guard smsOriginal.count <= 8000 else { return "短信内容过长，请只粘贴本条取件通知" }
            incoming.smsOriginal = smsOriginal
            incoming.smsFingerprint = ParcelIdentity.fingerprint(smsOriginal)
            incoming.smsSender = smsSender
            incoming.smsImportedAt = now
        }
        do {
            if let index = try ParcelIdentity.match(incoming, in: parcels, now: now) {
                guard parcels[index].deletedAt == nil else { return "该包裹的已取记录已删除，不会重复导入" }
                lastImportWasDuplicate = true
                if parcels[index].awaitingArrival == true {
                    parcels[index].awaitingArrival = false
                    parcels[index].station = incoming.station; parcels[index].pickupCode = incoming.pickupCode
                    parcels[index].providerID = providerID; parcels[index].source = source
                }
                if incoming.hasSMS && ParcelIdentity.text(incoming.smsOriginal ?? "") != ParcelIdentity.text(parcels[index].smsOriginal ?? "") {
                    parcels[index].smsOriginal = incoming.smsOriginal; parcels[index].smsSender = incoming.smsSender; parcels[index].smsImportedAt = now
                    parcels[index].smsFingerprint = incoming.smsFingerprint
                }
                if parcels[index].trackingNumber.isEmpty { parcels[index].trackingNumber = incoming.trackingNumber }
                if parcels[index].carrier.isEmpty { parcels[index].carrier = incoming.carrier }
                if parcels[index].arrivedOn == nil { parcels[index].arrivedOn = incoming.arrivedOn }
                parcels[index].attach(ParcelCredential(providerID: providerID, station: incoming.station, pickupCode: incoming.pickupCode,
                                                       source: source, isCurrent: true, lastSeenAt: now))
            } else {
                if incoming.title.range(of: "^[0-9]{4}包裹[0-9]+号$", options: .regularExpression) != nil {
                    incoming.title = ParcelNaming.nextTitle(in: parcels, date: now)
                }
                parcels.insert(incoming, at: 0)
            }
            persistParcels()
            return storageWarning
        } catch { return error.localizedDescription }
    }

    func deleteCollected(_ id: UUID) {
        guard storageWarning == nil, let index = parcels.firstIndex(where: { $0.id == id && $0.isCollected }) else { return }
        parcels[index].deletedAt = Date()
        parcels[index].smsFingerprint = parcels[index].smsFingerprint ?? parcels[index].smsOriginal.map { ParcelIdentity.fingerprint($0) }
        parcels[index].smsOriginal = nil; parcels[index].smsSender = nil; parcels[index].smsImportedAt = nil
        persistParcels()
    }

    func addTracking(number: String, carrier: String, title: String) -> String? {
        lastImportWasDuplicate = false
        guard storageWarning == nil else { return "本地数据异常，暂时无法保存" }
        guard !number.contains("\n"), !number.contains("\r") else { return "每次请只导入一个完整运单号" }
        let clean = ParcelIdentity.text(number)
        guard clean.range(of: "^[A-Z0-9]{8,40}$", options: .regularExpression) != nil,
              clean.range(of: "[0-9]", options: .regularExpression) != nil,
              clean.range(of: "^1[3-9][0-9]{9}$", options: .regularExpression) == nil else { return "请填写8–40位完整运单号，不能使用手机号" }
        let company = carrier.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard name.count <= 60, company.count <= 30 else { return "填写内容过长" }
        var parcel = Parcel(id: UUID(), title: name.isEmpty ? (company.isEmpty ? "单号导入包裹" : company + "包裹") : name,
            providerID: "manual", station: "", pickupCode: "", carrier: company, trackingNumber: clean, addedAt: Date(), isDemo: false, source: "tracking")
        parcel.awaitingArrival = true
        do {
            if let index = try ParcelIdentity.match(parcel, in: parcels) {
                guard parcels[index].deletedAt == nil else { return "该包裹记录已删除，不会重复导入" }
                lastImportWasDuplicate = true
                if parcels[index].carrier.isEmpty { parcels[index].carrier = company }
            } else { parcels.insert(parcel, at: 0) }
            persistParcels(); return storageWarning
        } catch { return error.localizedDescription }
    }

    func toggleCollected(_ parcel: Parcel) {
        guard storageWarning == nil, let index = parcels.firstIndex(where: { $0.id == parcel.id }) else { return }
        parcels[index].toggleCollected()
        persistParcels()
    }

    private func persistParcels() {
        do { defaults.set(try JSONEncoder().encode(parcels), forKey: parcelKey) }
        catch { storageWarning = "本地记录保存失败，请重试" }
    }
}
