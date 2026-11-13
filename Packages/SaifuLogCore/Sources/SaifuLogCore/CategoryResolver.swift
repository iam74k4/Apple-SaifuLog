import Foundation

/// ひとこと入力で読み取った記録のカテゴリを、AI に聞き直す前に手元の手がかりで決める（docs/design.md §3-2 の振り分けの順）。
///
/// 当てる順（上が強い）:
/// 1. 品目に作ったカテゴリの名前が書かれていれば、そのカテゴリ（`CategoryCatalog.customCategory(namedIn:)`）。品目と同じ言葉の
///    覚え（`CategoryMemory.exactCategory(forItem:)`）があれば、そのカテゴリ（利用者がその品目について選んだものなので、品目に
///    組み込みのカテゴリの名前が入っていても当てる）。組み込みのカテゴリの名前（「日用品」など）が書かれていれば、読み取った
///    カテゴリのまま（その場で書いたカテゴリを、ほかの言葉の覚えや履歴で変えない）。
/// 2. 覚えたカテゴリ（利用者が返事・⑥・チャットで選んだもの。品目に含まれる言葉の覚え。`CategoryMemory`）。
/// 3. 過去の記録のいつものカテゴリ（`CategoryHistory`）。
/// 4. 読み取ったカテゴリ（AI かキーワード辞書）が「その他」でなければ、それ。
/// 5. 店の名前の辞書のチェーンの名前（レシートと同じ `ReceiptStoreDictionary`。「マツキヨ」「ローソン」など。店の種類の語と、
///    ほかの意味にもなる名前は当てない。`ReceiptStoreDictionary.chainCategory(forTypedItem:)`）。
/// 6. どれでも決まらなければ「その他」のまま（AI に聞き直し、それでも決まらなければ返事で聞き返す。`CategoryRefinement`）。
///
/// 一覧に無い作ったカテゴリ（消した・まだ iCloud から届いていない）を指す覚えと履歴は当てない。収入は変えない（収入はカテゴリを
/// 持たず、いつも「その他」。`ParsedEntry.assemble`）。
public enum CategoryResolver {
    /// カテゴリを何で決めたか。AI に聞き直すか（`CategoryRefinement.requests`）と、返事で聞き返すか（`asksCategory`）を決める。
    public enum Source: Sendable, Hashable {
        /// 収入（カテゴリを持たない）。
        case income
        /// 品目にカテゴリの名前が書かれていた。
        case named
        /// 覚えたカテゴリ。
        case learned
        /// 過去の記録のいつものカテゴリ。
        case history
        /// 読み取ったカテゴリ（AI かキーワード辞書）。
        case parsed
        /// 店の名前の辞書。
        case store
        /// 決まらなかった（「その他」）。
        case unresolved
    }

    /// 記録 1 件の振り分け。
    public struct Resolution: Sendable, Hashable {
        public var entry: ParsedEntry
        public let source: Source

        public init(entry: ParsedEntry, source: Source) {
            self.entry = entry
            self.source = source
        }

        /// 品目（割り勘などの説明を除いたメモ）。
        public var item: String {
            CategoryMemory.item(ofMemo: entry.memo, amount: entry.amount, isIncome: entry.isIncome)
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        /// 返事でカテゴリを聞き返すか。決まらずに「その他」のままの支出で、品目が辞書の「その他」の語（「洋服」「美容院」など）にも
        /// 当たらないとき（その他と読んだ理由があるものは聞き返さない）。品目の無い記録（金額だけ）も聞き返す（覚えられないが、
        /// その記録のカテゴリは選べる）。AI に聞き直してカテゴリが決まった記録は聞き返さない。
        public var asksCategory: Bool {
            source == .unresolved && entry.category == .other && EntryCategory.matched(in: item) == nil
        }
    }

    /// 読み取った記録を、上の順で振り分ける（記録の順のまま）。
    public static func resolve(
        _ entries: [ParsedEntry], memory: CategoryMemory, history: CategoryHistory = CategoryHistory(),
        catalog: CategoryCatalog = .builtIn
    ) -> [Resolution] {
        entries.map { resolve($0, memory: memory, history: history, catalog: catalog) }
    }

    private static func resolve(
        _ entry: ParsedEntry, memory: CategoryMemory, history: CategoryHistory, catalog: CategoryCatalog
    ) -> Resolution {
        guard !entry.isIncome else { return Resolution(entry: entry, source: .income) }
        let item = CategoryMemory.item(ofMemo: entry.memo, amount: entry.amount, isIncome: false)
        func resolved(_ category: EntryCategory, _ source: Source) -> Resolution {
            var result = entry
            result.category = category
            return Resolution(entry: result, source: source)
        }
        if let named = catalog.customCategory(namedIn: item) { return resolved(named, .named) }
        if let exact = memory.exactCategory(forItem: item), catalog.contains(exact) { return resolved(exact, .learned) }
        if CategoryMemory.namesCategory(item) { return Resolution(entry: entry, source: .named) }
        if let learned = memory.category(forItem: item), catalog.contains(learned) { return resolved(learned, .learned) }
        if let usual = history.category(forItem: item), catalog.contains(usual) { return resolved(usual, .history) }
        if entry.category != .other { return Resolution(entry: entry, source: .parsed) }
        if let store = ReceiptStoreDictionary.chainCategory(forTypedItem: item) { return resolved(store, .store) }
        return Resolution(entry: entry, source: .unresolved)
    }
}
