import Foundation
import Observation
import SaifuLogCore
import SwiftData

/// 「直す」（⑥）のシートの状態と操作。1 件の記録の金額・品目・種別（支出か収入か）・カテゴリ・日付を直して保存する。
///
/// 画面（`EditEntrySheet`）から切り離し、保存先・時計・読み上げを差し替えて SaifuLogTests で確かめられるようにしている。
/// シートの中身は開いた時点の記録の値の写しで持ち、画面は記録（`Entry`）を直接読まない。シートから削除したあと、
/// 閉じる動きの途中で消えた記録の値を読みに行かないようにするため。
@MainActor
@Observable
final class EditEntryModel: Identifiable {
    /// 金額の入力欄（「1,280」の形）。
    var amountText: String
    /// 品目の入力欄。保存するときに前後の空白を除く。
    var memo: String
    /// 支出のカテゴリ。収入のときは使わない（保存するのは「その他」）。
    var category: EntryCategory
    var isIncome: Bool
    /// 日付の選択の値。保存するときは日だけを使い、時刻は元の記録のものを残す（`EntryDateEdit`）。
    var day: Date
    /// 書き込みの失敗（シートは閉じずにアラートを出す）。
    var failure: Failure?
    var showsDeleteConfirmation = false
    /// 直した内容を捨てて閉じるかの確認（キャンセル・下へのスワイプ）。
    var showsDiscardConfirmation = false

    /// 送った文（ひとこと入力の元の文）。読み違いを見比べられるよう、シートの上に出す。無ければ空。
    let originalText: String
    /// 削除の確認に出す「ランチ ¥850」。開いた時点の値で作る（直しかけの値ではなく、保存されている記録を指すため）。
    let deletionSummary: String

    @ObservationIgnored private let entry: Entry
    @ObservationIgnored private let original: EntryEdits
    @ObservationIgnored private let store: EntryStore
    @ObservationIgnored private let calendar: Calendar
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private let announce: @MainActor (String) -> Void
    @ObservationIgnored private let didSave: @MainActor (Entry) -> Void
    @ObservationIgnored private let didDelete: @MainActor (PersistentIdentifier) -> Void

    /// - Parameters:
    ///   - calendar: 日付の区切り（今日より先か、日付を変えたか）と読み上げの日付の基準。画面の暦を渡す。
    ///   - now: 「今日」の基準。テストで固定の日時にする。
    ///   - announce: VoiceOver に読み上げさせる。テストで読み上げる文を集める。
    ///   - didSave: 保存できたあとに呼ぶ（ホームが「取り消す」を片づける）。
    ///   - didDelete: 削除できたあとに、消した記録の ID を渡して呼ぶ（ホームが「取り消す」の対象から外す）。
    init(
        entry: Entry,
        store: EntryStore,
        calendar: Calendar,
        now: @escaping () -> Date = { .now },
        announce: @escaping @MainActor (String) -> Void = { VoiceOver.announce($0) },
        didSave: @escaping @MainActor (Entry) -> Void = { _ in },
        didDelete: @escaping @MainActor (PersistentIdentifier) -> Void = { _ in }
    ) {
        let original = EntryEdits(entry)
        self.entry = entry
        self.original = original
        self.store = store
        self.calendar = calendar
        self.now = now
        self.announce = announce
        self.didSave = didSave
        self.didDelete = didDelete
        self.amountText = EntryAmountInput.text(for: original.amount)
        self.memo = original.memo
        self.category = original.category
        self.isIncome = original.isIncome
        self.day = original.spentAt
        self.originalText = entry.originalText
        self.deletionSummary = entry.summaryText
    }

    // MARK: - 入力の確かめ

    /// 金額を保存できない理由。保存できる額なら nil。
    var amountIssue: EntryAmountIssue? {
        switch EntryAmountInput.validate(amountText) {
        case .success: nil
        case .failure(let issue): issue
        }
    }

    /// 保存する使った日時（選んだ日で、時刻は元の記録のまま）。
    var spentAt: Date {
        EntryDateEdit.date(on: day, keepingTimeOf: original.spentAt, calendar: calendar)
    }

