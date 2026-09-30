import Foundation

/// 覚えたカテゴリの 1 行の最小の形（「この言葉はこのカテゴリ」）。
///
/// 保存用のモデル（SwiftData）をコアに持ち込まずに覚えを読むための境目。アプリ側のモデルがこれに準拠する（`BudgetRecord` と同じ）。
public protocol LearnedCategoryRecord {
    /// 覚えた言葉（`CategoryMemory.key(for:)` でそろえた品目）。
    var phrase: String { get }
    /// カテゴリの rawValue。
    var categoryRawValue: String { get }
    /// 最後に書いた日時。
    var updatedAt: Date { get }
}

/// 利用者が選んだカテゴリの覚え（修正の記憶。docs/design.md §3-2 の「利用者の修正を覚える」）。
///
/// ⑥ でカテゴリを直したときと、「その他」になった記録の返事でカテゴリを選んだとき（聞き返し）に、品目の言葉とカテゴリの組を覚え、
/// 次から同じ言葉の記録をそのカテゴリにする。AI とキーワード辞書のどちらで読んだ記録にも、読み取った後に当てる（`applying(to:)`）。
///
/// 決め事:
/// - 言葉は品目（割り勘などの説明を除いたメモ。`item(ofMemo:amount:isIncome:)`）を、表記ゆれをそろえた形で持つ（`key(for:)`。
///   全角の英数字は半角に、ひらがなはカタカナに、英字は小文字に、続く空白は 1 つに）。「らんち」と「ランチ」、「UNIQLO」と
///   「uniqlo」を同じ言葉として扱うため。
/// - 当て方: そろえた品目と同じ言葉を覚えていればそれ。無ければ、品目に含まれる覚えた言葉（2 文字以上）のうち最も長いもの
///   （同じ長さなら文字の順で先のもの。覚えを読むたびに結果が変わらないように）。「ユニクロ」を覚えれば「ユニクロ 靴下」にも当てる。
///   1 文字の言葉を部分一致に使わないのは、「薬」を覚えたときに「薬局」「目薬」まで同じカテゴリにしないため（辞書の 1 文字の語を
///   絞っているのと同じ考え方。`EntryCategory.keywords`）。
/// - 覚えは、読み取ったカテゴリ（AI・辞書）より優先する。利用者がはっきり選んだものだから。ただし、品目にカテゴリの名前
///   （「日用品」など）が書かれていれば、その記録には当てない（その場で書いたカテゴリを、前の覚えで変えないため）。品目に作った
///   カテゴリの名前（「衣服」など）が書かれていれば、そのカテゴリにする（`CategoryCatalog.customCategory(namedIn:)`）。
/// - 一覧に無い作ったカテゴリ（消した・まだ iCloud から届いていない）を指す覚えは当てない。
/// - 収入には当てない（収入はカテゴリを持たず、いつも「その他」。`ParsedEntry.assemble`）。
/// - 同じ言葉の覚えが複数あれば（iCloud で別々の端末から届いた）、書いた日時の新しいものを採る。同じ日時ならカテゴリの
///   rawValue の順で先のもの（端末ごとに違うカテゴリにならないように。予算の行と同じ考え方。`BudgetPlan.preferred`）。
///   知らないカテゴリ（新しい版で足したカテゴリが iCloud で届いたとき）の行は読み飛ばす。
/// - 「その他のまま」を選んだ言葉も「その他」として覚える（同じ言葉でもう聞き返さないため。`asksCategory`）。
public struct CategoryMemory: Sendable, Hashable {
    /// 覚えた言葉とカテゴリ（言葉は `key(for:)` でそろえた形）。
    public let rules: [String: EntryCategory]

    public init(rules: [String: EntryCategory] = [:]) {
        self.rules = rules
    }

    /// 覚えた言葉の最大の長さ（文字）。これより長い品目は、同じ書き方で繰り返し記録することがまず無いので覚えない。
    public static let maximumKeyLength = 40
    /// 品目に含まれるかで当てる（部分一致の）覚えた言葉の最小の長さ（文字）。
    static let minimumContainedKeyLength = 2

    // MARK: - 読み込み

    /// 保存された覚えの行から、いま使う覚えを決める（上の決め事）。
    public static func resolve<Records: Sequence>(_ records: Records) -> CategoryMemory
    where Records.Element: LearnedCategoryRecord {
        var latest: [String: (category: EntryCategory, updatedAt: Date)] = [:]
        for record in records {
            guard let key = key(for: record.phrase),
                  let category = EntryCategory(rawValue: record.categoryRawValue)
            else { continue }
            if let current = latest[key], !isPreferred(
                category: category, updatedAt: record.updatedAt, over: current.category, updatedAt: current.updatedAt
            ) {
                continue
            }
            latest[key] = (category, record.updatedAt)
        }
        return CategoryMemory(rules: latest.mapValues(\.category))
    }

    /// 同じ言葉の行が複数あるとき、残す（有効とみなす）1 行。書いた日時の新しいもの、同じならカテゴリの rawValue の順で先のもの。
    /// 行が無ければ nil。アプリが覚えを書き換えるとき、この行を残してほかを片づける（`BudgetPlan.preferred` と同じ使い方）。
    public static func preferred<Record: LearnedCategoryRecord>(_ rows: [Record]) -> Record? {
        rows.reduce(nil) { best, row -> Record? in
            guard let best else { return row }
            let rowCategory = EntryCategory(rawValue: row.categoryRawValue)
            let bestCategory = EntryCategory(rawValue: best.categoryRawValue)
            // 知らないカテゴリの行は、知っているカテゴリの行に負ける（読めない行を残さないため）。
            switch (rowCategory, bestCategory) {
            case (nil, _): return best
            case (_?, nil): return row
            case let (rowCategory?, bestCategory?):
                return isPreferred(category: rowCategory, updatedAt: row.updatedAt, over: bestCategory, updatedAt: best.updatedAt)
                    ? row : best
            }
        }
    }

