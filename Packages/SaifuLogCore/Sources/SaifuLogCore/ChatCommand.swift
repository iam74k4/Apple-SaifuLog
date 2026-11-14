import Foundation

/// チャットの文で頼める操作（記録にも質問にもしない文。docs/design.md §2 の「チャットで操作する」）。
///
/// 返事のボタンや ⑥・設定を探さずに、会話のまま直す・消す・予算を決めるため。どの操作かは、まずコードの決まり
/// （`ChatCommandReader.command(in:now:calendar:catalog:)`）で読み、決まりで読めずに「記録か質問か決められない文」「前の記録を
/// 直そうとする文」になったものだけ、端末内 AI に操作の種類を選ばせる（`ChatCommandInterpreting`）。値（金額・カテゴリ）は
/// どちらのときも文からコードが読む（AI に数字を扱わせない決まり）。
public enum ChatCommand: Hashable, Sendable {
    /// 直前の記録のカテゴリを変える（「それ日用品」）。
    case recategorize(EntryCategory)
    /// 直前の記録の金額を直す（「さっきのを900に直して」「850じゃなくて950」）。
    case changeAmount(Int)
    /// 直前の記録を消す（「さっきの消して」「今のなし」）。
    case removeLast
    /// 月の全体の予算を決める（「今月の予算を5万にして」）。
    case setMonthlyBudget(Int)
}

/// 端末内 AI に選ばせる操作の種類。値は持たない（値は文からコードが読む。`ChatCommandReader.command(kind:in:now:calendar:catalog:)`）。
public enum ChatCommandKind: String, CaseIterable, Sendable {
    case recategorize
    case changeAmount
    case removeLast
    case setMonthlyBudget
    /// どの操作でもない（記録か質問か決められない文のまま、書き直しを頼む）。
    case none
}

/// 文がどの操作の種類かを選ぶもの（端末内 AI）。コアは AI に依存しないので、選び方はアプリが渡す。
public protocol ChatCommandInterpreting: Sendable {
    func kind(of text: String) async throws -> ChatCommandKind
}

/// チャットの文から操作を読む（純粋な関数）。**誤って記録を書き換えないことを優先する**（読めなければ nil にし、ふつうの送信として扱う）。
///
/// 決まりで読む操作（上から順に見る）:
/// 1. カテゴリを変える文（`CategoryCorrection`）。
/// 2. 消す文: 数字が無く、消す語（「消して」「削除」「取り消して」「なかったことに」「キャンセル」など）のほかは前の記録を指す語・
///    語尾だけ。「なし」「いらない」「やめて」は、前の記録を指す語（「さっき」「今の」「それ」など）があるときだけ（「なし」だけの
///    返事や「カテゴリなし」で記録を消さないため。「カテゴリ」「分類」は消す文に残ってよい語にしない）。消す語と「なし」「いらない」
///    「やめて」が一緒の文（「削除はいらない」「取り消すのはやめて」）と、消す語を打ち消す文（「削除しないで」）は消す文にしない。
/// 3. 月の予算を決める文: 「予算」とふつうの金額がちょうど 1 つあり（合計・ポイント・おつりの額は数えない）、カテゴリの名前が無く
///    （カテゴリごとの予算は無いので、決めたつもりにさせない）、ほかの期間（「来月」「前の月」「年間」「週」「日」「12月」）や残り・超えた額の
///    語（「残り」「超え」「オーバー」）が無く、残りが「今月」「毎月」・決める語（「にして」「に設定」など）・丁寧な語尾・助詞だけ
///    （「だった」「でした」のような過去の言い方は残してよい語にしない。前の月や過去の額を言う文で、今月の予算を書き換えないため）。
/// 4. 金額を直す文: 前の記録を直そうとする文（`InputIntentClassifier` の直す語）で、直した先の金額（ふつうの金額か税込みの額。
///    値引き・合計・おつり・ポイントは数えない）がちょうど 1 つあり、金額のほかは前の記録を指す語・直す語・語尾だけ（「前のタイヤ
///    変えて 20000」のように品目が残る文は記録）。前の記録を指す語が無くても、金額と直す語と語尾だけの文（「900に直して」）は直す文。
///    「AじゃなくてB」は後ろの金額にし、A は直す前の金額か前の記録を指す語だけのときに限る（「スタバじゃなくてドトール 400」は
///    金額を直す文ではない。A にポイント・おつり・値引きなどの額があれば読まない）。予算の語があれば読まない。
public enum ChatCommandReader {
    public static func command(
        in text: String, now: Date, calendar: Calendar, catalog: CategoryCatalog = .builtIn
    ) -> ChatCommand? {
        if let category = CategoryCorrection.category(in: text, catalog: catalog) { return .recategorize(category) }
        let normalized = TextNormalizer.normalize(text)
        guard !containsStrongQuestionWord(normalized) else { return nil }
        if isRemoval(normalized) { return .removeLast }
        if let budget = monthlyBudget(in: normalized, now: now, calendar: calendar, catalog: catalog, strict: true) {
            return .setMonthlyBudget(budget)
        }
        if !normalized.contains(budgetWord),
           let amount = correctedAmount(in: normalized, now: now, calendar: calendar, strict: true) {
            return .changeAmount(amount)
        }
        return nil
    }