    /// 今日より先の日付を選んでいるか（注意を出すだけで、保存は止めない）。
    var isFutureDate: Bool {
        EntryDateEdit.isAfterToday(spentAt, now: now(), calendar: calendar)
    }

    /// 保存する値。金額が保存できなければ nil。
    ///
    /// 収入のカテゴリは「その他」にする（ひとこと入力で収入を記録したときと同じ。収入はカテゴリ別の合計に数えないため）。
    var edits: EntryEdits? {
        guard case .success(let amount) = EntryAmountInput.validate(amountText) else { return nil }
        return EntryEdits(
            amount: amount,
            isIncome: isIncome,
            category: isIncome ? .other : category,
            memo: memo.trimmingCharacters(in: .whitespacesAndNewlines),
            spentAt: spentAt
        )
    }

    /// 開いた時点から何か直したか。金額を消したとき（保存はできない）も直したことにする（閉じるときに確認するため）。
    var hasChanges: Bool {
        guard let edits else { return true }
        return edits != original
    }

    /// 保存できるか。直していなければ押せない（押しても何も変わらないため）。
    var canSave: Bool {
        edits.map { $0 != original } ?? false
    }

    /// 金額の入力欄の文字を見せる形（「1,280」）にそろえる。入力欄が変わるたびに呼ぶ。
    func normalizeAmountText() {
        let formatted = EntryAmountInput.formatted(amountText)
        if formatted != amountText { amountText = formatted }
    }

    // MARK: - 操作

    /// 直した内容を保存する。保存できたら true（呼び出し側がシートを閉じる）。
    ///
    /// 書き込めなければ記録は直す前の値に戻し（`EntryStore.update`）、入力欄はそのまま残してアラートを出す
    /// （閉じると、直した内容を打ち直すことになるため）。
    @discardableResult
    func save() -> Bool {
        guard let edits, edits != original else { return false }
        do {
            try store.update(entry, with: edits)
        } catch {
            failure = .save
            return false
        }
        announce(String(localized: "直しました: \(spokenSummary(edits))"))
        didSave(entry)
        return true
    }

    /// 記録を削除する（確認のあと）。削除できたら true（呼び出し側がシートを閉じる）。
    @discardableResult
    func delete() -> Bool {
        // 消した記録の ID は、保存した後には読めないことがあるので先に取っておく。
        let id = entry.persistentModelID
        do {
            try store.delete([entry])
        } catch {
            failure = .delete
            return false
        }
        announce(String(localized: "削除しました: \(deletionSummary)"))
        didDelete(id)
        return true
    }

    /// シートを閉じてよいか。直した内容があれば閉じずに、捨てるかの確認を出す（false を返す）。
    func requestClose() -> Bool {
        guard hasChanges else { return true }
        showsDiscardConfirmation = true
        return false
    }

    /// 保存の結果の読み上げ。何を・どの種別で・いくらで・（今日でなければ）いつに直したかを読む。
    ///
    /// シートを閉じると、直した記録の吹き出しは画面に残るが、VoiceOver はそこへ移らない。読み上げないと、
    /// 直したとおりに保存されたかが分からない。
    private func spokenSummary(_ edits: EntryEdits) -> String {
        let kind = edits.isIncome ? String(localized: "収入") : String(localized: edits.category.label)
        var parts = edits.memo.isEmpty ? [kind] : [edits.memo, kind]
        parts.append(YenFormatter.string(from: edits.amount))
        let today = now()
        if !calendar.isDate(edits.spentAt, inSameDayAs: today) {
            var format: Date.FormatStyle = calendar.isDate(edits.spentAt, equalTo: today, toGranularity: .year)
                ? .dateTime.month().day() : .dateTime.year().month().day()
            // 日を比べた暦と同じ暦・時間帯で書く（比べた日と読み上げる日が食い違わないように）。
            format.calendar = calendar
            format.timeZone = calendar.timeZone
            parts.append(edits.spentAt.formatted(format))
        }
        return parts.joined(separator: " ")
    }

    // MARK: - 型

    /// 書き込みの失敗。シートを閉じずに知らせ、もう一度押せるようにする。
    enum Failure: Equatable {
        case save
        case delete
    }
}
