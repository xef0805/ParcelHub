import Foundation

struct ParcelCredential: Codable, Equatable {
    var providerID: String
    var station: String
    var pickupCode: String
    var source: String
    var isCurrent: Bool
    var lastSeenAt: Date
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
    var smsOriginal: String? = nil
    var smsSender: String? = nil
    var smsImportedAt: Date? = nil
    var smsFingerprint: String? = nil
    var credentials: [ParcelCredential]? = nil
    var deletedAt: Date? = nil
    var awaitingArrival: Bool? = nil
    var manualPendingOverride: Bool? = nil
    var collectionConfirmedBySync: Bool? = nil
    var arrivedOn: String? = nil

    var isCollected: Bool { collectedAt != nil }
    var hasSMS: Bool { !(smsOriginal ?? "").isEmpty }
    var pickupCredentials: [ParcelCredential] {
        credentials ?? [ParcelCredential(providerID: providerID, station: station, pickupCode: pickupCode,
                                          source: source ?? "manual", isCurrent: inLatestOfficialSnapshot != false, lastSeenAt: lastReadAt ?? addedAt)]
    }
    var isPending: Bool {
        guard !isDemo, !isCollected, deletedAt == nil, awaitingArrival != true else { return false }
        if manualPendingOverride == true { return true }
        let official = pickupCredentials.filter { $0.source.hasSuffix("-web") }
        return official.isEmpty ? inLatestOfficialSnapshot != false : official.contains { $0.isCurrent }
    }

    mutating func toggleCollected(now: Date = Date()) {
        guard deletedAt == nil else { return }
        let restoring = isCollected
        collectedAt = restoring ? nil : now
        collectionConfirmedBySync = nil
        // 手动恢复独立于官方清单；不能把过期的官方凭证标记为仍然有效。
        manualPendingOverride = restoring ? true : nil
    }