    /// 端末内 AI が選んだ種類の操作を、文に書かれた値で組み立てる。値が文から読めなければ nil（AI の選んだ種類だけでは書き換えない）。
    ///
    /// 決まりより緩く読むが、値は必ず文に書かれたものにし、種類に合う語の無い文では組み立てない（小さなモデルは、比べる文や
    /// 記録の文にも操作を選ぶことがあるため）:
    /// - カテゴリ: カテゴリの名前がちょうど 1 つ（「AじゃなくてB」は B）で、数字が無い。
    /// - 金額: 前の記録を指す語・直す語（「さっき」「それ」「直して」「実は」「金額」など）があり、直した先の金額がちょうど 1 つか
    ///   「じゃなくて」の後ろ（前は金額か前の記録を指す語だけ）。予算の語があれば読まない。
    /// - 消す: 消す語があり、数字とカテゴリの語（「カテゴリなし」）が無い。
    /// - 予算: 決まりと同じ期間の確かめをし、残りの語は問わない。
    public static func command(
        kind: ChatCommandKind, in text: String, now: Date, calendar: Calendar, catalog: CategoryCatalog = .builtIn
    ) -> ChatCommand? {
        let normalized = TextNormalizer.normalize(text)
        guard !containsStrongQuestionWord(normalized) else { return nil }
        switch kind {
        case .recategorize:
            guard !hasDigit(normalized),
                  let sole = CategoryCorrection.soleCategory(
                      in: CategoryCorrection.afterNegation(CategoryCatalog.fold(normalized)), catalog: catalog
                  )
            else { return nil }
            return .recategorize(sole.category)
        case .changeAmount:
            guard !normalized.contains(budgetWord), mentionsAmountEdit(normalized) else { return nil }
            return correctedAmount(in: normalized, now: now, calendar: calendar, strict: false).map(ChatCommand.changeAmount)
        case .removeLast:
            let folded = CategoryCatalog.fold(normalized)
            guard !hasDigit(normalized), removalCues.contains(where: { folded.contains($0) }),
                  !categoryWords.contains(where: { folded.contains($0) }), !negatesRemoval(folded)
            else { return nil }
            return .removeLast
        case .setMonthlyBudget:
            return monthlyBudget(in: normalized, now: now, calendar: calendar, catalog: catalog, strict: false)
                .map(ChatCommand.setMonthlyBudget)
        case .none:
            return nil
        }
    }

    // MARK: - 消す

    /// それだけで消す文になる語。
    static let removalWords = [
        "取り消して", "とりけして", "取り消し", "とりけし", "取り消す", "とりけす", "取消", "消しといて", "消しておいて", "消して",
        "けして", "削除して", "削除", "なかったことにして", "なかったことに", "無かったことにして", "無かったことに",
        "キャンセルして", "キャンセル",
    ]

