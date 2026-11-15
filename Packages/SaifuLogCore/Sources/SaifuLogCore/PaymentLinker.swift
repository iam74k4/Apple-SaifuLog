import Foundation

/// 文に書いた払い方（「楽天カードで」「カードで」「現金で」「PayPayで」）を読み、記録の払ったカードを決め、品目から払い方の言葉を
/// 除く。カードの引き落とし（「クレカ引き落とし 50000」）を書いた文も見分ける。docs/design.md §8-2 のカードの決め事。
///
/// 読み取り（AI・ルールベース）の後に、どちらで読んだ記録にも当てる（登録したカードは利用者ごとに違い、解析の辞書には持てないため）。
/// - カード: 登録したカードの名前（「楽天」と登録したら「楽天カード」も）を書けばそのカード。「カードで」「クレカで」「VISAカードで」
///   のように名前を書かずにカードと書けば、いつものカード（`PaymentCard.defaultCard`）
/// - 現金とほかの払い方（電子マネー・コード決済）: カードの記録にしない（品目からは除く）
/// - 送った文の中で 1 つの払い方しか書いていなければ、払い方の書いていない件にも使う（「コーヒー400 パン300 カードで」は両方）。
///   違う払い方が混ざっていれば、払い方を書いた件だけに使う
/// - 収入はカードの記録にしない
///
/// 品目から除くのは、払い方を表すと分かる形だけ。後ろに「で」「払い」「決済」などが続く（「カードで」「現金払い」）か、
/// 1 語で置いた（「ランチ 850 楽天カード」）登録したカード・「クレカ」「現金」。「カード」だけを 1 語で置いたもの（「誕生日 カード 300」）、
/// 図書カードやポイントカードのような払い方でないカード、「Suica チャージ」のようにチャージするものは除かない。除くと品目が
/// 空になるときは除かない（「楽天カード 3000」の品目が無くなるため）。
public struct PaymentLinker: Sendable {
    public let cards: [PaymentCard]

    public init(cards: [PaymentCard]) {
        self.cards = cards
    }

    // MARK: - 記録に当てる

    /// 1 回の送信で読んだ記録に、払ったカードを決め、品目から払い方の言葉を除く。
    public func link(_ entries: [ParsedEntry], text: String) -> [ParsedEntry] {
        let chars = Array(TextNormalizer.normalize(text))
        let textMentions = mentions(in: chars, requireRightBoundary: true).filter { $0.isRemovable(in: chars) }
        let shared = Self.singleChoice(textMentions.map(\.kind))
        // 文では「カードで」と書いても、ルールベースの品目には「カード」だけが残る（「で」は品目の後ろの助詞として落ちる）。
        // 文で払い方として書いた語は、品目に 1 語で残っていても除く。
        let writtenTerms = Set(textMentions.map { KeywordMatcher.fold(String(chars[$0.term])) })
        return entries.map { entry in
            var linked = entry
            let item = Self.item(of: entry)
            let itemChars = Array(item.text)
            let own = mentions(in: itemChars, requireRightBoundary: true).filter { $0.isRemovable(in: itemChars) }
            let kind = Self.singleChoice(own.map(\.kind)) ?? shared
            linked.cardID = entry.isIncome ? nil : kind.flatMap(cardID(for:))
            linked.memo = Self.memo(item: cleaned(itemChars, mentions: own, writtenTerms: writtenTerms), note: item.note)
            return linked
        }
    }

