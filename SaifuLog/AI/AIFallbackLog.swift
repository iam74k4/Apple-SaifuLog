import Foundation
import OSLog
import SaifuLogCore
import Synchronization

/// 端末内 AI を使う機能。ログと診断画面に、どの機能で AI の結果を使わなかったかを出す（値は訳さない）。
enum AIFeature: String, CaseIterable, Sendable {
    /// ひとこと入力の読み取り（`FoundationModelsEntryParser`）。
    case entry
    /// 家計への質問（`FoundationModelsQuestionAnswerer`）。
    case question
    /// 先週のふりかえりと月のまとめの一言（`FoundationModelsRecapRemarkWriter`）。
    case recap
    /// レシートの品名とカテゴリの整え（`FoundationModelsReceiptItemRefiner`）。
    case receipt
    /// 辞書で決まらなかった品目のカテゴリの聞き直し（`FoundationModelsCategoryClassifier`）。
    case category
}

/// 端末内 AI の失敗と時間切れ、AI の結果を使わなかった回数を残す（os.Logger と、起動してからのメモリの上の記録）。
///
/// AI が失敗しても、上限の時間（`AITimeouts`）までに返らなくても、利用者にはキーワード辞書の結果（ふりかえりは定型文だけ）を見せ、
/// 失敗は知らせない（docs/design.md §4-2）。
/// そのままでは「AI が使えると出るのに、生成が毎回失敗している端末」と「AI の使えない端末」を見分けられないので、開発者と
/// 所有者が Console.app（サブシステム com.iam74k4.SaifuLog・カテゴリ ai）と診断画面で確かめられるようにする。
///
/// 残すのはエラーの型・ドメイン・番号だけで、入力した文・金額・AI の返した文・エラーの説明文は残さない（`AIErrorSummary`）。
/// 記録はメモリの上だけで、アプリを終えると消える（家計のほかに端末へ書き残すものを増やさない）。記録を読むのは診断画面
/// （DEBUG と社内テスト用のビルド）だけだが、ログはどのビルドでも書く（App Store から入れた端末の Console.app でも見られるように）。
final class AIFallbackLog: Sendable {
    /// アプリで 1 つ。解析器や答え方は使うたびに作り直すので、記録はここに集める。
    static let shared = AIFallbackLog()

    /// ほかのログ（家計の共有の household）と同じサブシステムにし、カテゴリで分ける。
    static let logger = Logger(subsystem: "com.iam74k4.SaifuLog", category: "ai")

    /// 起動してからの記録。
    struct Snapshot: Equatable, Sendable {
        /// 機能ごとの、AI の結果を使わなかった回数（失敗・時間切れ・結果が無かったときのすべて）。
        var fallbacks: [AIFeature: Int] = [:]
        /// 機能ごとの、AI が上限の時間までに返らなかった回数（`fallbacks` にも数える）。上限の見直し（docs/design.md §15）に使う。
        var timeouts: [AIFeature: Int] = [:]
        /// 最後の失敗。まだ失敗していなければ nil（結果が無かっただけのときと、時間切れのときは変えない。時間切れは `timeouts` で分かる）。
        var lastError: LastError?

        var totalFallbacks: Int {
            fallbacks.values.reduce(0, +)
        }

        var totalTimeouts: Int {
            timeouts.values.reduce(0, +)
        }
    }

    struct LastError: Equatable, Sendable {
        var feature: AIFeature
        var error: AIErrorSummary
        /// 失敗した日時。ほかのログや操作と突き合わせるのに使う。
        var date: Date
    }

    private let state = Mutex(Snapshot())
    private let now: @Sendable () -> Date

    /// - Parameter now: 失敗した日時を読む時計。テストで決まった日時を渡す。
    init(now: @escaping @Sendable () -> Date = { .now }) {
        self.now = now
    }

    var snapshot: Snapshot {
        state.withLock { $0 }
    }

