import Foundation
import SaifuLogCore

/// 決まり（`ChatCommandReader`）で読めなかったチャットの文が、どの操作の種類かを端末内 AI に選ばせる（docs/design.md §2 の
/// 「チャットで操作する」）。
///
/// 使うのは、記録か質問か決められない文・前の記録を直そうとする文になったときだけ（`HomeModel.submit`）。AI は種類を選ぶだけで、
/// 値（金額・カテゴリ）は文からコードが読む（`ChatCommandReader.command(kind:in:now:calendar:catalog:)`）。AI が使えない端末では作らず、
/// これまでどおり書き直しや直し方を案内する。失敗と時間切れは利用者に知らせず、`AIFallbackLog` に残す（案内を出すだけ）。
struct ChatCommandInterpreter: Sendable {
    let interpreter: any ChatCommandInterpreting
    var timeout: Duration = AITimeouts.chatCommand
    var onFallback: (@Sendable (AIFallbackReason) -> Void)? = AIFallbackLog.shared.reporter(for: .chatCommand)

    /// いまの端末で使えるもの。AI が使えなければ nil。送るたびに呼ぶ（AI の使える・使えないは途中から変わるため）。
    static func forDevice() -> ChatCommandInterpreter? {
        #if canImport(FoundationModels)
        if FoundationModelsEntryParser.isAvailable {
            return ChatCommandInterpreter(interpreter: FoundationModelsChatCommandInterpreter())
        }
        #endif
        return nil
    }

    /// 文の操作の種類。選べなければ（失敗・時間切れ）`.none`。呼び出した Task が取り消されたら投げる。
    func kind(of text: String) async throws -> ChatCommandKind {
        do {
            return try await withDeadline(timeout) { [interpreter] in
                try await interpreter.kind(of: text)
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch is DeadlineExceeded {
            onFallback?(.timedOut(timeout))
            return .none
        } catch {
            onFallback?(.failed(error))
            return .none
        }
    }
}