    /// 文がカードの引き落とし（請求の支払い）を書いたものか。カードの支出は使った日に数えるので、引き落としを記録すると二重に
    /// 数える。記録する前に確かめるのに使う（金額があるかは呼び出し側が見る）。
    ///
    /// - カードの語（登録したカードの名前・「カード」「クレカ」「クレジット」）と、「引き落とし」「請求」「口座振替」「返済」「明細」が
    ///   どちらもある（「クレカ引き落とし 50000」「引き落とし 楽天カード 50000」）
    /// - カードの語の後ろに「の支払い」「は支払い」「代」「代金」が続く（「カードの支払い 50000」「カード代 5万」）。「カード支払い」
    ///   「カード払い」は、カードで払った買い物の書き方なので数えない
    /// - カードの名前と金額のほかに何も書いていない（「楽天カード 50000」「クレカ 11月分 50000」）。「カード 300」は除く
    ///   （カードを買ったのかもしれない）
    public func isCardBill(_ text: String) -> Bool {
        let chars = Array(TextNormalizer.normalize(text))
        let cardMentions = mentions(in: chars, requireRightBoundary: false).filter(\.kind.isCard)
        guard !cardMentions.isEmpty else { return false }
        let folded = KeywordMatcher.fold(String(chars))
        if Self.billWords.contains(where: { folded.contains($0) }) { return true }
        for mention in cardMentions {
            var i = Self.skippingSpaces(chars, from: mention.term.upperBound)
            let hasConnector = i < chars.count && Self.billConnectors.contains(chars[i])
            if hasConnector { i = Self.skippingSpaces(chars, from: i + 1) }
            let rest = String(chars[i...])
            if Self.chargeWords.contains(where: { rest.hasPrefix($0) }) { return true }
            if hasConnector, Self.paymentWords.contains(where: { rest.hasPrefix($0) }) { return true }
        }
        // カードの名前と金額だけの文。
        var remaining = chars.indices.map { _ in true }
        for mention in cardMentions {
            for i in mention.range { remaining[i] = false }
        }
        let leftover = chars.indices.filter { remaining[$0] }.map { chars[$0] }
        return cardMentions.contains(where: \.namesCard)
            && leftover.contains(where: \.isASCIIDigit)
            && leftover.allSatisfy { $0.isASCIIDigit || $0.isWhitespace || Self.amountOnlyCharacters.contains($0) }
    }

    /// レシートの支払いの行（「クレジット」「VISA」「楽天カード」）から、払ったカード。登録したカードの名前があればそのカード、
    /// カードで払ったと分かれば（クレジット・カードのブランド）いつものカード。現金や電子マネー、支払いの行が無ければ nil。
    public func cardID(forReceipt scan: ReceiptScan) -> String? {
        let text = scan.rows.filter { $0.kind == .payment }.map(\.text).joined(separator: " ")
        guard !text.isEmpty else { return nil }
        let found = mentions(in: Array(TextNormalizer.normalize(text)), requireRightBoundary: false)
        for mention in found {
            if case .card(let id) = mention.kind { return id }
        }
        let folded = KeywordMatcher.fold(text)
        guard found.contains(where: { $0.kind == .defaultCard }) || Self.cardBrands.contains(where: { folded.contains($0) }) else {
            return nil
        }
        return PaymentCard.defaultCard(in: cards)?.id
    }

    /// レシートの支払いの行に印字される、カードのブランド（そろえた形）。
    private static let cardBrands = ["VISA", "MASTER", "JCB", "AMEX", "AMERICAN EXPRESS", "DINERS", "銀聯"].map(KeywordMatcher.fold)

    // MARK: - 払い方の言葉

    /// 文の中の払い方の言葉。
    struct Mention {
        enum Kind: Hashable {
            /// 登録したカード（ID）。
            case card(String)
            /// 名前を書かずに「カード」「クレカ」と書いた（いつものカード）。
            case defaultCard
            /// 現金。
            case cash
            /// カードでないほかの払い方（電子マネー・コード決済・デビット）。
            case other

            var isCard: Bool {
                switch self {
                case .card, .defaultCard: true
                case .cash, .other: false
                }
            }
        }

        let kind: Kind
        /// 払い方の語（「楽天カード」）の位置。
        let term: Range<Int>
        /// 語と、後ろの「で」「払い」などを合わせた位置（品目から除く範囲）。
        let range: Range<Int>
        /// 後ろに「で」「払い」などが続いたか。
        let hasSuffix: Bool
        /// 1 語で置いたときにも払い方とみなせる語か（登録したカード・ブランドを付けたカード・「クレカ」「現金」）。
        let standsAlone: Bool
        /// カードを名前で指したか（「カード」だけではない）。引き落としの見分けに使う。
        let namesCard: Bool

        /// 品目から除いてよいか（後ろに「で」などが続くか、1 語で置いた）。
        func isRemovable(in chars: [Character]) -> Bool {
            if hasSuffix { return true }
            guard standsAlone else { return false }
            let startsToken = range.lowerBound == 0 || PaymentLinker.isTokenSeparator(chars[range.lowerBound - 1])
            let endsToken = range.upperBound == chars.count || PaymentLinker.isTokenSeparator(chars[range.upperBound])
            return startsToken && endsToken
        }
    }

