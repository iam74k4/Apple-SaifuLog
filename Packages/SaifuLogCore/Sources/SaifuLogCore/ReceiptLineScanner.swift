import Foundation

/// レシートの文字（OCR の行）から、店名・日付・品目・小計・税・合計・お預かり・お釣り・ポイントを見分ける。
///
/// 金額はすべてここがコードで読む（AI には読ませない）。読み方は次のとおり。
/// - 行: OCR は品名と金額を別の行として返すことが多いので、位置が分かれば縦の重なりで 1 行にまとめ、左から並べる
/// - 表記: 半角のカナを全角に、全角の数字・記号を半角にそろえ、桁区切りのカンマを除く（`TextNormalizer`）
/// - 品目の行: 行の最後の金額（「¥198」「198円」「198※」「198軽」）と、その前の品名。「※」「*」「軽」は軽減税率の印
/// - 数量の行: 「2コX単98」「@98×2」「2個 @98」。前の品名だけの行か、同じ額の品目の行と合わせる
/// - 値引きの行: 「値引 -20」「割引 ▲30」「20%OFF ▲96」「50-」。すぐ上の品目から引く。小計の後の値引きは品目に付けない。
///   品名の中の「OFF」「オフ」「引き」（「COFFEE」「オフィス」「引き出し」）では値引きにしない
/// - 集計の行: 「小計」「合計」「消費税」「内税」「外税」「お預り」「お釣り」「ポイント」は、語で見分けて品目にしない。
///   税率ごとの税の行とまとめた行（「消費税等」）が並ぶときは、まとめた行だけを税にする
/// - そのほか: 電話番号・住所・登録番号・レジの番号・カード番号・挨拶・区切りの線は品目にしない
///
/// 読めなかった値は nil のまま返し、推し量って埋めない（合計が読めなければ合計なしとして、利用者に確かめてもらう）。
public enum ReceiptLineScanner {
    /// OCR の行から、レシートを読み取る。
    ///
    /// - Parameters:
    ///   - now: 日付を「何日前か」にする基準（読み取った瞬間）。
    ///   - calendar: 日付の区切り（画面の暦）。年月日はグレゴリオ暦で数える（`DateExpression`）。
    public static func scan(_ lines: [ReceiptTextLine], now: Date, calendar: Calendar) -> ReceiptScan {
        var parser = Parser(texts: rows(from: lines).map(normalize), now: now, calendar: calendar)
        return parser.run()
    }

    // MARK: - 行にまとめる

    /// OCR の行を、レシートの 1 行ずつの文字にする。
    ///
    /// すべての行に位置があれば、縦に半分以上重なるものを 1 行にまとめ、左から空白でつなぐ（品名と金額が離れて印字され、
    /// OCR が別の行として返すため）。位置の無い行があれば、渡した順のまま、改行でも分ける。
    static func rows(from lines: [ReceiptTextLine]) -> [String] {
        let lines = lines.filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        let framed = lines.compactMap { line in line.frame.map { (text: line.text, frame: $0) } }
        guard !lines.isEmpty, framed.count == lines.count else {
            return lines.flatMap { $0.text.split(whereSeparator: \.isNewline).map(String.init) }
        }
        let sorted = framed.sorted { ($0.frame.midY, $0.frame.minX) < ($1.frame.midY, $1.frame.minX) }
        var rows: [(anchor: ReceiptTextLine.Frame, parts: [(minX: Double, text: String)])] = []
        for line in sorted {
            // 上から並べてあるので、重なる行は直前の数行のどれか。傾いて写ったレシートでは、金額が次の行の品名より
            // 少し下に来ることがあるので、直前の 1 行だけでなく 2 行まで見る。
            let candidates = rows.indices.suffix(2).filter { Self.overlapsVertically(rows[$0].anchor, line.frame) }
            if let index = candidates.max(by: {
                Self.verticalOverlap(rows[$0].anchor, line.frame) < Self.verticalOverlap(rows[$1].anchor, line.frame)
            }) {
                rows[index].parts.append((line.frame.minX, line.text))
            } else {
                rows.append((line.frame, [(line.frame.minX, line.text)]))
            }
        }
        return rows.map { row in
            row.parts.sorted { $0.minX < $1.minX }.map(\.text).joined(separator: " ")
        }
    }

    private static func verticalOverlap(_ a: ReceiptTextLine.Frame, _ b: ReceiptTextLine.Frame) -> Double {
        min(a.maxY, b.maxY) - max(a.minY, b.minY)
    }

    /// 縦に、低い方の行の高さの半分以上重なるか。
    private static func overlapsVertically(_ a: ReceiptTextLine.Frame, _ b: ReceiptTextLine.Frame) -> Bool {
        let smaller = min(a.height, b.height)
        return smaller > 0 && verticalOverlap(a, b) >= smaller * 0.5
    }

    // MARK: - 表記をそろえる

