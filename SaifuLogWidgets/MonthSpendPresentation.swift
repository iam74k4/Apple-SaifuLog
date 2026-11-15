import Foundation
import SaifuLogCore

/// ウィジェットの大きさ（WidgetKit の WidgetFamily のうち、作ったもの）。画面の外（テスト）でも並べられるよう、ここで持つ。
enum MonthSpendLayout: CaseIterable, Sendable {
    /// ホーム画面の小。
    case small
    /// ロック画面の長方形。
    case rectangular
    /// ロック画面の丸。
    case circular
    /// ロック画面の時計の上の 1 行。
    case inline
}

/// ウィジェットに出す文と数字（大きさと状態ごと）。画面（`MonthSpendContent`）はこれを並べるだけにして、何を出すかを
/// テストで確かめられるようにする（WidgetKit の画面は、テストから大きさを替えて描けないため）。
///
/// 出すのはホームの帯と同じ数字だけ（今月使った額と、予算を決めていれば残りか超えた額）。予算を超えたら、色だけでなく
/// 「オーバー」の語と注意の印でも伝える。
struct MonthSpendPresentation: Equatable {
    enum Kind: Equatable {
        /// 今月の数字。
        case figures
        /// アプリのロック中（数字を出さない）。
        case locked
        /// まだ数字が無い（入れてからアプリを開いていない・ファイルを読めない）。
        case empty
    }

    let kind: Kind
    /// 見出し（小の上の行・長方形と 1 行の数字の無いときの見出し）。
    let title: String
    /// 主の文。小は使った額、長方形は「今月 ¥…」、1 行は予算の残りまで続けた 1 行、丸は使った割合か（予算が無ければ）使った額。
    /// 数字が無いときは説明の文。
    let primary: String
    /// 予算の行（「あと ¥…」「¥… オーバー」）。予算が無い・数字が無い・1 行と丸のときは nil。
    let budgetLine: String?
    /// 予算を超えたか（注意の色と印）。
    let isOver: Bool
    /// バーとゲージの割合（0〜1）。予算が無い・数字が無いときは nil。
    let fraction: Double?
    /// 添える記号（SF Symbols の名前）。数字の無いときと、丸のゲージの記号。
    let symbol: String?
    /// VoiceOver で読む文（見出し・使った額・予算の行。数字の無いときは見出しと説明）。
    let accessibilityLabel: String

    /// - Parameters:
    ///   - bundle: 文の訳を引く場所。ウィジェットでは拡張そのもの（既定）。テストは言語ごとの lproj を渡す。
    ///   - locale: 割合と並べ方の書き方。
    init(display: WidgetDisplay?, layout: MonthSpendLayout, bundle: Bundle = .main, locale: Locale = .current) {
        let title = String(localized: "今月使った額", bundle: bundle)
        switch display {
        case .figures(let spent, let budget):
            self.init(spent: spent, budget: budget, layout: layout, title: title, bundle: bundle, locale: locale)
        case .hidden:
            let detail = String(localized: "アプリのロック中は金額を出しません", bundle: bundle)
            self.init(
                message: .locked, title: String(localized: "ロック中", bundle: bundle), detail: detail,
                symbol: "lock.fill", locale: locale
            )
        case nil:
            let detail = String(localized: "アプリを開くと出ます", bundle: bundle)
            self.init(message: .empty, title: title, detail: detail, symbol: "yensign.circle", locale: locale)
        }
    }

    private init(
        spent: Int, budget: BudgetStatus?, layout: MonthSpendLayout, title: String, bundle: Bundle, locale: Locale
    ) {
        let amount = YenFormatter.string(from: spent)
        let budgetLine = budget.map { Self.budgetLine($0, bundle: bundle) }
        kind = .figures
        self.title = title
        isOver = budget?.isOver == true
        accessibilityLabel = ([title, amount] + [budgetLine].compactMap { $0 }).formatted(.list(type: .and).locale(locale))
        switch layout {
        case .small:
            primary = amount
            self.budgetLine = budgetLine
            fraction = budget?.spentFraction
            symbol = nil
        case .rectangular:
            primary = String(localized: "今月 \(amount)", bundle: bundle)
            self.budgetLine = budgetLine
            fraction = budget?.spentFraction
            symbol = nil
        case .inline:
            // 時計の上の 1 行は 1 つの文にする（記号やバーを置けないため）。
            if let budget {
                primary = budget.isOver
                    ? String(localized: "今月 \(amount)・\(YenFormatter.string(from: budget.overspent)) オーバー", bundle: bundle)
                    : String(localized: "今月 \(amount)・あと \(YenFormatter.string(from: budget.remaining))", bundle: bundle)
            } else {
                primary = String(localized: "今月 \(amount)", bundle: bundle)
            }
            self.budgetLine = nil
            fraction = nil
            symbol = nil
        case .circular:
            // 丸は小さいので、予算があれば使った割合のゲージだけにする（超えたら割合の代わりに注意の印）。無ければ使った額。
            if let budget {
                primary = budget.isOver ? "" : budget.spentFraction.formatted(.percent.precision(.fractionLength(0)).locale(locale))
                fraction = budget.spentFraction
                symbol = "yensign"
            } else {
                primary = amount
                fraction = nil
                symbol = nil
            }
            self.budgetLine = nil
        }
    }

    private init(message kind: Kind, title: String, detail: String, symbol: String, locale: Locale) {
        self.kind = kind
        self.title = title
        primary = detail
        budgetLine = nil
        isOver = false
        fraction = nil
        self.symbol = symbol
        accessibilityLabel = [title, detail].formatted(.list(type: .and).locale(locale))
    }

    /// 予算の残り（「あと ¥…」）か、超えた額（「¥… オーバー」）。
    private static func budgetLine(_ budget: BudgetStatus, bundle: Bundle) -> String {
        budget.isOver
            ? String(localized: "\(YenFormatter.string(from: budget.overspent)) オーバー", bundle: bundle)
            : String(localized: "あと \(YenFormatter.string(from: budget.remaining))", bundle: bundle)
    }
}
