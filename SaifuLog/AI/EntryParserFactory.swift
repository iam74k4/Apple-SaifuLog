import SaifuLogCore

/// いまの端末で使える解析器を選ぶ。
///
/// AI が使える端末では AI で読み、失敗したときや何も読めなかったときはルールベースで読み直す。
/// AI が使えない端末では最初からルールベースで読む。どちらでも記録はできる（AI は上乗せ）。
enum EntryParserFactory {
    /// 記録のたびに呼ぶ。AI の使える・使えないは、設定の変更やモデルのダウンロードで途中から変わるため。
    static func makeParser() -> any EntryParsing {
        let rules = RuleBasedParser()
        #if canImport(FoundationModels)
        if FoundationModelsEntryParser.isAvailable {
            return FallbackEntryParser(primary: FoundationModelsEntryParser(), fallback: rules)
        }
        #endif
        return rules
    }

    /// いまの端末で AI を使えるか（使えないときはその理由）。ようこそ（①）の案内に使う。
    /// `makeParser()` と同じ判定（`FoundationModelsEntryParser.isAvailable` は、これが `.available` のとき）。
    static var aiStatus: OnDeviceAIStatus {
        #if canImport(FoundationModels)
        FoundationModelsEntryParser.status
        #else
        .unavailable
        #endif
    }
}