    /// 前の記録を指す語（`pointerWords`）と一緒のときだけ、消す文になる語（「今のなし」）。
    static let weakRemovalWords = [
        "なしにして", "なしで", "なしね", "なし", "無しにして", "無しで", "無しね", "無し", "いらない", "要らない", "やめて", "止めて",
    ]

    /// 前の記録を指す語。記録か質問かの見分け（`InputIntentClassifier.referenceWords`）と同じ語にする（片方にしか無い語で書いた
    /// 直す文が、こちらでは読めず、あちらでは新しい記録になったため）。
    static let pointerWords = InputIntentClassifier.referenceWords

    /// 消すことを打ち消す言い方（「削除しないで」「消さないで」「消してない」「取り消しません」。そろえた形）。
    static let removalNegations = ["ないで", "なくて", "しない", "さない", "てない", "ません", "せずに"].map(CategoryCatalog.fold)

    /// 打ち消しの言い方を含むが、打ち消しではない語（「すみません、さっきの消して」の「ません」）。そろえた形。
    static let removalNegationExceptions = ["すみません", "すいません", "申し訳ありません", "もうしわけありません"].map(CategoryCatalog.fold)

    private static func isRemoval(_ normalized: String) -> Bool {
        guard !hasDigit(normalized) else { return false }
        var folded = CategoryCatalog.fold(normalized)
        let strong = removalWords.map(CategoryCatalog.fold)
        let weak = weakRemovalWords.map(CategoryCatalog.fold)
        let hasStrong = strong.contains { folded.contains($0) }
        let hasWeak = weak.contains { folded.contains($0) }
        guard hasStrong || hasWeak, !negatesRemoval(folded) else { return false }
        if !hasStrong {
            let pointers = pointerWords.map(CategoryCatalog.fold)
            guard pointers.contains(where: { folded.contains($0) }) else { return false }
        }
        for word in (strong + weak).sorted(by: { $0.count > $1.count }) {
            folded = folded.replacingOccurrences(of: word, with: "")
        }
        return onlyFillers(folded, extra: removalFillers)
    }

    /// 消すことを打ち消す文か（そろえた文）。
    ///
    /// - 消す語を打ち消す言い方（「削除しないで」「消さないで」「消してない」）。
    /// - 消す語と「いらない」「やめて」「なし」が一緒の文（「削除はいらない」「取り消すのはやめて」「キャンセルはなしで」）。前は両方の
    ///   語を外してから残りを見ていたので、残りが助詞だけになり、直前の記録を消していた。決まりで読んだ消す操作は確認なしで行い、
    ///   元に戻せないので、どちらとも読める文は消さない（AI が消す操作を選んでも、確認を出す前に組み立てない）。
    private static func negatesRemoval(_ folded: String) -> Bool {
        let apologyMasked = removalNegationExceptions.reduce(folded) { $0.replacingOccurrences(of: $1, with: " ") }
        if removalNegations.contains(where: { apologyMasked.contains($0) }) { return true }
        let hasStrong = removalWords.map(CategoryCatalog.fold).contains { folded.contains($0) }
        let hasWeak = weakRemovalWords.map(CategoryCatalog.fold).contains { folded.contains($0) }
        return hasStrong && hasWeak
    }

    /// 消す文に残ってよい語（「やっぱり」「全部」など）。
    static let removalFillers = [
        "やっぱり", "やっぱ", "ごめんなさい", "ごめん", "すみません", "すいません", "まちがい", "間違い", "まちがえた", "間違えた",
        "全部", "ぜんぶ", "ください", "下さい",
    ]

    /// AI が消す操作を選んだ文に、どれか 1 つは要る語（消す語の頭。そろえた形）。
    static let removalCues = [
        "消", "ケシ", "削除", "取リ消", "トリケ", "取消", "ナカッタコト", "無カッタコト", "ナシ", "無シ", "イラナ", "要ラナ", "ヤメ",
        "止メ", "キャンセル",
    ].map(CategoryCatalog.fold)

