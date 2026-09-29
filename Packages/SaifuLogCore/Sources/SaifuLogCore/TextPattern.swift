import Foundation

/// 名前付きの組を持つ正規表現（レシートの読み取りで使う）。
///
/// Swift の `Regex` ではなく `NSRegularExpression` を使うのは、`Regex` が後読み（「数字の途中から読み始めない」ための
/// `(?<!\d)`）を扱えず、Sendable でもない（static let で共有できない）ため。`NSRegularExpression` は作った後は変わらず、
/// どのスレッドからでも使える。
struct TextPattern: @unchecked Sendable {
    private let expression: NSRegularExpression

    /// 形は固定の文字列なので、作れなければテスト（swift test）で必ず落ちる。
    init(_ pattern: String) {
        do {
            expression = try NSRegularExpression(pattern: pattern)
        } catch {
            preconditionFailure("正規表現の形が正しくない: \(pattern)")
        }
    }

    /// 最初に当たったところ。当たらなければ nil。
    func firstMatch(in text: String) -> TextMatch? {
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return expression.firstMatch(in: text, range: range).flatMap { TextMatch(text: text, result: $0) }
    }

    /// 当たるところがあるか。
    func matches(_ text: String) -> Bool {
        firstMatch(in: text) != nil
    }
}

/// `TextPattern` の当たったところ。
struct TextMatch {
    let text: String
    let result: NSTextCheckingResult
    /// 当たったところ全体。
    let range: Range<String.Index>

    init?(text: String, result: NSTextCheckingResult) {
        guard let range = Range(result.range, in: text) else { return nil }
        self.text = text
        self.result = result
        self.range = range
    }

    /// 名前付きの組の文字。組が当たっていなければ nil。
    subscript(name: String) -> String? {
        let nsRange = result.range(withName: name)
        guard nsRange.location != NSNotFound, let range = Range(nsRange, in: text) else { return nil }
        return String(text[range])
    }
}