    /// AI の結果を使わなかったことを残す。取り消し（画面を閉じたなど）は失敗ではないので残さない。
    func record(_ reason: AIFallbackReason, in feature: AIFeature) {
        switch reason {
        case .failed(let error):
            if error is CancellationError { return }
            let summary = AIErrorSummary(error)
            let date = now()
            state.withLock { snapshot in
                snapshot.fallbacks[feature, default: 0] += 1
                snapshot.lastError = LastError(feature: feature, error: summary, date: date)
            }
            Self.logger.error(
                "端末内 AI が失敗したので、AI の結果を使いません: \(feature.rawValue, privacy: .public) \(summary.description, privacy: .public)"
            )
        case .timedOut(let timeout):
            state.withLock { snapshot in
                snapshot.fallbacks[feature, default: 0] += 1
                snapshot.timeouts[feature, default: 0] += 1
            }
            Self.logger.error(
                "端末内 AI が上限の時間（\(String(describing: timeout), privacy: .public)）までに返らなかったので、AI の結果を使いません: \(feature.rawValue, privacy: .public)"
            )
        case .noResult:
            state.withLock { $0.fallbacks[feature, default: 0] += 1 }
            Self.logger.notice("端末内 AI が使える結果を返さなかったので、AI の結果を使いません: \(feature.rawValue, privacy: .public)")
        }
    }

    /// `feature` の失敗を残す関数（`FallbackEntryParser` などの `onFallback` に渡す）。
    func reporter(for feature: AIFeature) -> @Sendable (AIFallbackReason) -> Void {
        { [self] reason in record(reason, in: feature) }
    }
}

/// エラーを、ログと診断画面に出してよい形にしたもの（型・ドメイン・番号と、元のエラーのドメインと番号）。
///
/// 説明文（localizedDescription・debugDescription）と列挙の関連値は持たない。生成のエラーの説明には、モデルに渡した文
/// （入力した文や金額）が入ることがあるため。
struct AIErrorSummary: Equatable, Sendable {
    /// エラーの型。列挙ならケースの名前まで（例: FoundationModels.LanguageModelSession.GenerationError.assetsUnavailable）。
    /// NSError に包まれて届いたものは NSError（型はドメインで分かる）。
    var type: String
    var domain: String
    var code: Int
    /// 元のエラー（NSUnderlyingErrorKey か NSMultipleUnderlyingErrorsKey の最初）のドメインと番号。原因はこちらにしか出ないことが
    /// ある（モデルの資産が無いシミュレータの iOS 26.2 では、GenerationError の -1 の元が ModelManagerServices.ModelManagerError の 1026）。
    var underlyingDomain: String?
    var underlyingCode: Int?

    init(type: String, domain: String, code: Int, underlyingDomain: String? = nil, underlyingCode: Int? = nil) {
        self.type = type
        self.domain = domain
        self.code = code
        self.underlyingDomain = underlyingDomain
        self.underlyingCode = underlyingCode
    }

    init(_ error: any Error) {
        let nsError = error as NSError
        let underlying = nsError.underlyingErrors.first.map { $0 as NSError }
        self.init(
            type: Self.typeName(of: error), domain: nsError.domain, code: nsError.code,
            underlyingDomain: underlying?.domain, underlyingCode: underlying?.code
        )
    }

    /// 1 行の形。例: `NSError error(FoundationModels.LanguageModelSession.GenerationError -1) underlying(ModelManagerServices.ModelManagerError 1026)`。
    /// 番号の書き方（`error(ドメイン 番号)`）は診断画面のほかの行（保護クラス・iCloud のアカウント）と同じにする。
    var description: String {
        var text = "\(type) error(\(domain) \(code))"
        if let underlyingDomain, let underlyingCode {
            text += " underlying(\(underlyingDomain) \(underlyingCode))"
        }
        return text
    }

    /// エラーの型の名前。Objective-C の NSError は型の名前に意味が無い（ドメインで分かる）ので NSError とだけ書く。
    static func typeName(of error: any Error) -> String {
        let metatype = Swift.type(of: error)
        if metatype is NSError.Type { return "NSError" }
        var name = String(reflecting: metatype)
        // 列挙のエラーは、番号より SDK の定義と見比べやすいケースの名前を足す。関連値は読まない（説明の文が入っていることがあるため）。
        let mirror = Mirror(reflecting: error)
        if mirror.displayStyle == .enum {
            // 関連値のあるケースは、Mirror の子の名前がケースの名前。関連値の無いケースは値を持たない（入力した文が入りようがない）
            // ので、説明の文（既定ではケースの名前）を使う。
            name += ".\(mirror.children.first?.label ?? String(describing: error))"
        }
        return name
    }
}
