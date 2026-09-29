import Foundation
import Observation
import SaifuLogCore

/// ⑤ 読み取り結果のシートの状態と操作。店名・日付・品目の行（外す・直す）・照合・まとめて 1 件か品目ごとか・記録する。
///
/// 画面（`ReceiptResultSheet`）から切り離し、SaifuLogTests で確かめられるようにしている。記録そのもの（保存・無料の回数・
/// 「取り消す」）はホーム（`HomeModel.recordReceipt`）が受け持つ。
@MainActor
@Observable
final class ReceiptResultModel: Identifiable {
    /// 読み取りの進み。
    enum State: Equatable {
        /// 文字を読み取っている（AI が品名を整えている間も）。
        case reading
        /// 読めなかった（画像を読み込めない・文字が無い・品目も合計も無い）。撮り直しを案内する。
        case unreadable(ReceiptUnreadableReason)
        /// 読み取れた。行を確かめて記録できる。
        case ready
    }

    /// 品目の 1 行（画面で外したり直したりする）。
    struct Line: Identifiable, Equatable {
        let id = UUID()
        let kind: ReceiptDraftLine.Kind
        /// 品名（「税・その他」の行は空。画面が名前を出す）。
        var name: String
        /// 金額の入力欄（「1,280」の形）。
        var amountText: String
        var category: EntryCategory
        /// 記録するか（「外す」で false）。
        var isIncluded = true
        let quantity: Int?
        let unitPrice: Int?
        /// 引いた値引き（画面に「値引 ¥…」と添える）。
        let discount: Int
        let isReducedTaxRate: Bool

        /// 入力欄の金額。保存できない額なら nil。
        var amount: Int? {
            guard case .success(let amount) = EntryAmountInput.validate(amountText) else { return nil }
            return amount
        }
    }

    /// 記録した結果（ホームが返す）。
    enum RecordOutcome: Equatable {
        /// 記録した（ホームがシートを閉じる）。
        case recorded
        /// 書き込めなかった（シートは閉じずに知らせる）。
        case failed
        /// 無料の回数を使い切っていた（ホームがシートを閉じてプレミアムの案内を出す）。
        case limitReached
    }

    /// 記録するもの（ホームに渡す）。
    struct Submission: Equatable {
        var records: [ReceiptRecord]
        /// 使った日時（レシートの日付と時刻。日付を直したら直した日で、時刻はレシートのまま）。
        var spentAt: Date
        /// 記録の元の文（「レシート: 店名 合計 ¥…」。OCR の全文は入れない）。
        var originalText: String
    }

    private(set) var state: State = .reading
    /// どこから取り込んだか（撮り直しで同じところをもう一度開く）。
    let source: ReceiptCaptureSource
    /// 店名（直せる）。
    var storeName = ""
    /// 日付（直せる）。時刻はレシートのものを残す。
    var day: Date
    var lines: [Line] = []
    var mode: ReceiptRecordMode = .perItem
    /// まとめて 1 件のときのカテゴリ（既定は額のいちばん多いカテゴリ）。
    var singleCategory: EntryCategory = .other
    /// レシートの合計。読めなければ nil。
    private(set) var receiptTotal: Int?
    /// 書類カメラで上限より多く撮ったとき、読み取らなかった最初のページ（5 ページ目なら 5）。読み取らなかったページが無ければ nil。
    let firstSkippedPage: Int?
    /// 合計が合わないまま記録するかの確認。
    var showsMismatchConfirmation = false
    /// 直した内容を捨てて閉じるかの確認（直した後に「閉じる」か下へのスワイプ）。
    var showsDiscardConfirmation = false
    /// 書き込めなかったときのアラート。
    var showsSaveFailure = false

    /// 時刻の元（レシートの時刻、無ければ読み取った時刻）。日付を直しても時刻はこれのまま。
    @ObservationIgnored private var baseDate: Date
    @ObservationIgnored private let calendar: Calendar
    @ObservationIgnored private let announce: @MainActor (String) -> Void
    @ObservationIgnored private let record: @MainActor (Submission) -> RecordOutcome
    @ObservationIgnored private let retakeAction: @MainActor () -> Void
    /// 読み取れたときの直せる中身（直したかを比べる元）。読み取れるまでは nil。
    @ObservationIgnored private var loaded: Editable?

    /// 直せる中身。これが読み取れたときと違えば、直したことにする。
    private struct Editable: Equatable {
        var storeName: String
        var spentAt: Date
        var lines: [Line]
        var mode: ReceiptRecordMode
        var singleCategory: EntryCategory
    }