    /// 半角のカナを全角に、全角の英数字と記号を半角にそろえ、桁区切りを除き、空白を 1 つにする。
    ///
    /// レシートは半角のカナ（「ｷﾞｭｳﾆｭｳ」）で印字されることが多い。そのままではキーワード辞書（「牛乳」「パン」）にも
    /// 読みやすい品名にもならないので全角にする。全体を全角にすると数字まで全角になるので、半角のカナの続きだけを変える。
    static func normalize(_ row: String) -> String {
        let widened = widenHalfwidthKatakana(row)
        let normalized = TextNormalizer.normalize(widened)
        return normalized.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    private static func widenHalfwidthKatakana(_ text: String) -> String {
        var result = ""
        var run = ""
        func flush() {
            guard !run.isEmpty else { return }
            result += run.applyingTransform(.fullwidthToHalfwidth, reverse: true) ?? run
            run = ""
        }
        for character in text {
            if let scalar = character.unicodeScalars.first, (0xFF61...0xFF9F).contains(scalar.value) {
                run.append(character)
            } else {
                flush()
                result.append(character)
            }
        }
        flush()
        return result
    }
}

// MARK: - 行の読み取り

extension ReceiptLineScanner {
    /// 行の最後の金額と、その前の文字。
    struct Trailing: Hashable {
        /// 金額。無ければ nil。
        var amount: Int?
        /// マイナス（「-」「▲」「△」、後ろの「-」）が付いていたか。
        var isNegative = false
        /// 「¥」か「円」が付いていたか（品目の行らしさの手がかり）。
        var hasYenMark = false
        /// 金額より前の文字（後ろの印を除いたもの）。金額が無ければ行の文字そのもの。
        var body: String
        /// 軽減税率の印（「※」「*」「軽」「8%」）が金額の後ろにあったか。
        var isReducedTaxRate = false
        /// 金額の後ろの「外」「内」（外税・内税の印）。
        var taxHint: ReceiptTaxMode?
    }

    /// 行の最後の金額を読む。
    ///
    /// 住所や電話番号の「1-2-3」「03-1234」のように数字を「-」でつないだものは金額にしない。品名に続けて書かれた金額
    /// （「牛乳198」）は、直前が漢字・かなのときだけ読む（「No1234」「T1234567890123」のような番号を金額にしないため）。
    static func trailing(in text: String) -> Trailing {
        let chars = Array(text)
        var end = chars.count
        var reduced = false
        var hint: ReceiptTaxMode?
        // 金額の後ろの印（「※」「*」「軽」「外」「内」「8%」）を外す。
        stripping: while true {
            while end > 0, chars[end - 1].isWhitespace { end -= 1 }
            for marker in trailingMarkers where end >= marker.text.count {
                let start = end - marker.text.count
                guard String(chars[start..<end]) == marker.text else { continue }
                end = start
                if marker.isReduced { reduced = true }
                if let mode = marker.taxMode { hint = mode }
                continue stripping
            }
            // 「8%」「(10%)」の税率の印。
            var j = end
            if j > 0, chars[j - 1] == ")" { j -= 1 }
            if j > 0, chars[j - 1] == "%" {
                var k = j - 1
                while k > 0, chars[k - 1].isASCIIDigit { k -= 1 }
                let digits = j - 1 - k
                if (1...2).contains(digits) {
                    if k > 0, chars[k - 1] == "(" { k -= 1 }
                    if Int(String(chars[k..<(j - 1)]).filter(\.isASCIIDigit)) == 8 { reduced = true }
                    end = k
                    continue stripping
                }
            }
            break
        }
        let noAmount = Trailing(body: text.trimmingCharacters(in: .whitespaces))

        var i = end
        func skipSpaces() { while i > 0, chars[i - 1].isWhitespace { i -= 1 } }
        var negative = false
        if i > 0, chars[i - 1] == "-" {
            negative = true
            i -= 1
            skipSpaces()
        }
        var hasYenMark = false
        if i > 0, chars[i - 1] == "円" {
            hasYenMark = true
            i -= 1
            skipSpaces()
        }
        let digitsEnd = i
        while i > 0, chars[i - 1].isASCIIDigit { i -= 1 }
        let digitsStart = i
        let digitCount = digitsEnd - digitsStart
        guard (1...maximumAmountDigits).contains(digitCount),
              !(digitCount > 1 && chars[digitsStart] == "0"),
              let value = Int(String(chars[digitsStart..<digitsEnd]))
        else { return noAmount }
        // 小数や時刻・日付の後ろの数字（「1.5」「12:30」「9/27」）は金額にしない。
        if digitsStart > 0, [".", ":", "/", ","].contains(chars[digitsStart - 1]) { return noAmount }
        skipSpaces()
        var spaceBefore = i < digitsStart
        if i > 0, chars[i - 1] == "¥" || chars[i - 1] == "\\" {
            hasYenMark = true
            i -= 1
            skipSpaces()
        }
        if i > 0, ["-", "▲", "△"].contains(chars[i - 1]) {
            // 数字の直後の「-」は、住所や電話番号のつなぎ（「1-2-3」「03-1234」）。
            if chars[i - 1] == "-", i >= 2, chars[i - 2].isASCIIDigit, !hasYenMark { return noAmount }
            let isTriangle = chars[i - 1] != "-"
            negative = true
            i -= 1
            let beforeSign = i
            skipSpaces()
            // 「▲」「△」と、前と空白で離した「-」は、値引きの印として前の文字と切り離す（「20%OFF ▲96」「OFF -96」）。
            // 空白の無い「-」は番号のつなぎ（「SKU-123」）かもしれないので、前の文字に付いた数字として扱う。
            spaceBefore = spaceBefore || isTriangle || i < beforeSign
        }
        if i > 0, !spaceBefore, !hasYenMark {
            let previous = chars[i - 1]
            if previous.isASCIILetter || previous.isASCIIDigit || attachedNonPriceMarks.contains(previous) {
                return noAmount
            }
        }
        return Trailing(
            amount: value, isNegative: negative, hasYenMark: hasYenMark,
            body: String(chars[0..<i]).trimmingCharacters(in: .whitespaces),
            isReducedTaxRate: reduced, taxHint: hint
        )
    }