    /// 払い方の言葉を、文の頭から順に拾う（重ならない）。
    ///
    /// - Parameter requireRightBoundary: 後ろに「で」「払い」などが続かない語は、語が終わる（後ろに語の文字が続かない）ときだけ拾う。
    ///   引き落としの見分け（「クレカ引き落とし」）では見ない。
    func mentions(in chars: [Character], requireRightBoundary: Bool) -> [Mention] {
        let folded = chars.map(Self.fold)
        let terms = vocabulary()
        var found: [Mention] = []
        var i = 0
        while i < chars.count {
            guard i == 0 || !Self.isWordCharacter(chars[i - 1]) || Self.startsBareCard(folded, at: i) else {
                i += 1
                continue
            }
            var matched: Mention?
            for term in terms where Self.has(term.folded, in: folded, at: i) {
                let end = i + term.folded.count
                var start = i
                var kind = term.kind
                var standsAlone = term.standsAlone
                var namesCard = term.namesCard
                if term.isBareCard {
                    // 「VISAカード」「エポスカード」: 前の語をブランドの名前とみなして一緒に拾う。図書カードやポイントカードは払い方ではない。
                    while start > (found.last?.range.upperBound ?? 0), Self.isWordCharacter(chars[start - 1]) { start -= 1 }
                    let compound = String(folded[start..<end])
                    if Self.nonPaymentCards.contains(where: { compound.hasSuffix($0) }) { break }
                    if start < i {
                        standsAlone = true
                        namesCard = true
                    }
                    if let card = card(named: compound) { kind = .card(card.id) }
                }
                let suffixLength = Self.suffixLength(in: chars, at: end)
                if term.requiresSuffix, suffixLength == 0 { continue }
                if suffixLength == 0, requireRightBoundary, end < chars.count, Self.isWordCharacter(chars[end]) { continue }
                matched = Mention(
                    kind: kind, term: start..<end, range: start..<(end + suffixLength), hasSuffix: suffixLength > 0,
                    standsAlone: standsAlone, namesCard: namesCard
                )
                break
            }
            if let matched {
                found.append(matched)
                i = matched.range.upperBound
            } else {
                i += 1
            }
        }
        return found
    }

    /// 拾う語（長いものから）。
    private func vocabulary() -> [Term] {
        var terms: [Term] = []
        for card in cards {
            let name = KeywordMatcher.fold(card.name)
            guard !name.isEmpty else { continue }
            terms.append(Term(folded: Array(name), kind: .card(card.id), standsAlone: true, namesCard: true))
            if name.hasSuffix(Self.bareCard) {
                // 「エポスカード」と登録して「エポスで」と書いたとき。
                let brand = String(name.dropLast(Self.bareCard.count))
                if !brand.isEmpty {
                    terms.append(Term(folded: Array(brand), kind: .card(card.id), standsAlone: true, namesCard: true))
                }
            } else {
                // 「楽天」と登録して「楽天カードで」と書いたとき。
                terms.append(Term(folded: Array(name + Self.bareCard), kind: .card(card.id), standsAlone: true, namesCard: true))
            }
        }
        terms += Self.genericTerms
        return terms.sorted { $0.folded.count > $1.folded.count }
    }

    /// `compound`（そろえた形）を名前にした登録したカード。
    private func card(named compound: String) -> PaymentCard? {
        cards.first { card in
            let name = KeywordMatcher.fold(card.name)
            return name == compound || name + Self.bareCard == compound
        }
    }

    private func cardID(for kind: Mention.Kind) -> String? {
        switch kind {
        case .card(let id): id
        case .defaultCard: PaymentCard.defaultCard(in: cards)?.id
        case .cash, .other: nil
        }
    }

    /// 払い方が 1 つに決まれば、その払い方。書いていない・違う払い方が混ざっていれば nil。
    private static func singleChoice(_ kinds: [Mention.Kind]) -> Mention.Kind? {
        let distinct = Set(kinds)
        return distinct.count == 1 ? distinct.first : nil
    }

    // MARK: - 品目

    /// 記録のメモを、品目と書き足した説明（割り勘など）に分けたもの。
    private static func item(of entry: ParsedEntry) -> (text: String, note: String?) {
        guard let note = EntryMemoNote(memo: entry.memo, amount: entry.amount, isIncome: entry.isIncome) else {
            return (entry.memo, nil)
        }
        switch note.kind {
        case .split(let split): return (note.item, split.note)
        case .perPerson(let count): return (note.item, EntryMemoNote.perPersonNote(splitCount: count ?? 1))
        }
    }

