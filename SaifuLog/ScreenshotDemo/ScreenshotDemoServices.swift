#if DEBUG
import CoreGraphics
import Foundation
import SaifuLogCore

// 撮影用のデモ（`ScreenshotDemo`）で、端末や AI によって変わるものの代わりに使う決まった中身。どれも、実際のアプリが
// 出しうる中身にする（AI の一言は照合（`AnswerSentenceCheck`）を通る文、レシートは文字認識の結果として読める文字）。

/// 家計への質問の答え方。数字はキーワード辞書の読み取りとコアの計算（AI が使えない端末と同じ）で出し、AI の一言の代わりに、
/// 答えの数字をそのまま使った決まった形の一文を添える（端末内 AI が指示どおりに書いたときの形）。
struct ScreenshotDemoAnswerer: QuestionAnswering {
    /// 一言を添えるか（日本語の画面だけ。`ScreenshotDemo.showsAIRemarks`）。
    let writesRemark: Bool

    func answer(_ text: String, ledger: QuestionLedger, now: Date, calendar: Calendar) async throws -> QuestionReply {
        let reply = try await RuleBasedQuestionAnswerer().answer(text, ledger: ledger, now: now, calendar: calendar)
        guard writesRemark, case .answered(let answer, _) = reply,
              let sentence = Self.remark(for: answer),
              // 本物の AI の一言と同じ照合を通す（通らない文は、実際のアプリでも出ないため）。
              AnswerSentenceCheck.accepts(sentence, facts: LedgerAnswerFacts.text(for: answer, calendar: calendar))
        else { return reply }
        return .answered(answer, remark: .ai(sentence))
    }

    /// 答えに添える一文。決まった形にできない答えは nil（一言を添えない）。
    static func remark(for answer: LedgerAnswer) -> String? {
        let yen = YenFormatter.string(from:)
        switch answer.value {
        case .amount(let amount):
            let subject = answer.question.category.map { "\($0.displayName)の支出" } ?? "支出"
            return "\(LedgerAnswerFacts.periodName(answer.period))の\(subject)は\(yen(amount))です。"
        case .dailyAllowance(let status) where !status.isOver:
            return "月末まで、1日あたり\(yen(status.dailyAllowance))使えます。"
        default:
            return nil
        }
    }
}

/// ふりかえり（先週のふりかえり・月のまとめ）の AI の一言の代わり。数字の文（`RecapFacts`）から、支出のいちばん多いカテゴリを
/// 読んで、数字を書かない励ましの一文にする（端末内 AI への指示「励ましか気づきを一文か二文で」に沿う形）。
struct ScreenshotDemoRemarkWriter: RecapRemarkWriting {
    func remark(from facts: String) async throws -> String {
        Self.remark(from: facts)
    }

    static func remark(from facts: String) -> String {
        guard let top = topCategory(in: facts) else { return "記録を続けられていて、いい調子です。" }
        if facts.hasPrefix("期間: 先週") {
            return "先週いちばん多かったのは\(top)でした。こまめに記録できていて、いい調子です。"
        }
        if facts.hasPrefix("期間: 今月") {
            return "今月は\(top)がいちばん多くなっています。記録を続けられていて、いい調子です。"
        }
        return "この月は\(top)がいちばん多くなりました。記録を続けられていて、いい調子です。"
    }

    /// 「支出の多いカテゴリ: 食費 ¥6,000（49%）、…」の最初のカテゴリの名前。
    static func topCategory(in facts: String) -> String? {
        let label = "支出の多いカテゴリ: "
        guard let line = facts.split(separator: "\n").first(where: { $0.hasPrefix(label) }) else { return nil }
        return line.dropFirst(label.count).split(separator: " ").first.map(String.init)
    }
}

/// レシートの読み取りの画面で使う、文字認識の結果の代わり。架空の店（実在の店名・住所・電話番号は書かない）の内税のレシート。
enum ScreenshotDemoReceipt {
    /// 店名。架空の名前にする（実在の店と取り違えられないように）。
    static let storeName = "サイフマート 中央店"
    /// レシートの合計（品目の合計と同じ）。
    static let total = 1_766

