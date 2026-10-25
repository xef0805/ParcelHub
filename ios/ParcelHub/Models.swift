import Foundation
import SwiftUI
import JavaScriptCore

struct IdentityBinding: Codable, Equatable {
    var kind: String
    var value: String
    var confirmed: Bool

}

struct IdentityLinkResult: Decodable {
    var kind: String?
    var value: String?
    var message: String?
    var error: String?
    var resolvedURL: String?
}

enum IdentityLinkReader {
    static func parse(_ value: String, for provider: PickupProvider, landingHTML: String = "") -> IdentityLinkResult? {
        guard let url = Bundle.main.url(forResource: "identity-link", withExtension: "js"),
              let script = try? String(contentsOf: url, encoding: .utf8), let context = JSContext(),
              let data = try? JSONEncoder().encode([value, provider.miniProgramName, landingHTML]),
              let arguments = String(data: data, encoding: .utf8),
              let json = context.evaluateScript("JSON.stringify((\(script))(...\(arguments)))")?.toString(),
              context.exception == nil, let result = json.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(IdentityLinkResult.self, from: result)
    }

    @MainActor
    static func resolve(_ value: String, for provider: PickupProvider) async -> URL? {
        guard let parsed = parse(value, for: provider), parsed.kind == "launchURL", let url = URL(string: value) else { return nil }
        if url.scheme == "weixin" { return url }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 15
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        guard let (data, response) = try? await session.data(from: url), !Task.isCancelled,
              let response = response as? HTTPURLResponse, response.statusCode == 200,
              let finalURL = response.url, parse(finalURL.absoluteString, for: provider)?.kind == "launchURL",
              data.count <= 512_000, let html = String(data: data, encoding: .utf8),
              let result = parse(value, for: provider, landingHTML: html), let resolved = result.resolvedURL else { return nil }
        return URL(string: resolved)
    }
}

struct PickupProvider: Codable, Identifiable, Hashable {
    var id: String
    var name: String
    var shortName: String
    var color: String
    var symbol: String
    var miniProgramName: String
    var website: String
    var kind: String
    var featured: Bool
    var identityURL: String? = nil
    var parcelsURL: String? = nil
    var appStoreURL: String? = nil
    var miniProgramURL: String? = nil

    var tint: Color {
        let value = UInt64(color.trimmingCharacters(in: CharacterSet(charactersIn: "#")), radix: 16) ?? 0x479981
        return Color(red: Double((value >> 16) & 255) / 255,
                     green: Double((value >> 8) & 255) / 255,
                     blue: Double(value & 255) / 255)
    }
}

enum CarrierBrand {
    static func asset(for carrier: String) -> String? {
        let values = [("韵达", "yunda"), ("中通", "zto"), ("申通", "sto"), ("圆通", "yto"),
                      ("顺丰", "sf"), ("京东", "jd"), ("极兔", "jtexpress"), ("德邦", "deppon"),
                      ("EMS", "ems"), ("邮政", "post"), ("菜鸟", "cainiao")]
        return values.first { carrier.localizedCaseInsensitiveContains($0.0) }.map { "Brand-" + $0.1 }
    }
}

enum ParcelDraftValidator {
    static func validate(title: String, station: String, code: String, providerID: String, providers: [PickupProvider]) -> String? {
        if title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "请填写包裹名称" }
        if station.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "请填写取件地点" }
        if code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "请填写取件码" }
        if !providers.contains(where: { $0.id == providerID }) { return "请选择取件平台" }
        if title.count > 60 || station.count > 100 || code.count > 40 { return "填写内容过长，请缩短后重试" }
        return nil
    }
}
