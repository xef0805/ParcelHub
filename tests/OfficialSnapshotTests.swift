import Foundation

@main
struct OfficialSnapshotTests {
    static func main() throws {
        var arrivalCalendar = Calendar(identifier: .gregorian)
        arrivalCalendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let arrivalReadAt = "2026-10-31T23:58:00.000Z"
        precondition(ParcelArrival.day(daysAgo: 2, readAt: arrivalReadAt, calendar: arrivalCalendar) == "2026-10-29")
        precondition(ParcelArrival.day(daysAgo: -1, readAt: arrivalReadAt, calendar: arrivalCalendar) == nil)
        precondition(ParcelArrival.day(daysAgo: 1, readAt: "invalid", calendar: arrivalCalendar) == nil)
        let nextDay = ISO8601DateFormatter().date(from: "2026-11-01T00:01:00Z")!
        precondition(ParcelArrival.daysAgo(on: "2026-10-31", now: nextDay, calendar: arrivalCalendar) == 1)
        precondition(ParcelArrival.daysAgo(on: "2026-02-30", now: nextDay, calendar: arrivalCalendar) == nil)
        precondition(ParcelArrival.daysAgo(on: "2026-11-02", now: nextDay, calendar: arrivalCalendar) == nil)
        precondition(ParcelArrival.isSelectable("2026-10-25", now: nextDay, calendar: arrivalCalendar))
        precondition(!ParcelArrival.isSelectable("2026-10-24", now: nextDay, calendar: arrivalCalendar))
        let destination = URL(string: "https://pages-fast.m.taobao.com/wow/z/uniapp/test/home?first=1&second=2")!
        let logout = OfficialAuthenticationFlow.logoutURL(returningTo: destination)!
        precondition(logout.host == "login.m.taobao.com" && logout.path == "/logout.htm")
        let loginValue = URLComponents(url: logout, resolvingAgainstBaseURL: false)!.queryItems!.first { $0.name == "redirectURL" }!.value!
        let login = URLComponents(string: loginValue)!
        precondition(login.host == "login.m.taobao.com" && login.path == "/login.htm")
        precondition(login.queryItems!.first { $0.name == "redirectURL" }!.value == destination.absoluteString)
        precondition(OfficialAuthenticationFlow.logoutURL(returningTo: URL(string: "https://pages-fast.m.taobao.com.example.org/")!) == nil)
        precondition(OfficialAuthenticationFlow.logoutURL(returningTo: URL(string: "http://pages-fast.m.taobao.com/")!) == nil)
        precondition(AppServiceIssue.from(URLError(.notConnectedToInternet)) == .offline)
        precondition(AppServiceIssue.from(URLError(.networkConnectionLost)) == .offline)
        precondition(AppServiceIssue.from(URLError(.timedOut)) == .timeout)
        precondition(AppServiceIssue.from(AppServiceIssue.expiredLink) == .expiredLink)
        precondition(AppServiceIssue.from(NSError(domain: "other", code: -1009)) == .unavailable)
        let now = Date(timeIntervalSince1970: 1_000)
        let row = OfficialParcelRead(providerID: "cainiao", title: "测试包裹", station: "测试驿站", pickupCode: "01-02-0003", carrier: "中通", trackingNumber: "TEST00001")
        let snapshot = OfficialPageRead(state: "ready", message: "", parcels: [row], expectedCount: 1, readAt: "test")
        let first = try OfficialSnapshotMerge.applying(snapshot, to: [], now: now)
        var datedSnapshot = snapshot
        datedSnapshot.readAt = arrivalReadAt
        datedSnapshot.parcels[0].arrivalDaysAgo = 2
        let dated = try OfficialSnapshotMerge.applying(datedSnapshot, to: [], now: now)
        precondition(dated[0].arrivedOn != nil)
        let sameStation = try OfficialSnapshotMerge.applying(snapshot, to: dated, now: now)
        precondition(sameStation[0].arrivedOn == dated[0].arrivedOn)
        var staleArrivalSnapshot = datedSnapshot
        staleArrivalSnapshot.readAt = "2026-11-01T09:00:00.000Z"
        staleArrivalSnapshot.parcels[0].arrivalDaysAgo = 0
        let staleArrival = try OfficialSnapshotMerge.applying(staleArrivalSnapshot, to: dated, now: nextDay)
        precondition(staleArrival[0].arrivedOn == dated[0].arrivedOn)
        let persistedArrival = try JSONDecoder().decode(Parcel.self, from: JSONEncoder().encode(dated[0]))
        precondition(persistedArrival.arrivedOn == dated[0].arrivedOn)
        var movedSnapshot = snapshot
        movedSnapshot.parcels[0].station = "另一测试驿站"
        let movedStation = try OfficialSnapshotMerge.applying(movedSnapshot, to: dated, now: now)
        precondition(movedStation[0].arrivedOn == nil)
        precondition(first.count == 1 && first[0].providerID == "taobao" && first[0].pickupCode == "01-02-0003")
        precondition(first[0].title.hasSuffix("包裹1号"))
        precondition(ParcelNaming.nextTitle(in: first, date: now).hasSuffix("包裹2号"))
        let renamedAgain = try OfficialSnapshotMerge.applying(snapshot, to: first, now: now)
        precondition(renamedAgain[0].title == first[0].title)
        var watched = Parcel(id: UUID(), title: "单号导入测试", providerID: "manual", station: "", pickupCode: "", carrier: row.carrier,
                             trackingNumber: row.trackingNumber, addedAt: now, isDemo: false, source: "tracking")
        watched.awaitingArrival = true
        precondition(!watched.isPending)
        let arrived = try OfficialSnapshotMerge.applying(snapshot, to: [watched], now: now)
        precondition(arrived.count == 1 && arrived[0].id == watched.id && arrived[0].isPending && arrived[0].awaitingArrival == false)
        var legacy = first[0]
        legacy.source = "cainiao-web"
        legacy.providerID = "cainiao"
        var manual = first[0]
        manual.id = UUID(); manual.source = nil; manual.providerID = "fcbox"; manual.trackingNumber = "MANUAL00001"; manual.credentials = nil
        var other = first[0]
        other.id = UUID(); other.source = "tuxi-web"; other.providerID = "tuxi"; other.trackingNumber = "TUXI00001"; other.credentials = nil
        var collected = first[0]
        collected.id = UUID(); collected.collectedAt = now; collected.trackingNumber = "COLLECTED00001"; collected.credentials = nil
        let original = [legacy, manual, other, collected]
        var confirmation = OfficialEmptyConfirmation()
        let emptyCandidate = OfficialPageRead(state: "filtered_empty", message: "", parcels: [], expectedCount: nil, readAt: "2026-10-31T04:00:00.000Z")
        var repeatedEmpty = emptyCandidate
        repeatedEmpty.readAt = "2026-10-31T04:00:00.750Z"
        precondition(confirmation.accepting(emptyCandidate).state == "filtered_empty")
        precondition(confirmation.accepting(emptyCandidate).state == "filtered_empty", "Cached snapshot replay is not a second read")
        let confirmedEmpty = confirmation.accepting(repeatedEmpty)
        precondition(confirmedEmpty.state == "ready" && confirmedEmpty.expectedCount == 0)
        let afterPickup = try OfficialSnapshotMerge.applying(confirmedEmpty, to: original)
        precondition(!afterPickup[0].isPending && afterPickup[1].isPending && afterPickup[2].isPending)
        precondition(afterPickup[0].isCollected && afterPickup[0].collectionConfirmedBySync == true)
        precondition(afterPickup[3].collectedAt == now && afterPickup.count == original.count)
        confirmation.reset()
        _ = confirmation.accepting(emptyCandidate)
        _ = confirmation.accepting(OfficialPageRead(state: "login_required", message: "", parcels: [], expectedCount: nil, readAt: ""))
        precondition(confirmation.accepting(repeatedEmpty).state == "filtered_empty", "Login failure resets empty confirmation")
        confirmation.reset()
        _ = confirmation.accepting(emptyCandidate)
        var staleEmpty = repeatedEmpty
        staleEmpty.readAt = "2026-10-31T04:00:06.000Z"
        precondition(confirmation.accepting(staleEmpty).state == "filtered_empty")
        let empty = OfficialPageRead(state: "ready", message: "", parcels: [], expectedCount: 0, readAt: "test")
        let cleared = try OfficialSnapshotMerge.applying(empty, to: original, now: now)
        precondition(cleared.count == 4 && cleared[0].inLatestOfficialSnapshot == false)
        precondition(cleared[1].inLatestOfficialSnapshot == true && cleared[2].inLatestOfficialSnapshot == true)
        precondition(cleared[3].collectedAt == now && cleared[3].inLatestOfficialSnapshot == false)
        precondition(cleared[0].collectedAt == now && cleared[0].collectionConfirmedBySync == true)
        precondition(!cleared[1].isCollected && !cleared[2].isCollected)
        var restored = cleared[0]
        restored.toggleCollected(now: now)
        precondition(restored.isPending && !restored.isCollected && restored.collectionConfirmedBySync == nil)
        precondition(restored.inLatestOfficialSnapshot == false && !restored.pickupCredentials[0].isCurrent)
        let reloaded = try JSONDecoder().decode(Parcel.self, from: JSONEncoder().encode(restored))
        let restoredWithOfficial = try OfficialSnapshotMerge.applying(snapshot, to: [reloaded], now: now)
        var refreshed = try OfficialSnapshotMerge.applying(empty, to: restoredWithOfficial, now: now)
        precondition(refreshed.count == 1 && refreshed[0].id == restored.id && refreshed[0].isPending)
        refreshed[0].toggleCollected(now: now)
        let markedAgain = try OfficialSnapshotMerge.applying(snapshot, to: refreshed, now: now)
        precondition(markedAgain[0].isCollected && !markedAgain[0].isPending && markedAgain[0].collectionConfirmedBySync == nil)
        var restoredBeforeEmpty = first[0]
        restoredBeforeEmpty.toggleCollected(now: now)
        restoredBeforeEmpty.toggleCollected(now: now)
        let keptRestored = try OfficialSnapshotMerge.applying(empty, to: [restoredBeforeEmpty], now: now)
        precondition(keptRestored[0].isPending)
        // 旧版隐藏的记录在成功读取后归档，原数据与标识不丢失。
        var oldHidden = cleared[0]
        oldHidden.collectedAt = nil; oldHidden.collectionConfirmedBySync = nil
        let recovered = try OfficialSnapshotMerge.applying(empty, to: [oldHidden], now: now)
        precondition(recovered[0].id == oldHidden.id && recovered[0].isCollected)
        let repeatedArchive = try OfficialSnapshotMerge.applying(empty, to: recovered, now: now.addingTimeInterval(60))
        precondition(repeatedArchive[0].collectedAt == now)
        precondition(original[0].inLatestOfficialSnapshot == true)
        let updated = try OfficialSnapshotMerge.applying(snapshot, to: [legacy, other])
        precondition(updated.count == 2 && updated[0].id == legacy.id && updated[0].providerID == "taobao")
        precondition(updated[1].source == "tuxi-web")
        var same = other
        same.trackingNumber = row.trackingNumber; same.carrier = "中通快递"; same.pickupCode = "R-001"
        same.smsOriginal = "【中通】测试通知，取件码R-001。"; same.smsImportedAt = now
        let merged = try OfficialSnapshotMerge.applying(snapshot, to: [same], now: now)
        precondition(merged.count == 1 && merged[0].id == same.id && merged[0].smsOriginal == same.smsOriginal)
        precondition(merged[0].pickupCredentials.count == 2, "Keep each source credential while deduplicating the physical parcel")
        let otherStillPending = try OfficialSnapshotMerge.applying(empty, to: merged, now: now)
        precondition(otherStillPending[0].isPending && !otherStillPending[0].isCollected)
        var deleted = merged[0]
        deleted.collectedAt = now; deleted.deletedAt = now; deleted.smsOriginal = nil
        let noResurrection = try OfficialSnapshotMerge.applying(snapshot, to: [deleted], now: now)
        precondition(noResurrection.count == 1 && !noResurrection[0].isPending && noResurrection[0].smsOriginal == nil)
        deleted.toggleCollected(now: now)
        precondition(deleted.isCollected && deleted.deletedAt == now)
        let deletedAfterEmpty = try OfficialSnapshotMerge.applying(empty, to: [deleted], now: now)
        precondition(deletedAfterEmpty[0].deletedAt == now && deletedAfterEmpty[0].collectionConfirmedBySync == nil)
        let legacyDuplicates = ParcelIdentity.coalescing([same, merged[0]])
        precondition(legacyDuplicates.count == 1 && legacyDuplicates[0].pickupCredentials.count == 2)
        var matchingCollected = first[0]
        matchingCollected.collectedAt = now
        let delayed = try OfficialSnapshotMerge.applying(snapshot, to: [matchingCollected])
        precondition(delayed[0].collectedAt == now, "Auto refresh must preserve manual collection while official status is delayed")
        for invalid in [
            OfficialPageRead(state: "error", message: "请求超时", parcels: [], expectedCount: 0, readAt: "test"),
            OfficialPageRead(state: "filtered_empty", message: "网页未返回当前手机号的包裹", parcels: [], expectedCount: nil, readAt: "test"),
            OfficialPageRead(state: "ready", message: "", parcels: [], expectedCount: nil, readAt: "test"),
            OfficialPageRead(state: "ready", message: "", parcels: [row], expectedCount: 2, readAt: "test"),
            OfficialPageRead(state: "ready", message: "", parcels: [row, row], expectedCount: 2, readAt: "test")
        ] {
            do {
                _ = try OfficialSnapshotMerge.applying(invalid, to: original)
                fatalError("Invalid snapshot must not overwrite records")
            } catch is OfficialSnapshotMerge.InvalidSnapshot { }
        }
        // 用户操作撤销必须与真实官方合并共存，不能回滚整份存档。
        var noteParcel = first[0]
        noteParcel.note = "帮家人取"
        let noteMerged = try OfficialSnapshotMerge.applying(snapshot, to: [noteParcel], now: now)
        precondition(noteMerged[0].note == "帮家人取")
        let savedNote = try JSONDecoder().decode(Parcel.self, from: JSONEncoder().encode(noteMerged[0]))
        precondition(savedNote.note == "帮家人取")
        var marked = noteParcel
        marked.toggleCollected(now: now)
        let receipt = ParcelUndo(kind: .collection, before: [noteParcel], after: [marked], message: "test")
        var duringSync = try OfficialSnapshotMerge.applying(OfficialPageRead(state: "ready", message: "", parcels: [], expectedCount: 0, readAt: "test"), to: [marked], now: now)
        duringSync[0].note = "新备注"
        var unrelated = first[0]; unrelated.id = UUID(); unrelated.trackingNumber = "TEST999999"
        duringSync.append(unrelated)
        let undone = receipt.applying(to: duringSync)
        precondition(undone.restored == 1 && undone.records.count == 2 && undone.records[0].isPending)
        precondition(undone.records[0].note == "新备注" && undone.records[0].manualPendingOverride == true)
        var changed = marked; changed.toggleCollected(now: now)
        precondition(receipt.applying(to: [changed]).restored == 0)
        var withSMS = marked
        withSMS.smsOriginal = "虚构短信"; withSMS.smsSender = "测试"; withSMS.smsImportedAt = now
        var removed = withSMS
        removed.deletedAt = now; removed.smsOriginal = nil; removed.smsSender = nil; removed.smsImportedAt = nil
        let deletion = ParcelUndo(kind: .deletion, before: [withSMS], after: [removed], message: "test")
        removed.lastReadAt = Date(timeIntervalSince1970: 2000)
        let restoredSMS = deletion.applying(to: [removed])
        precondition(restoredSMS.restored == 1 && restoredSMS.records[0].smsOriginal == "虚构短信")
        precondition(restoredSMS.records[0].lastReadAt == removed.lastReadAt && restoredSMS.records[0].collectedAt == now)
        let stationPreference = StationPreference(alias: "公司楼下", pinned: true)
        let savedPreference = try JSONDecoder().decode(StationPreference.self, from: JSONEncoder().encode(stationPreference))
        precondition(savedPreference.alias == "公司楼下" && savedPreference.pinned)
        print("Native snapshot checks passed: empty, legacy migration, source isolation, history, leading zeros, errors and duplicate guards")
    }
}
