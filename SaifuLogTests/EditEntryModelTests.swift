import Foundation
import SaifuLogCore
import SwiftData
import Testing
@testable import SaifuLog

/// 「直す」のシート（EditEntryModel）。メモリの上の保存先と、固定の日時で確かめる。
@MainActor
struct EditEntryModelTests {
    /// EditEntryModel と、その保存先・読み上げ・ホームへの知らせの代わり。
    @MainActor
    final class Fixture {
        let context: ModelContext
        let entry: Entry
        /// true の間は保存（書き込み）が失敗する。
        var failsSave = false
        private(set) var announcements: [String] = []
        private(set) var savedEntries: [Entry] = []
        private(set) var deletedIDs: [PersistentIdentifier] = []
        private(set) var model: EditEntryModel!

        init(entry: Entry = TestSupport.entry()) throws {
            context = try TestSupport.makeContext()
            self.entry = entry
            try EntryStore(context: context).insert([entry])
            var store = EntryStore(context: context)
            store.save = { [unowned self] context in
                if failsSave { throw TestError() }
                try context.save()
            }
            model = EditEntryModel(
                entry: entry,
                store: store,
                calendar: TestSupport.calendar,
                now: { TestSupport.now },
                announce: { [unowned self] in announcements.append($0) },
                didSave: { [unowned self] in savedEntries.append($0) },
                didDelete: { [unowned self] in deletedIDs.append($0) }
            )
        }

        func entries() throws -> [Entry] {
            try context.fetch(FetchDescriptor<Entry>())
        }
    }

    static func income() -> Entry {
        Entry(
            amount: 250_000, isIncome: true, category: .other, memo: "給料",
            spentAt: TestSupport.now, createdAt: TestSupport.now, source: .text, originalText: "給料 25万"
        )
    }

    // MARK: - 開いたとき

    /// 開いたときは記録のいまの値が入っていて、直していないので保存は押せない。
    @Test func opensWithEntryValues() throws {
        let fixture = try Fixture()
        let model = fixture.model!

        #expect(model.amountText == "850")
        #expect(model.memo == "ランチ")
        #expect(model.category == .food)
        #expect(!model.isIncome)
        #expect(model.day == TestSupport.now)
        #expect(model.originalText == "ランチ 850")
        #expect(model.deletionSummary == "ランチ ¥850")
        #expect(model.amountIssue == nil)
        #expect(!model.isFutureDate)
        #expect(!model.hasChanges)
        #expect(!model.canSave)
        // 押せなくても save() を呼ばれたら何もしない。
        #expect(!model.save())
        #expect(fixture.announcements.isEmpty)
    }

    /// 大きい額も 3 桁ごとにカンマを入れて見せる。
    @Test func opensWithGroupedAmount() throws {
        let fixture = try Fixture(entry: Self.income())

        #expect(fixture.model.amountText == "250,000")
        #expect(fixture.model.isIncome)
    }

    // MARK: - 金額の確かめ

    @Test func amountMustBePositiveAndWithinLimit() throws {
        let fixture = try Fixture()
        let model = fixture.model!

        model.amountText = ""
        #expect(model.amountIssue == .missing)
        #expect(!model.canSave)
        // 金額を消しただけでも、閉じるときは確認を出す（直した内容として扱う）。
        #expect(model.hasChanges)

        model.amountText = "0"
        #expect(model.amountIssue == .notPositive)
        #expect(!model.canSave)

        model.amountText = "1,000,000,000,000"
        #expect(model.amountIssue == .tooLarge)
        #expect(!model.canSave)

        model.amountText = "999,999,999,999"
        #expect(model.amountIssue == nil)
        #expect(model.canSave)
    }

    /// 入力欄は打つたびに「1,280」の形にそろえる（全角の数字や貼り付けた記号も）。
    @Test func normalizesAmountText() throws {
        let fixture = try Fixture()
        let model = fixture.model!

        model.amountText = "1280"
        model.normalizeAmountText()
        #expect(model.amountText == "1,280")

        model.amountText = "¥１２００円"
        model.normalizeAmountText()
        #expect(model.amountText == "1,200")
    }

