/// この端末でいま端末内の AI（Foundation Models）を使えるか。使えないときはその理由。
///
/// 解析器の選び方（`EntryParserFactory.makeParser(now:calendar:)`）は使えるかどうかだけを見るが、ようこそ（①）の案内では
/// 理由まで分ける。理由ごとに利用者にできること（設定でオンにする・準備が済むのを待つ・何もしなくてよい）が違うため。
/// どの理由でも、記録はキーワード辞書でできる。
enum OnDeviceAIStatus: Equatable, Sendable, CaseIterable {
    /// 使える。文章の読み取りを AI が行う。
    case available
    /// Apple Intelligence に対応していない機種。
    case deviceNotEligible
    /// 対応機種だが、Apple Intelligence がオフ。
    case appleIntelligenceNotEnabled
    /// モデルのダウンロード中など、準備が済んでいない。
    case modelNotReady
    /// それ以外（日本語に対応していない、OS が新しい理由を返したなど）。
    case unavailable

    var isAvailable: Bool {
        self == .available
    }
}