    private static func memo(item: String, note: String?) -> String {
        guard let note else { return item }
        return EntryMemoNote.memo(item: item, note: note)
    }

    /// 品目から払い方の言葉を除く。除くと空になるなら、元の品目のまま。
    private func cleaned(_ chars: [Character], mentions: [Mention], writtenTerms: Set<String>) -> String {
        var keep = chars.indices.map { _ in true }
        for mention in mentions {
            for i in mention.range { keep[i] = false }
        }
        var text = String(chars.indices.filter { keep[$0] }.map { chars[$0] })
        // 文で払い方として書いた語が、品目に 1 語で残っているもの（「ランチ カード」の「カード」）。
        var words = text.split(whereSeparator: \.isWhitespace).map(String.init)
        words.removeAll { writtenTerms.contains(KeywordMatcher.fold($0)) }
        text = words.joined(separator: " ")
        // 払い方を除いた跡に残る空の括弧（「ランチ(カード払い)」）と、端の記号・助詞を落とす。
        text = text.replacingOccurrences(of: #"[(\[「【]\s*[)\]」】]"#, with: " ", options: .regularExpression)
        text = text.split(whereSeparator: \.isWhitespace).joined(separator: " ").trimmingCharacters(in: Self.trimmedEdges)
        while let last = text.last, Self.trailingParticles.contains(last) {
            text.removeLast()
            text = text.trimmingCharacters(in: Self.trimmedEdges)
        }
        while let first = text.first, Self.leadingParticles.contains(first) {
            text.removeFirst()
            text = text.trimmingCharacters(in: Self.trimmedEdges)
        }
        return text.isEmpty ? String(chars) : text
    }

    // MARK: - 辞書

    struct Term {
        let folded: [Character]
        let kind: Mention.Kind
        /// 1 語で置いたときにも払い方とみなすか。
        var standsAlone = false
        /// 後ろに「で」「払い」などが続くときだけ拾うか。
        var requiresSuffix = false
        /// カードを名前で指したか。
        var namesCard = false
        /// 「カード」だけ（前の語をブランドの名前として一緒に拾う）。
        var isBareCard = false

        init(
            folded: [Character], kind: Mention.Kind, standsAlone: Bool = false, requiresSuffix: Bool = false,
            namesCard: Bool = false, isBareCard: Bool = false
        ) {
            self.folded = folded
            self.kind = kind
            self.standsAlone = standsAlone
            self.requiresSuffix = requiresSuffix
            self.namesCard = namesCard
            self.isBareCard = isBareCard
        }

        init(_ word: String, _ kind: Mention.Kind, standsAlone: Bool = false, requiresSuffix: Bool = false, namesCard: Bool = false) {
            self.init(
                folded: Array(KeywordMatcher.fold(word)), kind: kind, standsAlone: standsAlone, requiresSuffix: requiresSuffix,
                namesCard: namesCard
            )
        }
    }

    private static let bareCard = KeywordMatcher.fold("カード")

    /// どの利用者にも共通の払い方の語。
    private static let genericTerms: [Term] = {
        var terms: [Term] = [
            Term("クレジットカード", .defaultCard, standsAlone: true, namesCard: true),
            Term("クレカ", .defaultCard, standsAlone: true, namesCard: true),
            Term("クレジット", .defaultCard, standsAlone: true, namesCard: true),
            Term(folded: Array(bareCard), kind: .defaultCard, isBareCard: true),
            Term("デビットカード", .other, standsAlone: true),
            Term("デビット", .other, requiresSuffix: true),
            Term("現金", .cash, standsAlone: true),
            Term("キャッシュ", .cash, requiresSuffix: true),
        ]
        // 電子マネーとコード決済は、チャージする（「Suica チャージ」）ので 1 語では除かない。
        terms += [
            "PayPay", "ペイペイ", "楽天ペイ", "d払い", "auPAY", "au PAY", "メルペイ", "LINE Pay", "LINEPay", "Apple Pay", "ApplePay",
            "アップルペイ", "Google Pay", "GooglePay", "QUICPay", "クイックペイ", "iD", "Suica", "PASMO", "ICOCA", "nanaco", "WAON",
            "楽天Edy", "Edy", "交通系IC", "電子マネー", "QR決済", "コード決済", "スマホ決済", "バーコード決済",
        ].map { Term($0, .other, requiresSuffix: true) }
        return terms
    }()

    /// 「カード」の付く語のうち、払い方ではないもの（そろえた形。前に付いた語ごと見る）。
    private static let nonPaymentCards: [String] = [
        "図書カード", "クオカード", "QUOカード", "ギフトカード", "プリペイドカード", "ポイントカード", "テレホンカード", "ICカード",
        "メッセージカード", "バースデーカード", "誕生日カード", "グリーティングカード", "クリスマスカード", "トレーディングカード",
        "SDカード", "メモリーカード", "メモリカード", "グラフィックカード", "ビデオカード", "サウンドカード", "キャッシュカード",
        "ゲームカード", "マイナンバーカード", "ナンバーカード", "診察カード", "会員カード", "メンバーズカード", "スタンプカード",
        "名刺カード", "iTunesカード", "Google Playカード", "GooglePlayカード", "Amazonカード",
    ].map(KeywordMatcher.fold)

    /// 払い方の語の後ろに続けて、払い方として書いたと分かる語（元の文字のまま比べる。「で」をそろえると「デザイン」に当たるため）。
    private static let suffixes: [[Character]] = [
        "で支払った", "で払った", "で支払い", "で支払", "で決済", "で払い", "で払", "払いで", "決済で", "支払いで", "支払い", "支払",
        "払い", "決済", "にて", "で", "払",
    ].map { Array($0) }.sorted { $0.count > $1.count }

    private static func suffixLength(in chars: [Character], at index: Int) -> Int {
        for suffix in suffixes where index + suffix.count <= chars.count && Array(chars[index..<(index + suffix.count)]) == suffix {
            return suffix.count
        }
        return 0
    }

    /// 引き落としを書いたとみなす語（そろえた形）。
    private static let billWords = ["引き落とし", "引き落し", "引落し", "引落", "請求", "口座振替", "返済", "明細"].map(KeywordMatcher.fold)
    /// カードの語の後ろの、「の」「は」などの助詞。
    private static let billConnectors: Set<Character> = ["の", "は", "が", "を"]
    /// カードの語に続けて、請求の支払いを書いたとみなす語（助詞を挟んだときだけ）。
    private static let paymentWords = ["お支払い", "支払い", "支払"]
    /// カードの語に続けて、請求の額を書いたとみなす語（「カード代」）。
    private static let chargeWords = ["代金", "代"]
    /// カードの名前と金額だけの文に残ってよい文字（金額の表記と「11月分」）。
    private static let amountOnlyCharacters: Set<Character> = ["円", "¥", ",", ".", "万", "千", "百", "十", "月", "分", "/", "の"]

    private static let trimmedEdges = CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "、,。/;+"))
    private static let trailingParticles: Set<Character> = ["を", "で", "の", "は"]
    private static let leadingParticles: Set<Character> = ["を"]

    // MARK: - 文字

    private static func fold(_ c: Character) -> Character {
        KeywordMatcher.fold(String(c)).first ?? c
    }

    private static func has(_ word: [Character], in folded: [Character], at index: Int) -> Bool {
        guard index + word.count <= folded.count else { return false }
        return Array(folded[index..<(index + word.count)]) == word
    }

    /// `index` から「カード」が始まるか（前に語の文字が続いていても、ブランドの名前として拾うため）。
    private static func startsBareCard(_ folded: [Character], at index: Int) -> Bool {
        has(Array(bareCard), in: folded, at: index)
    }

    /// 語の文字か（カタカナ・漢字・英字）。ひらがな・数字・空白・記号は語の区切りとみなす（「850カードで」「ランチをカードで」）。
    static func isWordCharacter(_ c: Character) -> Bool {
        if c.isASCII { return c.isLetter }
        guard let scalar = c.unicodeScalars.first, c.unicodeScalars.count == 1 else { return false }
        let value = scalar.value
        return (0x30A1...0x30FA).contains(value) || value == 0x30FC
            || (0x4E00...0x9FFF).contains(value) || (0x3400...0x4DBF).contains(value) || value == 0x3005
    }

    /// 1 語の区切りの文字か（空白と区切りの記号）。
    static func isTokenSeparator(_ c: Character) -> Bool {
        c.isWhitespace || "、,。/;()[]「」【】".contains(c)
    }

    private static func skippingSpaces(_ chars: [Character], from index: Int) -> Int {
        var i = index
        while i < chars.count, chars[i].isWhitespace { i += 1 }
        return i
    }
}
