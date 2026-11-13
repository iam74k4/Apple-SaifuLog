import Foundation

/// 直前の記録のカテゴリを、チャットの文で直す（「それ日用品」「さっきのは交際費にして」「食費じゃなくて日用品」。docs/design.md §3-2）。
///
/// 返事のボタンや ⑥ を探さずに、会話のまま直せるようにする。読み取りはコードで決める（AI に任せない。誤って記録を書き換えない
/// ことを優先し、テストで境目を確かめるため）。
///
/// 決め事:
/// - 数字を含む文は直す文にしない（金額のある文は記録か、金額を直す文。`InputIntentClassifier`）。「?」などのはっきりした
///   質問の語を含む文もしない。
/// - 文の中にカテゴリの名前（組み込みの表示名と言い換え・作ったカテゴリの名前）がちょうど 1 つあり、名前を除いた残りが、
///   前の記録を指す語（「さっき」「それ」「今の」など）・直す語（「にして」「に変えて」など）・助詞と語尾（「は」「だよ」など）
///   だけのときに限る（「ランチは食費」「今月の食費」のように、ほかの語が残る文は直さない）。名前だけの文（「日用品」）も直す文にする
///   （金額の無い記録の文としては読めないため）。
/// - 「AじゃなくてB」は、後ろのカテゴリ（B）にする。
/// - どの記録を直すかはアプリが決める（直前の送信の記録が 1 件か、聞き返している記録が 1 件のときだけ。`HomeModel`）。
public enum CategoryCorrection {
    /// 直す文なら、直した先のカテゴリ。直す文でなければ nil。
    public static func category(in text: String, catalog: CategoryCatalog = .builtIn) -> EntryCategory? {
        let normalized = TextNormalizer.normalize(text)
        guard !normalized.contains(where: \.isNumber) else { return nil }
        let questionWords = InputIntentClassifier.strongQuestionWords
        guard !questionWords.contains(where: { normalized.contains($0) }) else { return nil }

        var folded = CategoryCatalog.fold(normalized)
        // 「AじゃなくてB」は後ろを見る（前は直す前のカテゴリなので、名前でも語でもよい）。
        for marker in negationMarkers.map(CategoryCatalog.fold) {
            if let range = folded.range(of: marker, options: .backwards) {
                folded = String(folded[range.upperBound...])
                break
            }
        }
        guard let match = longestName(in: folded, catalog: catalog) else { return nil }
        let (category, name) = match
        var rest = folded.replacingOccurrences(of: name, with: " ")
        // ほかのカテゴリの名前が残っていれば、どれにするか決められない。
        guard longestName(in: rest.replacingOccurrences(of: " ", with: ""), catalog: catalog) == nil else { return nil }
        for filler in fillers {
            rest = rest.replacingOccurrences(of: filler, with: "")
        }
        rest = rest.filter { !$0.isWhitespace && !fillerCharacters.contains($0) }
        return rest.isEmpty ? category : nil
    }

    // MARK: - 名前

    /// カテゴリの名前と、その言い換え（そろえた形）。
    static func names(in catalog: CategoryCatalog) -> [(category: EntryCategory, name: String)] {
        var result: [(category: EntryCategory, name: String)] = []
        for category in catalog.all {
            let names = [catalog.name(of: category)] + (aliases[category] ?? [])
            for name in names {
                let folded = CategoryCatalog.fold(name)
                if !folded.isEmpty { result.append((category: category, name: folded)) }
            }
        }
        return result
    }

    /// 文の中のいちばん長いカテゴリの名前（同じ長さなら一覧で前のもの）。
    private static func longestName(in folded: String, catalog: CategoryCatalog) -> (EntryCategory, String)? {
        var best: (EntryCategory, String)?
        for (category, name) in names(in: catalog) where folded.contains(name) {
            if let current = best, current.1.count >= name.count { continue }
            best = (category, name)
        }
        return best
    }

    /// 組み込みのカテゴリの言い換え（表示名のほかに、直すときに書きそうな名前）。
    static let aliases: [EntryCategory: [String]] = [
        .food: ["食べ物", "食料品"],
        .transport: ["交通費"],
        .entertainment: ["娯楽費", "趣味"],
        .utilities: ["光熱費", "通信費", "光熱", "通信"],
        .medical: ["医療費"],
    ]

    // MARK: - 残りの語

    /// 「AじゃなくてB」の、間の語。
    static let negationMarkers = ["じゃなくて", "じゃなく", "ではなくて", "ではなく"]

    /// 名前のほかに残ってよい語（前の記録を指す語・直す語・語尾。長いものから外す）。
    static let fillers: [String] = [
        "に変更してください", "に変えてください", "にしてください", "に直してください", "でお願いします", "でおねがいします",
        "に変更して", "に変えて", "にかえて", "に直して", "になおして", "にしといて", "にしておいて", "にしておく", "にする",
        "にして", "に変更", "でお願い", "でおねがい", "お願いします", "お願い", "おねがい",
        "さっきの", "さっき", "いまの", "今の", "直前の", "最後の", "前の", "それは", "それ", "これ", "あれ", "やつ",
        "カテゴリー", "カテゴリ", "分類", "記録", "でした", "だった", "です", "だよ", "だね", "して",
    ].map(CategoryCatalog.fold).sorted { $0.count > $1.count }

    /// 名前のほかに残ってよい 1 文字（助詞・語尾・記号。そろえた形）。
    static let fillerCharacters = Set(CategoryCatalog.fold("はをものにでがへとてだよねなっ") + "。、.,!！~〜…・")
}
