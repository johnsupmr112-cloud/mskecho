import Foundation

/// 比對「自動產生的文字」與「你修改後的定稿」，找出可重複使用的修正規則候選。
/// 候選規則不會自動生效，需在「學習」頁按「採用」。
enum CorrectionLearner {
    struct Candidate: Hashable {
        let from: String
        let to: String
    }

    /// 臨床語意上互斥的詞：改了這些通常是「內容修正」而不是「辨識錯誤」，絕不學成規則
    /// （例如口誤說成右側、定稿改成左側；若學成「右側→左側」會造成嚴重錯誤）
    static let semanticGuard: Set<String> = [
        "左", "右", "雙", "單", "left", "right", "bilateral",
        "輕", "中", "重", "mild", "moderate", "severe",
        "無", "有", "沒", "未", "no", "not", "without", "with", "negative", "positive",
        "partial", "full", "complete", "部", "全",
        "上", "下", "內", "外", "前", "後", "medial", "lateral", "anterior", "posterior", "proximal", "distal",
        "increased", "decreased", "增", "減"
    ]

    static let maxSpanTokens = 6

    static func learn(auto: String, final: String) -> [Candidate] {
        let a = Array(Tokenizer.tokens(auto).prefix(1500))
        let b = Array(Tokenizer.tokens(final).prefix(1500))
        guard !a.isEmpty, !b.isEmpty else { return [] }

        var results: [Candidate] = []
        var seen = Set<Candidate>()

        for hunk in diffHunks(a, b) {
            var aR = hunk.a, bR = hunk.b
            guard !aR.isEmpty, !bR.isEmpty else { continue }                      // 純新增/純刪除＝內容變動
            guard aR.count <= maxSpanTokens, bR.count <= maxSpanTokens else { continue }

            let changed = a[aR] + b[bR]
            if changed.allSatisfy({ $0.kind == .number || $0.kind == .punct }) { continue }
            if changed.contains(where: { semanticGuard.contains($0.text.lowercased()) }) { continue }

            // 太短（單一漢字）時往左右各帶一個相鄰漢字當上下文，避免規則過度泛化（「雞」→「肌」太危險，「雞腱」→「肌腱」才安全）
            let fromLength = a[aR].reduce(0) { $0 + $1.text.count }
            if fromLength < 2 {
                if aR.lowerBound > 0, bR.lowerBound > 0, a[aR.lowerBound - 1].kind == .cjk {
                    aR = (aR.lowerBound - 1)..<aR.upperBound
                    bR = (bR.lowerBound - 1)..<bR.upperBound
                }
                if aR.upperBound < a.count, bR.upperBound < b.count, a[aR.upperBound].kind == .cjk {
                    aR = aR.lowerBound..<(aR.upperBound + 1)
                    bR = bR.lowerBound..<(bR.upperBound + 1)
                }
            }

            let from = Tokenizer.join(a[aR]).trimmingCharacters(in: .whitespaces)
            let to = Tokenizer.join(b[bR]).trimmingCharacters(in: .whitespaces)
            guard from.count >= 2, !to.isEmpty, from != to else { continue }

            let c = Candidate(from: from, to: to)
            if seen.insert(c).inserted { results.append(c) }
        }
        return results
    }

    // MARK: - LCS diff

    struct Hunk {
        let a: Range<Int>
        let b: Range<Int>
    }

    static func diffHunks(_ a: [Tokenizer.Token], _ b: [Tokenizer.Token]) -> [Hunk] {
        let n = a.count, m = b.count
        // dp[i][j] = LCS 長度 of a[i...], b[j...]
        var dp = Array(repeating: Array(repeating: Int32(0), count: m + 1), count: n + 1)
        if n > 0 && m > 0 {
            for i in stride(from: n - 1, through: 0, by: -1) {
                for j in stride(from: m - 1, through: 0, by: -1) {
                    dp[i][j] = a[i] == b[j] ? dp[i + 1][j + 1] + 1 : max(dp[i + 1][j], dp[i][j + 1])
                }
            }
        }

        var hunks: [Hunk] = []
        var i = 0, j = 0
        var hunkStart: (Int, Int)?

        func closeHunk() {
            if let (si, sj) = hunkStart {
                hunks.append(Hunk(a: si..<i, b: sj..<j))
                hunkStart = nil
            }
        }

        while i < n || j < m {
            if i < n, j < m, a[i] == b[j] {
                closeHunk()
                i += 1; j += 1
            } else {
                if hunkStart == nil { hunkStart = (i, j) }
                if j < m, (i >= n || dp[i][j + 1] >= dp[i + 1][j]) {
                    j += 1
                } else {
                    i += 1
                }
            }
        }
        closeHunk()
        return hunks
    }
}