    /// 同じ額に戻したり、品目の前後に空白を足しただけなら、直していないのと同じ（保存は押せない）。
    @Test func sameValuesAreNotChanges() throws {
        let fixture = try Fixture()
        let model = fixture.model!

        model.amountText = "900"
        #expect(model.canSave)
        model.amountText = "850"
        model.memo = "  ランチ \n"
        // 日付の選択は、同じ日でも時刻の違う日時を返すことがある。
        model.day = TestSupport.date(2026, 9, 28)

        #expect(!model.hasChanges)
        #expect(!model.canSave)
    }

    // MARK: - 保存

    @Test func savesAmountAndCategory() throws {
        let fixture = try Fixture()
        let model = fixture.model!
        model.amountText = "1,200"
        model.category = .cafe

        #expect(model.canSave)
        #expect(model.save())

        #expect(fixture.entry.amount == 1_200)
        #expect(fixture.entry.category == .cafe)
        #expect(fixture.entry.memo == "ランチ")
        #expect(!fixture.context.hasChanges)
        #expect(fixture.savedEntries.count == 1)
        // 何を・どのカテゴリで・いくらに直したかを VoiceOver に読み上げる（今日なので日付は読まない）。
        #expect(fixture.announcements.count == 1)
        let spoken = try #require(fixture.announcements.first)
        #expect(spoken.contains("ランチ"))
        #expect(spoken.contains(String(localized: EntryCategory.cafe.label)))
        #expect(spoken.contains("¥1,200"))
    }

    /// 品目は前後の空白を除いて保存する。空にすると、吹き出しの見出しはカテゴリ名になる。
    @Test func savesTrimmedMemo() throws {
        let fixture = try Fixture()
        fixture.model.memo = "  焼肉定食 "

        #expect(fixture.model.save())
        #expect(fixture.entry.memo == "焼肉定食")

        let second = try Fixture()
        second.model.memo = "   "
        #expect(second.model.save())
        #expect(second.entry.memo.isEmpty)
    }

    /// 日付を直しても、時刻は元の記録のまま。今日でない日付は読み上げにも入れる。
    @Test func savesDateKeepingTime() throws {
        let original = TestSupport.entry(spentAt: TestSupport.date(2026, 9, 28, hour: 12, minute: 34))
        let fixture = try Fixture(entry: original)
        fixture.model.day = TestSupport.date(2026, 9, 26)

        #expect(!fixture.model.isFutureDate)
        #expect(fixture.model.save())

        #expect(fixture.entry.spentAt == TestSupport.date(2026, 9, 26, hour: 12, minute: 34))
        var format = Date.FormatStyle.dateTime.month().day()
        format.calendar = TestSupport.calendar
        format.timeZone = TestSupport.calendar.timeZone
        let expectedDay = TestSupport.date(2026, 9, 26, hour: 12, minute: 34).formatted(format)
        #expect(fixture.announcements.last?.contains(expectedDay) == true)
    }

    /// 今日より先の日付は注意を出すが、保存は止めない（払う予定の家賃のように、先の日付で記録することがある）。
    @Test func futureDateWarnsButSaves() throws {
        let fixture = try Fixture()
        fixture.model.day = TestSupport.date(2026, 10, 1)

        #expect(fixture.model.isFutureDate)
        #expect(fixture.model.canSave)
        #expect(fixture.model.save())
        #expect(fixture.entry.spentAt == TestSupport.date(2026, 10, 1, hour: 12))
    }

    /// 支出を収入に直すと、カテゴリは「その他」で保存する（ひとこと入力で収入を記録したときと同じ）。
    @Test func switchingToIncomeSavesOtherCategory() throws {
        let fixture = try Fixture()
        fixture.model.isIncome = true

        #expect(fixture.model.canSave)
        #expect(fixture.model.save())

        #expect(fixture.entry.isIncome)
        #expect(fixture.entry.category == .other)
        #expect(fixture.announcements.last?.contains(String(localized: "収入")) == true)
    }

