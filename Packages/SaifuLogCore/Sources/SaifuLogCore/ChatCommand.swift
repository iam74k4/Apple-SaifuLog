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
/// 2. 消す文: 数字が無く、消す語（「消して」「削除」「取り消して」「なしで」など）のほかは前の記録を指す語・語尾だけ。
/// 3. 月の予算を決める文: 「予算」と金額がちょうど 1 つあり、カテゴリの名前が無く（カテゴリ別の予算は ⑧ で決める）、残りが
///    「今月」「毎月」・決める語（「にして」「に設定」など）・語尾だけ。「来月」「先月」は読まない（予算はいまの月から当てるため）。
/// 4. 金額を直す文: 前の記録を直そうとする文（`InputIntentClassifier` の直す語）で、直した先の金額がちょうど 1 つ読める。
///    「AじゃなくてB」は後ろの金額にする。予算の語があれば読まない。
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
        if InputIntentClassifier.containsCorrectionWord(normalized), !normalized.contains(budgetWord),
           let amount = correctedAmount(in: normalized, now: now, calendar: calendar) {
            return .changeAmount(amount)
        }
        return nil
    }

    /// 端末内 AI が選んだ種類の操作を、文に書かれた値で組み立てる。値が文から読めなければ nil（AI の選んだ種類だけでは書き換えない）。
    ///
    /// 決まりより緩く読むが、値は必ず文に書かれたものにする（カテゴリはちょうど 1 つの名前、金額はちょうど 1 つか「じゃなくて」の後ろ）。
    public static func command(
        kind: ChatCommandKind, in text: String, now: Date, calendar: Calendar, catalog: CategoryCatalog = .builtIn
    ) -> ChatCommand? {
        let normalized = TextNormalizer.normalize(text)
        switch kind {
        case .recategorize:
            let folded = CategoryCatalog.fold(normalized)
            let named = Set(CategoryCorrection.names(in: catalog).filter { folded.contains($0.name) }.map { $0.category })
            guard named.count == 1, let category = named.first, !hasDigit(normalized) else { return nil }
            return .recategorize(category)
        case .changeAmount:
            guard !normalized.contains(budgetWord) else { return nil }
            return correctedAmount(in: normalized, now: now, calendar: calendar).map(ChatCommand.changeAmount)
        case .removeLast:
            return hasDigit(normalized) ? nil : .removeLast
        case .setMonthlyBudget:
            return monthlyBudget(in: normalized, now: now, calendar: calendar, catalog: catalog, strict: false)
                .map(ChatCommand.setMonthlyBudget)
        case .none:
            return nil
        }
    }

    // MARK: - 消す

    /// 消す語。
    static let removalWords = [
        "取り消して", "とりけして", "取り消し", "とりけし", "消しといて", "消しておいて", "消して", "けして", "削除して", "削除",
        "なかったことにして", "なかったことに", "なしにして", "なしで", "なしね", "なし", "いらない", "やめて",
    ]

    private static func isRemoval(_ normalized: String) -> Bool {
        guard !hasDigit(normalized) else { return false }
        var folded = CategoryCatalog.fold(normalized)
        let words = removalWords.map(CategoryCatalog.fold).sorted { $0.count > $1.count }
        guard words.contains(where: { folded.contains($0) }) else { return false }
        for word in words { folded = folded.replacingOccurrences(of: word, with: "") }
        return onlyFillers(folded, extra: removalFillers)
    }

    /// 消す文に残ってよい語（「やっぱり」「今のは」など）。
    static let removalFillers = ["やっぱり", "やっぱ", "ごめん", "まちがい", "間違い", "まちがえた", "間違えた"]

    // MARK: - 予算

    static let budgetWord = "予算"
    /// 予算の文に残ってよい語（期間と決める語）。この順に外す（「今月」を「月」より先に外し、「今」を残さないため）。
    static let budgetFillers = [
        "今月から", "今月", "毎月", "ひと月", "全体の", "全体",
        "に設定して", "に設定", "設定して", "設定", "に変更して", "に変更", "に変えて", "にかえて", "にして", "にする",
        "で決めて", "に決めて", "決めて", "きめて", "でお願い", "でおねがい", "お願い", "月の", "月", "円",
    ]
    /// 予算の文で読まない期間の語（予算はいまの月から当てるので、ほかの月を指す文は決めない）。
    static let otherMonthWords = ["来月", "先月", "去年", "来年"]

    /// 月の全体の予算として読める金額。`strict` なら、予算・金額・期間・決める語のほかに語が残る文は読まない。
    private static func monthlyBudget(
        in normalized: String, now: Date, calendar: Calendar, catalog: CategoryCatalog, strict: Bool
    ) -> Int? {
        guard normalized.contains(budgetWord), !otherMonthWords.contains(where: { normalized.contains($0) }) else { return nil }
        // カテゴリ別の予算は読まない（⑧ で決める）。
        let folded = CategoryCatalog.fold(normalized)
        guard !CategoryCorrection.names(in: catalog).contains(where: { folded.contains($0.name) }) else { return nil }
        let scan = EntryScan(normalized, now: now, calendar: calendar)
        guard scan.amounts.count == 1, let amount = scan.amounts.first, amount.value > 0,
              amount.value <= BudgetPlan.maximumAmount else { return nil }
        guard strict else { return amount.value }
        var rest = String(scan.chars.enumerated().filter { !amount.range.contains($0.offset) }.map(\.element))
        rest = CategoryCatalog.fold(rest).replacingOccurrences(of: CategoryCatalog.fold(budgetWord), with: "")
        for word in budgetFillers.map(CategoryCatalog.fold) {
            rest = rest.replacingOccurrences(of: word, with: "")
        }
        return onlyFillers(rest, extra: []) ? amount.value : nil
    }

    // MARK: - 金額を直す

    /// 直した先の金額。「AじゃなくてB」は後ろの文の金額、それ以外は文の中にちょうど 1 つある金額。
    private static func correctedAmount(in normalized: String, now: Date, calendar: Calendar) -> Int? {
        var target = normalized
        for marker in CategoryCorrection.negationMarkers {
            if let range = normalized.range(of: marker, options: .backwards) {
                target = String(normalized[range.upperBound...])
                break
            }
        }
        let amounts = EntryScan(target, now: now, calendar: calendar).amounts
        guard amounts.count == 1, let amount = amounts.first, amount.value > 0,
              amount.value <= EntryAmountInput.maximumAmount else { return nil }
        return amount.value
    }

    // MARK: - 共通

    private static func hasDigit(_ text: String) -> Bool {
        text.contains(where: \.isNumber)
    }

    private static func containsStrongQuestionWord(_ normalized: String) -> Bool {
        InputIntentClassifier.strongQuestionWords.contains { normalized.contains($0) }
    }

    /// そろえた文が、前の記録を指す語・語尾（`CategoryCorrection` と同じ）と `extra` だけか。
    private static func onlyFillers(_ folded: String, extra: [String]) -> Bool {
        var rest = folded
        for word in (CategoryCorrection.fillers + extra.map(CategoryCatalog.fold)).sorted(by: { $0.count > $1.count }) {
            rest = rest.replacingOccurrences(of: word, with: "")
        }
        return rest.allSatisfy { $0.isWhitespace || CategoryCorrection.fillerCharacters.contains($0) }
    }
}
