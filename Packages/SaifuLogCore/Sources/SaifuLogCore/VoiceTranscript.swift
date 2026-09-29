import Foundation

/// 声の書き起こし（端末の中の SpeechTranscriber / DictationTranscriber が返す結果）を、入力欄に入れる 1 行にまとめる。
///
/// 書き起こしは、音声の範囲ごとに「途中の結果（volatile）」を何度か出し直してから「確定した結果（final）」を出す。
/// 確定した文は後ろへ足していき、途中の文は次の結果で置き換える（途中の結果を毎回足すと、同じ語が何度も並ぶため）。
///
/// 数字や句読点の読み替えはしない。SpeechTranscriber は金額を数字で返し（「ランチ 850円」）、「、」「。」「？」も付けて返すが、
/// どれも記録の読み取り（`RuleBasedParser`・`InputIntentClassifier`）がそのまま読めるため（`VoiceTranscriptTests` で確かめる）。
/// 読み違い（漢数字が混ざる・語を取り違える）は、入力欄に入れた文を利用者が直してから送る（勝手に記録しない）ことで受け止める。
public struct VoiceTranscript: Equatable, Sendable {
    /// 書き起こしの結果 1 つ。時刻は音声の頭からの秒。
    public struct Segment: Equatable, Sendable {
        public var text: String
        /// この結果が受け持つ音声の範囲の始まりと終わり。
        public var start: Double
        public var end: Double
        /// この結果を出した時点で確定した音声の時刻。ここより前の範囲の結果は、もう変わらない。
        public var finalizedThrough: Double

        public init(text: String, start: Double, end: Double, finalizedThrough: Double) {
            self.text = text
            self.start = start
            self.end = end
            self.finalizedThrough = finalizedThrough
        }

        /// 確定した結果か（後から同じ範囲の結果が出ることはない）。
        public var isFinal: Bool {
            finalizedThrough >= end
        }
    }

    /// 確定した文（書き起こしが返したまま、つないだもの）。
    public private(set) var finalizedText = ""
    /// 途中の文（次の結果で置き換わる）。
    public private(set) var volatileText = ""
    /// 途中の文が受け持つ音声の範囲の終わり。
    private var volatileEnd: Double?

    public init() {}

    /// 結果を 1 つ足す。
    public mutating func apply(_ segment: Segment) {
        // 途中の文が、その後の結果の時点で確定していたら、確定した文へ移す。書き起こしは、途中の文が確定しても中身が
        // 変わらなければ、確定した結果を出し直さないことがある（Apple の説明の resultsFinalizationTime）。移さずに次の途中の文で
        // 置き換えると、その部分が消えるため。新しい結果が同じ範囲を受け持つ（出し直しの）ときは移さない。
        if let end = volatileEnd, end <= segment.finalizedThrough, segment.start >= end {
            promoteVolatile()
        }
        if segment.isFinal {
            // 確定した結果は、同じ範囲の途中の文を置き換える。
            finalizedText += segment.text
            volatileText = ""
            volatileEnd = nil
        } else {
            volatileText = segment.text
            volatileEnd = segment.end
        }
    }

    /// 書き起こしを終えた。残っている途中の文も確定したものとして扱う。
    ///
    /// 止めた後の確定を待ちきれなかったとき（割り込み・アプリが裏に回った）も、聞き取れた分を落とさずに入力欄へ入れる。
    /// 途中の文は読み違いを含みうるが、送る前に利用者が入力欄で見て直せるので、捨てるより残す。
    public mutating func finish() {
        promoteVolatile()
    }

    private mutating func promoteVolatile() {
        finalizedText += volatileText
        volatileText = ""
        volatileEnd = nil
    }

    /// 入力欄に入れる文（確定した文と途中の文をつないで整えたもの）。
    public var text: String {
        Self.tidy(finalizedText + volatileText)
    }

    /// 何も聞き取れていないか。
    public var isEmpty: Bool {
        text.isEmpty
    }