    /// 収入を支出に直すときは、選んだカテゴリで保存する。
    @Test func switchingToExpenseUsesChosenCategory() throws {
        let fixture = try Fixture(entry: Self.income())
        fixture.model.isIncome = false
        fixture.model.category = .entertainment

        #expect(fixture.model.save())

        #expect(!fixture.entry.isIncome)
        #expect(fixture.entry.category == .entertainment)
    }

    /// 収入のままカテゴリだけ触っても（収入ではカテゴリの欄を出さない）、直したことにしない。
    @Test func categoryIsIgnoredForIncome() throws {
        let fixture = try Fixture(entry: Self.income())
        fixture.model.category = .food

        #expect(!fixture.model.hasChanges)
        #expect(!fixture.model.canSave)
    }

    /// 保存に失敗したら、シートは閉じず（false）にアラートを出す。記録は直す前の値に戻し、入力欄はそのまま残す
    /// （閉じると直した内容を打ち直すことになる）。保存できるようになれば、もう一度押して保存できる。
    @Test func saveFailureKeepsSheetAndRollsBack() throws {
        let fixture = try Fixture()
        let model = fixture.model!
        model.amountText = "900"
        model.category = .cafe
        fixture.failsSave = true

        #expect(!model.save())

        #expect(model.failure == .save)
        #expect(fixture.entry.amount == 850)
        #expect(fixture.entry.category == .food)
        #expect(!fixture.context.hasChanges)
        #expect(model.amountText == "900")
        #expect(model.category == .cafe)
        #expect(model.canSave)
        #expect(fixture.announcements.isEmpty)
        #expect(fixture.savedEntries.isEmpty)

        fixture.failsSave = false
        model.failure = nil
        #expect(model.save())
        #expect(fixture.entry.amount == 900)
        #expect(fixture.entry.category == .cafe)
    }

    // MARK: - 削除

    @Test func deleteRemovesEntry() throws {
        let fixture = try Fixture()
        let id = fixture.entry.persistentModelID

        #expect(fixture.model.delete())

        #expect(try fixture.entries().isEmpty)
        #expect(fixture.deletedIDs == [id])
        #expect(fixture.announcements.last?.contains("ランチ ¥850") == true)
    }

    /// 直しかけの値ではなく、保存されている記録（開いた時点の値）を指して確認し、読み上げる。
    @Test func deleteUsesSavedSummary() throws {
        let fixture = try Fixture()
        fixture.model.amountText = "12,000"
        fixture.model.memo = "焼肉"

        #expect(fixture.model.deletionSummary == "ランチ ¥850")
        #expect(fixture.model.delete())
        #expect(fixture.announcements.last?.contains("ランチ ¥850") == true)
    }

    /// 削除を書き込めなければ、記録は残してシートも閉じない。
    @Test func deleteFailureKeepsEntry() throws {
        let fixture = try Fixture()
        fixture.failsSave = true

        #expect(!fixture.model.delete())

        #expect(fixture.model.failure == .delete)
        #expect(try fixture.entries().map(\.amount) == [850])
        #expect(!fixture.context.hasChanges)
        #expect(fixture.deletedIDs.isEmpty)
        #expect(fixture.announcements.isEmpty)
    }

    // MARK: - 閉じる

    /// 直していなければそのまま閉じ、直した内容があれば捨ててよいかを確かめる（キャンセル・下へのスワイプ）。
    @Test func closingAsksOnlyWhenChanged() throws {
        let fixture = try Fixture()
        let model = fixture.model!

        #expect(model.requestClose())
        #expect(!model.showsDiscardConfirmation)

        model.memo = "カツ丼"
        #expect(!model.requestClose())
        #expect(model.showsDiscardConfirmation)
        // 確認を出すだけで、記録は変えない。
        #expect(fixture.entry.memo == "ランチ")
        #expect(!fixture.context.hasChanges)
    }
}