    /// 数量 × 単価の書き方。
    struct Quantity: Hashable {
        /// 数量の前の品名（無ければ空）。
        var name: String
        var quantity: Int
        var unitPrice: Int
        /// 数量の後ろに書かれた額（「2コX単98 196」の 196）。無ければ nil。
        var amount: Int?
        var isReducedTaxRate: Bool
    }

    /// 「2コX単98」「@98×2」「2個 @98」「98円×2個」を読む。
    static func quantity(in text: String) -> Quantity? {
        for pattern in quantityPatterns {
            guard let match = pattern.firstMatch(in: text),
                  let quantity = match["qty"].flatMap({ Int($0) }),
                  let unit = match["unit"].flatMap({ Int($0) }),
                  (1...999).contains(quantity), unit > 0
            else { continue }
            let before = cleanedName(String(text[..<match.range.lowerBound]))
            let after = trailing(in: String(text[match.range.upperBound...]))
            return Quantity(
                name: hasLetters(before.name) ? before.name : "", quantity: quantity, unitPrice: unit,
                amount: after.isNegative ? nil : after.amount,
                isReducedTaxRate: before.isReducedTaxRate || after.isReducedTaxRate
            )
        }
        return nil
    }

    /// 品名の前後の印・コード・区切りを除く。
    ///
    /// 先頭の「※」「*」「軽」は軽減税率の印、先頭の 4 桁以上の数字は商品のコード（JAN など）、末尾の「……」「・」「:」は
    /// 金額までのつなぎ。
    static func cleanedName(_ text: String) -> (name: String, isReducedTaxRate: Bool) {
        var name = text.trimmingCharacters(in: .whitespaces)
        var reduced = false
        var changed = true
        while changed {
            changed = false
            for marker in leadingMarkers where name.hasPrefix(marker) {
                name = String(name.dropFirst(marker.count)).trimmingCharacters(in: .whitespaces)
                if marker != "(" && marker != "（" { reduced = true }
                changed = true
            }
            for marker in trailingNameMarkers where name.hasSuffix(marker) {
                name = String(name.dropLast(marker.count)).trimmingCharacters(in: .whitespaces)
                reduced = true
                changed = true
            }
            if let code = leadingCodePattern.firstMatch(in: name) {
                name = String(name[code.range.upperBound...])
                changed = true
            }
        }
        name = name.trimmingCharacters(in: nameEdgeSeparators)
        return (name, reduced)
    }

    /// 文字に、品名になりうる文字（かな・漢字・英字）が含まれるか。
    static func hasLetters(_ text: String) -> Bool {
        text.contains { $0.isLetter }
    }

    /// 品目の金額として読む最大の桁数（¥9,999,999 まで）。レシートの 1 行としてありえない長さの数字（JAN のコードや
    /// カード番号）を金額にしないため。
    static let maximumAmountDigits = 7

    /// 金額の後ろの印。長いものを先に置く。
    static let trailingMarkers: [(text: String, isReduced: Bool, taxMode: ReceiptTaxMode?)] = [
        ("(軽)", true, nil), ("（軽）", true, nil), ("軽減", true, nil), ("非課税", false, nil), ("外税", false, .exclusive),
        ("内税", false, .inclusive), ("※", true, nil), ("*", true, nil), ("★", true, nil), ("☆", true, nil),
        ("軽", true, nil), ("外", false, .exclusive), ("内", false, .inclusive), ("非", false, nil), ("税", false, nil),
        (")", false, nil), ("）", false, nil),
    ]
    /// 品名の頭の印。「軽」は後ろに空白があるときだけ印とみなす（「軽量カップ」の「軽」を外さないため）。
    static let leadingMarkers = ["※", "*", "★", "☆", "(", "（", "軽 "]
    /// 品名の末尾の軽減税率の印。「軽」は前に空白があるときだけ（「お手軽」の「軽」を外さないため）。
    static let trailingNameMarkers = ["(軽)", "（軽）", "※", "*", "★", "☆", " 軽"]

    /// 品名に続けて書かれた金額の直前にあれば、金額ではない（単価の「@」、掛け算の「×」、番号の「#」）。
    /// 「*」は軽減税率の印として金額の直前にも置く（「おにぎり *150」）ので入れない。
    static let attachedNonPriceMarks: Set<Character> = ["@", "×", "#", "~", "〜", "_"]

    static let nameEdgeSeparators = CharacterSet.whitespaces.union(CharacterSet(charactersIn: ".…・:：-=_~〜|()（）[]"))

