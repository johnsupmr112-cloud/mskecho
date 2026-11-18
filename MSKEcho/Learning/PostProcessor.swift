import Foundation

/// 辨識結果 → 報告文字 的後處理管線
/// 順序：口令標點 → 修正規則（學到的 > 個人別名 > 內建誤辨 > 縮寫唸法 > 大小寫）→ 數字單位 → 中英間距 → 整理
struct PostProcessor {
    struct Replacement {
        let from: String
        let to: String
    }

    private struct CompiledRule {
        let regex: NSRegularExpression
        let template: String
    }

    private let rules: [CompiledRule]
    var addCJKLatinSpacing: Bool

    init(vocab: VocabBundle,
         learned: [Replacement] = [],
         userAliases: [Replacement] = [],
         addCJKLatinSpacing: Bool = true) {
        self.addCJKLatinSpacing = addCJKLatinSpacing

        var pairs: [Replacement] = []
        pairs += learned
        pairs += userAliases
        pairs += vocab.misrecognitions.map { Replacement(from: $0.key, to: $0.value) }
        for a in vocab.abbreviations {
            for spoken in a.spoken {
                // 只收 ≥3 個字母的唸法（「p d」「r a」太容易誤觸）
                let letters = spoken.filter { $0.isLetter }.count
                if letters >= 3, spoken.caseInsensitiveCompare(a.abbr) != .orderedSame {
                    pairs.append(Replacement(from: spoken, to: a.abbr))
                }
            }
        }
        // 專有名詞大小寫：doppler → Doppler、achilles → Achilles
        for term in vocab.allTerms where term.contains(where: { $0.isUppercase }) {
            pairs.append(Replacement(from: term, to: term))
        }

        // 去重（先出現者優先），再依長度由長到短，避免短規則先吃掉長詞
        var seen = Set<String>()
        let unique = pairs.filter { seen.insert($0.from.lowercased()).inserted }
        let ordered = unique.enumerated().sorted { lhs, rhs in
            lhs.element.from.count != rhs.element.from.count
                ? lhs.element.from.count > rhs.element.from.count
                : lhs.offset < rhs.offset
        }.map(\.element)

        rules = ordered.compactMap { r in
            guard let pattern = Self.pattern(for: r.from),
                  let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
            return CompiledRule(regex: re, template: NSRegularExpression.escapedTemplate(for: r.to))
        }
    }

    /// 建立容忍空白差異的比對式：「super spinatus」也能比對「superspinatus」以外的「super  spinatus」
    static func pattern(for phrase: String) -> String? {
        let tokens = Tokenizer.tokens(phrase)
        guard !tokens.isEmpty else { return nil }
        var p = tokens.map { NSRegularExpression.escapedPattern(for: $0.text) }.joined(separator: "\\s*")
        if tokens.first?.kind == .word { p = "(?<![A-Za-z])" + p }
        if tokens.last?.kind == .word { p += "(?![A-Za-z])" }
        return p
    }

    func process(_ raw: String) -> String {
        var s = Self.applyVoiceCommands(raw)
        for r in rules {
            s = r.regex.stringByReplacingMatches(in: s, range: NSRange(s.startIndex..., in: s), withTemplate: r.template)
        }
        s = NumberNormalizer.normalize(s)
        if addCJKLatinSpacing { s = Self.cjkLatinSpacing(s) }
        return Self.tidy(s)
    }

    // MARK: - Steps

    static let voiceCommands: [(String, String)] = [
        ("下一段", "\n\n"), ("新段落", "\n\n"), ("換行", "\n"),
        ("句號", "。"), ("逗號", "，"), ("冒號", "："), ("分號", "；"), ("頓號", "、"), ("斜線", "/")
    ]

    static func applyVoiceCommands(_ s: String) -> String {
        var out = s
        for (spoken, symbol) in voiceCommands {
            out = out.replacingOccurrences(of: spoken, with: symbol)
        }
        return out
    }

    static func cjkLatinSpacing(_ s: String) -> String {
        var out = NumberNormalizer.regexReplace(s, "(\\p{Han})([A-Za-z0-9])", "$1 $2")
        out = NumberNormalizer.regexReplace(out, "([A-Za-z0-9%²])(\\p{Han})", "$1 $2")
        return out
    }

    static func tidy(_ s: String) -> String {
        var out = NumberNormalizer.regexReplace(s, "[ \\t]{2,}", " ")
        out = NumberNormalizer.regexReplace(out, "[ \\t]+([，。：；、！？）])", "$1")
        out = NumberNormalizer.regexReplace(out, "[，、,][ \\t]*\\n", "\n")              // 「，換行」→ 換行
        out = NumberNormalizer.regexReplace(out, "[ \\t]*\\n[ \\t]*[，。、,.;；]*", "\n")  // 「換行。」→ 換行
        out = NumberNormalizer.regexReplace(out, "([，。：；、])\\1+", "$1")
        return out.trimmingCharacters(in: .whitespaces)
    }
}
