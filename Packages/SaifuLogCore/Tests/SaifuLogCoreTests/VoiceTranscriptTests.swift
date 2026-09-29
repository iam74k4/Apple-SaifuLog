import Foundation
import Testing
@testable import SaifuLogCore

/// 声の書き起こしのまとめ方（VoiceTranscript）と、自動で止める決まり（VoiceListeningLimit）。
@Suite("声の書き起こし")
struct VoiceTranscriptTests {
    typealias Segment = VoiceTranscript.Segment

    static func volatile(_ text: String, _ start: Double, _ end: Double, finalizedThrough: Double) -> Segment {
        Segment(text: text, start: start, end: end, finalizedThrough: finalizedThrough)
    }

    static func final(_ text: String, _ start: Double, _ end: Double) -> Segment {
        Segment(text: text, start: start, end: end, finalizedThrough: end)
    }

    // MARK: - 途中と確定

    @Test("途中の結果は置き換え、確定した結果で途中の文を置き換える")
    func volatileIsReplacedByFinal() {
        var transcript = VoiceTranscript()
        transcript.apply(Self.volatile("ラン", 0, 0.4, finalizedThrough: 0))
        transcript.apply(Self.volatile("ランチ 8", 0, 0.8, finalizedThrough: 0))
        #expect(transcript.finalizedText.isEmpty)
        #expect(transcript.volatileText == "ランチ 8")
        #expect(transcript.text == "ランチ 8")

        transcript.apply(Self.final("ランチ 850円", 0, 1.2))
        #expect(transcript.finalizedText == "ランチ 850円")
        #expect(transcript.volatileText.isEmpty)
        #expect(transcript.text == "ランチ 850円")
    }

    @Test("確定した文の後ろに、次の範囲の途中と確定を足していく")
    func finalsAccumulate() {
        var transcript = VoiceTranscript()
        transcript.apply(Self.final("電車代 3400円、", 0, 1.8))
        transcript.apply(Self.volatile("タクシー 19", 1.8, 2.6, finalizedThrough: 1.8))
        #expect(transcript.text == "電車代 3400円、タクシー 19")
        transcript.apply(Self.final("タクシー 1980円。", 1.8, 3.2))
        #expect(transcript.text == "電車代 3400円、タクシー 1980円")
    }

    /// 書き起こしは、途中の文が確定しても中身が変わらなければ、確定した結果を出し直さないことがある。
    @Test("確定した結果が出ないまま確定した途中の文は、次の範囲の結果が来たら確定した文へ移す")
    func volatilePromotedWhenFinalizationPassesIt() {
        var transcript = VoiceTranscript()
        transcript.apply(Self.volatile("コーヒー 1280円", 0, 2.0, finalizedThrough: 0))
        transcript.apply(Self.volatile("と", 2.5, 2.8, finalizedThrough: 2.0))
        #expect(transcript.finalizedText == "コーヒー 1280円")
        #expect(transcript.volatileText == "と")
    }

    @Test("同じ範囲を出し直した途中の文は、確定した文へ移さずに置き換える")
    func revisedVolatileIsNotPromoted() {
        var transcript = VoiceTranscript()
        transcript.apply(Self.volatile("ランチ 8", 0, 1.0, finalizedThrough: 0))
        // 確定した時刻は前の途中の文の終わりに届いたが、新しい結果が同じ範囲（0 から）を受け持つ。
        transcript.apply(Self.volatile("ランチ 850", 0, 1.4, finalizedThrough: 1.0))
        #expect(transcript.finalizedText.isEmpty)
        #expect(transcript.volatileText == "ランチ 850")
    }

    @Test("終えたら、残っている途中の文も確定したものとして残す")
    func finishPromotesVolatile() {
        var transcript = VoiceTranscript()
        transcript.apply(Self.final("ランチ", 0, 0.5))
        transcript.apply(Self.volatile(" 850円", 0.5, 1.0, finalizedThrough: 0.5))
        transcript.finish()
        #expect(transcript.finalizedText == "ランチ 850円")
        #expect(transcript.volatileText.isEmpty)
        #expect(transcript.text == "ランチ 850円")
    }

    @Test("何も聞き取れていなければ空")
    func emptyTranscript() {
        var transcript = VoiceTranscript()
        #expect(transcript.isEmpty)
        transcript.apply(Self.volatile("  ", 0, 0.5, finalizedThrough: 0))
        transcript.finish()
        #expect(transcript.isEmpty)
    }

    // MARK: - 整え方

    @Test("入力欄の 1 行に整える", arguments: [
        ("ランチ 850円", "ランチ 850円"),
        // 文の終わりの「。」は除き、途中の「、」「。」は件の区切りなので残す。
        ("電車代 3400円、タクシー 1980円。", "電車代 3400円、タクシー 1980円"),
        ("ランチ850円。コーヒー400円。", "ランチ850円。コーヒー400円"),
        // 記号の前の空白を除き、質問の印の「？」は残す。
        ("今月カフェにいくら使った ？", "今月カフェにいくら使った？"),
        ("  ランチ\n850円  ", "ランチ 850円"),
        ("ランチ\u{3000}\u{3000}850円", "ランチ 850円"),
        ("給料 50,000円 。", "給料 50,000円"),
        ("。", ""),
        ("", ""),
    ])
    func tidy(raw: String, expected: String) {
        #expect(VoiceTranscript.tidy(raw) == expected)
    }