    /// カテゴリを指す語（そろえた形）。「カテゴリなし」「分類いらない」は記録を消す文ではないので、消す文・金額を直す文に残さない。
    static let categoryWords = ["カテゴリー", "カテゴリ", "分類"].map(CategoryCatalog.fold)

    // MARK: - 予算

    static let budgetWord = "予算"
    /// 予算の文に残ってよい語（期間と決める語）。この順に外す（「今月」を「月」より先に外し、「今」を残さないため）。
    static let budgetFillers = [
        "今月から", "今月", "毎月", "ひと月", "全体の", "全体",
        "に設定して", "に設定", "設定して", "設定", "に変更して", "に変更", "に変えて", "にかえて",
        "にしといて", "にしておいて", "にしておく", "にして", "にする",
        "で決めて", "に決めて", "決めて", "きめて", "でお願い", "でおねがい", "お願い", "月の", "月", "円",
    ]
    /// 予算の文に、期間と決める語のほかに残ってよい語（丁寧な語尾）。前の記録を指す語や「だった」「でした」は入れない
    /// （「前の月の予算は5万だった」のような、過ぎた月や前の額を言う文で、今月の予算を書き換えないため）。
    static let budgetTails = [
        "でお願いします", "でおねがいします", "お願いします", "おねがいします", "ください", "下さい", "です", "だよ",
    ]
    /// 予算の文で読まない期間の語（予算はいまの月から当てるので、ほかの月を指す文は決めない）。
    static let otherMonthWords = ["来月", "先月", "去年", "来年", "前の月", "前月", "翌月", "次の月", "先々月", "再来月"]
    /// 月の予算を決める文では読まない語（月ではない期間と、予算の残り・超えた額を言う語）。「年間の予算60万」「予算の残り3万」
    /// 「予算を5000オーバー」を、月の予算をその額にする文にしないため。
    static let nonMonthlyBudgetWords = ["年", "週", "日", "残り", "のこり", "超え", "こえ", "オーバー", "超過"]

    /// 月の全体の予算として読める金額。`strict` なら、予算・金額・期間・決める語のほかに語が残る文は読まない。
    private static func monthlyBudget(
        in normalized: String, now: Date, calendar: Calendar, catalog: CategoryCatalog, strict: Bool
    ) -> Int? {
        guard normalized.contains(budgetWord), !mentionsOtherPeriod(normalized) else { return nil }
        // カテゴリの名前のある予算の文は読まない（カテゴリごとの予算は無いので、全体の予算をその額にしてしまわないように）。
        let folded = CategoryCatalog.fold(normalized)
        guard !CategoryCorrection.names(in: catalog).contains(where: { folded.contains($0.name) }) else { return nil }
        let scan = EntryScan(normalized, now: now, calendar: calendar)
        // 予算の額はふつうの金額だけ（「今月の合計 3000円の予算」の合計の額や、ポイント・おつりの額を予算にしない）。
        guard scan.amounts.count == 1, let amount = scan.amounts.first, amount.role == .primary, !amount.isNegative,
              amount.value > 0, amount.value <= BudgetPlan.maximumAmount else { return nil }
        guard strict else { return amount.value }
        var rest = String(scan.chars.enumerated().filter { !amount.range.contains($0.offset) }.map(\.element))
        rest = CategoryCatalog.fold(rest).replacingOccurrences(of: CategoryCatalog.fold(budgetWord), with: "")
        // 丁寧な語尾を先に外し（「でお願いします」を「でお願い」より先に）、期間と決める語は並べた順に外す（「今月」を「月」より先に
        // 外し、「今」を残さないため）。
        for word in (budgetTails + budgetFillers).map(CategoryCatalog.fold) {
            rest = rest.replacingOccurrences(of: word, with: "")
        }
        // 前の記録を指す語・過去の言い方（`recordFillers`）は残してよい語にしない。残りは助詞と記号だけにする。
        return rest.allSatisfy({ $0.isWhitespace || CategoryCorrection.fillerCharacters.contains($0) }) ? amount.value : nil
    }

