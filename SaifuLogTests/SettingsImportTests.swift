import Foundation
import SaifuLogCore
import SwiftData
import Testing
@testable import SaifuLog

/// 設定の「CSV から読み込む」（SettingsModel・LedgerImporter）。メモリの上の保存先、使い捨てのディレクトリに書いた CSV、
/// 固定の日時（2026-09-28 12:00、日本時間）で確かめる。
@MainActor
struct SettingsImportTests {
    struct TestError: Error {}

    @MainActor
    final class Fixture {
        let context: ModelContext
        /// 読み込む CSV を置く使い捨てのディレクトリ。
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "SettingsImportTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        var failsSave = false

        init() throws {
            context = try TestSupport.makeContext()
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }

        func cleanUp() {
            try? FileManager.default.removeItem(at: directory)
        }

        func makeModel() -> SettingsModel {
            var store = EntryStore(context: context)
            store.save = { [unowned self] context in
                if failsSave { throw TestError() }
                try context.save()
            }
            return SettingsModel(
                context: context,
                entryStore: store,
                exporter: LedgerExporter(container: context.container, directory: directory.appending(path: "export")),
                bundleInfo: [:],
                now: { TestSupport.now },
                announce: { _ in }
            )
        }

        func insert(_ entries: [Entry]) throws {
            try EntryStore(context: context).insert(entries)
        }

        func entries() throws -> [Entry] {
            try context.fetch(FetchDescriptor<Entry>(sortBy: [SortDescriptor(\.createdAt)]))
        }

        /// 記録を、このアプリの書き出しと同じ形の CSV ファイルにする。
        func writeCSV(_ entries: [Entry], catalog: CategoryCatalog = .builtIn, name: String = "saifulog.csv") throws -> URL {
            let url = directory.appending(path: name)
            try LedgerCSVWriter.data(entries, language: .japanese, timeZone: TestSupport.calendar.timeZone, catalog: catalog)
                .write(to: url)
            return url
        }

        func writeText(_ text: String, name: String = "other.csv") throws -> URL {
            let url = directory.appending(path: name)
            try Data(text.utf8).write(to: url)
            return url
        }
    }

    static func entry(
        _ amount: Int, memo: String, category: EntryCategory = .food, isIncome: Bool = false, spentAt: Date = TestSupport.now,
        originalText: String? = nil
    ) -> Entry {
        Entry(
            amount: amount, isIncome: isIncome, category: isIncome ? .other : category, memo: memo, spentAt: spentAt,
            createdAt: spentAt, source: .text, originalText: originalText ?? "\(memo) \(amount)"
        )
    }

    /// 別の端末で書き出した CSV にする記録（保存先には入れない）。
    static var exportedEntries: [Entry] {
        [
            entry(850, memo: "ランチ", spentAt: TestSupport.date(2026, 9, 27, hour: 12, minute: 10)),
            entry(480, memo: "カフェラテ", category: .cafe, spentAt: TestSupport.date(2026, 9, 27, hour: 15)),
            entry(250_000, memo: "給料", isIncome: true, spentAt: TestSupport.date(2026, 9, 25, hour: 9)),
        ]
    }

    // MARK: - 読み込み

    @Test("選んだ CSV を読み、件数を確かめてから「読み込む」で記録を入れる（入力元は読み込み、記録した日時は使った日時）")
    func importsAfterConfirmation() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let url = try fixture.writeCSV(Self.exportedEntries)
        let model = fixture.makeModel()

        model.requestImport()
        #expect(model.showsImporter)
        await model.importFile(.success(url), calendar: TestSupport.calendar)?.value

        #expect(model.showsImporter == false)
        #expect(model.isImporting == false)
        let preview = try #require(model.importPreview)
        #expect(preview.importCount == 3)
        #expect(preview.duplicateCount == 0)
        #expect(preview.unreadableCount == 0)
        // 確かめている間は、まだ何も入れていない。設定を閉じずに待つ（Siri の頼みで黙って閉じない）。
        #expect(try fixture.entries().isEmpty)
        #expect(model.isPresentingSheet)

