import Foundation
import Observation
import SaifuLogCore
import SwiftData
import SwiftUI

/// ホームの状態と操作（送信・取り消し・直す・削除・予算を決める画面と月のまとめと設定の出し入れ）。
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
    /// 「予算を決める」のシートの状態と操作。シートを出していなければ nil（シートを閉じると画面が nil に戻す）。
    var budgetSetup: BudgetSetupModel?
    /// 「直す」のシートで直している記録の状態と操作。シートを出していなければ nil（シートを閉じると画面が nil に戻す）。
    var editing: EditEntryModel?
    /// 「月のまとめ」（横に進む画面）の状態と操作。出していなければ nil（ホームへ戻ると画面が nil に戻す）。
    var monthlyReport: MonthlyReportModel?
    /// 「設定」（横に進む画面）の状態と操作。出していなければ nil（ホームへ戻ると画面が nil に戻す）。
    var settings: SettingsModel?
    /// 今日。「今月」の範囲と、日付に年を添えるかの基準にする。
    ///
    /// 描画のたびに `.now` を読むだけだと、アプリを開いたまま（または裏に置いたまま）月をまたいだとき、
    /// 描き直しが起きずに前の月の合計が「今月」として出続ける。前面に戻ったときと日付が変わったときに
    /// `refreshToday()` で更新する。
    private(set) var today: Date
    /// タイムラインに読み込む件数。上の「前の記録を表示」で増やす。
    private(set) var timelineLimit = HomeModel.timelinePageSize

    @ObservationIgnored private let store: EntryStore
    @ObservationIgnored private let budgetStore: BudgetStore
    @ObservationIgnored private let pendingWrites: PendingStoreWrites
    @ObservationIgnored private let makeParser: (Date, Calendar) -> any EntryParsing
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private let announce: @MainActor (String) -> Void

    /// - Parameters:
    ///   - budgetStore: 予算の読み書き。渡さなければ記録と同じ保存先（`store` の ModelContext）を使う。
    ///   - pendingWrites: 解析を待ってから記録する処理を数える先（`StoreHost.pendingWrites`）。保存先を開き直すとき、
    ///     記録し終えるのを待ってもらうため。
    ///   - makeParser: 送信のたびに解析器を選ぶ（AI の使える・使えないは途中から変わるため）。送った瞬間の日時と暦を渡し、
    ///     「昨日」「9/26」をその日時を基準に読ませる。テストで差し替える。
    ///   - now: 記録の日時と「今日」の基準。テストで固定の日時にする。
    ///   - announce: VoiceOver に読み上げさせる。テストで読み上げる文を集める。
    init(
        store: EntryStore,
        budgetStore: BudgetStore? = nil,
        pendingWrites: PendingStoreWrites = PendingStoreWrites(),
        makeParser: @escaping (Date, Calendar) -> any EntryParsing = { EntryParserFactory.makeParser(now: $0, calendar: $1) },
        now: @escaping () -> Date = { .now },
        announce: @escaping @MainActor (String) -> Void = { VoiceOver.announce($0) }
    ) {
        self.store = store
        self.budgetStore = budgetStore ?? BudgetStore(context: store.context)
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

    /// 「取り消す」のバナーを時間で引っ込めてよいか（画面の 8 秒のタイマーを動かすか）。
    ///
    /// 「直す」のシートを出している間は数えない。シートの下でもホームは表示されたままなので、数え続けると、
    /// 直すのに 8 秒以上かけてやめたときには「取り消す」が消えていて、直すのをやめても取り消せる、という約束を破るため。
    /// 保存の失敗のアラート（「取り消せませんでした」など）を出している間も数えない。アラートを読んでいる間に
    /// バナーが消えると、「もう一度お試しください」に従えないため。どちらも閉じたら数え直す（閉じた直後にも押せるように）。
    var autoHidesUndo: Bool {
        canUndo && editing == nil && storeFailure == nil
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
        // 前の記録の「取り消す」（バナーと VoiceOver の操作）を引っ込める。読み取りの間も出したままだと、押したときに
        // 前の記録が消え、前の文が入力欄に戻る。それを送り直したり、いま送った文の記録だけが残ったりして、
        // 取り消したつもりのものと違う記録が残るため。
        justRecorded = []
        // 送った瞬間の日時を 1 つ決め、解析（「昨日」「9/26」の基準）と保存（記録した日時・使った日時）の両方に使う。
        // 保存のときに時計を読み直すと、読み取りを待つ間に日付が変わったとき（23:59:59 に送って 0:00:01 に保存）、
        // 「9/26」と書いた記録が 1 日ずれて保存されるため。
        let sentAt = now()
        let parser = makeParser(sentAt, calendar)
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
            let recorded = Entry.records(from: parsed, originalText: text, source: .text, now: sentAt, calendar: calendar)
            do {
                try store.insert(recorded)
            } catch {
                // 保存できなかった。記録したことにはせず、送った文を戻して送り直せるようにする。
                restoreDraft(text)
                storeFailure = .record
                return
            }
            justRecorded = recorded
            announceRecorded(recorded, today: sentAt, calendar: calendar)
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
    /// 今日かどうかは、記録の日付を決めたのと同じ送った瞬間（`today`）で見る。
    private func announceRecorded(_ recorded: [Entry], today: Date, calendar: Calendar) {
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

    // MARK: - 直す

    /// 「直す」のシートを出す（吹き出しのタップ・長押しのメニュー・「取り消す」のバナー・VoiceOver の操作から）。
    ///
    /// 直した内容の保存は同期的に書き込む（送信のように、あとで書き込む処理ではない）ので、`pendingWrites` には数えない。
    /// - Parameter calendar: 日付の区切りの基準（画面の暦）。今日より先かの判定と、日付を直したかの判定に使う。
    func presentEdit(_ entry: Entry, calendar: Calendar) {
        editing = EditEntryModel(
            entry: entry,
            store: store,
            calendar: calendar,
            now: now,
            announce: announce,
            didSave: { [weak self] entry in self?.finishEditing(entry) },
            didDelete: { [weak self] id in self?.justRecorded.removeAll { $0.persistentModelID == id } }
        )
    }

    /// 直前に記録したものを直したら、「取り消す」を引っ込める。
    ///
    /// 取り消すと、直す前の送った文を入力欄に戻すことになり、直した内容と食い違うため（送り直すと、直す前の読み方で
    /// 記録し直すことになる）。直した後も消したければ、長押しの「削除」か、直すシートの「この記録を削除」から消せる。
    private func finishEditing(_ entry: Entry) {
        let id = entry.persistentModelID
        if justRecorded.contains(where: { $0.persistentModelID == id }) {
            justRecorded = []
        }
    }

    // MARK: - 予算

    /// 「予算を決める」のシートを出す。いまの予算を入力欄に入れて開く（予算を変えるときも同じ画面）。
    ///
    /// 予算の保存は同期的に書き込む（送信のように、あとで書き込む処理ではない）ので、`pendingWrites` には数えない。
    func presentBudgetSetup() {
        budgetSetup = BudgetSetupModel(store: budgetStore, announce: announce)
    }

    // MARK: - 月のまとめ

    /// 「月のまとめ」へ進む（帯の今月の合計を押したとき）。今月を開く。
    ///
    /// まとめの記録の一覧からも「直す」を開けるので、ホームから開いたときと同じく、直したら「取り消す」を引っ込め、
    /// 消したら「取り消す」の対象から外す（戻ったあとで、消えた記録や直す前の文を取り消しで扱わないように）。
    /// - Parameter calendar: 月の区切りの暦（ホームの画面の暦。帯の今月と同じ月でまとめるため）。
    func presentMonthlyReport(calendar: Calendar) {
        monthlyReport = MonthlyReportModel(
            store: store,
            calendar: calendar,
            now: now,
            announce: announce,
            didSave: { [weak self] entry in self?.finishEditing(entry) },
            didDelete: { [weak self] id in self?.justRecorded.removeAll { $0.persistentModelID == id } }
        )
    }

    // MARK: - 設定

    /// 「設定」へ進む（帯の右上の歯車を押したとき）。
    ///
    /// 設定から開く「予算を決める」も、ホームの帯から開くときと同じ保存先と読み上げを使う。
    func presentSettings() {
        settings = SettingsModel(context: store.context, budgetStore: budgetStore, now: now, announce: announce)
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