    /// いまの月の全体の予算ではない期間や、予算の残り・超えた額を言う文か（「12月の予算」の「12月」も）。
    private static func mentionsOtherPeriod(_ normalized: String) -> Bool {
        if (otherMonthWords + nonMonthlyBudgetWords).contains(where: { normalized.contains($0) }) { return true }
        let chars = Array(normalized)
        return chars.indices.contains { $0 > 0 && chars[$0] == "月" && chars[$0 - 1].isASCIIDigit }
    }

    // MARK: - 金額を直す

    /// 金額を直す文に残ってよい語（金額を指す語・直す語・言い直しの語。`CategoryCorrection.fillers` のほかに）。
    static let amountFillers = [
        "金額", "お値段", "値段", "額", "訂正して", "訂正", "修正して", "修正", "間違えた", "まちがえた", "間違い", "まちがい",
        "直しといて", "直しておいて", "直して", "なおして", "直す", "変えて", "かえて", "変更して", "変更", "ごめん", "やっぱり",
        "やっぱ", "正しくは", "本当は", "ほんとは", "実は", "円", "ください", "下さい",
    ]

    /// AI が金額を直す操作を選んだ文に、どれか 1 つは要る語（前の記録を指す語・直す語・言い直しの語）。比べる文（「今月の食費 3万
    /// 超えた」）や金額の 2 つある文（「900か1000」）に AI が金額を直す操作を選んでも、前の記録を書き換えないため。
    static let amountEditCues = [
        "さっき", "先ほど", "さきほど", "前の", "今の", "直前", "最後の", "それ", "これ", "あれ", "直し", "直す", "なおし", "変え",
        "かえて", "変更", "訂正", "修正", "間違", "まちが", "実は", "本当は", "ほんとは", "正しくは", "金額", "値段",
    ]

    private static func mentionsAmountEdit(_ normalized: String) -> Bool {
        InputIntentClassifier.containsCorrectionWord(normalized) || amountEditCues.contains { normalized.contains($0) }
    }

    /// 直した先の金額。「AじゃなくてB」は B の金額（A は直す前の金額か、前の記録を指す語だけ）、それ以外は文の中にちょうど 1 つある金額。
    ///
    /// `strict` なら、金額のほかに前の記録を指す語・直す語・語尾しか残らない文だけを読み、「AじゃなくてB」でない文は前の記録を
    /// 直そうとする文（`InputIntentClassifier.containsCorrectionWord`）か、直す語のある文（「900に直して」。残りの語の確かめで、
    /// 金額と直す語と語尾だけの文に限る）に限る。
    private static func correctedAmount(in normalized: String, now: Date, calendar: Calendar, strict: Bool) -> Int? {
        if let marker = lastNegation(in: normalized) {
            let before = EntryScan(String(normalized[..<marker.lowerBound]), now: now, calendar: calendar)
            let beforeAmounts = candidates(in: before)
            // A にポイント・おつり・値引き・合計の額があれば読まない（「ポイント100じゃなくて200」は、ポイントの言い直しで、記録の金額を
            // 直す文ではない。前は候補にならない額を役目の語ごと外したので、A が前の記録を指す語だけに見え、記録の金額を書き換えていた）。
            guard beforeAmounts.count == before.amounts.count else { return nil }
            let beforeIsPointer = onlyFillers(residual(of: before, removing: before.amounts), extra: amountFillers)
            if strict {
                guard beforeAmounts.count <= 1, beforeIsPointer else { return nil }
            } else {
                guard !beforeAmounts.isEmpty || beforeIsPointer else { return nil }
            }
            return soleAmount(in: String(normalized[marker.upperBound...]), now: now, calendar: calendar, strict: strict)
        }
        guard !strict || InputIntentClassifier.containsCorrectionWord(normalized)
            || InputIntentClassifier.containsEditWord(normalized) else { return nil }
        return soleAmount(in: normalized, now: now, calendar: calendar, strict: strict)
    }

