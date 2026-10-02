import Foundation

/// 入力文の表記ゆれをそろえる。
///
/// 日本語の入力では、IME の設定しだいで数字や記号が全角になる（「１２００円」「￥８５０」）。
/// 解析の前にここで半角へそろえ、以降の処理は半角だけを相手にすればよいようにする。
enum TextNormalizer {
    /// 全角の英数字・記号を半角に、全角スペースを半角スペースに、マイナス記号の異体（−・‐・–・— など）を「-」に、
    /// 改行の CRLF・CR を LF にし、桁区切りのカンマ（と IME の「、」）を取り除く。
    ///
    /// `applyingTransform(.fullwidthToHalfwidth)` は使わない。カタカナまで半角（ｶﾀｶﾅ）に
    /// してしまい、キーワード辞書と照合できなくなるため。
    static func normalize(_ text: String) -> String {
        var scalars = String.UnicodeScalarView()
        var previousWasCarriageReturn = false
        for scalar in text.unicodeScalars {
            defer { previousWasCarriageReturn = scalar.value == 0x0D }
            switch scalar.value {
            case 0xFF01...0xFF5E:
                // 全角の ASCII（！〜～、全角の「－」も）は、半角から 0xFEE0 ずれた位置にある。
                scalars.append(Unicode.Scalar(scalar.value - 0xFEE0)!)
            case 0xFFE5:
                scalars.append("¥")
            case 0x2212, 0x2010...0x2015, 0xFE63:
                // 数学のマイナス記号（「−500」）、ハイフン（‐）、ダッシュ（–・—・―）。IME の変換や他のアプリからの
                // 貼り付けで「-」の代わりに入る。そろえないと「返金 –500」を返金として読めず、¥500 の支出になるため。
                scalars.append("-")
            case 0x3000:
                scalars.append(" ")
            case 0x0D:
                // CRLF と CR は LF にする。Swift の String は CRLF を 1 文字として数えるので、そのままだと
                // 区切りの記号（LF）に当たらず、2 行に書いた 2 件が 1 件にまとめられるため。
                scalars.append("\n")
            case 0x0A where previousWasCarriageReturn:
                // CRLF の LF。CR の分をもう LF にしてある。
                break
            default:
                scalars.append(scalar)
            }
        }
        return removingThousandsSeparators(String(scalars))
    }

    /// 桁区切りに使う記号。「、」は日本語の入力で「,」の代わりに入る（「1、280円」）。
    private static let thousandsSeparators: Set<Character> = [",", "、"]

    /// 「1,280」「1,000,000」「1、280」の桁区切りだけを取り除く。
    ///
    /// 3 桁区切りの形になっていないカンマは区切り（2 件の入力）として残す。
    /// 「2480,1200」は後ろが 3 桁でなく、「2480,120」は前の組が 4 桁あるので、どちらも 2 件。
    /// 前の組を見ないと、2 件目がたまたま 3 桁のときだけ 1 つの大きな金額（2,480,120 円）になるため。
    ///
    /// 「、」は前後が数字で後ろがちょうど 3 桁のうえ、さらに、数の先頭の組が 1〜2 桁（「1、280」「12、800」）か、
    /// 後ろの組が「000」（「128、000」）のときだけ取り除く。「、」は件の区切りにも使い、「ランチ850、400」
    /// 「850、100円引き」のように 3 桁の金額を並べた「、」まで取り除くと、¥850,400 のような金額を黙って記録するため。
    /// 「ランチ 850、カフェ 400」のように区切りとして使った「、」は、後ろが数字でないので残る。
    ///
    /// 日付の日・時刻の分・小数の後ろの桁（「9/26、850円」の 26、「12:30、400円」の 30）は数の先頭の組ではないので、
    /// その後ろの「、」「,」は取り除かない。取り除くと「9/26850円」「12:30400円」になり、¥26,850 や ¥30,400 の
    /// ような金額を黙って記録するため。
    static func removingThousandsSeparators(_ text: String) -> String {
        let chars = Array(text)
        var result = ""
        result.reserveCapacity(chars.count)
        // 直前のカンマを桁区切りとして取り除いたか。取り除いたカンマの後ろの組は、ちょうど 3 桁でなければならない。
        var previousCommaRemoved = false
        for (i, c) in chars.enumerated() {
            if thousandsSeparators.contains(c) {
                var groupStart = i
                while groupStart > 0, chars[groupStart - 1].isASCIIDigit { groupStart -= 1 }
                let groupLength = i - groupStart
                // 前の組: 数の先頭の組なら 1〜3 桁、桁区切りのカンマに続く組ならちょうど 3 桁。
                let continuesNumber = groupStart > 0 && thousandsSeparators.contains(chars[groupStart - 1])
                // 後ろの組: ちょうど 3 桁（4 桁目が続かない）。
                let trailingGroupIsValid = i + 3 < chars.count
                    && chars[(i + 1)...(i + 3)].allSatisfy(\.isASCIIDigit)
                    && (i + 4 == chars.count || !chars[i + 4].isASCIIDigit)
                let leadingGroupIsValid: Bool
                if continuesNumber {
                    leadingGroupIsValid = previousCommaRemoved && groupLength == 3
                } else if continuesDateOrTime(chars, groupStart: groupStart) {
                    leadingGroupIsValid = false
                } else if c == "、" {
                    leadingGroupIsValid = (1...2).contains(groupLength)
                        || (groupLength == 3 && trailingGroupIsValid && chars[(i + 1)...(i + 3)].allSatisfy { $0 == "0" })
                } else {
                    leadingGroupIsValid = (1...3).contains(groupLength)
                }
                previousCommaRemoved = leadingGroupIsValid && trailingGroupIsValid
                if previousCommaRemoved { continue }
            }
            result.append(c)
        }
        return result
    }