    /// 書き起こしの文を、入力欄の 1 行として整える。
    ///
    /// - 改行・タブ・全角の空白は半角の空白にし、続く空白は 1 つにまとめる（入力欄は 1 行なので）。
    /// - 句読点と閉じ括弧の前の空白を除く（SpeechTranscriber は「使った ？」のように、語と記号の間に空白を入れて返す）。
    /// - 文の終わりの「。」を除く（一行で送る入力の例「ランチ 850」にそろえる。解析は「。」があっても読める）。
    ///   「？」は質問の印なので残す。
    public static func tidy(_ text: String) -> String {
        var result = ""
        var pendingSpace = false
        for character in text {
            if character.isWhitespace || character == "\u{3000}" {
                pendingSpace = !result.isEmpty
                continue
            }
            if pendingSpace && !closingPunctuation.contains(character) {
                result.append(" ")
            }
            pendingSpace = false
            result.append(character)
        }
        while let last = result.last, sentenceEnds.contains(last) {
            result.removeLast()
            while result.last?.isWhitespace == true { result.removeLast() }
        }
        return result
    }

    /// 前の空白を除く記号（句読点と閉じ括弧）。
    private static let closingPunctuation: Set<Character> = [
        "、", "。", "，", "．", ",", ".", "？", "?", "！", "!", "」", "』", "）", ")", "］", "]",
    ]

    /// 文の終わりから除く記号。
    private static let sentenceEnds: Set<Character> = ["。", "．"]

    /// 入力欄の文の後ろに、書き起こしの文を足す。
    ///
    /// 入力欄に打ちかけの文（「ランチ」）があれば、空白を 1 つ挟んで後ろに足す（「ランチ 850円」）。消すと打った分が無駄になり、
    /// 前に置くと語順が変わるため。書き起こしが空なら入力欄はそのまま。
    public static func draft(appending transcript: String, to existing: String) -> String {
        let addition = tidy(transcript)
        guard !addition.isEmpty else { return existing }
        var base = existing
        while base.last?.isWhitespace == true { base.removeLast() }
        guard !base.isEmpty else { return addition }
        return base + " " + addition
    }
}

/// 声の入力を自動で止める決まり（止めるボタンのほかに）。
///
/// 「聞こえた」は、書き起こしの文が変わったとき（途中の結果を含む）とする。マイクの音量で決めると、周りの音が大きい場所では
/// 話し終えても止まらず、静かな場所の小さな声では話している途中で止まるため。
public enum VoiceListeningLimit {
    /// 話し終えたとみなす、聞こえなくなってからの秒数。
    public static let silenceAfterSpeech: TimeInterval = 2
    /// 話し始めるのを待つ秒数。ボタンを押してから何を言うか考える間があるので、話し終えたときより長くする。
    public static let waitForFirstSpeech: TimeInterval = 6
    /// 1 回の長さの上限。一行の記録や質問には十分で、マイクを開いたままにしないため。
    public static let maximumDuration: TimeInterval = 30

    /// 自動で止めた理由。
    public enum StopReason: Equatable, Sendable {
        /// 話し終えた（聞こえなくなってから `silenceAfterSpeech` 秒）。
        case silence
        /// 話し始めなかった（`waitForFirstSpeech` 秒、何も聞こえない）。
        case noSpeech
        /// 上限の長さに届いた。
        case maximumDuration
    }

    /// いま止めるべきか。止めないなら nil。
    ///
    /// - Parameters:
    ///   - startedAt: 聞き始めた日時。
    ///   - lastHeardAt: 最後に書き起こしの文が変わった日時。まだ何も聞こえていなければ nil。
    ///   - now: いまの日時。
    public static func stopReason(startedAt: Date, lastHeardAt: Date?, now: Date) -> StopReason? {
        if now.timeIntervalSince(startedAt) >= maximumDuration { return .maximumDuration }
        guard let lastHeardAt else {
            return now.timeIntervalSince(startedAt) >= waitForFirstSpeech ? .noSpeech : nil
        }
        return now.timeIntervalSince(lastHeardAt) >= silenceAfterSpeech ? .silence : nil
    }
}