    mutating func attach(_ credential: ParcelCredential) {
        var all = pickupCredentials
        if let index = all.firstIndex(where: { $0.providerID == credential.providerID && $0.source == credential.source && $0.station == credential.station }) {
            all[index] = credential
        } else { all.append(credential) }
        credentials = all
    }

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

enum ParcelIdentity {
    struct Ambiguous: LocalizedError { var errorDescription: String? { "有多条可能相同的记录，请补全快递公司和完整运单号后再导入" } }
    static func text(_ value: String) -> String {
        value.precomposedStringWithCompatibilityMapping.components(separatedBy: .whitespacesAndNewlines).joined().uppercased()
    }
    static func carrier(_ value: String) -> String {
        let aliases = [("菜鸟速递", ["菜鸟速递", "丹鸟"]), ("韵达", ["韵达", "YUNDA"]), ("中通", ["中通", "ZTO"]),
                       ("圆通", ["圆通", "YTO"]), ("申通", ["申通", "STO"]), ("顺丰", ["顺丰", "SF", "S.F."]),
                       ("京东", ["京东", "JDL"]), ("极兔", ["极兔", "J&T"]), ("德邦", ["德邦", "DEPPON"]), ("EMS", ["EMS"]), ("邮政", ["邮政"])]
        let clean = text(value)
        return aliases.first { pair in pair.1.contains { clean.contains($0) } }?.0 ?? clean
    }
    static func fullTracking(_ value: String) -> Bool {
        let clean = text(value)
        return clean.count >= 6 && clean.count <= 40 && clean.range(of: "^[A-Z0-9-]+$", options: .regularExpression) != nil
    }
    static func fingerprint(_ value: String) -> String {
        var hash: UInt64 = 14695981039346656037
        for byte in text(value).utf8 { hash = (hash ^ UInt64(byte)) &* 1099511628211 }
        return String(hash, radix: 16)
    }
    static func coalescing(_ records: [Parcel]) -> [Parcel] {
        var result: [Parcel] = []
        for parcel in records {
            if !parcel.isDemo, fullTracking(parcel.trackingNumber), !carrier(parcel.carrier).isEmpty,
               let index = result.firstIndex(where: { !$0.isDemo && text($0.trackingNumber) == text(parcel.trackingNumber) && carrier($0.carrier) == carrier(parcel.carrier) }) {
                for credential in parcel.pickupCredentials { result[index].attach(credential) }
                result[index].addedAt = min(result[index].addedAt, parcel.addedAt)
                result[index].awaitingArrival = (result[index].awaitingArrival == true && parcel.awaitingArrival == true)
                if result[index].arrivedOn == nil && text(result[index].station) == text(parcel.station) {
                    result[index].arrivedOn = parcel.arrivedOn
                }
                if let date = parcel.collectedAt, date >= (result[index].collectedAt ?? .distantPast) {
                    result[index].collectedAt = date
                    result[index].collectionConfirmedBySync = parcel.collectionConfirmedBySync
                }
                result[index].manualPendingOverride = (result[index].manualPendingOverride == true || parcel.manualPendingOverride == true) ? true : nil
                result[index].deletedAt = result[index].deletedAt ?? parcel.deletedAt
                result[index].smsFingerprint = result[index].smsFingerprint ?? parcel.smsFingerprint ?? parcel.smsOriginal.map { fingerprint($0) }
                if parcel.hasSMS && (!result[index].hasSMS || (parcel.smsImportedAt ?? .distantPast) > (result[index].smsImportedAt ?? .distantPast)) {
                    result[index].smsOriginal = parcel.smsOriginal; result[index].smsSender = parcel.smsSender; result[index].smsImportedAt = parcel.smsImportedAt
                    result[index].smsFingerprint = parcel.smsFingerprint ?? parcel.smsOriginal.map { fingerprint($0) }
                }
                if result[index].deletedAt != nil { result[index].smsOriginal = nil; result[index].smsSender = nil; result[index].smsImportedAt = nil }
            } else { result.append(parcel) }
        }
        return result
    }
    static func match(_ incoming: Parcel, in records: [Parcel], now: Date = Date()) throws -> Int? {
        let number = text(incoming.trackingNumber), company = carrier(incoming.carrier)
        func compatible(_ parcel: Parcel) -> Bool {
            let existing = carrier(parcel.carrier)
            return company.isEmpty || existing.isEmpty || company == existing
        }
        let strong = records.indices.filter { !records[$0].isDemo && fullTracking(number) && fullTracking(records[$0].trackingNumber)
            && text(records[$0].trackingNumber) == number && compatible(records[$0]) }
        if strong.count > 1 { throw Ambiguous() }
        if let first = strong.first { return first }
        let weak = records.indices.filter { index in
            let parcel = records[index]
            guard !parcel.isDemo, compatible(parcel), abs(now.timeIntervalSince(parcel.addedAt)) < 72 * 3600 else { return false }
            if fullTracking(number), fullTracking(parcel.trackingNumber), text(parcel.trackingNumber) != number { return false }
            let incomingFingerprint = incoming.smsFingerprint ?? incoming.smsOriginal.map { fingerprint($0) }
            let previousFingerprint = parcel.smsFingerprint ?? parcel.smsOriginal.map { fingerprint($0) }
            if let incomingFingerprint, incomingFingerprint == previousFingerprint { return true }
            return !parcel.isCollected && parcel.deletedAt == nil && !company.isEmpty && carrier(parcel.carrier) == company
                && text(parcel.station) == text(incoming.station) && text(parcel.pickupCode) == text(incoming.pickupCode)
        }
        if weak.count > 1 { throw Ambiguous() }
        return weak.first
    }
}

struct OfficialParcelRead: Codable, Equatable {
    var providerID: String
    var title: String
    var station: String
    var pickupCode: String
    var carrier: String
    var trackingNumber: String
    var arrivalDaysAgo: Int? = nil
}

enum ParcelArrival {
    private static func formatter(calendar: Calendar) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.isLenient = false
        return formatter
    }

    static func day(for date: Date, calendar: Calendar = Calendar(identifier: .gregorian)) -> String {
        formatter(calendar: calendar).string(from: date)
    }

    static func isSelectable(_ day: String, now: Date = Date(), calendar: Calendar = Calendar(identifier: .gregorian)) -> Bool {
        guard let days = daysAgo(on: day, now: now, calendar: calendar) else { return false }
        return days <= 7
    }

    static func day(daysAgo: Int?, readAt: String, calendar: Calendar = Calendar(identifier: .gregorian)) -> String? {
        guard let daysAgo, (0...3650).contains(daysAgo) else { return nil }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let fractional = iso.date(from: readAt)
        iso.formatOptions = [.withInternetDateTime]
        guard let readDate = fractional ?? iso.date(from: readAt),
              let arrival = calendar.date(byAdding: .day, value: -daysAgo, to: readDate) else { return nil }
        return formatter(calendar: calendar).string(from: arrival)
    }

