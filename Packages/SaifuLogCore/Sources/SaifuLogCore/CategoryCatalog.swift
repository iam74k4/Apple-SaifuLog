import Foundation

/// 利用者が作ったカテゴリの表示の情報（名前・記号・色）。docs/design.md §8 の作ったカテゴリの決め事。
public struct CustomCategoryInfo: Sendable, Hashable, Identifiable {
    /// ID（UUID の小文字の文字列）。記録にはこの ID だけを保存する（`EntryCategory.custom`）。
    public let id: String
    /// 名前（利用者が決める。`CategoryCatalog.validateName` で確かめた形）。
    public var name: String
    /// SF Symbols の名前（`CategoryCatalog.symbolChoices` から選ぶ）。
    public var symbolName: String
    /// 色の番号（アプリの色の選択肢の位置。範囲の外なら 0 番として扱う）。
    public var colorIndex: Int

    public init(id: String, name: String, symbolName: String, colorIndex: Int) {
        self.id = id
        self.name = name
        self.symbolName = symbolName
        self.colorIndex = colorIndex
    }

    /// 記録に保存するカテゴリ。
    public var category: EntryCategory {
        .custom(id)
    }
}

/// カテゴリの一覧（組み込みの 8 種と、利用者が作ったカテゴリ）。作ったカテゴリの名前・記号・色を引き、画面の並びを決める。
///
/// 決め事:
/// - 画面の並びは、組み込みの「その他」以外（定義の順）、作ったカテゴリ（利用者が決めた順）、「その他」（`all`）。
///   「その他」を最後に置くのは、どれにも当たらないときに選ぶものだから。
/// - 一覧に無い作ったカテゴリ（別の端末で消した・まだ iCloud から届いていない）は、「その他」として名前を出す（`name(of:)`）。
///   記録そのものは書き換えない（届けば名前が出る）。
/// - 作ったカテゴリには、文の中にその名前が書かれていれば当てる（`customCategory(namedIn:)`。修正の記憶より先に見る。
///   `CategoryMemory`）。名前が 2 つ当たれば長いほう。
/// - AI の選択肢とキーワード辞書は組み込みの 8 種だけ（`EntryCategory.builtIns`）。
public struct CategoryCatalog: Sendable, Hashable {
    /// 作ったカテゴリ（利用者が決めた順）。
    public let customs: [CustomCategoryInfo]

    /// 組み込みの 8 種だけの一覧（作ったカテゴリが無い、または一覧を読めないとき）。
    public static let builtIn = CategoryCatalog(customs: [])

    /// 作れるカテゴリの数の上限。多すぎると、聞き返しのボタンや予算の欄が長くなって選びにくくなるため。
    public static let maximumCustomCount = 20
    /// 名前の最大の長さ（文字）。返事の行・月のまとめの行・ボタンに収まる長さにする。
    public static let maximumNameLength = 12

    /// 作ったカテゴリに選べる記号（SF Symbols）。組み込みのカテゴリの記号とは別のもの。
    public static let symbolChoices = [
        "tshirt", "scissors", "house", "gift", "graduationcap", "pawprint", "car", "dumbbell",
        "heart", "gamecontroller", "book", "airplane", "leaf", "bag", "wineglass", "music.note",
        "camera", "wrench.and.screwdriver", "building.columns", "sparkles",
    ]

    public init(customs: [CustomCategoryInfo]) {
        self.customs = customs
    }

    /// 画面に並べるカテゴリ（組み込みの「その他」以外、作ったカテゴリ、「その他」の順）。
    public var all: [EntryCategory] {
        EntryCategory.builtIns.filter { $0 != .other } + customs.map(\.category) + [.other]
    }

    /// 作ったカテゴリの情報。組み込みのカテゴリと、一覧に無い作ったカテゴリは nil。
    public func info(for category: EntryCategory) -> CustomCategoryInfo? {
        guard let id = category.customID else { return nil }
        return customs.first { $0.id == id }
    }

    /// 一覧にあるカテゴリか（組み込みはいつもある）。
    public func contains(_ category: EntryCategory) -> Bool {
        !category.isCustom || info(for: category) != nil
    }

    /// 日本語の名前（AI に渡す文・CSV・読み上げの元）。組み込みは表示名、作ったカテゴリはその名前、一覧に無い作ったカテゴリは
    /// 「その他」。
    public func name(of category: EntryCategory) -> String {
        info(for: category)?.name ?? category.displayName
    }

    /// 文の中に名前が書かれた作ったカテゴリ（表記ゆれをそろえて比べる。2 つ当たれば長い名前、同じ長さなら一覧で前のもの）。
    /// 当たらなければ nil。
    public func customCategory(namedIn text: String) -> EntryCategory? {
        let haystack = KeywordMatcher.fold(TextNormalizer.normalize(text))
        var best: (category: EntryCategory, length: Int)?
        for custom in customs {
            let needle = KeywordMatcher.fold(TextNormalizer.normalize(custom.name))
            guard !needle.isEmpty, haystack.contains(needle) else { continue }
            if let current = best, current.length >= needle.count { continue }
            best = (custom.category, needle.count)
        }
        return best?.category
    }

    /// 文に、組み込みか作ったカテゴリの名前が書かれているか。
    public func namesCategory(_ text: String) -> Bool {
        CategoryMemory.namesCategory(text) || customCategory(namedIn: text) != nil
    }

    // MARK: - 名前の確かめ

    /// 作るカテゴリの名前を確かめる。使える名前なら、前後の空白を除いた名前を返す。
    ///
    /// - Parameter editing: 名前を変えている作ったカテゴリの ID（自分の今の名前とは重なってよい）。
    public func validateName(_ name: String, editing: String? = nil) -> Result<String, CategoryNameIssue> {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .failure(.empty) }
        guard trimmed.count <= Self.maximumNameLength else { return .failure(.tooLong) }
        let folded = Self.fold(trimmed)
        let builtInNames = EntryCategory.builtIns.map(\.displayName) + ["光熱", "通信"]
        if builtInNames.contains(where: { Self.fold($0) == folded }) { return .failure(.duplicate) }
        if customs.contains(where: { $0.id != editing && Self.fold($0.name) == folded }) { return .failure(.duplicate) }
        return .success(trimmed)
    }

    /// 名前を比べる形にそろえる（全角・半角、ひらがな・カタカナ、英字の大小、空白を同じに扱う）。
    static func fold(_ name: String) -> String {
        KeywordMatcher.fold(TextNormalizer.normalize(name)).filter { !$0.isWhitespace }
    }
}

/// 作るカテゴリの名前が使えない理由。
public enum CategoryNameIssue: Error, Sendable, Hashable {
    /// 空。
    case empty
    /// 長すぎる（`CategoryCatalog.maximumNameLength` を超える）。
    case tooLong
    /// ほかのカテゴリ（組み込みか作ったもの）と同じ名前。
    case duplicate
}
