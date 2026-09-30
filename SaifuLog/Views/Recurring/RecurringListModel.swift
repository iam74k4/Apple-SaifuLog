import Foundation
import Observation
import SaifuLogCore

/// 設定の「くり返しの記録」の状態と操作。決まりを一覧し（次に記録する日つき）、足す・直す・やめる。
///
/// 画面（`RecurringListView`）から切り離し、保存先・時計・読み上げを差し替えて SaifuLogTests で確かめられるようにしている。
@MainActor
@Observable
final class RecurringListModel {
    /// 一覧の 1 行（決まりの値。保存先の行をそのまま画面に渡さない）。
    struct Row: Identifiable, Equatable {
        let id: String
        let memo: String
        let amount: Int
        let isIncome: Bool
        let category: EntryCategory
        let dayOfMonth: Int
        /// 次に記録する日。
        let nextDate: Date?
    }

    /// 決まり（毎月の日の順）。
    private(set) var rows: [Row] = []
    /// 作る・直すシートの状態と操作。出していなければ nil（シートを閉じると画面が nil に戻す）。
    var editor: RecurringEditorModel?
    /// やめる前の確認に出している行。出していなければ nil。
    var pendingDeletion: Row?
    /// 読み書きの失敗（アラートを出す）。
    var failure: Failure?

    @ObservationIgnored private let store: RecurringEntryStore
    @ObservationIgnored private let timeZone: TimeZone
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private let announce: @MainActor (String) -> Void
    @ObservationIgnored private let didChange: @MainActor () -> Void

    /// - Parameter didChange: 足した・直した・やめたあとに呼ぶ（ホームが、記録する日を過ぎた分をすぐ記録する）。
    init(
        store: RecurringEntryStore,
        timeZone: TimeZone = .autoupdatingCurrent,
        now: @escaping () -> Date = { .now },
        announce: @escaping @MainActor (String) -> Void = { VoiceOver.announce($0) },
        didChange: @escaping @MainActor () -> Void = {}
    ) {
        self.store = store
        self.timeZone = timeZone
        self.now = now
        self.announce = announce
        self.didChange = didChange
        reload()
    }

    /// 保存先から読み直す（画面を開いたとき・シートを閉じたとき・iCloud でほかの端末の変更が届いたとき）。
    func reload() {
        do {
            let current = now()
            rows = try store.rules().map { row in
                Row(
                    id: row.recurrenceID, memo: row.memo, amount: row.amount, isIncome: row.isIncome, category: row.category,
                    dayOfMonth: row.dayOfMonth,
                    nextDate: row.rule.flatMap { RecurringSchedule.nextDate(for: $0, now: current, timeZone: timeZone) }
                )
            }
        } catch {
            rows = []
            failure = .load
        }
    }

    /// 足すシートを出す。
    func presentCreation() {
        editor = RecurringEditorModel(
            store: store, timeZone: timeZone, now: now, announce: announce, didChange: { [weak self] in self?.changed() }
        )
    }

    /// 直すシートを出す。
    func presentEditing(_ row: Row) {
        guard let entry = try? store.rules().first(where: { $0.recurrenceID == row.id }) else {
            // ほかの端末でやめた。一覧を読み直す。
            reload()
            return
        }
        editor = RecurringEditorModel(
            editing: entry, store: store, timeZone: timeZone, now: now, announce: announce,
            didChange: { [weak self] in self?.changed() }
        )
    }

    /// やめる前の確認を出す（左へのスワイプ・VoiceOver の操作）。
    func requestDeletion(_ row: Row) {
        pendingDeletion = row
    }

    /// 確認のあとでやめる。記録したものは残す。
    func confirmDeletion(_ row: Row) {
        pendingDeletion = nil
        do {
            try store.delete(row.id)
        } catch {
            failure = .save
            return
        }
        announce(String(localized: "くり返しの記録をやめました"))
        changed()
    }

    private func changed() {
        reload()
        didChange()
    }

    /// 読み書きの失敗。
    enum Failure: Equatable {
        case load
        case save
    }
}
