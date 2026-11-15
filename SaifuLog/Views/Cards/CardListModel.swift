import Foundation
import Observation
import SaifuLogCore
import SwiftData

/// 設定の「カード」の状態と操作。登録したクレジットカードを並べ、カードごとに今の締めの利用額と次の引き落としを出す。
/// 登録する・直す・並べ替える・削除する。docs/design.md §8-2。
///
/// 一覧はホームと同じ `CardCatalogModel` を読み、変えたらそれを読み直す（ホームの記録にもすぐ使うように）。
/// 画面（`CardListView`）から切り離し、保存先・時計・読み上げを差し替えて SaifuLogTests で確かめられるようにしている。
@MainActor
@Observable
final class CardListModel {
    /// カードを登録する・直すシートの状態と操作。出していなければ nil（シートを閉じると画面が nil に戻す）。
    var editor: CardEditorModel?
    /// 削除の確認に出しているカード。出していなければ nil。
    var pendingDeletion: PendingDeletion?
    /// 読み書きの失敗（アラートを出す）。
    var failure: Failure?
    /// カードごとの今の締めと次の引き落とし（一覧に出す）。読めなければ空。
    private(set) var overviews: [String: Overview] = [:]

    /// いまのカードの一覧（ホームと同じもの）。
    let catalog: CardCatalogModel

    @ObservationIgnored let context: ModelContext
    @ObservationIgnored let now: () -> Date
    @ObservationIgnored let timeZone: TimeZone
    @ObservationIgnored let announce: @MainActor (String) -> Void
    @ObservationIgnored let entryDidSave: @MainActor (Entry) -> Void
    @ObservationIgnored let entryDidDelete: @MainActor (PersistentIdentifier) -> Void
    private var store: CreditCardStore { catalog.store }

    /// - Parameters:
    ///   - timeZone: 締め日と引き落とし日を数える時間帯（画面の暦の時間帯）。
    ///   - entryDidSave: 締めの記録の一覧から直した記録を渡して呼ぶ（ホームが「取り消す」を片づける）。
    ///   - entryDidDelete: 締めの記録の一覧から消した記録の ID を渡して呼ぶ（ホームが「取り消す」の対象から外す）。
    init(
        cards: CardCatalogModel,
        context: ModelContext,
        now: @escaping () -> Date = { .now },
        timeZone: TimeZone = .current,
        announce: @escaping @MainActor (String) -> Void = { VoiceOver.announce($0) },
        entryDidSave: @escaping @MainActor (Entry) -> Void = { _ in },
        entryDidDelete: @escaping @MainActor (PersistentIdentifier) -> Void = { _ in }
    ) {
        self.catalog = cards
        self.context = context
        self.now = now
        self.timeZone = timeZone
        self.announce = announce
        self.entryDidSave = entryDidSave
        self.entryDidDelete = entryDidDelete
    }

    /// 登録したカード（並びの順）。
    var cards: [PaymentCard] { catalog.cards }

    /// まだ登録できるか（`PaymentCard.maximumCount` まで）。
    var canCreate: Bool { cards.count < PaymentCard.maximumCount }

    /// 保存先から読み直す（画面を開いたとき・iCloud でほかの端末の変更が届いたとき・記録を直したとき）。
    func reload() {
        catalog.reload()
        let today = now()
        var overviews: [String: Overview] = [:]
        for card in cards {
            guard let current = card.statement(containing: today, timeZone: timeZone) else { continue }
            let next = card.nextPaymentStatement(after: today, timeZone: timeZone)
            let start = min(current.period.start, next?.period.start ?? current.period.start)
            let end = max(current.period.end, next?.period.end ?? current.period.end)
            guard let entries = try? context.fetch(Entry.descriptor(spentIn: DateInterval(start: start, end: end))) else { continue }
            overviews[card.id] = Overview(
                current: CardStatementSummary(statement: current, records: entries),
                next: next.map { CardStatementSummary(statement: $0, records: entries) }
            )
        }
        if overviews != self.overviews { self.overviews = overviews }
    }

    /// カードを登録するシートを出す。
    func presentCreation() {
        guard canCreate else { return }
        editor = CardEditorModel(mode: .create, store: store, cards: cards, announce: announce) { [weak self] _ in
            self?.reload()
        }
    }

    /// カードを直すシートを出す。
    func presentEditing(_ card: PaymentCard) {
        editor = CardEditorModel(mode: .edit(card), store: store, cards: cards, announce: announce) { [weak self] _ in
            self?.reload()
        }
    }

    /// 締めの記録の一覧（カードの行から進む画面）の状態と操作。
    func statementModel(for card: PaymentCard) -> CardStatementModel {
        CardStatementModel(card: card, list: self)
    }

    /// 削除の確認を出す。確認には、そのカードの記録の件数（「現金・その他」になる件数）を出す。
    func requestDeletion(_ card: PaymentCard) {
        do {
            pendingDeletion = PendingDeletion(card: card, entryCount: try store.entryCount(of: card.id))
        } catch {
            failure = .load
        }
    }

    /// 確認で「削除」を押した。記録とくり返しの記録は「現金・その他」にする（`CreditCardStore.delete`）。
    ///
    /// 何を消すかは、確認に出していた値を受け取る（ボタンを押すと確認を閉じる側が先に `pendingDeletion` を nil にすることがあるため）。
    func confirmDeletion(_ deletion: PendingDeletion) {
        pendingDeletion = nil
        do {
            try store.delete(deletion.card.id)
        } catch {
            failure = .save
            return
        }
        reload()
        announce(String(localized: "カード「\(deletion.card.name)」を削除しました"))
    }