    // 数量の語（コ・個・点…）は、数量の後ろにだけ付く。
    private static let counter = #"(?:コ|個|点|本|袋|パック|ケ|ヶ|枚|缶|玉|束|P)"#
    /// 単価を先に書く形（「@98×2」）を先に見る。数量を先に書く形から見ると、「@98 x 2」を数量 98・単価 2 と読むため。
    private static let quantityPatterns = [
        // 「@98×2」「単98x2コ」
        TextPattern(#"(?:@|単価?)\s*¥?\s*(?<unit>\d{1,7})\s*円?\s*[xX×*]\s*(?<qty>\d{1,3})\s*"# + counter + #"?(?!\d)"#),
        // 「2コX単98」「2個×@98」「2 x 98円」
        TextPattern(#"(?<![\d@])(?<qty>\d{1,3})\s*"# + counter + #"?\s*[xX×*]\s*(?:単価?|@)?\s*¥?\s*(?<unit>\d{1,7})\s*円?(?!\d)"#),
        // 「2個 @98」「2点 単価98」
        TextPattern(#"(?<![\d@])(?<qty>\d{1,3})\s*"# + counter + #"\s*(?:@|単価?)\s*¥?\s*(?<unit>\d{1,7})\s*円?(?!\d)"#),
        // 「98円×2個」
        TextPattern(#"(?<![\d@])(?<unit>\d{1,7})\s*円\s*[xX×*]\s*(?<qty>\d{1,3})\s*"# + counter + #"?(?!\d)"#),
    ]
    private static let leadingCodePattern = TextPattern(#"^\d{4,}\s+"#)
}

// MARK: - 見分けと組み立て

extension ReceiptLineScanner {
    /// 1 行の見分け（前後の行を見る前）。
    enum Classified: Hashable {
        case noise
        case cardNumber
        case date(ReceiptDate?)
        case time(hour: Int, minute: Int)
        case label(Label, amount: Int?, taxMode: ReceiptTaxMode?)
        case discount(amount: Int?)
        case quantity(Quantity)
        case item(name: String, amount: Int, isReducedTaxRate: Bool, taxHint: ReceiptTaxMode?, looksLikePrice: Bool)
        case priceOnly(amount: Int, isNegative: Bool)
        case nameOnly(String)
    }

    /// 集計の行の種類。
    enum Label: Hashable {
        case subtotal, total, tax, taxBase, tendered, change, points, payment, count
    }

    static func classify(_ text: String, now: Date, calendar: Calendar) -> Classified {
        guard !text.isEmpty, text.contains(where: { $0.isLetter || $0.isASCIIDigit }) else { return .noise }
        if cardNumberPattern.matches(text) || containsAny(text, cardWords) { return .cardNumber }
        // 「※印は軽減税率対象商品です」のような印の説明は、品目にも対象額にもしない。
        if text.contains("軽減"), text.contains("印") || text.contains("です") { return .noise }
        if let date = ReceiptDateReader.date(in: text, now: now, calendar: calendar) { return .date(date) }
        if let time = ReceiptDateReader.time(in: text), text.filter({ $0.isLetter && !"時分".contains($0) }).isEmpty {
            return .time(hour: time.hour, minute: time.minute)
        }
        // 店名と電話番号を 1 行に書いたもの（「〇〇ストア TEL03-…」）は、電話番号の前を店名の候補にする。
        if let contact = contactMarkers.lazy.compactMap({ text.range(of: $0) }).first {
            let name = cleanedName(String(text[..<contact.lowerBound])).name
            return name.filter(\.isLetter).count >= 2 && !isNoise(name) ? .nameOnly(name) : .noise
        }
        if isNoise(text) { return .noise }
        if let quantity = quantity(in: text) { return .quantity(quantity) }

        let parsed = trailing(in: text)
        let label = cleanedLabel(parsed.body)
        if containsAny(label, countWords) || countPattern.matches(label) {
            return .label(.count, amount: nil, taxMode: nil)
        }
        if isDiscountLabel(label) {
            // 値引きの合計（「値引合計」「割引計」。すでに品目から引いた額のまとめ）は、二重に引かないよう読まない。
            // 「小計値引」は小計からの値引きなので読む。
            if label.contains("合計") || label.hasSuffix("計") { return .noise }
            return .discount(amount: parsed.amount)
        }
        if let taxLabel = taxLabel(label) {
            return .label(taxLabel.label, amount: parsed.amount, taxMode: taxLabel.mode ?? parsed.taxHint)
        }
        for (words, kind) in labelWords where startsWithAny(label, words) {
            return .label(kind, amount: parsed.isNegative ? nil : parsed.amount, taxMode: nil)
        }
        // 1 文字や 2 文字の語は、品名の頭にも来る（「計量カップ」「釣り竿」）ので、その語だけの行のときに限る。
        if let kind = wholeLabelWords[label] {
            return .label(kind, amount: parsed.isNegative ? nil : parsed.amount, taxMode: nil)
        }

        guard let amount = parsed.amount else {
            let name = cleanedName(text).name
            return hasLetters(name) ? .nameOnly(name) : .noise
        }
        let cleaned = cleanedName(parsed.body)
        guard hasLetters(cleaned.name) else { return .priceOnly(amount: amount, isNegative: parsed.isNegative) }
        if parsed.isNegative { return .discount(amount: amount) }
        return .item(
            name: cleaned.name, amount: amount, isReducedTaxRate: parsed.isReducedTaxRate || cleaned.isReducedTaxRate,
            taxHint: parsed.taxHint, looksLikePrice: parsed.hasYenMark || parsed.isReducedTaxRate || cleaned.isReducedTaxRate
        )
    }

    /// 税の行か、税率ごとの対象額の行か。「(8%対象 ¥1,000 内税 ¥74)」のように両方を含むときは、後ろに書かれた方。
    private static func taxLabel(_ text: String) -> (label: Label, mode: ReceiptTaxMode?)? {
        let taxPosition = taxWords.compactMap { text.range(of: $0, options: .backwards)?.lowerBound }.max()
            ?? rateTaxPattern.firstMatch(in: text)?.range.lowerBound
        let basePosition = text.range(of: "対象", options: .backwards)?.lowerBound
        if let basePosition, taxPosition.map({ $0 < basePosition }) ?? true { return (.taxBase, nil) }
        guard let taxPosition else { return nil }
        let tail = text[taxPosition...]
        // 「うち消費税」「(内 消費税等」も内税の書き方（「内消費」のかなの書き方と、括弧の中の「内」）。印が無いと、行の足し算だけで
        // 内税か外税かを決めることになり、税と同じ額の品目を読み落とした内税のレシートを外税と取り違えて、合計が合ってしまうため。
        let mode: ReceiptTaxMode? = tail.hasPrefix("外") ? .exclusive : tail.hasPrefix("内") ? .inclusive
            : text.contains("外税") || text.hasPrefix("外") ? .exclusive
            : text.hasPrefix("内") || containsAny(text, inclusiveTaxMarkers) ? .inclusive : nil
        return (.tax, mode)
    }

    /// 値引き・割引の行の語か。
    ///
    /// 品名の中にも出てくる短い語（「COFFEE」「Office」の OFF、「オフィス」のオフ、「引き出し」の引き）では値引きの行にしない。
    /// 品名の途中にあるだけで値引きの行にすると、その品目が一覧から消え、⑤ でも戻せないため。「OFF」「オフ」は数字・「%」・「円」の
    /// 直後か、前後が英字でない独立した語のときだけ値引きの語とみなす。マイナスの付いた額（「-20」「▲30」）は、語が無くても
    /// 値引きとして読む（`classify` の後半）。
    static func isDiscountLabel(_ label: String) -> Bool {
        containsAny(label, discountWords) || discountTokenPattern.matches(label)
    }

    /// 行に書かれた税率（「外税8%」「(10%対象」の 8・10）。無ければ nil。
    static func taxRate(in text: String) -> Int? {
        taxRatePattern.firstMatch(in: text)?["rate"].flatMap { Int($0) }
    }

    /// 集計の語を見る前に、頭の括弧や印を除く（「(内消費税等」「*合計」）。
    private static func cleanedLabel(_ text: String) -> String {
        text.trimmingCharacters(in: CharacterSet(charactersIn: " ([（【<＜*※"))
    }

    private static func isNoise(_ text: String) -> Bool {
        if containsAny(text, noiseWords) { return true }
        if noisePattern.matches(text) { return true }
        // 数字（と「-」・空白）だけの長い並びは、バーコードの番号や電話番号。
        let digitsOnly = text.filter { !$0.isWhitespace && $0 != "-" }
        if digitsOnly.count >= 8, digitsOnly.allSatisfy(\.isASCIIDigit) { return true }
        return false
    }

    private static func containsAny(_ text: String, _ words: [String]) -> Bool {
        words.contains { text.contains($0) }
    }

    private static func startsWithAny(_ text: String, _ words: [String]) -> Bool {
        words.contains { text.hasPrefix($0) }
    }

    private static let cardWords = ["カード番号", "会員番号", "カードNo", "カード No"]
    /// 「************1234」「XXXX-XXXX-XXXX-1234」「1234-****-****-5678」。
    private static let cardNumberPattern = TextPattern(
        #"(?:[*xX#●]{4}[\s\-]*){2,}\d{2,4}|\d{4}[\s\-]*(?:[*xX#●]{4}[\s\-]*){2,}"#
    )

    /// 連絡先の語。これより後ろは電話番号など。
    private static let contactMarkers = ["TEL", "Tel", "tel", "電話", "℡", "FAX"]
    private static let noiseWords = [
        "TEL", "Tel", "tel", "電話", "℡", "FAX", "〒", "登録番号", "No.", "NO.", "No:", "担当", "領収", "レシート",
        "ありがとう", "いらっしゃいませ", "毎度", "ご来店", "またの", "営業時間", "http", "www.", ".com", ".jp",
        "お問い合わせ", "お問合せ", "取引番号", "伝票", "端末", "承認番号", "明細", "丁目", "番地", "再発行",
    ]
    /// レジや責任者の番号（「レジ01」「責:123」「#0012」）、住所（「1-2-3」「渋谷区神南1-2」）、登録番号（「T1234567890123」）。
    private static let noisePattern = TextPattern(
        #"レジ\s*[#:：No.]*\s*\d|責\s*[:：No.]*\s*\d|^#\d|\d+-\d+-\d+|T\d{13}|[都道府県市区町村郡]\S{0,12}\d+-\d+"#
    )

    private static let countWords = ["点数"]
    private static let countPattern = TextPattern(#"^\d+\s*点$"#)
    /// 行のどこにあっても値引きとみなす語（品名にはまず出てこない語。「アプリクーポン 50」のように、マイナスを付けずに印字する
    /// 値引きもあるので、「クーポン」はどこにあっても値引きとする）。
    private static let discountWords = [
        "値引", "割引", "値下げ", "クーポン", "%引", "円引", "ディスカウント", "まとめ買", "セット割", "ネビキ", "ワリビキ",
    ]
    /// 独立した「OFF」（「20%OFF」「50円 OFF」。「COFFEE」「OFFICE」は除く）と、数字・「%」・「円」の後の「オフ」（「10%オフ」。
    /// 「オフィス」は除く）。
    private static let discountTokenPattern = TextPattern(
        #"(?<![A-Za-z])(?:OFF|Off|off)(?![A-Za-z])|[\d%円]\s*オフ(?![ァ-ヶー])"#
    )
    private static let taxWords = ["内税", "外税", "消費税", "税額", "税等", "内消費", "外消費"]
    /// 内税の印（「内税」「内消費税」「うち消費税」「(内 消費税」）。
    private static let inclusiveTaxMarkers = ["内税", "内消費", "うち", "(内", "（内"]
    private static let taxRatePattern = TextPattern(#"(?<!\d)(?<rate>\d{1,2})\s*%"#)
    /// 「(内8% ¥74)」「外10% 50」のような、税の語の無い税額の行。
    private static let rateTaxPattern = TextPattern(#"^[内外]\s*\d{1,2}\s*%"#)
    /// 集計の語（行の頭にあるときだけ見る。品名の中の「計量カップ」「現金書留」などに当てないため）。
    private static let labelWords: [(words: [String], kind: Label)] = [
        (["小計", "税抜合計", "税抜計", "本体合計", "税抜金額"], .subtotal),
        (
            [
                "合計", "総計", "総合計", "税込合計", "お買上計", "お買上げ計", "お買い上げ計", "お買上合計", "お買上げ合計",
                "お会計", "御会計", "会計", "ご請求", "請求額", "お支払金額", "お支払い金額", "支払金額", "TOTAL", "Total",
            ],
            .total
        ),
        (["お釣り", "おつり", "お釣", "釣銭", "釣り銭", "つり銭", "お返し"], .change),
        (["お預り", "お預かり", "お預", "預り", "預かり", "現金"], .tendered),
        (["ポイント", "Pt", "pt", "PT", "残高"], .points),
        (
            [
                "クレジット", "クレカ", "カード払", "カード支払", "VISA", "Visa", "MASTER", "Master", "JCB", "AMEX",
                "電子マネー", "交通系", "Suica", "PASMO", "iD", "QUICPay", "QUICPAY", "PayPay", "楽天ペイ", "d払い",
                "auPAY", "au PAY", "メルペイ", "WAON", "nanaco", "Edy", "支払", "お支払", "コード決済", "QR",
            ],
            .payment
        ),
    ]

    /// 行がその語だけのときに見る集計の語。
    private static let wholeLabelWords: [String: Label] = ["計": .total, "釣り": .change, "釣": .change]

    /// 行を順に読み、品目と集計を組み立てる。
    struct Parser {
        let texts: [String]
        let now: Date
        let calendar: Calendar

        private var classified: [Classified] = []
        private var kinds: [ReceiptRow.Kind] = []
        private var items: [ReceiptItem] = []
        /// 品目ごとの、見分けた行の位置（最後の行）。
        private var itemRows: [Int] = []
        private var stage = Stage.header
        private var date: ReceiptDate?
        private var sawDate = false
        private var receiptDiscount = 0
        private var subtotal: Int?
        private var totals: [Int] = []
        private var taxes: [TaxLine] = []
        private var itemTaxHint: ReceiptTaxMode?
        private var tendered: Int?
        private var change: Int?
        private var points: Int?
        /// 品名だけの行（次の数量の行か金額だけの行と合わせる）。
        private var pendingName: (index: Int, name: String)?
        /// 金額の無い集計の行（次の金額だけの行と合わせる）。
        private var pendingLabel: (index: Int, label: Label, taxMode: ReceiptTaxMode?)?
        /// 品名の無い数量の行（次の同じ額の品目に合わせる）。
        private var pendingQuantity: Quantity?
        /// 金額の無い値引きの行（次の金額だけの行と合わせる）。
        private var pendingDiscount: Int?
        /// 日付より上の行に書かれた時刻（日付を読んだら、その日付に付ける）。
        private var pendingTime: (hour: Int, minute: Int)?

        /// 税の行 1 つ。
        struct TaxLine {
            var amount: Int
            var mode: ReceiptTaxMode?
            /// 行に書かれた税率（「外税8%」の 8）。無ければ nil（「消費税等」のようなまとめた行）。
            var rate: Int?
        }

        /// どこまで読んだか。品目は小計・合計より前にしか無い。
        enum Stage: Int, Comparable {
            case header, items, afterSubtotal, afterTotal

            static func < (lhs: Stage, rhs: Stage) -> Bool { lhs.rawValue < rhs.rawValue }
        }

        init(texts: [String], now: Date, calendar: Calendar) {
            self.texts = texts
            self.now = now
            self.calendar = calendar
        }

        mutating func run() -> ReceiptScan {
            classified = texts.map { ReceiptLineScanner.classify($0, now: now, calendar: calendar) }
            kinds = Array(repeating: .noise, count: texts.count)
            for index in texts.indices {
                read(index)
            }
            return finish()
        }

        private mutating func read(_ index: Int) {
            let previousName = pendingName.flatMap { $0.index == index - 1 ? $0 : nil }
            let previousLabel = pendingLabel.flatMap { $0.index == index - 1 ? $0 : nil }
            let followsDiscount = pendingDiscount == index - 1
            pendingName = nil
            pendingLabel = nil
            pendingDiscount = nil
            switch classified[index] {
            case .noise:
                kinds[index] = .noise
            case .cardNumber:
                kinds[index] = .cardNumber
            case .date(let found):
                kinds[index] = .date
                sawDate = true
                if date == nil, var found {
                    // 時刻を日付より上の行に印字するレシートもある。先に読んだ時刻を付けないと、読み取った時刻で記録してしまう。
                    if found.hour == nil, let pendingTime {
                        found.hour = pendingTime.hour
                        found.minute = pendingTime.minute
                    }
                    date = found
                }
            case .time(let hour, let minute):
                kinds[index] = .date
                if var found = date {
                    if found.hour == nil {
                        found.hour = hour
                        found.minute = minute
                        date = found
                    }
                } else if pendingTime == nil {
                    pendingTime = (hour, minute)
                }
            case .label(let label, let amount, let taxMode):
                guard let amount else {
                    kinds[index] = rowKind(for: label)
                    if label != .count { pendingLabel = (index, label, taxMode) }
                    return
                }
                apply(label, amount: amount, taxMode: taxMode, at: index)
            case .discount(let amount):
                kinds[index] = .discount
                if let amount {
                    applyDiscount(amount, at: index)
                } else {
                    pendingDiscount = index
                }
            case .quantity(let quantity):
                readQuantity(quantity, at: index, previousName: previousName)
            case .item(let name, let amount, let reduced, let taxHint, let looksLikePrice):
                readItem(
                    name: name, amount: amount, reduced: reduced, taxHint: taxHint, looksLikePrice: looksLikePrice, at: index
                )
            case .priceOnly(let amount, let isNegative):
                if let previousLabel {
                    apply(
                        previousLabel.label, amount: amount, taxMode: previousLabel.taxMode, at: index, labelRow: previousLabel.index
                    )
                } else if isNegative || followsDiscount {
                    kinds[index] = .discount
                    applyDiscount(amount, at: index)
                } else if let previousName, acceptsItems {
                    addItem(ReceiptItem(name: previousName.name, amount: amount), rows: [previousName.index, index])
                } else {
                    kinds[index] = .noise
                }
            case .nameOnly(let name):
                kinds[index] = .noise
                if acceptsItems { pendingName = (index, name) }
            }
        }

        /// 品目を受け付けるか。小計・合計の後に品目は無い。
        private var acceptsItems: Bool {
            stage <= .items
        }

        private mutating func readItem(
            name: String, amount: Int, reduced: Bool, taxHint: ReceiptTaxMode?, looksLikePrice: Bool, at index: Int
        ) {
            guard acceptsItems, amount > 0 else {
                kinds[index] = .noise
                return
            }
            // 品目の前（店名・住所のあたり）の「店名 123」のような番号を品目にしないよう、最初の品目は、「¥」「円」か
            // 軽減税率の印が付いているか、日付の行の後か、すぐ下にも品目が続くときだけ受け付ける。
            if stage == .header, !looksLikePrice, !sawDate, !nextRowLooksLikeItem(after: index) {
                kinds[index] = .noise
                return
            }
            var item = ReceiptItem(name: name, amount: amount, isReducedTaxRate: reduced)
            if let quantity = pendingQuantity, quantity.quantity * quantity.unitPrice == amount {
                item.quantity = quantity.quantity
                item.unitPrice = quantity.unitPrice
            }
            pendingQuantity = nil
            if let taxHint { itemTaxHint = taxHint }
            addItem(item, rows: [index])
        }

        private mutating func readQuantity(_ quantity: Quantity, at index: Int, previousName: (index: Int, name: String)?) {
            kinds[index] = .quantity
            guard acceptsItems else {
                kinds[index] = .noise
                return
            }
            let (product, overflow) = quantity.quantity.multipliedReportingOverflow(by: quantity.unitPrice)
            guard !overflow else { return }
            let amount = quantity.amount ?? product
            if !quantity.name.isEmpty || previousName != nil {
                let name = quantity.name.isEmpty ? previousName!.name : quantity.name
                let rows = quantity.name.isEmpty ? [previousName!.index, index] : [index]
                addItem(
                    ReceiptItem(
                        name: name, amount: amount, quantity: quantity.quantity, unitPrice: quantity.unitPrice,
                        isReducedTaxRate: quantity.isReducedTaxRate
                    ),
                    rows: rows
                )
                return
            }
            // 品名の行の下に書く数量（「牛乳 ¥196」の下の「2コX単98」）は、すぐ上の同じ額の品目に合わせる。
            if let last = items.indices.last, itemRows[last] == index - 1, items[last].quantity == nil,
               items[last].amount == product || items[last].amount == quantity.amount {
                items[last].quantity = quantity.quantity
                items[last].unitPrice = quantity.unitPrice
                return
            }
            // 品名の行の上に書く数量は、次の同じ額の品目に合わせる。
            pendingQuantity = quantity
        }

        private func nextRowLooksLikeItem(after index: Int) -> Bool {
            guard index + 1 < classified.count else { return false }
            switch classified[index + 1] {
            case .item, .quantity: return true
            default: return false
            }
        }

        private mutating func addItem(_ item: ReceiptItem, rows: [Int]) {
            items.append(item)
            itemRows.append(rows.max() ?? 0)
            for row in rows { kinds[row] = .item }
            if let quantityRow = rows.first(where: { if case .quantity = classified[$0] { true } else { false } }) {
                kinds[quantityRow] = .quantity
            }
            stage = max(stage, .items)
        }

        /// 値引きを、すぐ上の品目から引く。品目が無い・小計の後・引ききれない値引きは、品目に付けずにレシート全体から引く。
        private mutating func applyDiscount(_ amount: Int, at index: Int) {
            guard amount > 0 else { return }
            switch stage {
            case .afterTotal:
                // 合計の後の値引き（ポイントの利用など）は、合計に含まれているか、支払いの方法なので読まない。
                kinds[index] = .noise
            case .items:
                if let last = items.indices.last, items[last].netAmount - amount >= 1 {
                    items[last].discount += amount
                } else {
                    receiptDiscount += amount
                }
            case .header, .afterSubtotal:
                receiptDiscount += amount
            }
        }

        /// 集計の行を読む。
        ///
        /// - Parameter labelRow: 語だけの行と金額だけの行を合わせたときの、語の行（税率はどちらの行にも書かれうるため）。
        private mutating func apply(_ label: Label, amount: Int, taxMode: ReceiptTaxMode?, at index: Int, labelRow: Int? = nil) {
            kinds[index] = rowKind(for: label)
            switch label {
            case .subtotal:
                subtotal = amount
                stage = max(stage, .afterSubtotal)
            case .total:
                totals.append(amount)
                stage = .afterTotal
            case .tax:
                let rowTexts = [labelRow, index].compactMap { $0 }.map { texts[$0] }
                let rate = rowTexts.lazy.compactMap { ReceiptLineScanner.taxRate(in: $0) }.first
                taxes.append(TaxLine(amount: amount, mode: taxMode, rate: rate))
                if stage == .items { stage = .afterSubtotal }
            case .taxBase:
                if stage == .items { stage = .afterSubtotal }
            case .tendered:
                if tendered == nil { tendered = amount }
                stage = .afterTotal
            case .change:
                if change == nil { change = amount }
                stage = .afterTotal
            case .points:
                if points == nil { points = amount }
            case .payment, .count:
                break
            }
        }

        private func rowKind(for label: Label) -> ReceiptRow.Kind {
            switch label {
            case .subtotal: .subtotal
            case .total: .total
            case .tax: .tax
            case .taxBase: .taxBase
            case .tendered: .tendered
            case .change: .change
            case .points: .points
            case .payment: .payment
            case .count: .count
            }
        }

        private mutating func finish() -> ReceiptScan {
            let storeIndex = findStoreName()
            let storeName = storeIndex.map { ReceiptSummary.cleanedStoreName(texts[$0]) }.flatMap { $0.isEmpty ? nil : $0 }
            if let storeIndex, storeName != nil { kinds[storeIndex] = .storeName }
            let storeCategory = storeName.flatMap { name in
                ReceiptStoreDictionary.category(forStoreName: name)
                    ?? { let guess = EntryCategory.guess(from: name); return guess == .other ? nil : guess }()
            }
            for index in items.indices {
                let guess = EntryCategory.guess(from: items[index].name)
                items[index].category = guess != .other ? guess : storeCategory ?? .other
            }

            // 合計が無ければ、お預かりとお釣りの差（現金で払ったレシート）を合計にする。
            var total = totals.last
            if total == nil, let tendered, let change, tendered > change { total = tendered - change }

            let taxSum = Self.taxSum(taxes)
            let itemsTotal = items.reduce(0) { $0 + $1.netAmount }
            let taxMode: ReceiptTaxMode
            if taxes.contains(where: { $0.mode == .inclusive }) {
                taxMode = .inclusive
            } else if taxes.contains(where: { $0.mode == .exclusive }) || itemTaxHint == .exclusive {
                taxMode = .exclusive
            } else if taxSum > 0, let total,
                      subtotal.map({ $0 + taxSum == total }) ?? false || (itemsTotal - receiptDiscount + taxSum == total) {
                // 内税・外税の語が無いときは、足し算が合う方にする（小計 + 税 = 合計なら外税）。
                taxMode = .exclusive
            } else {
                taxMode = .inclusive
            }

            let rows = texts.indices.compactMap { index -> ReceiptRow? in
                texts[index].isEmpty ? nil : ReceiptRow(text: texts[index], kind: kinds[index])
            }
            return ReceiptScan(
                storeName: storeName,
                storeCategory: storeCategory,
                purchasedOn: date,
                items: items,
                receiptDiscount: receiptDiscount,
                subtotal: subtotal,
                taxMode: taxMode,
                exclusiveTax: taxMode == .exclusive ? taxSum : 0,
                total: total,
                tendered: tendered,
                change: change,
                points: points,
                rows: rows
            )
        }

        /// 税の行の合計。税率ごとの行と、それをまとめた行（「外税8% ¥40」「外税10% ¥50」「消費税等 ¥90」、税率が 1 つなら
        /// 「外税8% ¥40」「消費税等 ¥40」）が並ぶときは、まとめた行だけを使う（二重に数えないため）。
        ///
        /// まとめた行は、ほかの行の合計と同じ額の行。行が 2 つのときは、同じ額の税率の違う行（「外税8% ¥40」「外税10% ¥40」）も
        /// ありうるので、税率の書かれていない行か、もう一方と同じ税率の行（同じ税を 2 度印字したもの）のときだけまとめた行とみなす。
        static func taxSum(_ taxes: [TaxLine]) -> Int {
            let total = taxes.reduce(0) { $0 + $1.amount }
            guard taxes.count >= 2 else { return total }
            let summary = taxes.indices.first { index in
                let line = taxes[index]
                guard line.amount * 2 == total else { return false }
                if taxes.count >= 3 || line.rate == nil { return true }
                return taxes[1 - index].rate == line.rate
            }
            return summary.map { taxes[$0].amount } ?? total
        }

        /// 店名の行。品目より前（品目が無ければ合計より前、それも無ければ先頭から 8 行）の、品名だけの形の行のうち、
        /// チェーンの名前か店の種類の語を含む行、無ければいちばん上の行。
        private func findStoreName() -> Int? {
            let firstItem = kinds.firstIndex(of: .item)
            let firstTotal = kinds.firstIndex(where: { [.subtotal, .total, .tax].contains($0) })
            let limit = min(firstItem ?? firstTotal ?? texts.count, 8)
            let candidates = (0..<limit).filter { index in
                guard case .nameOnly(let name) = classified[index], kinds[index] == .noise else { return false }
                return name.filter(\.isLetter).count >= 2 && !ReceiptLineScanner.containsAny(name, storeNameExclusions)
            }
            return candidates.first { ReceiptStoreDictionary.containsStoreWord(texts[$0]) } ?? candidates.first
        }

        /// 店名にしない行（見出しと、「またお越しください」のような挨拶の文）。
        private let storeNameExclusions = [
            "領収", "レシート", "明細", "ようこそ", "いらっしゃいませ", "お買上", "お買い上げ", "控え", "ください", "ます", "ませ",
            "です", "ご利用", "お越し",
        ]
    }
}
