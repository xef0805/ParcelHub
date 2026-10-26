import Foundation

enum OfficialSnapshotMerge {
    struct InvalidSnapshot: LocalizedError {
        var errorDescription: String? { "官方清单尚未完整读取，原有记录保持不变" }
    }

    static func applying(_ snapshot: OfficialPageRead, to original: [Parcel], now: Date = Date()) throws -> [Parcel] {
        guard snapshot.state == "ready", snapshot.expectedCount == snapshot.parcels.count else { throw InvalidSnapshot() }
        var keys = Set<String>()
        for row in snapshot.parcels {
            guard ["cainiao", "taobao"].contains(row.providerID),
                  [row.title, row.station, row.pickupCode, row.carrier, row.trackingNumber].allSatisfy({ !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }),
                  keys.insert(key(row.carrier, row.trackingNumber)).inserted else { throw InvalidSnapshot() }
        }
        var parcels = ParcelIdentity.coalescing(original)
        // 空快照也会移出旧记录；仅处理淘宝读取来源，手动和其他平台记录不受影响。
        for index in parcels.indices where ["cainiao-web", "taobao-web"].contains(parcels[index].source ?? "") {
            parcels[index].inLatestOfficialSnapshot = false
        }
        for index in parcels.indices {
            parcels[index].credentials = parcels[index].pickupCredentials.map { credential in
                var value = credential
                if ["cainiao-web", "taobao-web"].contains(value.source) { value.isCurrent = false }
                return value
            }
        }
        for row in snapshot.parcels {
            let incoming = Parcel(id: UUID(), title: row.title, providerID: "taobao", station: row.station, pickupCode: row.pickupCode,
                                  carrier: row.carrier, trackingNumber: row.trackingNumber, addedAt: now, isDemo: false, source: "taobao-web")
            let index = try ParcelIdentity.match(incoming, in: parcels, now: now)
            var parcel = index.map { parcels[$0] } ?? Parcel(id: UUID(), title: row.title, providerID: "taobao", station: row.station,
                pickupCode: row.pickupCode, carrier: row.carrier, trackingNumber: row.trackingNumber, addedAt: now, isDemo: false, source: "taobao-web")
            parcel.providerID = "taobao"
            parcel.awaitingArrival = false
            parcel.attach(ParcelCredential(providerID: "taobao", station: row.station, pickupCode: row.pickupCode,
                                            source: "taobao-web", isCurrent: true, lastSeenAt: now))
            parcel.station = row.station
            parcel.pickupCode = row.pickupCode
            parcel.carrier = row.carrier
            parcel.trackingNumber = row.trackingNumber
            // 用户手动标记已取后，官方出库状态可能延迟；自动刷新不能把它反复恢复。
            parcel.source = "taobao-web"
            parcel.inLatestOfficialSnapshot = true
            parcel.lastReadAt = now
            if let index { parcels[index] = parcel } else { parcels.insert(parcel, at: 0) }
        }
        return parcels
    }

    private static func key(_ carrier: String, _ tracking: String) -> String {
        ParcelIdentity.carrier(carrier) + ":" + ParcelIdentity.text(tracking)
    }
}
