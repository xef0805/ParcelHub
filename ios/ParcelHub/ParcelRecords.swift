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

    var isCollected: Bool { collectedAt != nil }
    var hasSMS: Bool { !(smsOriginal ?? "").isEmpty }
    var pickupCredentials: [ParcelCredential] {
        credentials ?? [ParcelCredential(providerID: providerID, station: station, pickupCode: pickupCode,
                                          source: source ?? "manual", isCurrent: inLatestOfficialSnapshot != false, lastSeenAt: lastReadAt ?? addedAt)]
    }
    var isPending: Bool {
        guard !isDemo, !isCollected, deletedAt == nil, awaitingArrival != true else { return false }
        let official = pickupCredentials.filter { $0.source.hasSuffix("-web") }
        return official.isEmpty ? inLatestOfficialSnapshot != false : official.contains { $0.isCurrent }
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
                result[index].collectedAt = [result[index].collectedAt, parcel.collectedAt].compactMap { $0 }.max()
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
}

struct OfficialPageRead: Codable, Equatable {
    var state: String
    var message: String
    var parcels: [OfficialParcelRead]
    var expectedCount: Int?
    var readAt: String
}

enum AppServiceIssue: Error, LocalizedError, Equatable {
    case offline, timeout, login, wechatMissing, openFailed, expiredLink, unavailable, incomplete
    var message: String {
        switch self {
        case .offline: return "当前网络不可用，已保留本地包裹。请联网后重试。"
        case .timeout: return "连接超时，已保留本地包裹。请稍后重试。"
        case .login: return "淘宝登录已失效或尚未登录，已保留本地包裹。请重新登录后刷新。"
        case .wechatMissing: return "未检测到可用的微信。请先安装或打开微信，再返回重试。"
        case .openFailed: return "无法打开微信。请手动打开微信后重试；仍失败时请重新获取小程序链接。"
        case .expiredLink: return "链接已失效或无法核对目标。请在对应小程序重新获取完整链接，原绑定已保留。"
        case .unavailable: return "官方服务暂时不可用，已保留本地记录。请稍后重试。"
        case .incomplete: return "尚未完整读取官方清单，已保留本地包裹。请稍后刷新。"
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
