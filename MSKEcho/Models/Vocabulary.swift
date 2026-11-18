import Foundation

/// 內建 MSK 超音波詞庫（Resources/msk_vocab.json）
struct VocabBundle: Codable {
    struct Abbreviation: Codable, Hashable {
        let abbr: String
        let expansion: String
        let spoken: [String]
    }
    struct Templates: Codable {
        let classes: [String: [String]]
        let patterns: [String]
    }

    let version: Int
    let locale: String
    let terms: [String: [String]]
    let abbreviations: [Abbreviation]
    let misrecognitions: [String: String]
    let templates: Templates
    /// 由 merge_vocab.py 併入的定稿句子（選擇性），訓練語言模型時使用
    var trainingSentences: [String]? = nil

    static let shared: VocabBundle = load()

    static func load(bundle: Bundle = .main) -> VocabBundle {
        guard let url = bundle.url(forResource: "msk_vocab", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let vocab = try? JSONDecoder().decode(VocabBundle.self, from: data) else {
            assertionFailure("msk_vocab.json 無法載入")
            return VocabBundle(version: 0, locale: "zh-TW", terms: [:], abbreviations: [],
                               misrecognitions: [:], templates: .init(classes: [:], patterns: []), trainingSentences: nil)
        }
        return vocab
    }

    /// 依類別排序的所有詞彙（去重）
    var allTerms: [String] {
        var seen = Set<String>(), out: [String] = []
        for key in terms.keys.sorted() {
            for t in terms[key] ?? [] where seen.insert(t).inserted { out.append(t) }
        }
        for a in abbreviations {
            for t in [a.abbr, a.expansion] where seen.insert(t).inserted { out.append(t) }
        }
        return out
    }

    var termCount: Int { allTerms.count }

    /// 給辨識器的偏置詞（contextualStrings）。個人詞彙優先，其次縮寫與英文專有名詞。
    func contextualStrings(userTerms: [String], limit: Int = 150) -> [String] {
        var seen = Set<String>(), out: [String] = []
        func add(_ s: String) { if out.count < limit, seen.insert(s).inserted { out.append(s) } }
        userTerms.forEach(add)
        abbreviations.forEach { add($0.abbr) }
        for key in ["user", "finding", "shoulder", "wrist_hand", "knee", "ankle_foot", "elbow", "hip", "nerve", "procedure", "impression"] {
            (terms[key] ?? []).forEach(add)
        }
        return out
    }

    /// 樣板展開：<side> <structure> 有 <finding> → 「右側 supraspinatus 有 calcification」…
    func expandedTemplates(limit: Int = 3000) -> [String] {
        var out: [String] = []
        for pattern in templates.patterns {
            expand(pattern, into: &out, limit: limit)
            if out.count >= limit { break }
        }
        return out
    }

    private func expand(_ text: String, into out: inout [String], limit: Int) {
        guard out.count < limit else { return }
        guard let open = text.firstIndex(of: "<"),
              let close = text[open...].firstIndex(of: ">") else {
            out.append(text); return
        }
        let name = String(text[text.index(after: open)..<close])
        for value in templates.classes[name] ?? [] {
            var next = text
            next.replaceSubrange(open...close, with: value)
            expand(next, into: &out, limit: limit)
            if out.count >= limit { return }
        }
    }
}
