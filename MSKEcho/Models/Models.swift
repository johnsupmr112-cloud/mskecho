import Foundation
import SwiftData

/// 一份口述報告。rawText＝辨識原文、autoText＝後處理後、finalText＝你修改後的定稿
@Model
final class DictationReport {
    var createdAt: Date
    var updatedAt: Date
    var rawText: String
    var autoText: String
    var finalText: String
    var isFinalized: Bool

    init(rawText: String = "", autoText: String = "", finalText: String = "", isFinalized: Bool = false) {
        self.createdAt = .now
        self.updatedAt = .now
        self.rawText = rawText
        self.autoText = autoText
        self.finalText = finalText
        self.isFinalized = isFinalized
    }

    var title: String {
        let firstLine = finalText.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
        return firstLine.isEmpty ? "（空白報告）" : String(firstLine.prefix(40))
    }
}

/// 從你的修改中學到的修正規則
@Model
final class LearnedRule {
    @Attribute(.unique) var key: String
    var from: String
    var to: String
    var hitCount: Int
    var isActive: Bool
    var createdAt: Date
    var lastSeen: Date

    init(from: String, to: String) {
        self.key = LearnedRule.makeKey(from: from, to: to)
        self.from = from
        self.to = to
        self.hitCount = 1
        self.isActive = false
        self.createdAt = .now
        self.lastSeen = .now
    }

    static func makeKey(from: String, to: String) -> String { "\(from)\u{1F}\(to)" }
}

/// 個人詞彙（可附帶「常被辨識成」的別名）
@Model
final class UserTerm {
    @Attribute(.unique) var text: String
    var aliases: [String]
    var createdAt: Date

    init(text: String, aliases: [String] = []) {
        self.text = text
        self.aliases = aliases
        self.createdAt = .now
    }
}
