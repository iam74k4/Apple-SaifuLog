import Foundation
import SaifuLogCore

/// いまの端末で使える解析器を選ぶ。
///
/// AI が使える端末では AI で読み、失敗したときや何も読めなかったときはルールベースで読み直す。
/// AI が使えない端末では最初からルールベースで読む。どちらでも記録はできる（AI は上乗せ）。
enum EntryParserFactory {
    /// 記録のたびに呼ぶ。AI の使える・使えないは、設定の変更やモデルのダウンロードで途中から変わるため。
    ///
    /// - Parameters:
    ///   - now: 送った瞬間の日時。「昨日」「9/26」はこの日時を基準に読む。保存する日時にも同じ値を使う（`HomeModel`）。
    ///     解析の中で時計を読み直すと、AI の読み取りを待つ間に日付が変わったとき、読んだ日付と保存する日付が 1 日ずれるため。
    ///   - calendar: 日付の区切りの基準（画面の暦）。保存するときと同じものを渡す。
    static func makeParser(now: Date, calendar: Calendar) -> any EntryParsing {
        let rules = RuleBasedParser(calendar: calendar, now: { now })
        #if canImport(FoundationModels)
        if FoundationModelsEntryParser.isAvailable {
            return FallbackEntryParser(primary: FoundationModelsEntryParser(calendar: calendar, now: now), fallback: rules)
        }
        #endif
        return rules
    }

    /// いまの端末で AI を使えるか（使えないときはその理由）。ようこそ（①）の案内に使う。
    /// `makeParser(now:calendar:)` と同じ判定（`FoundationModelsEntryParser.isAvailable` は、これが `.available` のとき）。
    static var aiStatus: OnDeviceAIStatus {
        #if canImport(FoundationModels)
        FoundationModelsEntryParser.status
        #else
        .unavailable
        #endif
    }
}
