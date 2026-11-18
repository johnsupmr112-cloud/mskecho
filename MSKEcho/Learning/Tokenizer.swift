import Foundation

/// 把中英夾雜文字切成 token：英文字（含 ' -）、數字（含小數點）、單一漢字、標點。
/// 修正學習（diff）與後處理（建立容忍空白的比對規則）共用。
enum Tokenizer {
    enum Kind { case word, number, cjk, punct }

    struct Token: Equatable {
        let text: String
        let kind: Kind
    }

    static func tokens(_ s: String) -> [Token] {
        var out: [Token] = []
        var buffer = ""
        var bufferKind: Kind?
        let chars = Array(s)

        func flush() {
            if let k = bufferKind, !buffer.isEmpty { out.append(Token(text: buffer, kind: k)) }
            buffer = ""; bufferKind = nil
        }

        for (i, c) in chars.enumerated() {
            let next: Character? = i + 1 < chars.count ? chars[i + 1] : nil
            if c.isASCII && c.isLetter {
                if bufferKind != .word { flush(); bufferKind = .word }
                buffer.append(c)
            } else if (c == "'" || c == "’" || c == "-"), bufferKind == .word,
                      let n = next, n.isASCII, n.isLetter {
                buffer.append(c)                           // Baker's / full-thickness
            } else if c.isASCII && c.isNumber {
                if bufferKind != .number { flush(); bufferKind = .number }
                buffer.append(c)
            } else if c == ".", bufferKind == .number, let n = next, n.isASCII, n.isNumber {
                buffer.append(c)                           // 0.35
            } else if c.isWhitespace {
                flush()
            } else if isCJK(c) {
                flush()
                out.append(Token(text: String(c), kind: .cjk))
            } else {
                flush()
                out.append(Token(text: String(c), kind: .punct))
            }
        }
        flush()
        return out
    }

    /// 還原成字串：英文/數字之間補一個空白，其餘直接相連。
    static func join<S: Sequence>(_ tokens: S) -> String where S.Element == Token {
        var s = ""
        var prev: Token?
        for t in tokens {
            if let p = prev, (p.kind == .word || p.kind == .number), (t.kind == .word || t.kind == .number) {
                s += " "
            }
            s += t.text
            prev = t
        }
        return s
    }

    static func isCJK(_ c: Character) -> Bool {
        guard let v = c.unicodeScalars.first?.value else { return false }
        return (0x4E00...0x9FFF).contains(v) || (0x3400...0x4DBF).contains(v) || (0xF900...0xFAFF).contains(v)
    }
}