    /// 日付・時刻・小数で、数字どうしをつなぐ記号（「9/26」「12:30」「9-26」「9.26」「2025年9」「9月26」）。
    private static let numberJoiners: Set<Character> = ["/", ":", "-", ".", "年", "月"]

    /// `groupStart` から始まる数字の組が、日付・時刻・小数の途中（数字とつなぎの記号の後ろ）か。
    ///
    /// つなぎの記号の前に数字があるときだけ見る。「返金 -1,280」の「-」はマイナスの記号で、その後ろは数の先頭のため。
    private static func continuesDateOrTime(_ chars: [Character], groupStart: Int) -> Bool {
        groupStart >= 2 && numberJoiners.contains(chars[groupStart - 1]) && chars[groupStart - 2].isASCIIDigit
    }
}

/// キーワード照合のための表記ゆれ吸収。
enum KeywordMatcher {
    /// ひらがなをカタカナに、英字を小文字にそろえる（「らんち」「ランチ」、「Suica」「suica」を同じに扱う）。
    static func fold(_ text: String) -> String {
        let katakana = text.applyingTransform(.hiraganaToKatakana, reverse: false) ?? text
        return katakana.lowercased()
    }

    /// `haystack`（`fold` した文）の中で、`needle`（`fold` した語）が最初に出てくる範囲。無ければ nil。
    ///
    /// 英字の語（"bus"・"wi-fi" のように ASCII だけで書いた語）は、前後が英字でないところだけを数える（"business" の中の
    /// "bus"、"steak" の中の "tea"、"iphone" の中の "phone" に当てない）。英語は語の中に別の短い語がよく入っているので、
    /// 文字の並びだけで当てると、黙って違うカテゴリになるため。語の後ろの "s"・"es"（複数形）は語の一部とみなす（"snacks"・
    /// "sandwiches"）。前後が数字や日本語の文字なら区切りとみなす（"dinner500"・"Suicaチャージ"）。
    /// 日本語の語は、文字の並びで当てる（空白で語を区切らないため）。
    static func firstRange(of needle: String, in haystack: String) -> Range<String.Index>? {
        guard !needle.isEmpty, needle.allSatisfy(\.isASCII), needle.contains(where: \.isASCIILetter) else {
            return haystack.range(of: needle)
        }
        var searchStart = haystack.startIndex
        while searchStart < haystack.endIndex,
              let range = haystack.range(of: needle, range: searchStart..<haystack.endIndex) {
            let startsWord = range.lowerBound == haystack.startIndex
                || !haystack[haystack.index(before: range.lowerBound)].isASCIILetter
            if startsWord, endsWord(at: range.upperBound, in: haystack) {
                return range
            }
            searchStart = haystack.index(after: range.lowerBound)
        }
        return nil
    }

    /// `index` で英字の語が終わるか（英字が続かないか）。複数形の "s"・"es" が続いても、その後ろで終われば終わりとみなす。
    private static func endsWord(at index: String.Index, in text: String) -> Bool {
        let rest = text[index...]
        return ["", "s", "es"].contains { suffix in
            guard rest.hasPrefix(suffix) else { return false }
            let end = rest.index(rest.startIndex, offsetBy: suffix.count)
            return end == rest.endIndex || !rest[end].isASCIILetter
        }
    }

    /// `text` に `keywords` のどれかが含まれるか。
    ///
    /// `excluding` に当たる部分は先に取り除いてから見る。「給料日」の中の「給料」のように、
    /// 別の意味の長い語の一部として出てきたものを数えないため。
    static func containsAny(_ keywords: [String], in text: String, excluding: [String] = []) -> Bool {
        var haystack = fold(text)
        for word in excluding {
            // 空白ではなく使われない文字で埋める。前後がつながって新しい語ができないようにするため。
            haystack = haystack.replacingOccurrences(of: fold(word), with: "\u{0}")
        }
        return keywords.contains { haystack.contains(fold($0)) }
    }
}

extension Character {
    /// 半角の 0〜9 か。`isNumber` は漢数字や全角数字も真になるため、明示的に絞る。
    var isASCIIDigit: Bool {
        guard let ascii = asciiValue else { return false }
        return ascii >= 0x30 && ascii <= 0x39
    }
}
