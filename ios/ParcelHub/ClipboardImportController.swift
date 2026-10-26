import Foundation
import UIKit
import Combine
import JavaScriptCore

struct ImportTextResult: Decodable {
    let kind: String
    let text: String
    let trackingNumber: String
    let carrier: String
}

enum ImportTextReader {
    static func read(_ text: String) -> ImportTextResult? {
        guard let url = Bundle.main.url(forResource: "import-reader", withExtension: "js"),
              let script = try? String(contentsOf: url, encoding: .utf8), let context = JSContext(),
              let data = try? JSONEncoder().encode(text), let input = String(data: data, encoding: .utf8),
              let result = context.evaluateScript("JSON.stringify((\(script))(\(input)))")?.toString(),
              context.exception == nil, let json = result.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(ImportTextResult.self, from: json)
    }
}

struct PackageImportRequest: Identifiable, Equatable {
    let id = UUID()
    var kind: String
    var text: String = ""
    var carrier: String = ""
}

@MainActor
final class ClipboardImportController: ObservableObject {
    @Published private(set) var candidate: ImportTextResult?
    @Published var request: PackageImportRequest?
    @Published var isEditing = false
    @Published var enabled = UserDefaults.standard.object(forKey: "parcelhub.clipboard-detection.v1") as? Bool ?? true {
        didSet {
            UserDefaults.standard.set(enabled, forKey: "parcelhub.clipboard-detection.v1")
            if !enabled { candidate = nil }
            else { lastChangeCount = nil; check() }
        }
    }
    private var lastChangeCount: Int?

    func check() {
        guard enabled else { return }
        let board = UIPasteboard.general
        guard lastChangeCount != board.changeCount else { return }
        lastChangeCount = board.changeCount
        candidate = nil
        // 只在进入前台且内容变化时检测；系统的“允许粘贴”询问仍由用户决定。
        guard board.hasStrings, let text = board.string else { return }
        let recognized = ImportTextReader.read(text)
        candidate = recognized?.kind == "sms" ? recognized : nil
    }

    func openImport() {
        guard let candidate, candidate.kind == "sms" else { return }
        request = PackageImportRequest(kind: candidate.kind, text: candidate.text, carrier: candidate.carrier)
        self.candidate = nil
    }
    func dismissCandidate() { candidate = nil }
    func ignoreCurrentChange() { lastChangeCount = UIPasteboard.general.changeCount; candidate = nil }
}