    private static func isPreferred(
        category: EntryCategory, updatedAt: Date, over other: EntryCategory, updatedAt otherUpdatedAt: Date
    ) -> Bool {
        if updatedAt != otherUpdatedAt { return updatedAt > otherUpdatedAt }
        return category.rawValue < other.rawValue
    }

    // MARK: - 言葉のそろえ方

    /// 品目を、覚えの言葉の形にそろえる（全角の英数字は半角、ひらがなはカタカナ、英字は小文字、前後の空白を除いて続く空白は 1 つ）。
    /// 空か、長すぎる（`maximumKeyLength` を超える）なら nil（覚えない）。
    public static func key(for item: String) -> String? {
        let folded = KeywordMatcher.fold(TextNormalizer.normalize(item))
        let key = folded.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        guard !key.isEmpty, key.count <= maximumKeyLength else { return nil }
        return key
    }

    /// 記録のメモから品目を取り出す（解析が書き足した割り勘などの説明を除く）。
    ///
    /// 解析の書いた形そのものなら `EntryMemoNote` で分ける。金額を直した記録などで書いた形と合わなくても、全角の括弧で終わる
    /// メモはその括弧の前までを品目にする（入力の全角の括弧は解析の前に半角にそろえるので、全角の括弧は説明にしか出てこない。
    /// `EntryMemoNote`）。
    public static func item(ofMemo memo: String, amount: Int, isIncome: Bool) -> String {
        if let note = EntryMemoNote(memo: memo, amount: amount, isIncome: isIncome) {
            return note.item
        }
        if memo.hasSuffix("）"), let open = memo.lastIndex(of: "（") {
            return String(memo[..<open]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return memo
    }

    // MARK: - 当て方

    /// 品目に当てる覚えたカテゴリ。覚えていなければ nil。
    public func category(forItem item: String) -> EntryCategory? {
        guard let key = Self.key(for: item) else { return nil }
        if let exact = rules[key] { return exact }
        var best: (key: String, category: EntryCategory)?
        for (learned, category) in rules where learned.count >= Self.minimumContainedKeyLength && key.contains(learned) {
            if let current = best,
               current.key.count > learned.count || (current.key.count == learned.count && current.key < learned) {
                continue
            }
            best = (learned, category)
        }
        return best?.category
    }

    /// 読み取った記録のカテゴリを、作ったカテゴリの名前と覚えで置き換える（上の決め事。収入と、品目に組み込みのカテゴリの名前が
    /// 書かれた記録は置き換えない）。
    ///
    /// - Parameter catalog: カテゴリの一覧（作ったカテゴリの名前を品目から探し、覚えが一覧に無いカテゴリを指していないかを見る）。
    public func applying(to entries: [ParsedEntry], catalog: CategoryCatalog = .builtIn) -> [ParsedEntry] {
        guard !rules.isEmpty || !catalog.customs.isEmpty else { return entries }
        return entries.map { entry in
            guard !entry.isIncome else { return entry }
            let item = Self.item(ofMemo: entry.memo, amount: entry.amount, isIncome: false)
            let resolved: EntryCategory? = if let named = catalog.customCategory(namedIn: item) {
                named
            } else if Self.namesCategory(item) {
                nil
            } else {
                category(forItem: item).flatMap { catalog.contains($0) ? $0 : nil }
            }
            guard let resolved else { return entry }
            var result = entry
            result.category = resolved
            return result
        }
    }

    /// 記録の返事で、カテゴリを聞き返すか（「その他」になった支出で、品目が辞書にも覚えにも当たらないとき）。
    ///
    /// 辞書の「その他」の語（「洋服」「美容院」など）やカテゴリの名前に当たった品目は、その他と読んだ理由があるので聞き返さない
    /// （`EntryCategory.matched(in:)`）。覚えた言葉（「その他のまま」を選んだ言葉も）は聞き返さない。ただし、一覧に無い作ったカテゴリを
    /// 指す覚え（ほかの端末で消した・まだ届いていない）は、当てない（`applying`）ので無いものとして聞き返す。品目の無い記録（金額だけ）は
    /// 聞き返す（覚えられないが、その記録のカテゴリは選べる）。自信が無いときだけ聞き返し、一行入力の軽さを保つ（§3-2）。
    ///
    /// - Parameter catalog: カテゴリの一覧（作ったカテゴリの名前が書かれた品目は聞き返さない）。
    public func asksCategory(
        memo: String, amount: Int, category: EntryCategory, isIncome: Bool, catalog: CategoryCatalog = .builtIn
    ) -> Bool {
        guard !isIncome, category == .other else { return false }
        let item = Self.item(ofMemo: memo, amount: amount, isIncome: false)
        let learned = self.category(forItem: item).flatMap { catalog.contains($0) ? $0 : nil }
        guard learned == nil, catalog.customCategory(namedIn: item) == nil else { return false }
        return EntryCategory.matched(in: item) == nil
    }

    /// 品目に組み込みのカテゴリの名前（「食費」「日用品」など）が書かれているか。
    static func namesCategory(_ item: String) -> Bool {
        let haystack = KeywordMatcher.fold(item)
        return EntryCategory.builtIns.contains { haystack.contains(KeywordMatcher.fold($0.displayName)) }
    }
}
