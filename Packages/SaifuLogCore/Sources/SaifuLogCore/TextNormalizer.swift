import Foundation

/// 入力文の表記ゆれをそろえる。
///
/// 日本語の入力では、IME の設定しだいで数字や記号が全角になる（「１２００円」「￥８５０」）。
/// 解析の前にここで半角へそろえ、以降の処理は半角だけを相手にすればよいようにする。
enum TextNormalizer {
    /// 全角の英数字・記号を半角に、全角スペースを半角スペースに、マイナス記号（−）を「-」にし、
    /// 桁区切りのカンマを取り除く。
    ///
    /// `applyingTransform(.fullwidthToHalfwidth)` は使わない。カタカナまで半角（ｶﾀｶﾅ）に
    /// してしまい、キーワード辞書と照合できなくなるため。
    static func normalize(_ text: String) -> String {
        var scalars = String.UnicodeScalarView()
        for scalar in text.unicodeScalars {
            switch scalar.value {
            case 0xFF01...0xFF5E:
                // 全角の ASCII（！〜～）は、半角から 0xFEE0 ずれた位置にある。
                scalars.append(Unicode.Scalar(scalar.value - 0xFEE0)!)
            case 0xFFE5:
                scalars.append("¥")
            case 0x2212:
                // 数学のマイナス記号（「−500」）。IME や他のアプリからの貼り付けで入る。
                scalars.append("-")
            case 0x3000:
                scalars.append(" ")
            default:
                scalars.append(scalar)
            }
        }
        return removingThousandsSeparators(String(scalars))
    }

    /// 「1,280」「1,000,000」の桁区切りだけを取り除く。
    ///
    /// 3 桁区切りの形になっていないカンマは区切り（2 件の入力）として残す。
    /// 「2480,1200」は後ろが 3 桁でなく、「2480,120」は前の組が 4 桁あるので、どちらも 2 件。
    /// 前の組を見ないと、2 件目がたまたま 3 桁のときだけ 1 つの大きな金額（2,480,120 円）になるため。
    static func removingThousandsSeparators(_ text: String) -> String {
        let chars = Array(text)
        var result = ""
        result.reserveCapacity(chars.count)
        // 直前のカンマを桁区切りとして取り除いたか。取り除いたカンマの後ろの組は、ちょうど 3 桁でなければならない。
        var previousCommaRemoved = false
        for (i, c) in chars.enumerated() {
            if c == "," {
                var groupStart = i
                while groupStart > 0, chars[groupStart - 1].isASCIIDigit { groupStart -= 1 }
                let groupLength = i - groupStart
                // 前の組: 数の先頭の組なら 1〜3 桁、桁区切りのカンマに続く組ならちょうど 3 桁。
                let continuesNumber = groupStart > 0 && chars[groupStart - 1] == ","
                let leadingGroupIsValid = continuesNumber
                    ? previousCommaRemoved && groupLength == 3
                    : (1...3).contains(groupLength)
                // 後ろの組: ちょうど 3 桁（4 桁目が続かない）。
                let trailingGroupIsValid = i + 3 < chars.count
                    && chars[(i + 1)...(i + 3)].allSatisfy(\.isASCIIDigit)
                    && (i + 4 == chars.count || !chars[i + 4].isASCIIDigit)
                previousCommaRemoved = leadingGroupIsValid && trailingGroupIsValid
                if previousCommaRemoved { continue }
            }
            result.append(c)
        }
        return result
    }
}

/// キーワード照合のための表記ゆれ吸収。
enum KeywordMatcher {
    /// ひらがなをカタカナに、英字を小文字にそろえる（「らんち」「ランチ」、「Suica」「suica」を同じに扱う）。
    static func fold(_ text: String) -> String {
        let katakana = text.applyingTransform(.hiraganaToKatakana, reverse: false) ?? text
        return katakana.lowercased()
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
