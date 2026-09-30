import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif
import SaifuLogCore
import Testing
@testable import SaifuLog

/// 端末内 AI の失敗の記録（`AIFallbackLog`）と、エラーをログと診断画面に出してよい形にすること（`AIErrorSummary`）。
///
/// 記録はテストごとに新しく作る（アプリの `AIFallbackLog.shared` には、ほかのテストの失敗も入るため）。
struct AIFallbackLogTests {
    /// 関連値に入力した文が入ったエラー（生成のエラーの説明に、モデルに渡した文が入る場面の代わり）。
    enum PayloadError: Error {
        case rejected(String)
    }

    /// 関連値の無いエラー。
    enum PlainError: Error {
        case unavailable
    }

    /// 入力した文と金額の代わり。ログと診断画面に出してはいけないもの。
    static let secret = "内緒の焼肉 98765"

    // MARK: - 記録

    @Test("失敗は、機能ごとの回数と最後のエラー（機能・日時）に残す")
    func recordsFailure() {
        let log = AIFallbackLog(now: { TestSupport.now })

        log.record(.failed(NSError(domain: "com.apple.UnifiedAssetFramework", code: 5000)), in: .entry)

        let snapshot = log.snapshot
        #expect(snapshot.fallbacks == [.entry: 1])
        #expect(snapshot.totalFallbacks == 1)
        #expect(snapshot.lastError == AIFallbackLog.LastError(
            feature: .entry,
            error: AIErrorSummary(type: "NSError", domain: "com.apple.UnifiedAssetFramework", code: 5000),
            date: TestSupport.now
        ))
    }

    @Test("結果が無かっただけのときは回数だけを増やし、最後のエラーは変えない")
    func recordsNoResultWithoutChangingLastError() {
        let log = AIFallbackLog(now: { TestSupport.now })
        log.record(.failed(PlainError.unavailable), in: .recap)

        log.record(.noResult, in: .question)
        log.record(.noResult, in: .question)

        let snapshot = log.snapshot
        #expect(snapshot.fallbacks == [.recap: 1, .question: 2])
        #expect(snapshot.totalFallbacks == 3)
        #expect(snapshot.lastError?.feature == .recap)
    }

    @Test("最後のエラーは、いちばん新しい失敗に替わる")
    func lastErrorIsTheNewest() {
        let log = AIFallbackLog(now: { TestSupport.now })

        log.record(.failed(PlainError.unavailable), in: .entry)
        log.record(.failed(NSError(domain: "com.apple.UnifiedAssetFramework", code: 5000)), in: .receipt)

        #expect(log.snapshot.lastError?.feature == .receipt)
        #expect(log.snapshot.lastError?.error.domain == "com.apple.UnifiedAssetFramework")
    }

    @Test("取り消しは失敗ではないので残さない")
    func ignoresCancellation() {
        let log = AIFallbackLog()

        log.record(.failed(CancellationError()), in: .entry)

        #expect(log.snapshot == AIFallbackLog.Snapshot())
    }

    @Test("機能ごとの関数は、その機能の失敗として残す")
    func reporterRecordsForItsFeature() {
        let log = AIFallbackLog()

        log.reporter(for: .question)(.noResult)
        log.reporter(for: .entry)(.failed(PlainError.unavailable))

        #expect(log.snapshot.fallbacks == [.question: 1, .entry: 1])
        #expect(log.snapshot.lastError?.feature == .entry)
    }

    // MARK: - エラーの形

    @Test("NSError は、ドメインと番号と、元のエラーのドメインと番号を持つ")
    func summarizesNSErrorWithUnderlyingError() {
        let error = NSError(domain: "com.apple.modelmanager", code: 1, userInfo: [
            NSUnderlyingErrorKey: NSError(domain: "com.apple.UnifiedAssetFramework", code: 5000),
        ])

        let summary = AIErrorSummary(error)

        #expect(summary == AIErrorSummary(
            type: "NSError", domain: "com.apple.modelmanager", code: 1,
            underlyingDomain: "com.apple.UnifiedAssetFramework", underlyingCode: 5000
        ))
        #expect(summary.description == "NSError error(com.apple.modelmanager 1) underlying(com.apple.UnifiedAssetFramework 5000)")
    }

    /// モデルの資産が無いシミュレータ（iOS 26.2）で、AI が使えると出るのに生成が返したエラーの形。元のエラーは
    /// NSUnderlyingErrorKey ではなく NSMultipleUnderlyingErrorsKey に入っていた。
    @Test("元のエラーが NSMultipleUnderlyingErrorsKey にあっても、そのドメインと番号を持つ")
    func summarizesMultipleUnderlyingErrors() {
        let error = NSError(domain: "FoundationModels.LanguageModelSession.GenerationError", code: -1, userInfo: [
            NSMultipleUnderlyingErrorsKey: [NSError(domain: "ModelManagerServices.ModelManagerError", code: 1026)],
        ])

        #expect(
            AIErrorSummary(error).description
                == "NSError error(FoundationModels.LanguageModelSession.GenerationError -1) underlying(ModelManagerServices.ModelManagerError 1026)"
        )
    }

    @Test("列挙のエラーはケースの名前まで出し、関連値は出さない")
    func summarizesEnumErrorWithoutPayload() {
        let summary = AIErrorSummary(PayloadError.rejected(Self.secret))

        #expect(summary.type == "\(String(reflecting: PayloadError.self)).rejected")
        #expect(summary.domain == String(reflecting: PayloadError.self))
        #expect(summary.code == 0)
        #expect(!summary.description.contains("内緒"))
        #expect(!summary.description.contains("98765"))
    }

    @Test("関連値の無い列挙のエラーも、ケースの名前まで出す")
    func summarizesPlainEnumError() {
        #expect(AIErrorSummary(PlainError.unavailable).type == "\(String(reflecting: PlainError.self)).unavailable")
        // モデルがツールを呼ばなかったとき（質問はキーワード辞書で答え直す）の見え方。
        #expect(AIErrorSummary(QuestionAIError.toolNotCalled).type == "SaifuLog.QuestionAIError.toolNotCalled")
    }

    @Test("エラーの説明文は持たない（入力した文や金額が入ることがあるため）")
    func summaryExcludesDescriptions() {
        let error = NSError(domain: "com.apple.modelmanager", code: 7, userInfo: [
            NSLocalizedDescriptionKey: Self.secret,
            NSLocalizedFailureReasonErrorKey: Self.secret,
            NSDebugDescriptionErrorKey: Self.secret,
        ])

        let description = AIErrorSummary(error).description

        #expect(description == "NSError error(com.apple.modelmanager 7)")
    }

    #if canImport(FoundationModels)
    /// Foundation Models の生成のエラー（関連値に説明の文を持つ列挙）は、ケースの名前まで出し、説明の文は出さない。
    @Test("生成のエラーは、型とケースの名前を出し、説明の文を出さない")
    func summarizesGenerationError() {
        let error = LanguageModelSession.GenerationError.assetsUnavailable(.init(debugDescription: Self.secret))

        let summary = AIErrorSummary(error)

        #expect(summary.type == "FoundationModels.LanguageModelSession.GenerationError.assetsUnavailable")
        #expect(!summary.description.contains("内緒"))
        #expect(!summary.description.contains("98765"))
    }
    #endif
}
