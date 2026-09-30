import Foundation
import SaifuLogCore
import SwiftData

/// くり返しの記録の決まり（家賃・サブスク・給料のように、毎月同じ記録）。docs/design.md §9 のくり返しの記録の決め事。
///
/// 毎月、決めた日を過ぎて最初にアプリを開いたときに、その月の分を記録する（`RecurringEntryStore.recordDue`）。記録した月は
/// `lastRecordedMonthKey` に覚え、同じ月の分をもう記録しない（取り消した・消した月も）。記録には、どの決まりのどの月の分かの印
/// （`Entry.recurrenceKey`）を付け、iCloud で 2 台が同じ月を記録したときに片づける（`RecurringDuplicates`）。
///
/// 記録（`Entry`）・予算（`Budget`）と同じく、最初から iCloud 同期（SwiftData + CloudKit）の制約に合わせる。すべてのプロパティに
/// 既定値を持たせ、一意制約も関係も持たせない。**項目はすべて CloudKit の暗号化フィールドにする**（理由は `Entry`。金額と品目は
/// 家計の中身そのもの）。
@Model
final class RecurringEntry {
    /// ID（UUID の小文字の文字列）。記録に付ける印の頭にする。SwiftData の `id` と重ならない名前にする。
    @Attribute(.allowsCloudEncryption) var recurrenceID: String = ""
    /// 品目（空でもよい）。
    @Attribute(.allowsCloudEncryption) var memo: String = ""
    /// 金額（円）。支出も収入も正の数で持つ（`Entry` と同じ）。
    @Attribute(.allowsCloudEncryption) var amount: Int = 0
    @Attribute(.allowsCloudEncryption) var isIncome: Bool = false
    /// カテゴリの rawValue（`Entry` と同じ。収入では使わない）。
    @Attribute(.allowsCloudEncryption) var categoryRawValue: String = EntryCategory.other.rawValue
    /// 毎月の何日か（1〜31。その月に無い日は月末）。
    @Attribute(.allowsCloudEncryption) var dayOfMonth: Int = 1
    /// 最初に記録する月（`RecurringMonth.key`。202610）。
    @Attribute(.allowsCloudEncryption) var startMonthKey: Int = 0
    /// 記録を済ませたいちばん新しい月（`RecurringMonth.key`）。まだなら 0。
    @Attribute(.allowsCloudEncryption) var lastRecordedMonthKey: Int = 0
    /// 作った日時。一覧で同じ日のものを並べる順に使う。
    @Attribute(.allowsCloudEncryption) var createdAt: Date = Date.now
    /// 利用者が最後に直した日時。同じ ID の行が重なったとき（行き違い）に、新しいほうの中身を採る。
    @Attribute(.allowsCloudEncryption) var updatedAt: Date = Date.now

    init(recurrenceID: String, draft: RecurringDraft, startMonth: RecurringMonth, createdAt: Date) {
        self.recurrenceID = recurrenceID
        self.startMonthKey = startMonth.key
        self.createdAt = createdAt
        self.updatedAt = createdAt
        apply(draft)
    }

    var category: EntryCategory {
        get { EntryCategory(rawValue: categoryRawValue) ?? .other }
        set { categoryRawValue = newValue.rawValue }
    }

    /// 直せる中身（金額・品目・支出か収入か・カテゴリ・日）。
    var draft: RecurringDraft {
        RecurringDraft(amount: amount, memo: memo, isIncome: isIncome, category: category, dayOfMonth: dayOfMonth)
    }

    func apply(_ draft: RecurringDraft) {
        amount = draft.amount
        memo = draft.memo
        isIncome = draft.isIncome
        category = draft.isIncome ? .other : draft.category
        dayOfMonth = min(max(draft.dayOfMonth, RecurringSchedule.dayRange.lowerBound), RecurringSchedule.dayRange.upperBound)
    }

