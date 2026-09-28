import Foundation
import Observation
import SaifuLogCore
import SwiftData
import SwiftUI

/// ホームの状態と操作（送信・取り消し・削除）。
///
/// 画面（`HomeView`）から切り離し、解析器・時計・読み上げを差し替えて SaifuLogTests で確かめられるようにしている。
/// 画面は、ここの値を表示し、操作をここへ渡すだけにする。
@MainActor
@Observable
final class HomeModel {
    /// タイムラインに一度に読み込む件数。
    static let timelinePageSize = 200

    /// 入力欄の文。
    var draft = ""
    /// 送った文を読み取っている間（送信ボタンを押せなくし、読み取り中の印を出す）。
    private(set) var isParsing = false
    /// 直前に記録したもの。記録の直後に「取り消す」を出すため。
    private(set) var justRecorded: [Entry] = []
    var showsNoAmountAlert = false
    var storeFailure: StoreFailure?
    var pendingDeletion: PendingDeletion?
    /// 今日。「今月」の範囲と、日付に年を添えるかの基準にする。
    ///
    /// 描画のたびに `.now` を読むだけだと、アプリを開いたまま（または裏に置いたまま）月をまたいだとき、
    /// 描き直しが起きずに前の月の合計が「今月」として出続ける。前面に戻ったときと日付が変わったときに
    /// `refreshToday()` で更新する。
    private(set) var today: Date
    /// タイムラインに読み込む件数。上の「前の記録を表示」で増やす。
    private(set) var timelineLimit = HomeModel.timelinePageSize

    @ObservationIgnored private let store: EntryStore
    @ObservationIgnored private let pendingWrites: PendingStoreWrites
    @ObservationIgnored private let makeParser: () -> any EntryParsing
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private let announce: @MainActor (String) -> Void

    /// - Parameters:
    ///   - pendingWrites: 解析を待ってから記録する処理を数える先（`StoreHost.pendingWrites`）。保存先を開き直すとき、
    ///     記録し終えるのを待ってもらうため。
    ///   - makeParser: 送信のたびに解析器を選ぶ（AI の使える・使えないは途中から変わるため）。テストで差し替える。
    ///   - now: 記録の日時と「今日」の基準。テストで固定の日時にする。
    ///   - announce: VoiceOver に読み上げさせる。テストで読み上げる文を集める。
    init(
        store: EntryStore,
        pendingWrites: PendingStoreWrites = PendingStoreWrites(),
        makeParser: @escaping () -> any EntryParsing = { EntryParserFactory.makeParser() },
        now: @escaping () -> Date = { .now },
        announce: @escaping @MainActor (String) -> Void = { VoiceOver.announce($0) }
    ) {
        self.store = store
        self.pendingWrites = pendingWrites
        self.makeParser = makeParser
        self.now = now
        self.announce = announce
        self.today = now()
    }

    convenience init(context: ModelContext, pendingWrites: PendingStoreWrites = PendingStoreWrites()) {
        self.init(store: EntryStore(context: context), pendingWrites: pendingWrites)
    }

    /// 直前の記録を取り消せるか（「取り消す」のバナーと入力欄の VoiceOver の操作を出すか）。
    var canUndo: Bool {
        !justRecorded.isEmpty
    }

    // MARK: - 送信

    /// 入力欄の文を読み取って記録する。読み取りが終わるのを待つための Task を返す（テストで使う）。
    /// 空の文や、読み取り中の送信は受け付けない（nil を返す）。
    @discardableResult
    func send(calendar: Calendar) -> Task<Void, Never>? {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isParsing else { return nil }
        isParsing = true
        // 送った時点で入力欄を空ける。解析（AI だと 1 秒以上かかることがある）を待ってから空けると、
        // 入力欄にとどまって打ち始めた次の入力まで、黙って消してしまうため。
        draft = ""
        let parser = makeParser()
        // 解析の間に保存先が開き直されないよう、Task を作る前に数える（Task は画面のツリーを畳んだ後も動き続け、
        // この後で前の保存先に書き込むため）。
        pendingWrites.begin()
        return Task {
            defer {
                isParsing = false
                pendingWrites.end()
            }
            let parsed = (try? await parser.parse(text)) ?? []
            guard !parsed.isEmpty else {
                // 送った文を入力欄に戻し、その場で直せるようにする。
                restoreDraft(text)
                showsNoAmountAlert = true
                return
            }
            let recorded = Entry.records(from: parsed, originalText: text, source: .text, now: now(), calendar: calendar)
            do {
                try store.insert(recorded)
            } catch {
                // 保存できなかった。記録したことにはせず、送った文を戻して送り直せるようにする。
                restoreDraft(text)
                storeFailure = .record
                return
            }
            justRecorded = recorded
            announceRecorded(recorded, calendar: calendar)
        }
    }