    /// - Parameters:
    ///   - readAt: 読み取りを始めた瞬間（日付が読めなければこの日時で記録する）。
    ///   - calendar: 日付の区切り（画面の暦）。
    ///   - firstSkippedPage: 書類カメラで上限より多く撮ったとき、読み取らなかった最初のページ。
    ///   - record: 記録する（ホームが保存し、無料の回数を数える）。
    ///   - retake: 撮り直す（ホームがシートを閉じて、同じ取り込み口をもう一度開く）。
    init(
        source: ReceiptCaptureSource,
        readAt: Date,
        calendar: Calendar,
        firstSkippedPage: Int? = nil,
        announce: @escaping @MainActor (String) -> Void = { VoiceOver.announce($0) },
        record: @escaping @MainActor (Submission) -> RecordOutcome,
        retake: @escaping @MainActor () -> Void
    ) {
        self.source = source
        self.day = readAt
        self.baseDate = readAt
        self.calendar = calendar
        self.firstSkippedPage = firstSkippedPage
        self.announce = announce
        self.record = record
        self.retakeAction = retake
    }

    // MARK: - 読み取りの結果

    /// 読み取りの結果を入れる。読めなければ撮り直しの案内に、読めれば品目の行を並べる。
    func load(_ reading: ReceiptReading) {
        switch reading {
        case .unreadable(let reason):
            showUnreadable(reason)
        case .read(let scan):
            let draft = ReceiptReconciler.draftLines(for: scan)
            guard !draft.isEmpty else {
                showUnreadable(.noAmounts)
                return
            }
            storeName = ReceiptSummary.storeLabel(scan.storeName) ?? ""
            let date = scan.purchasedOn?.date(now: baseDate, calendar: calendar) ?? baseDate
            baseDate = date
            day = date
            lines = draft.map { line in
                Line(
                    kind: line.kind, name: line.name, amountText: EntryAmountInput.text(for: line.amount), category: line.category,
                    quantity: line.quantity, unitPrice: line.unitPrice, discount: line.discount,
                    isReducedTaxRate: line.isReducedTaxRate
                )
            }
            receiptTotal = scan.total
            // 品目が 1 つ（合計だけのレシートを含む）なら 1 件、2 つ以上なら品目ごとを既定にする（品目ごとに仕分けるための機能のため）。
            mode = draft.count >= 2 ? .perItem : .single
            singleCategory = ReceiptReconciler.dominantCategory(of: draft.map { ($0.amount, $0.category) })
                ?? scan.storeCategory ?? .other
            state = .ready
            loaded = editable
            // シートの中身が替わっただけでは VoiceOver に伝わらないので、読み取れた件数と照合の結果を読み上げる。
            // 読み取らなかったページがあれば、それも伝える（合計や後ろの品目が足りないことに気づけるように）。
            var spoken = String(localized: "品目を\(lines.count)件読み取りました。\(reconciliationSpoken)")
            // 照合の結果の文は句点で終わらないので、空白で区切ってから続ける（続けて読み上げないように）。
            if let skippedPagesNotice { spoken += " " + skippedPagesNotice }
            announce(spoken)
        }
    }

    /// 読み取らなかったページの知らせ。読み取らなかったページが無ければ nil。
    ///
    /// 長いレシートは合計が最後のページにあることが多く、そのページを黙って落とすと、合計が読めないまま品目の合計で記録してしまうため。
    var skippedPagesNotice: String? {
        guard let page = firstSkippedPage else { return nil }
        return String(localized: "\(page)ページ目からは読み取っていません。合計や品目が足りないときは、\(page - 1)ページまでで撮り直してください。")
    }

    private func showUnreadable(_ reason: ReceiptUnreadableReason) {
        state = .unreadable(reason)
        announce(String(localized: "レシートを読み取れませんでした"))
    }

    // MARK: - 閉じる

    /// 読み取れた後に何か直したか（店名・日付・行の品名・金額・カテゴリ・外した行・足した行・記録のしかた・まとめたときのカテゴリ）。
    /// 閉じるときに確かめるため。画像は保存しないので、閉じると撮り直すしか戻す方法が無い。
    var hasChanges: Bool {
        guard state == .ready, let loaded else { return false }
        return editable != loaded
    }

    /// シートを閉じてよいか。直した内容があれば閉じずに、捨てるかの確認を出す（false を返す）。
    func requestClose() -> Bool {
        guard hasChanges else { return true }
        showsDiscardConfirmation = true
        return false
    }

    private var editable: Editable {
        Editable(storeName: storeName, spentAt: spentAt, lines: lines, mode: mode, singleCategory: singleCategory)
    }

    // MARK: - 行の操作

    /// 行を外す・戻す。
    func setIncluded(_ isIncluded: Bool, for id: Line.ID) {
        guard let index = lines.firstIndex(where: { $0.id == id }), lines[index].isIncluded != isIncluded else { return }
        lines[index].isIncluded = isIncluded
        let name = displayName(of: lines[index])
        announce(isIncluded ? String(localized: "戻しました: \(name)") : String(localized: "外しました: \(name)"))
    }

    /// 金額の入力欄の文字を見せる形（「1,280」）にそろえる。入力欄が変わるたびに呼ぶ。
    func normalizeAmountText(for id: Line.ID) {
        guard let index = lines.firstIndex(where: { $0.id == id }) else { return }
        let formatted = EntryAmountInput.formatted(lines[index].amountText)
        if formatted != lines[index].amountText { lines[index].amountText = formatted }
    }