    static func daysAgo(on day: String?, now: Date = Date(), calendar: Calendar = Calendar(identifier: .gregorian)) -> Int? {
        guard let day, day.count == 10 else { return nil }
        let format = formatter(calendar: calendar)
        guard let date = format.date(from: day), format.string(from: date) == day,
              let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: date), to: calendar.startOfDay(for: now)).day,
              days >= 0 else { return nil }
        return days
    }
}

enum ParcelNaming {
    static func nextTitle(in parcels: [Parcel], date: Date = Date()) -> String {
        let calendar = Calendar(identifier: .gregorian)
        let day = ParcelArrival.day(for: date, calendar: calendar)
        let compact = day.replacingOccurrences(of: "-", with: "")
        let short = String(compact.suffix(4))
        var next = 1
        for parcel in parcels where !parcel.isDemo && calendar.component(.year, from: parcel.addedAt) == calendar.component(.year, from: date) {
            let prefix = [compact, day + " ", short].first { parcel.title.hasPrefix($0) }
            guard let prefix else { continue }
            let suffix = String(parcel.title.dropFirst(prefix.count))
            guard suffix.range(of: "^(?:包裹|快件)[0-9]+号$", options: .regularExpression) != nil,
                  let serial = Int(suffix.dropFirst(2).dropLast()), serial < Int.max else { continue }
            next = max(next, serial + 1)
        }
        return "\(short)包裹\(next)号"
    }
}

struct OfficialPageRead: Codable, Equatable {
    var state: String
    var message: String
    var parcels: [OfficialParcelRead]
    var expectedCount: Int?
    var readAt: String
}

struct OfficialEmptyConfirmation {
    private var previousEmptyAt: Date?

    mutating func reset() { previousEmptyAt = nil }

    /// 同一页面连续两次独立读取为空才更新；相同快照重放和加载失败不能算确认。
    mutating func accepting(_ snapshot: OfficialPageRead) -> OfficialPageRead {
        guard snapshot.state == "filtered_empty", snapshot.parcels.isEmpty,
              snapshot.expectedCount == nil || snapshot.expectedCount == 0 else {
            reset(); return snapshot
        }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let readAt = formatter.date(from: snapshot.readAt) else { reset(); return snapshot }
        let previous = previousEmptyAt
        previousEmptyAt = readAt
        guard let previous, readAt > previous, readAt.timeIntervalSince(previous) <= 5 else { return snapshot }
        reset()
        var confirmed = snapshot
        confirmed.state = "ready"
        confirmed.expectedCount = 0
        confirmed.message = "已确认淘宝当前待取页为空"
        return confirmed
    }
}

enum OfficialAuthenticationFlow {
    /// 与淘宝页面公开 lib-login 的 generateUrl 使用相同的官方入口和 redirectURL 参数。
    static func logoutURL(returningTo destination: URL) -> URL? {
        guard destination.scheme == "https", destination.host == "pages-fast.m.taobao.com" else { return nil }
        var login = URLComponents(string: "https://login.m.taobao.com/login.htm")!
        login.queryItems = [URLQueryItem(name: "redirectURL", value: destination.absoluteString)]
        guard let loginURL = login.url else { return nil }
        var logout = URLComponents(string: "https://login.m.taobao.com/logout.htm")!
        logout.queryItems = [URLQueryItem(name: "redirectURL", value: loginURL.absoluteString)]
        return logout.url
    }
}

enum AppServiceIssue: Error, LocalizedError, Equatable {
    case offline, timeout, login, wechatMissing, openFailed, expiredLink, unavailable, incomplete, phoneFilter
    var message: String {
        switch self {
        case .offline: return "网络未连接，记录已保留"
        case .timeout: return "连接超时，记录已保留"
        case .login: return "请重新登录淘宝，记录已保留"
        case .wechatMissing: return "未检测到微信，请先安装或打开"
        case .openFailed: return "微信未打开，请重试"
        case .expiredLink: return "请重新获取链接，原绑定已保留"
        case .unavailable: return "暂时无法连接，记录已保留"
        case .incomplete: return "清单未读完整，记录已保留"
        case .phoneFilter: return "正在确认空清单，记录暂时保留"
        }
    }
    var errorDescription: String? { message }
    static func from(_ error: Error) -> AppServiceIssue {
        if let issue = error as? AppServiceIssue { return issue }
        let native = error as NSError
        guard native.domain == NSURLErrorDomain else { return .unavailable }
        switch native.code {
        case NSURLErrorNotConnectedToInternet, NSURLErrorNetworkConnectionLost, NSURLErrorDataNotAllowed: return .offline
        case NSURLErrorTimedOut: return .timeout
        default: return .unavailable
        }
    }
}