    /// コアに渡す決まり。ID か最初の月が読めない行（壊れた行）は nil。
    var rule: RecurringRule? {
        guard !recurrenceID.isEmpty, let start = RecurringMonth(key: startMonthKey) else { return nil }
        return RecurringRule(
            id: recurrenceID, memo: memo, amount: amount, isIncome: isIncome, category: category, dayOfMonth: dayOfMonth,
            startMonth: start, lastRecordedMonth: RecurringMonth(key: lastRecordedMonthKey)
        )
    }
}

/// くり返しの記録の、利用者が決める中身（作る・直すシートの値）。
struct RecurringDraft: Equatable {
    var amount: Int
    var memo: String
    var isIncome: Bool
    var category: EntryCategory
    var dayOfMonth: Int
}

/// くり返しの記録の読み書き。保存に失敗したら変更を巻き戻し、呼び出し側に知らせる（`EntryStore`・`BudgetStore` と同じ）。
@MainActor
struct RecurringEntryStore {
    let context: ModelContext
    /// 変更を書き込む処理。テストで失敗させるために差し替えられるようにしている。
    var save: (ModelContext) throws -> Void = { try $0.save() }
    /// 作った日時・直した日時の基準。テストで固定の日時にする。
    var now: () -> Date = { .now }
    /// 新しい決まりの ID を作る。テストで決めた ID にする。
    var makeID: () -> String = { UUID().uuidString.lowercased() }

    /// 決まりの一覧（毎月の日の順、同じ日なら作った順）。同じ ID の行が重なっていれば、直した日時の新しい行を採る。
    func rules() throws -> [RecurringEntry] {
        Self.resolved(try context.fetch(FetchDescriptor<RecurringEntry>()))
    }

    /// 作る。最初の月は呼び出し側が決める（`RecurringSchedule.startMonth`）。
    @discardableResult
    func create(_ draft: RecurringDraft, startMonth: RecurringMonth) throws -> RecurringEntry {
        let row = RecurringEntry(recurrenceID: makeID(), draft: draft, startMonth: startMonth, createdAt: now())
        context.insert(row)
        try commit()
        return row
    }

    /// 直す。記録済みの月は変えない（前に記録したものも変えない。次に記録する分から、直した中身にする）。
    func update(_ recurrenceID: String, with draft: RecurringDraft) throws {
        let rows = try context.fetch(FetchDescriptor<RecurringEntry>()).filter { $0.recurrenceID == recurrenceID }
        guard !rows.isEmpty else { throw RecurringEntryError.notFound }
        for row in rows {
            row.apply(draft)
            row.updatedAt = now()
        }
        try commit()
    }

    /// やめる（決まりを消す）。これまでに記録したものは残す（ふつうの記録として、直したり消したりできる）。
    func delete(_ recurrenceID: String) throws {
        for row in try context.fetch(FetchDescriptor<RecurringEntry>()) where row.recurrenceID == recurrenceID {
            context.delete(row)
        }
        try commit()
    }