    /// 文字認識の結果の行（デモの「いま」の日付と 18:32 の時刻を入れる）。軽減税率の品目には「※」を付ける。
    static func lines(now: Date, calendar: Calendar) -> [ReceiptTextLine] {
        // レシートは西暦で印字されるので、端末の暦（和暦など）によらず西暦の年月日で書く（時間帯は端末の暦のまま）。
        var gregorian = Calendar(identifier: .gregorian)
        gregorian.timeZone = calendar.timeZone
        let parts = gregorian.dateComponents([.year, .month, .day, .weekday], from: now)
        let weekdays = ["日", "月", "火", "水", "木", "金", "土"]
        let weekday = weekdays[((parts.weekday ?? 1) - 1) % weekdays.count]
        let date = String(format: "%04d年%02d月%02d日(%@) 18:32", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0, weekday)
        return [
            storeName,
            date,
            "※牛乳 ￥198",
            "※食パン ￥158",
            "※カット野菜 ￥128",
            "※卵 10個入 ￥258",
            "※鶏むね肉 ￥398",
            "洗剤 ￥328",
            "ティッシュ ￥298",
            "小計 ￥1,766",
            "(8%対象 ￥1,140 内税 ￥84)",
            "(10%対象 ￥626 内税 ￥56)",
            "合計 ￥1,766",
            "お預り ￥2,000",
            "お釣り ￥234",
        ].map { ReceiptTextLine($0) }
    }

    /// 読み取りに渡す画像（中身は使わない。読み取りは画像が無いと始まらないため、1 画素の白い画像を渡す）。
    static func image() -> ReceiptImage {
        let context = CGContext(
            data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        )
        context?.setFillColor(red: 1, green: 1, blue: 1, alpha: 1)
        context?.fill(CGRect(x: 0, y: 0, width: 1, height: 1))
        guard let cgImage = context?.makeImage() else {
            preconditionFailure("1 画素の画像を作れませんでした")
        }
        return ReceiptImage(cgImage: cgImage)
    }
}

/// 声の書き起こしの代わり。聞き始めると、確定した文（「ドラッグストア」）と途中の文（「1280円」）を流し、止めるまで聞いている
/// 表示のままにする（シミュレータではマイクの声を流せず、書き起こしのモデルも無いため）。
@MainActor
final class ScreenshotDemoTranscriber: VoiceTranscribing {
    private var continuation: AsyncStream<VoiceEvent>.Continuation?

    func availability() async -> VoiceAvailability {
        VoiceAvailability(route: .speechTranscriber, model: .installed)
    }

    func installModel(progress: @escaping @MainActor (Double) -> Void) async throws {}

    func start() async throws -> AsyncStream<VoiceEvent> {
        let (stream, continuation) = AsyncStream.makeStream(of: VoiceEvent.self)
        self.continuation = continuation
        continuation.yield(.level(0.6))
        continuation.yield(.segment(.init(text: "ドラッグストア", start: 0, end: 1.2, finalizedThrough: 1.2)))
        continuation.yield(.segment(.init(text: "1280円", start: 1.2, end: 2.0, finalizedThrough: 1.2)))
        return stream
    }

    func stop() {
        finish()
    }

    func cancel() {
        finish()
    }

    private func finish() {
        continuation?.finish()
        continuation = nil
    }
}

/// マイクの許可（デモでは許可済み。iOS の確認を出さない）。
struct ScreenshotDemoMicrophone: MicrophoneAuthorizing {
    var permission: MicrophonePermission { .granted }

    func requestPermission() async -> Bool {
        true
    }
}

/// 回線の種類（デモではモデルをダウンロードしないので使わない）。
struct ScreenshotDemoNetwork: NetworkCostChecking {
    func isExpensive() async -> Bool {
        false
    }
}
#endif