    /// 金額と直す語（「に直して」「に変えて」など）と語尾だけの文か（「900に直して」）。前の記録を指す語が無くても、前の記録の
    /// 金額を直そうとする文とみなす（品目が無いので新しい記録としては読めず、記録すると直したつもりの支出が二重になるため）。
    /// 記録か質問かの見分け（`InputIntentClassifier.classify`）が、直す文として扱うのに使う。
    static func isBareAmountEdit(_ normalized: String, now: Date, calendar: Calendar) -> Bool {
        guard InputIntentClassifier.containsEditWord(normalized) else { return false }
        let scan = EntryScan(normalized, now: now, calendar: calendar)
        guard !scan.amounts.isEmpty else { return false }
        return onlyFillers(residual(of: scan, removing: scan.amounts), extra: amountFillers)
    }

    /// 文の中にちょうど 1 つある、直した先の金額。`strict` なら、金額のほかに残ってよい語だけの文に限る。
    private static func soleAmount(in normalized: String, now: Date, calendar: Calendar, strict: Bool) -> Int? {
        let scan = EntryScan(normalized, now: now, calendar: calendar)
        let found = candidates(in: scan)
        guard found.count == 1, let amount = found.first, amount.value > 0,
              amount.value <= EntryAmountInput.maximumAmount else { return nil }
        if strict {
            guard onlyFillers(residual(of: scan, removing: [amount]), extra: amountFillers) else { return nil }
        }
        return amount.value
    }

    /// 直した先の金額に採る額（ふつうの金額と税込みの額）。値引き・税抜きの値段・合計・おつり・ポイントと、マイナスを付けた額は
    /// 採らない（「900 100円引き」の 100 を、直した先の金額の候補に数えないため）。
    private static func candidates(in scan: EntryScan) -> [EntryScan.Amount] {
        scan.amounts.filter { !$0.isNegative && ($0.role == .primary || $0.role == .taxIncluded) }
    }

    /// `amounts` の範囲を除いた文（そろえた形）。
    private static func residual(of scan: EntryScan, removing amounts: [EntryScan.Amount]) -> String {
        let removed = Set(amounts.flatMap { Array($0.range) })
        return CategoryCatalog.fold(String(scan.chars.enumerated().filter { !removed.contains($0.offset) }.map(\.element)))
    }

    /// 文の中の最後の「じゃなくて」などの範囲。
    private static func lastNegation(in normalized: String) -> Range<String.Index>? {
        for marker in CategoryCorrection.negationMarkers {
            if let range = normalized.range(of: marker, options: .backwards) { return range }
        }
        return nil
    }

    // MARK: - 共通

    /// 半角の数字を含むか（全角の数字はそろえてある）。`isNumber` は漢数字（「一旦」の「一」）も数字とみなすので使わない。
    private static func hasDigit(_ text: String) -> Bool {
        text.contains(where: \.isASCIIDigit)
    }

    private static func containsStrongQuestionWord(_ normalized: String) -> Bool {
        InputIntentClassifier.strongQuestionWords.contains { normalized.contains($0) }
    }

    /// 消す文・金額を直す文・予算の文に残ってよい語（`CategoryCorrection` の前の記録を指す語・語尾。「カテゴリ」「分類」は除く）。
    static let recordFillers = CategoryCorrection.fillers.filter { !categoryWords.contains($0) }

    /// そろえた文が、前の記録を指す語・語尾（`recordFillers`）と `extra` だけか。
    private static func onlyFillers(_ folded: String, extra: [String]) -> Bool {
        var rest = folded
        for word in (recordFillers + extra.map(CategoryCatalog.fold)).sorted(by: { $0.count > $1.count }) {
            rest = rest.replacingOccurrences(of: word, with: "")
        }
        return rest.allSatisfy { $0.isWhitespace || CategoryCorrection.fillerCharacters.contains($0) }
    }
}