    /// 並べ替える（リストのドラッグ）。
    func move(fromOffsets source: IndexSet, toOffset destination: Int) {
        var order = cards.map(\.id)
        order.move(fromOffsets: source, toOffset: destination)
        guard order != cards.map(\.id) else { return }
        do {
            try store.reorder(order)
        } catch {
            failure = .save
            return
        }
        reload()
    }

    /// 1 つ前へ動かす（VoiceOver の操作）。
    func moveEarlier(_ card: PaymentCard) {
        guard let index = cards.firstIndex(where: { $0.id == card.id }), index > 0 else { return }
        move(fromOffsets: [index], toOffset: index - 1)
        announce(String(localized: "\(index) 番目にしました"))
    }

    /// 1 つ後ろへ動かす（VoiceOver の操作）。
    func moveLater(_ card: PaymentCard) {
        guard let index = cards.firstIndex(where: { $0.id == card.id }), index < cards.count - 1 else { return }
        move(fromOffsets: [index], toOffset: index + 2)
        announce(String(localized: "\(index + 2) 番目にしました"))
    }

    /// カードの今の締めと次の引き落とし。
    struct Overview: Equatable {
        /// 今の締め（まだ締めていない分）。
        let current: CardStatementSummary
        /// 次の引き落とし（今の締めより前の、締めた分のことがある）。
        let next: CardStatementSummary?
    }

    /// 削除の確認の中身。
    struct PendingDeletion: Identifiable, Equatable {
        let card: PaymentCard
        /// このカードの記録の件数（「現金・その他」になる件数）。
        let entryCount: Int

        var id: String { card.id }
    }

    /// 読み書きの失敗。
    enum Failure: Equatable {
        case load
        case save
    }
}

/// カードの行から進む、1 回分の締めの記録の一覧（前後の締めへ送れる）。記録を押すと「直す」（⑥）を開き、長押しで削除できる
/// （月のまとめのカテゴリの一覧と同じ）。
@MainActor
@Observable
final class CardStatementModel {
    let card: PaymentCard
    /// いま出している締めの月。
    private(set) var closingMonth: RecurringMonth
    private(set) var summary: CardStatementSummary?
    /// 締めの記録（使った日時の新しい順）。
    private(set) var entries: [Entry] = []
    /// 「直す」のシート。出していなければ nil。
    var editing: EditEntryModel?
    /// 長押しで消そうとしている記録（確認を出している間）。
    var pendingDeletion: HomeModel.PendingDeletion?
    var showsDeleteFailure = false

    @ObservationIgnored private let list: CardListModel
    /// 今の締めの月（これより先へは送らない）。
    @ObservationIgnored private let currentMonth: RecurringMonth

    init(card: PaymentCard, list: CardListModel) {
        self.card = card
        self.list = list
        let current = card.statement(containing: list.now(), timeZone: list.timeZone)?.closingMonth
            ?? RecurringMonth(containing: list.now(), timeZone: list.timeZone)
        self.currentMonth = current
        self.closingMonth = current
        reload()
    }

    var store: EntryStore { EntryStore(context: list.context) }
    var today: Date { list.now() }

    var canShowNext: Bool { closingMonth < currentMonth }

    func showPrevious() {
        closingMonth = closingMonth.adding(months: -1)
        reload()
    }

    func showNext() {
        guard canShowNext else { return }
        closingMonth = closingMonth.adding(months: 1)
        reload()
    }

    func reload() {
        guard let statement = card.statement(closingIn: closingMonth, timeZone: list.timeZone),
              let loaded = try? list.context.fetch(Entry.descriptor(spentIn: statement.period))
        else {
            summary = nil
            entries = []
            return
        }
        let id = card.id
        summary = CardStatementSummary(statement: statement, records: loaded)
        entries = loaded.filter { !$0.isIncome && $0.cardID == id }.sorted { $0.spentAt > $1.spentAt }
    }

    /// 記録を直すシートを出す。ほかの端末で消されていれば、開かずに読み直す（月のまとめと同じ）。
    func presentEdit(_ entry: Entry, calendar: Calendar, catalog: CategoryCatalog) {
        guard store.exists(entry.persistentModelID) else {
            reload()
            return
        }
        editing = EditEntryModel(
            entry: entry, store: store, calendar: calendar, now: list.now, announce: list.announce,
            didSave: { [weak self] entry in
                self?.afterChange()
                self?.list.entryDidSave(entry)
            },
            didDelete: { [weak self] id in
                self?.afterChange()
                self?.list.entryDidDelete(id)
            },
            catalog: catalog
        )
    }

    /// 長押しの「削除」の確認を出す。
    func requestDelete(_ entry: Entry, catalog: CategoryCatalog) {
        guard store.exists(entry.persistentModelID) else {
            reload()
            return
        }
        pendingDeletion = HomeModel.PendingDeletion(entry: entry, id: entry.persistentModelID, summary: entry.summaryText(in: catalog))
    }

    /// 確認のあとで記録を削除する。
    func delete(_ pending: HomeModel.PendingDeletion) {
        pendingDeletion = nil
        if store.exists(pending.id) {
            do {
                try store.delete([pending.entry])
            } catch {
                showsDeleteFailure = true
                return
            }
        }
        afterChange()
        list.entryDidDelete(pending.id)
        list.announce(String(localized: "削除しました"))
    }

    private func afterChange() {
        reload()
        list.reload()
    }
}
