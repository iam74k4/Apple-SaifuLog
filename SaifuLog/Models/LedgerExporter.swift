import Foundation
import SaifuLogCore
import SwiftData

/// 記録を CSV ファイルに書き出す（設定の「記録を書き出す」）。CSV の中身はコアの `LedgerCSVWriter` が作る。
///
/// 読み込みと書き出しは、メインスレッドの外で行う。記録が 1 万件あると、保存先から読んで CSV にするまでに
/// 画面が止まって見えるほどかかるため。保存先はメインの ModelContext を使わず、同じ保存先（コンテナ）から
/// 書き出しのための ModelContext を作って読む（ModelContext はスレッドをまたいで使えないため）。
/// 読むだけで書き込まないので、保存先の開き直しが待つ処理（`StoreHost.pendingWrites`）には数えない。
struct LedgerExporter: Sendable {
    /// 書き出しの結果。
    enum Outcome: Sendable, Equatable {
        /// 書き出したファイルと、その記録の件数。
        case file(URL, recordCount: Int)
        /// その期間に記録が無かった（ファイルは作らない）。
        case empty
    }

    let container: ModelContainer
    /// 書き出したファイルを置くディレクトリ。書き出しのたびに、この中に使い捨てのディレクトリを作る。
    let directory: URL
    /// 保存先から読み始める直前に、書き出しを進めているところで呼ぶ。アプリでは渡さない。
    ///
    /// テストで、書き出しがメインスレッドの外で進み、その間もメインアクター（画面）が動けることを確かめるために使う。
    /// メインスレッドの外で進むのは `export` の `@concurrent` が支えている。メインアクターに載せたり（`@MainActor` や
    /// 既定のアクターの設定）、`@concurrent` を外して呼んだ側のアクターで動く設定（NonisolatedNonsendingByDefault）に
    /// したりして画面が止まるように戻っても、CI で気づけるようにする（`@MainActor` に替えると落ちることを確かめた）。
    let willRead: (@Sendable () -> Void)?

    /// アプリの一時ディレクトリの中の、書き出し専用のディレクトリ。共有を終えたら中身を消す（残っていても、iOS が
    /// 一時ディレクトリを片づける）。書き出しのほかのファイルを置かないので、ディレクトリごと消してよい。
    static var defaultDirectory: URL {
        FileManager.default.temporaryDirectory.appending(path: "CSVExport", directoryHint: .isDirectory)
    }

    init(
        container: ModelContainer,
        directory: URL = LedgerExporter.defaultDirectory,
        willRead: (@Sendable () -> Void)? = nil
    ) {
        self.container = container
        self.directory = directory
        self.willRead = willRead
    }

    /// `period` の記録を CSV ファイルに書き出す。途中で取り消されたら、作りかけのファイルを消して CancellationError を投げる。
    ///
    /// ファイルの名前は `saifulog-YYYYMMDD.csv`（書き出した日）にし、書き出しのたびに使い捨てのディレクトリへ置く
    /// （同じ日に何度書き出しても、名前を変えずに済むように）。ファイルの保護クラスは Complete にする（画面のロック中は
    /// 読めない。家計の記録なので、保存先と同じ扱いにする）。
    /// - Parameters:
    ///   - now: 期間の基準と、ファイル名の日付。
    ///   - calendar: 期間を区切る暦（画面の暦）。日付と時刻の欄は、この暦の時間帯で書く。
    @concurrent
    func export(
        period: LedgerExportPeriod, now: Date, calendar: Calendar, language: LedgerCSVWriter.Language
    ) async throws -> Outcome {
        willRead?()
        let context = ModelContext(container)
        var descriptor = period.interval(now: now, calendar: calendar).map(Entry.descriptor(spentIn:))
            ?? FetchDescriptor<Entry>()
        // 並べ替えは `LedgerCSVWriter.records` が決めるが、保存先でも同じ順に読んでおく。すでに並んだものの並べ直しは
        // 比べる回数が少なく、1 万件でも速く済むため。
        descriptor.sortBy = [SortDescriptor(\.spentAt), SortDescriptor(\.createdAt)]
        let records = LedgerCSVWriter.records(try context.fetch(descriptor), in: period, now: now, calendar: calendar)
        try Task.checkCancellation()
        guard !records.isEmpty else { return .empty }
        let data = LedgerCSVWriter.data(records, language: language, timeZone: calendar.timeZone)
        try Task.checkCancellation()

        let folder = directory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(
            at: folder, withIntermediateDirectories: true, attributes: [.protectionKey: FileProtectionType.complete]
        )
        let url = folder.appending(path: LedgerCSVWriter.fileName(exportedAt: now, timeZone: calendar.timeZone))
        do {
            try data.write(to: url, options: [.withoutOverwriting, .completeFileProtection])
            try Task.checkCancellation()
        } catch {
            remove(url)
            throw error
        }
        return .file(url, recordCount: records.count)
    }

    /// 書き出したファイルを、入れた使い捨てのディレクトリごと消す。このディレクトリの外のものは消さない。
    func remove(_ fileURL: URL) {
        let folder = fileURL.deletingLastPathComponent()
        guard folder.deletingLastPathComponent().standardizedFileURL == directory.standardizedFileURL else { return }
        try? FileManager.default.removeItem(at: folder)
    }

    /// 前に書き出して残ったファイルをすべて消す（共有の途中でアプリが終了したときなど）。
    func removeAll() {
        try? FileManager.default.removeItem(at: directory)
    }
}
