import Foundation

@main
struct OfficialSnapshotTests {
    static func main() throws {
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
        precondition(first.count == 1 && first[0].providerID == "taobao" && first[0].pickupCode == "01-02-0003")
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
        let cleared = try OfficialSnapshotMerge.applying(empty, to: original)
        precondition(cleared.count == 4 && cleared[0].inLatestOfficialSnapshot == false)
        precondition(cleared[1].inLatestOfficialSnapshot == true && cleared[2].inLatestOfficialSnapshot == true)
        precondition(cleared[3].collectedAt == now && cleared[3].inLatestOfficialSnapshot == false)
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
        var deleted = merged[0]
        deleted.collectedAt = now; deleted.deletedAt = now; deleted.smsOriginal = nil
        let noResurrection = try OfficialSnapshotMerge.applying(snapshot, to: [deleted], now: now)
        precondition(noResurrection.count == 1 && !noResurrection[0].isPending && noResurrection[0].smsOriginal == nil)
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
        print("Native snapshot checks passed: empty, legacy migration, source isolation, history, leading zeros, errors and duplicate guards")
    }
}
