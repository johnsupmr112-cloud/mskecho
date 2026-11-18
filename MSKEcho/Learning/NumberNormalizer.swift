import Foundation

/// 「零點三五公分」→「0.35 cm」、「十二平方毫米」→「12 mm²」、「3.2 乘 1.5 公分」→「3.2 x 1.5 cm」
enum NumberNormalizer {
    private static let unitAlternation = "平方毫米|平方公釐|平方公分|平方釐米|公分|釐米|厘米|毫米|公釐|度|%|趴"
    private static let cnNum = "[零〇一二兩三四五六七八九十百千]+(?:點[零〇一二兩三四五六七八九]+)?"

    static func normalize(_ input: String) -> String {
        var s = input

        // 1. 中文數字（後面接單位或「乘」時才轉換，避免誤改「一些」「第一」）
        let cnPattern = "(\(cnNum))(?=\\s*(?:\(unitAlternation)|乘以|乘|x|X|×))"
        s = replace(s, pattern: cnPattern) { match in
            convertChinese(match) ?? match
        }

        // 2. 阿拉伯數字中的「點」：0點35 → 0.35
        s = regexReplace(s, "(\\d+)\\s*點\\s*(\\d+)", "$1.$2")

        // 3. 尺寸相乘
        s = regexReplace(s, "(\\d+(?:\\.\\d+)?)\\s*(?:乘以|乘|×|[xX])\\s*(?=\\d)", "$1 x ")

        // 4. 單位（先長後短）
        s = regexReplace(s, "(\\d+(?:\\.\\d+)?)\\s*(?:平方毫米|平方公釐)", "$1 mm²")
        s = regexReplace(s, "(\\d+(?:\\.\\d+)?)\\s*(?:平方公分|平方釐米)", "$1 cm²")
        s = regexReplace(s, "(\\d+(?:\\.\\d+)?)\\s*(?:公分|釐米|厘米)", "$1 cm")
        s = regexReplace(s, "(\\d+(?:\\.\\d+)?)\\s*(?:毫米|公釐)", "$1 mm")
        s = regexReplace(s, "(\\d+(?:\\.\\d+)?)\\s*(?:%|趴)", "$1%")
        return s
    }

    // MARK: - 中文數字轉換

    private static let digitMap: [Character: Int] = [
        "零": 0, "〇": 0, "一": 1, "二": 2, "兩": 2, "三": 3, "四": 4,
        "五": 5, "六": 6, "七": 7, "八": 8, "九": 9
    ]
    private static let unitMap: [Character: Int] = ["十": 10, "百": 100, "千": 1000]

    static func convertChinese(_ text: String) -> String? {
        let parts = text.split(separator: "點", maxSplits: 1, omittingEmptySubsequences: false)
        guard let intPart = parts.first, let intValue = parseInteger(String(intPart)) else { return nil }
        if parts.count == 2 {
            let decimals = parts[1].compactMap { digitMap[$0] }.map(String.init).joined()
            guard !decimals.isEmpty else { return String(intValue) }
            return "\(intValue).\(decimals)"
        }
        return String(intValue)
    }

    private static func parseInteger(_ s: String) -> Int? {
        if s.isEmpty { return 0 }
        let hasUnit = s.contains { unitMap[$0] != nil }
        if !hasUnit {
            // 「二零」→ 20、「三」→ 3
            let digits = s.compactMap { digitMap[$0] }
            guard digits.count == s.count else { return nil }
            return digits.reduce(0) { $0 * 10 + $1 }
        }
        var section = 0, num = 0
        for c in s {
            if let d = digitMap[c] { num = d }
            else if let u = unitMap[c] {
                if num == 0 && u == 10 { num = 1 }   // 十二 → 12
                section += num * u; num = 0
            } else { return nil }
        }
        return section + num
    }

    // MARK: - Regex helpers

    static func regexReplace(_ s: String, _ pattern: String, _ template: String) -> String {
        guard let re = try? NSRegularExpression(pattern: pattern) else { return s }
        return re.stringByReplacingMatches(in: s, range: NSRange(s.startIndex..., in: s), withTemplate: template)
    }

    private static func replace(_ s: String, pattern: String, transform: (String) -> String) -> String {
        guard let re = try? NSRegularExpression(pattern: pattern) else { return s }
        var result = s
        let matches = re.matches(in: s, range: NSRange(s.startIndex..., in: s))
        for m in matches.reversed() {
            guard let r = Range(m.range(at: 1), in: result) else { continue }
            result.replaceSubrange(r, with: transform(String(result[r])))
        }
        return result
    }
}
