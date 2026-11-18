import Foundation
import SwiftData
import SwiftUI
import UIKit

/// 學習資料的匯出格式（手機 → Mac 的 merge_vocab.py，或換機/重裝時匯回）
struct LearningExport: Codable {
    static let formatID = "mskecho-learning"

    struct Term: Codable {
        var text: String
        var aliases: [String]
    }
    struct Rule: Codable {
        var from: String
        var to: String
        var hitCount: Int
        var isActive: Bool
    }

    var format: String = LearningExport.formatID
    var version: Int = 1
    var exportedAt: Date
    var appVersion: String
    var userTerms: [Term]
    var rules: [Rule]
    /// 定稿句子（選擇性；可能含臨床內容，預設不匯出）
    var sentences: [String]?
}

enum LearningSync {
    enum SyncError: LocalizedError {
        case wrongFormat
        var errorDescription: String? { "這不是 MSKEcho 的學習資料檔" }
    }

    struct ImportResult {
        var newTerms = 0
        var mergedTerms = 0
        var newRules = 0
        var updatedRules = 0
        var skippedSentences = 0

        var summary: String {
            var s = "匯入完成：新增 \(newTerms) 個詞彙、\(newRules) 條規則"
            if mergedTerms + updatedRules > 0 { s += "，更新 \(mergedTerms + updatedRules) 筆既有資料" }
            if skippedSentences > 0 { s += "。檔案內的 \(skippedSentences) 句定稿句子請用 Mac 的 merge_vocab.py 併入內建詞庫" }
            return s
        }
    }

    // MARK: - Export

    static func export(context: ModelContext, includeSentences: Bool) throws -> URL {
        let terms = try context.fetch(FetchDescriptor<UserTerm>(sortBy: [SortDescriptor(\.createdAt)]))
        let rules = try context.fetch(FetchDescriptor<LearnedRule>(sortBy: [SortDescriptor(\.createdAt)]))

        var sentences: [String]?
        if includeSentences {
            let reports = try context.fetch(FetchDescriptor<DictationReport>(predicate: #Predicate { $0.isFinalized }))
            var seen = Set<String>()
            sentences = reports.flatMap { CustomLMTrainer.splitSentences($0.finalText) }
                .filter { seen.insert($0).inserted }
        }

        let payload = LearningExport(
            exportedAt: .now,
            appVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?",
            userTerms: terms.map { .init(text: $0.text, aliases: $0.aliases) },
            rules: rules.map { .init(from: $0.from, to: $0.to, hitCount: $0.hitCount, isActive: $0.isActive) },
            sentences: sentences
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(payload)

        let stamp = DateFormatter()
        stamp.dateFormat = "yyyyMMdd-HHmm"
        stamp.locale = Locale(identifier: "en_US_POSIX")
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("MSKEcho-learning-\(stamp.string(from: .now)).json")
        try data.write(to: url, options: .atomic)
        return url
    }

    // MARK: - Import（合併，不會刪除手機上既有資料）

    static func importFile(_ url: URL, context: ModelContext) throws -> ImportResult {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let payload = try decoder.decode(LearningExport.self, from: Data(contentsOf: url))
        guard payload.format == LearningExport.formatID else { throw SyncError.wrongFormat }

        var result = ImportResult()

        for t in payload.userTerms {
            let text = t.text
            if let existing = try context.fetch(FetchDescriptor<UserTerm>(predicate: #Predicate { $0.text == text })).first {
                let merged = Array(Set(existing.aliases + t.aliases)).sorted()
                if merged != existing.aliases.sorted() {
                    existing.aliases = merged
                    result.mergedTerms += 1
                }
            } else {
                context.insert(UserTerm(text: t.text, aliases: t.aliases))
                result.newTerms += 1
            }
        }

        for r in payload.rules {
            let key = LearnedRule.makeKey(from: r.from, to: r.to)
            if let existing = try context.fetch(FetchDescriptor<LearnedRule>(predicate: #Predicate { $0.key == key })).first {
                let count = max(existing.hitCount, r.hitCount)
                let active = existing.isActive || r.isActive
                if count != existing.hitCount || active != existing.isActive {
                    existing.hitCount = count
                    existing.isActive = active
                    result.updatedRules += 1
                }
            } else {
                let rule = LearnedRule(from: r.from, to: r.to)
                rule.hitCount = r.hitCount
                rule.isActive = r.isActive
                context.insert(rule)
                result.newRules += 1
            }
        }

        result.skippedSentences = payload.sentences?.count ?? 0
        try context.save()
        return result
    }
}

/// iOS 分享面板（AirDrop 到 Mac、存到「檔案」）
struct ShareSheet: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

struct ExportFile: Identifiable {
    let id = UUID()
    let url: URL
}
