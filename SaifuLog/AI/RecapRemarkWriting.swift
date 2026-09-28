import Foundation
import SaifuLogCore

/// ふりかえり（先週のふりかえりのカード・月のまとめ）に添える、端末内 AI の一言を書く。
///
/// 数字はコアが計算し、AI には計算した数字の文（`RecapFacts`）だけを渡して、励ましか気づきの一言を書かせる。一言に文に無い数字
/// があれば使わない（`RecapRemark.checked`。家計への質問の一言と同じ `AnswerSentenceCheck`）。
protocol RecapRemarkWriting: Sendable {
    /// `facts` だけを元に一言を書く。
    func remark(from facts: String) async throws -> String
}

enum RecapRemark {
    /// AI の一言を数字の文と突き合わせ、使えるなら前後の空白を除いた文を返す。空・長すぎる・文に無い数字や収支の向きを含むなら nil
    /// （画面には定型文だけを出す）。
    static func checked(_ sentence: String, facts: String) -> String? {
        let trimmed = sentence.trimmingCharacters(in: .whitespacesAndNewlines)
        return AnswerSentenceCheck.accepts(trimmed, facts: facts) ? trimmed : nil
    }
}

/// いまの端末で一言を書けるものを選ぶ。
enum RecapRemarkWriterFactory {
    /// AI が使えない端末（非対応機種・オフ・モデルの準備中）では nil（プレミアムでも定型文だけにする）。
    ///
    /// 書くたびに呼ぶ。AI の使える・使えないは、設定の変更やモデルのダウンロードで途中から変わるため（`EntryParserFactory` と同じ判定）。
    static func makeWriter() -> (any RecapRemarkWriting)? {
        #if canImport(FoundationModels)
        if FoundationModelsEntryParser.isAvailable {
            return FoundationModelsRecapRemarkWriter()
        }
        #endif
        return nil
    }
}