    @Test("入力欄に打ちかけの文があれば、空白を挟んで後ろに足す")
    func draftAppends() {
        #expect(VoiceTranscript.draft(appending: "850円。", to: "ランチ") == "ランチ 850円")
        #expect(VoiceTranscript.draft(appending: "850円", to: "ランチ  ") == "ランチ 850円")
        #expect(VoiceTranscript.draft(appending: "ランチ 850円", to: "") == "ランチ 850円")
        #expect(VoiceTranscript.draft(appending: "ランチ 850円", to: "   ") == "ランチ 850円")
        // 何も聞き取れなければ、入力欄はそのまま。
        #expect(VoiceTranscript.draft(appending: " 。", to: "ランチ") == "ランチ")
    }

    // MARK: - 既存の読み取りで読めること

    /// SpeechTranscriber（日本語）が返した書き起こしの形（金額は数字・語と数字の間に空白・「、」「。」「？」付き）を、整えた後に
    /// 記録の読み取りと記録か質問かの見分けがそのまま読めること。macOS 26 の SpeechTranscriber に日本語の読み上げを聞かせて
    /// 得た文を元にしている（数字は漢数字ではなく数字で返った）。
    @Test("書き起こしの形の文を、整えた後に記録として読める", arguments: [
        ("ランチ 850円", [850]),
        ("昨日焼肉 12000円 4人で割り勘。", [3_000]),
        ("スーパーで 2480円とドラッグストアで 1200円。", [2_480, 1_200]),
        ("電車代 3400円、タクシー 1980円。", [3_400, 1_980]),
        ("コーヒー 1,280円", [1_280]),
        ("給料 50,000円。", [50_000]),
        ("一昨日本屋で 1500円", [1_500]),
        // 「、」の後ろが人数なので桁区切りにせず、割り勘の句として前の件にかける（§4-4 の「、」の決め事のまま）。
        ("焼肉 12000円、4人で割り勘", [3_000]),
        // 「円」の後ろの「、」は区切り。
        ("ランチ 850円、400円", [850, 400]),
    ])
    func transcriptsParseAsRecords(raw: String, amounts: [Int]) {
        let text = VoiceTranscript.tidy(raw)
        #expect(InputIntentClassifier.classify(text, now: Fixture.now, calendar: Fixture.calendar) == .record, "\(text)")
        #expect(Fixture.parser.entries(from: text).map(\.amount) == amounts, "\(text)")
    }

    @Test("書き起こしの日付と割り勘も、ひとこと入力と同じに読む")
    func transcriptDatesAndSplits() {
        let splitBill = Fixture.parser.entries(from: VoiceTranscript.tidy("昨日焼肉 12000円 4人で割り勘。"))
        #expect(splitBill.map(\.daysAgo) == [1])
        #expect(splitBill.map(\.splitCount) == [4])
        let dayBeforeYesterday = Fixture.parser.entries(from: VoiceTranscript.tidy("一昨日本屋で 1500円"))
        #expect(dayBeforeYesterday.map(\.daysAgo) == [2])
        let salary = Fixture.parser.entries(from: VoiceTranscript.tidy("給料 50,000円。"))
        #expect(salary.map(\.isIncome) == [true])
    }

    @Test("書き起こしの形の質問は、整えた後も質問として見分ける", arguments: [
        "今月カフェにいくら使った ？",
        "今月あと何日でいくら使える ？",
        "先月の食費は ？",
    ])
    func transcriptsClassifyAsQuestions(raw: String) {
        let text = VoiceTranscript.tidy(raw)
        #expect(InputIntentClassifier.classify(text, now: Fixture.now, calendar: Fixture.calendar) == .question, "\(text)")
    }

    // MARK: - 自動で止める

    @Test("話し終えてから 2 秒で止める")
    func stopsAfterSilence() {
        let start = Fixture.now
        let heard = start.addingTimeInterval(3)
        #expect(VoiceListeningLimit.stopReason(startedAt: start, lastHeardAt: heard, now: heard.addingTimeInterval(1.9)) == nil)
        #expect(VoiceListeningLimit.stopReason(startedAt: start, lastHeardAt: heard, now: heard.addingTimeInterval(2)) == .silence)
    }

    @Test("話し始めなければ 6 秒で止める（話し始めるまでは 2 秒では止めない）")
    func stopsWithoutSpeech() {
        let start = Fixture.now
        #expect(VoiceListeningLimit.stopReason(startedAt: start, lastHeardAt: nil, now: start.addingTimeInterval(2)) == nil)
        #expect(VoiceListeningLimit.stopReason(startedAt: start, lastHeardAt: nil, now: start.addingTimeInterval(5.9)) == nil)
        #expect(VoiceListeningLimit.stopReason(startedAt: start, lastHeardAt: nil, now: start.addingTimeInterval(6)) == .noSpeech)
    }

    @Test("話し続けていても 30 秒で止める")
    func stopsAtMaximumDuration() {
        let start = Fixture.now
        let now = start.addingTimeInterval(30)
        #expect(VoiceListeningLimit.stopReason(startedAt: start, lastHeardAt: now, now: now) == .maximumDuration)
        #expect(
            VoiceListeningLimit.stopReason(
                startedAt: start, lastHeardAt: start.addingTimeInterval(29.5), now: start.addingTimeInterval(29.9)
            ) == nil
        )
    }
}