    /// 記録する日を過ぎた月の分を記録する（`RecurringSchedule.dueMonths`）。記録したもの（使った日時の古い順）を返す。
    ///
    /// 記録と、記録した月を覚えることは 1 回で書き込む（一部だけ書かれて、同じ月の分をもう一度記録したり、記録しないまま
    /// 記録したことにしたりしないように）。同じ印の記録がもうあれば（ほかの端末が記録して届いた）、記録せずに記録した月だけ覚える。
    func recordDue(now: Date, timeZone: TimeZone) throws -> [Entry] {
        let rules = try rules()
        guard !rules.isEmpty else { return [] }
        let existingKeys = Set(try context.fetch(Self.occurrenceDescriptor).map(\.recurrenceKey))
        var planned: [(rule: RecurringRule, month: RecurringMonth, spentAt: Date)] = []
        var recordedMonths: [String: RecurringMonth] = [:]
        for rule in rules.compactMap(\.rule) {
            let months = RecurringSchedule.dueMonths(for: rule, now: now, timeZone: timeZone)
            guard let last = months.last else { continue }
            recordedMonths[rule.id] = last
            for month in months {
                let key = RecurringSchedule.occurrenceKey(ruleID: rule.id, month: month)
                guard !existingKeys.contains(key),
                      let spentAt = RecurringSchedule.date(in: month, dayOfMonth: rule.dayOfMonth, timeZone: timeZone) else { continue }
                planned.append((rule, month, spentAt))
            }
        }
        guard !recordedMonths.isEmpty else { return [] }
        // 使った日時の順に並べ、記録した日時を 1 ミリ秒ずつずらす（ひとこと入力の複数件と同じ。タイムラインで 1 つの返事にまとまる）。
        let recorded = planned.sorted { $0.spentAt < $1.spentAt }.enumerated().map { index, item in
            let entry = Entry(
                amount: item.rule.amount, isIncome: item.rule.isIncome, category: item.rule.isIncome ? .other : item.rule.category,
                memo: item.rule.memo, spentAt: item.spentAt,
                createdAt: now.addingTimeInterval(Double(index) * ParsedEntry.orderingStep), source: .recurring, originalText: ""
            )
            entry.recurrenceKey = RecurringSchedule.occurrenceKey(ruleID: item.rule.id, month: item.month)
            return entry
        }
        recorded.forEach(context.insert)
        for row in try context.fetch(FetchDescriptor<RecurringEntry>()) {
            guard let month = recordedMonths[row.recurrenceID], row.lastRecordedMonthKey < month.key else { continue }
            row.lastRecordedMonthKey = month.key
        }
        try commit()
        return recorded
    }

    /// iCloud で 2 台が同じ月の分をそれぞれ記録していたら、記録した日時のいちばん古い 1 件を残してほかを消す
    /// （`RecurringDuplicates`）。消した記録の ID を返す。
    func removeDuplicateOccurrences() throws -> [PersistentIdentifier] {
        let entries = try context.fetch(Self.occurrenceDescriptor)
        let redundant = Set(RecurringDuplicates.redundant(in: entries.map {
            RecurringDuplicates.Record(id: $0.persistentModelID, key: $0.recurrenceKey, createdAt: $0.createdAt)
        }))
        guard !redundant.isEmpty else { return [] }
        for entry in entries where redundant.contains(entry.persistentModelID) {
            context.delete(entry)
        }
        try commit()
        return Array(redundant)
    }

    /// くり返しの記録から記録したもの（印の付いた記録）。
    private static var occurrenceDescriptor: FetchDescriptor<Entry> {
        FetchDescriptor(predicate: #Predicate { $0.recurrenceKey != "" })
    }

    /// 同じ ID の行を 1 つにし（直した日時の新しい行）、毎月の日の順・作った順に並べる。ID の空の行は除く。
    static func resolved(_ rows: [RecurringEntry]) -> [RecurringEntry] {
        var latest: [String: RecurringEntry] = [:]
        for row in rows where !row.recurrenceID.isEmpty {
            if let current = latest[row.recurrenceID], current.updatedAt >= row.updatedAt { continue }
            latest[row.recurrenceID] = row
        }
        return latest.values.sorted { lhs, rhs in
            if lhs.dayOfMonth != rhs.dayOfMonth { return lhs.dayOfMonth < rhs.dayOfMonth }
            if lhs.createdAt != rhs.createdAt { return lhs.createdAt < rhs.createdAt }
            return lhs.recurrenceID < rhs.recurrenceID
        }
    }

    /// 書き込めなかった変更は取り消す（EntryStore と同じ理由。画面と保存先を食い違わせないため）。
    private func commit() throws {
        do {
            try save(context)
        } catch {
            context.rollback()
            throw error
        }
    }
}

/// くり返しの記録の読み書きの失敗。
enum RecurringEntryError: Error, Equatable {
    /// 直そうとした決まりが無い（ほかの端末でやめた）。
    case notFound
}
