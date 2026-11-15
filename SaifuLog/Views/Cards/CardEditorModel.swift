import Foundation
import Observation
import SaifuLogCore

/// カードを登録する・直す画面（シート）の状態と操作。名前・締め日・引き落とし日（翌月か翌々月か）・いつものカードを決めて保存する。
///
/// 画面（`CardEditorSheet`）から切り離し、保存先と読み上げを差し替えて SaifuLogTests で確かめられるようにしている。
@MainActor
@Observable
final class CardEditorModel: Identifiable {
    enum Mode: Equatable {
        case create
        case edit(PaymentCard)
    }

    let mode: Mode
    var name: String {
        didSet { issue = nil }
    }
    /// 締め日（1〜31。31 は月末）。
    var closingDay: Int
    /// 引き落とし日（1〜31。31 は月末）。
    var paymentDay: Int
    /// 締めた月の何か月後に引き落とすか（1 = 翌月、2 = 翌々月）。
    var paymentMonthOffset: Int
    var isDefault: Bool
    /// 保存しようとしたときの名前の問題（入力欄の下に出す）。直し始めたら消す。
    private(set) var issue: CardNameIssue?
    var showsSaveFailure = false
    var showsDiscardConfirmation = false

    /// よく使うカードの候補（押すと名前と、そのカードのよくある締め日・引き落とし日を入れる）。日付はカードの会員の規約で
    /// 違うことがあるので、入れた後に利用明細で確かめてもらう（シートの説明に書く）。名前は訳さない（カードの名前のため）。
    /// 日付は 2026-11-15 に各社の案内で確かめた基本の形（三井住友カードは 15 日締め・翌月 10 日と、月末締め・翌月 26 日から
    /// 選べるので、15 日締めを入れる）。
    static let presets: [(name: String, closingDay: Int, paymentDay: Int)] = [
        ("楽天カード", 31, 27),
        ("三井住友カード", 15, 10),
        ("JCBカード", 15, 10),
        ("イオンカード", 10, 2),
        ("PayPayカード", 31, 27),
        ("dカード", 15, 10),
        ("セゾンカード", 10, 4),
    ]

    @ObservationIgnored private let store: CreditCardStore
    @ObservationIgnored private let cards: [PaymentCard]
    @ObservationIgnored private let announce: @MainActor (String) -> Void
    @ObservationIgnored private let didSave: @MainActor (PaymentCard) -> Void
    @ObservationIgnored private var initial: PaymentCard

    /// - Parameters:
    ///   - cards: 開いた時点のカードの一覧（名前の重なりを見る）。
    ///   - didSave: 保存できたあとに、登録した（直した）カードを渡して呼ぶ。
    init(
        mode: Mode,
        store: CreditCardStore,
        cards: [PaymentCard],
        announce: @escaping @MainActor (String) -> Void = { VoiceOver.announce($0) },
        didSave: @escaping @MainActor (PaymentCard) -> Void = { _ in }
    ) {
        self.mode = mode
        self.store = store
        self.cards = cards
        self.announce = announce
        self.didSave = didSave
        let card: PaymentCard
        switch mode {
        case .create:
            // 月末締め・翌月 27 日引き落とし（多くのカードの形）を既定にする。最初の 1 枚はいつものカードにする。
            card = PaymentCard(id: "", name: "", closingDay: 31, paymentDay: 27, paymentMonthOffset: 1, isDefault: cards.isEmpty)
        case .edit(let editing):
            card = editing
        }
        name = card.name
        closingDay = card.closingDay
        paymentDay = card.paymentDay
        paymentMonthOffset = card.paymentMonthOffset
        isDefault = card.isDefault
        initial = card
    }

    /// 入れた値のカード。
    private var draft: PaymentCard {
        PaymentCard(
            id: initial.id, name: name, closingDay: closingDay, paymentDay: paymentDay, paymentMonthOffset: paymentMonthOffset,
            isDefault: isDefault
        )
    }

    var hasChanges: Bool { draft != initial }

    var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && (mode == .create || hasChanges)
    }

    /// まだ登録していない候補。登録するときだけ出す。
    var availablePresets: [(name: String, closingDay: Int, paymentDay: Int)] {
        guard mode == .create else { return [] }
        return Self.presets.filter { if case .success = PaymentCard.validateName($0.name, among: cards) { true } else { false } }
    }

    func choosePreset(name: String, closingDay: Int, paymentDay: Int) {
        self.name = name
        self.closingDay = closingDay
        self.paymentDay = paymentDay
        paymentMonthOffset = 1
    }

    /// 入れた値の締めと引き落としの例（「10月16日〜11月15日の利用を12月10日に引き落とし」）。シートの下に出す。
    func example(now: Date, calendar: Calendar) -> String? {
        guard let statement = draft.statement(containing: now, timeZone: calendar.timeZone) else { return nil }
        return String(localized: "\(CardTexts.period(statement, calendar: calendar))の利用を\(CardTexts.day(statement.paymentDate, calendar: calendar))に引き落とします。")
    }

    /// シートを閉じてよいか。入れた内容があれば閉じずに、捨てるかの確認を出す（false を返す）。
    func requestClose() -> Bool {
        guard hasChanges else { return true }
        showsDiscardConfirmation = true
        return false
    }

    /// 保存する。保存できたら true（呼び出し側がシートを閉じる）。名前が使えなければ `issue` に理由を入れて false。
    @discardableResult
    func save() -> Bool {
        let saved: PaymentCard
        do {
            switch mode {
            case .create:
                saved = try store.create(draft)
            case .edit:
                try store.update(draft)
                saved = draft
            }
        } catch let error as CardNameIssue {
            issue = error
            return false
        } catch {
            showsSaveFailure = true
            return false
        }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        switch mode {
        case .create: announce(String(localized: "カード「\(trimmed)」を登録しました"))
        case .edit: announce(String(localized: "カード「\(trimmed)」を直しました"))
        }
        didSave(saved)
        return true
    }
}
