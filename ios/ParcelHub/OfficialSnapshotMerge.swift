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
        // 先更新来源状态，完整合并后再将不再待取的淘宝记录归入已取历史。
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
        for index in parcels.indices {
            let parcel = parcels[index]
            guard !parcel.isDemo, !parcel.isCollected, parcel.deletedAt == nil, parcel.awaitingArrival != true,
                  !parcel.isPending,
                  parcel.pickupCredentials.contains(where: { ["cainiao-web", "taobao-web"].contains($0.source) }) else { continue }
            // 官方没有返回实际出库时间，按本次同步时间归档，并在界面注明。
            parcels[index].collectedAt = now
            parcels[index].collectionConfirmedBySync = true
        }
        return parcels
    }

    private static func key(_ carrier: String, _ tracking: String) -> String {
        ParcelIdentity.carrier(carrier) + ":" + ParcelIdentity.text(tracking)
    }
}