    /// 合計が足りないとき、差額を「税・その他」の 1 行として足す（品目の読み落としや、読めなかった税の分）。
    func addDifferenceLine() {
        guard case .mismatched(let difference) = reconciliation.status, difference > 0 else { return }
        lines.append(Line(
            kind: .taxAndOther, name: "", amountText: EntryAmountInput.text(for: difference), category: singleCategory,
            quantity: nil, unitPrice: nil, discount: 0, isReducedTaxRate: false
        ))
        announce(String(localized: "差額 \(YenFormatter.string(from: difference)) を足しました"))
    }

    // MARK: - 照合

    /// 記録する行（外していない行）。
    var includedLines: [Line] {
        lines.filter(\.isIncluded)
    }

    /// 金額を保存できない行があるか（空欄・0 円・上限を超えた額）。
    var hasInvalidAmount: Bool {
        includedLines.contains { $0.amount == nil }
    }

    /// 記録する行の合計（金額を保存できない行は数えない）。
    var linesTotal: Int {
        includedLines.compactMap(\.amount).reduce(0, +)
    }

    /// 行の合計とレシートの合計の照合。
    var reconciliation: ReceiptReconciliation {
        ReceiptReconciler.reconcile(linesTotal: linesTotal, receiptTotal: receiptTotal)
    }

    /// 記録する件数（まとめて 1 件なら 1）。
    var recordCount: Int {
        includedLines.isEmpty ? 0 : mode == .single ? 1 : includedLines.count
    }

    /// 記録できるか（行が 1 つ以上あり、どの行の金額も保存できる）。
    var canRecord: Bool {
        state == .ready && !includedLines.isEmpty && !hasInvalidAmount
    }

    /// 保存する使った日時（選んだ日で、時刻はレシートのまま）。
    var spentAt: Date {
        EntryDateEdit.date(on: day, keepingTimeOf: baseDate, calendar: calendar)
    }

    // MARK: - 記録

    /// 「記録する」。合計が合わなければ、黙って記録せずに確認を出す（`showsMismatchConfirmation`）。
    func requestRecord() {
        guard canRecord else { return }
        if case .mismatched = reconciliation.status {
            showsMismatchConfirmation = true
            return
        }
        recordNow()
    }

    /// 記録する（合計が合わないときは、確認の後で呼ぶ）。
    func recordNow() {
        guard canRecord else { return }
        let submission = makeSubmission()
        switch record(submission) {
        case .recorded, .limitReached:
            break
        case .failed:
            showsSaveFailure = true
        }
    }

    /// ホームに渡す記録。
    func makeSubmission() -> Submission {
        let recordLines = includedLines.compactMap { line in
            line.amount.map { ReceiptRecordLine(name: memoName(of: line), amount: $0, category: line.category) }
        }
        let records = ReceiptReconciler.records(
            recordLines, mode: mode, storeName: storeName, singleCategory: singleCategory
        )
        return Submission(
            records: records,
            spentAt: spentAt,
            originalText: Self.summaryText(storeName: storeName, total: records.reduce(0) { $0 + $1.amount })
        )
    }

    /// 撮り直す（シートを閉じて、同じ取り込み口をもう一度開く）。
    func retake() {
        retakeAction()
    }

    // MARK: - 文

    /// 記録の元の文。「レシート: 店名 合計 ¥…」だけにし、OCR の全文（電話番号・住所・カード番号の一部など）や品名は入れない。
    /// 店名も電話番号や長い数字を除いたもの（`ReceiptSummary.storeLabel`）。
    static func summaryText(storeName: String, total: Int) -> String {
        let yen = YenFormatter.string(from: total)
        if let store = ReceiptSummary.storeLabel(storeName) {
            return String(localized: "レシート: \(store) 合計 \(yen)")
        }
        return String(localized: "レシート: 合計 \(yen)")
    }

    /// 画面と読み上げに出す行の名前（品名が空なら「税・その他」かカテゴリ名）。
    func displayName(of line: Line) -> String {
        let name = line.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !name.isEmpty { return name }
        return line.kind == .taxAndOther ? String(localized: "税・その他") : String(localized: line.category.label)
    }

    /// 記録のメモにする名前（「税・その他」の行は、その名前をメモにする）。
    private func memoName(of line: Line) -> String {
        let name = line.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty && line.kind == .taxAndOther ? String(localized: "税・その他") : name
    }

    /// 照合の結果の読み上げ。
    var reconciliationSpoken: String {
        switch reconciliation.status {
        case .matched:
            String(localized: "合計 \(YenFormatter.string(from: linesTotal)) と合っています")
        case .mismatched(let difference):
            String(localized: "合計が合いません（差 \(YenFormatter.string(from: abs(difference)))）")
        case .totalMissing:
            String(localized: "合計を読み取れませんでした")
        }
    }
}