    /// 送った文を入力欄に戻す。ただし解析の間に次の入力を打ち始めていたら、そちらを上書きしない。
    private func restoreDraft(_ text: String) {
        if draft.isEmpty { draft = text }
    }

    /// 何円をどのカテゴリに記録したかを VoiceOver に読み上げさせる。
    ///
    /// 「記録しました / 取り消す」のバナーは、画面に出ても VoiceOver では読まれない。読み上げないと、
    /// VoiceOver の利用者は記録できたかも、AI がどう読んだかも分からず、読み違いにその場で気づけない。
    /// 今日でない日付に記録したときは日付も読む（「昨日」の読み違いや、未来の日付に気づけるように）。
    private func announceRecorded(_ recorded: [Entry], calendar: Calendar) {
        let today = now()
        let items = recorded.map { entry in
            var item = "\(entry.kindText) \(YenFormatter.string(from: entry.amount))"
            if !calendar.isDate(entry.spentAt, inSameDayAs: today) {
                let format: Date.FormatStyle = entry.showsYear(today: today, calendar: calendar)
                    ? .dateTime.year().month().day() : .dateTime.month().day()
                item += " \(entry.spentAt.formatted(format))"
            }
            return item
        }
        announce(String(localized: "記録しました: \(items.formatted(.list(type: .and)))"))
    }

    // MARK: - 取り消し

    /// 直前の記録を取り消す。元の文を入力欄に戻し、その場で直して送り直せるようにする。
    func undoLastRecord() {
        let targets = justRecorded
        guard !targets.isEmpty else { return }
        // 消した記録の値は、保存した後には読めない。読み上げと入力欄に戻す文は先に取っておく。
        let items = targets.map { "\($0.kindText) \(YenFormatter.string(from: $0.amount))" }
        let originalText = targets.first?.originalText ?? ""
        do {
            try store.delete(targets)
        } catch {
            // バナーは残し、もう一度押せるようにする。
            storeFailure = .undo
            return
        }
        justRecorded = []
        restoreDraft(originalText)
        announce(String(localized: "取り消しました: \(items.formatted(.list(type: .and)))"))
    }

    /// 「取り消す」のバナーを引っ込める（時間切れ・「閉じる」の操作）。記録はそのまま残る。
    func dismissUndo() {
        justRecorded = []
    }

    // MARK: - 削除

    /// 削除の確認を出す。確認の文は先に作っておく（消した後の記録の値は読めないため）。
    func requestDelete(_ entry: Entry) {
        pendingDeletion = PendingDeletion(entry: entry, summary: entry.summaryText)
    }

    /// 確認のあとで記録を削除する。
    func delete(_ pending: PendingDeletion) {
        pendingDeletion = nil
        let id = pending.entry.persistentModelID
        do {
            try store.delete([pending.entry])
        } catch {
            storeFailure = .delete
            return
        }
        // 直前に記録したものを消したら、「取り消す」の対象からも外す（消えた記録を取り消そうとしないように）。
        justRecorded.removeAll { $0.persistentModelID == id }
        announce(String(localized: "削除しました: \(pending.summary)"))
    }

    // MARK: - 日付とタイムライン

    /// 「今日」を読み直す。前面に戻ったときと、日付が変わったとき（0 時・時間帯の変更など）に呼ぶ。
    func refreshToday() {
        today = now()
    }

    /// タイムラインにさらに前の記録を読み込む。
    func showMoreTimeline() {
        timelineLimit += Self.timelinePageSize
    }

    // MARK: - 型

    /// 削除の確認を待っている記録。確認の文は先に作っておく（消した後の記録の値は読めないため）。
    struct PendingDeletion {
        let entry: Entry
        let summary: String
    }

    /// 保存先への書き込みの失敗。利用者に知らせ、記録したつもり・消したつもりにさせない。
    enum StoreFailure: Equatable {
        case record
        case undo
        case delete
    }
}