        model.confirmImport(preview)

        #expect(model.importPreview == nil)
        #expect(model.importAlert == .imported(count: 3))
        let entries = try fixture.entries()
        #expect(entries.map(\.memo) == ["給料", "ランチ", "カフェラテ"])
        #expect(entries.map(\.amount) == [250_000, 850, 480])
        #expect(entries.map(\.category) == [.other, .food, .cafe])
        #expect(entries.map(\.isIncome) == [true, false, false])
        #expect(entries.allSatisfy { $0.source == .imported })
        #expect(entries.allSatisfy { $0.createdAt == $0.spentAt })
        #expect(entries.map(\.originalText) == ["給料 250000", "ランチ 850", "カフェラテ 480"])
        #expect(entries.allSatisfy { !$0.needsCategoryReview && $0.recurrenceKey.isEmpty })
    }

    @Test("同じファイルをもう一度読み込んでも二重にしない（入れる記録が無いことを知らせる）")
    func reimportAddsNothing() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let url = try fixture.writeCSV(Self.exportedEntries)
        let model = fixture.makeModel()
        await model.importFile(.success(url), calendar: TestSupport.calendar)?.value
        model.confirmImport(try #require(model.importPreview))
        model.importAlert = nil

        await model.importFile(.success(url), calendar: TestSupport.calendar)?.value

        #expect(model.importPreview == nil)
        #expect(model.importAlert == .nothingToImport(duplicates: 3, unreadable: 0))
        #expect(try fixture.entries().count == 3)
    }

    @Test("この端末にすでにある記録は飛ばし、無い記録だけを入れる")
    func skipsRecordsAlreadyHere() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        // 同じ記録（秒まで違っても、分まで同じなら同じ記録）。
        try fixture.insert([Self.entry(850, memo: "ランチ", spentAt: TestSupport.date(2026, 9, 27, hour: 12, minute: 10).addingTimeInterval(30))])
        let url = try fixture.writeCSV(Self.exportedEntries)
        let model = fixture.makeModel()

        await model.importFile(.success(url), calendar: TestSupport.calendar)?.value

        let preview = try #require(model.importPreview)
        #expect(preview.importCount == 2)
        #expect(preview.duplicateCount == 1)
        model.confirmImport(preview)
        #expect(try fixture.entries().count == 3)
        #expect(model.importAlert == .imported(count: 2))
    }

    @Test("作ったカテゴリは、この端末の同じ名前のカテゴリに戻す")
    func mapsCustomCategoriesByName() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let hobby = try CustomCategoryStore(context: fixture.context).create(name: "推し活", symbolName: "heart", colorIndex: 0)
        let catalog = try CustomCategoryStore(context: fixture.context).catalog()
        let url = try fixture.writeCSV([Self.entry(3_990, memo: "グッズ", category: hobby)], catalog: catalog)
        let model = fixture.makeModel()

        await model.importFile(.success(url), calendar: TestSupport.calendar)?.value
        model.confirmImport(try #require(model.importPreview))

        #expect(try fixture.entries().map(\.category) == [hobby])
    }

    @Test("このアプリの書き出しでない CSV は読まず、何も入れない")
    func rejectsOtherCSV() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let url = try fixture.writeText("Date,Amount,Memo\r\n2026-09-28,850,Lunch\r\n")
        let model = fixture.makeModel()

        await model.importFile(.success(url), calendar: TestSupport.calendar)?.value

        #expect(model.importPreview == nil)
        #expect(model.importAlert == .notSaifuLogCSV)
        #expect(try fixture.entries().isEmpty)
    }

    @Test("読めない行だけのファイルは、入れる記録が無いことを知らせる")
    func reportsUnreadableRows() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let url = try fixture.writeText("日付,時刻,種類,カテゴリ,品目,金額,送った文\r\n2026-02-30,12:00,支出,食費,ランチ,850,\r\n")
        let model = fixture.makeModel()

        await model.importFile(.success(url), calendar: TestSupport.calendar)?.value

        #expect(model.importAlert == .nothingToImport(duplicates: 0, unreadable: 1))
    }

    @Test("ファイルを開けなければ（選べなかった・消えた）知らせる")
    func reportsUnreadableFile() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let model = fixture.makeModel()

        await model.importFile(.success(fixture.directory.appending(path: "missing.csv")), calendar: TestSupport.calendar)?.value
        #expect(model.importAlert == .unreadable)

        model.importAlert = nil
        #expect(model.importFile(.failure(TestError()), calendar: TestSupport.calendar) == nil)
        #expect(model.importAlert == .unreadable)
    }

    @Test("書き込めなければ何も入れずに知らせる")
    func saveFailureAddsNothing() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let url = try fixture.writeCSV(Self.exportedEntries)
        let model = fixture.makeModel()
        await model.importFile(.success(url), calendar: TestSupport.calendar)?.value
        let preview = try #require(model.importPreview)

        fixture.failsSave = true
        model.confirmImport(preview)

        #expect(model.importAlert == .saveFailed)
        fixture.failsSave = false
        #expect(try fixture.entries().isEmpty)
    }

    @Test("確かめで「キャンセル」を押すと何も入れない")
    func cancelAddsNothing() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let url = try fixture.writeCSV(Self.exportedEntries)
        let model = fixture.makeModel()
        await model.importFile(.success(url), calendar: TestSupport.calendar)?.value

        model.cancelImport()

        #expect(model.importPreview == nil)
        #expect(model.importAlert == nil)
        #expect(try fixture.entries().isEmpty)
        #expect(model.isPresentingSheet == false)
    }

    @Test("件数を確かめている間は、もう一度ファイルを選ばせない")
    func ignoresRequestsWhileConfirming() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let url = try fixture.writeCSV(Self.exportedEntries)
        let model = fixture.makeModel()
        await model.importFile(.success(url), calendar: TestSupport.calendar)?.value

        model.requestImport()

        #expect(model.showsImporter == false)
        #expect(model.importFile(.success(url), calendar: TestSupport.calendar) == nil)
    }

    // MARK: - 記録の作り方

    @Test("同じ分の行は、記録した日時をファイルの順に 1 ミリ秒ずつずらす（1 回の送信が 1 つにまとまるように）")
    func entriesKeepFileOrder() {
        let spentAt = TestSupport.now
        let rows = [
            LedgerCSVReader.Row(line: 2, spentAt: spentAt, isIncome: false, category: .food, memo: "ランチ", amount: 850, originalText: "ランチ850 コーヒー400"),
            LedgerCSVReader.Row(line: 3, spentAt: spentAt, isIncome: false, category: .cafe, memo: "コーヒー", amount: 400, originalText: "ランチ850 コーヒー400"),
        ]

        let entries = LedgerImporter.entries(from: rows)

        #expect(entries.map(\.createdAt) == [spentAt, spentAt.addingTimeInterval(0.001)])
        #expect(entries.allSatisfy { $0.source == .imported && $0.spentAt == spentAt })
        #expect(entries.map(\.originalText) == ["ランチ850 コーヒー400", "ランチ850 コーヒー400"])
    }

    @Test("読み込んだ記録の入力元は保存したまま読み直せ、知らない値は打った記録として読む")
    func importedSourceRoundTrips() {
        let entry = Self.entry(850, memo: "ランチ")
        entry.source = .imported
        #expect(entry.sourceRawValue == "imported")
        #expect(entry.source == .imported)
        entry.sourceRawValue = "future-source"
        #expect(entry.source == .text)
    }
}
