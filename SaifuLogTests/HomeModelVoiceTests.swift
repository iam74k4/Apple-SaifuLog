import Foundation
import SaifuLogCore
import SwiftData
import Testing
@testable import SaifuLog

/// ホームの声の入力（HomeModel と VoiceInputModel のつなぎ）。書き起こした文は入力欄に入るだけで、送信ボタンを押したときだけ記録になる。
@MainActor
struct HomeModelVoiceTests {
    /// 声の入力（書き起こしを差し替えたもの）をつないだホーム。
    @MainActor
    final class Fixture {
        let voice = VoiceFixture()
        let home: HomeModelTests.Fixture

        init() throws {
            home = try HomeModelTests.Fixture(voice: voice.model)
        }

        var model: HomeModel { home.model }

        /// マイクのボタンを押して聞き、確定した文 `text` を書き起こして止める（入力欄へ入るまで待つ）。
        func speak(_ text: String) async throws {
            voice.transcriber.finalsOnStop = [.final(text, 0, 1)]
            await model.voice.refreshAvailability()
            await model.voice.toggle()?.value
            try #require(model.voice.phase == .listening)
            model.voice.toggle()
            try #require(await voice.eventually { model.voice.phase == .idle })
        }
    }

    @Test("書き起こした文は入力欄に入るだけで、送信を押すまで記録しない")
    func transcriptGoesIntoDraftWithoutRecording() async throws {
        let fixture = try Fixture()

        try await fixture.speak("ランチ 850円。")

        #expect(fixture.model.draft == "ランチ 850円")
        #expect(fixture.model.draftSource == .voice)
        #expect(try fixture.home.entries().isEmpty)
        #expect(!fixture.model.isParsing)
        #expect(!fixture.model.canUndo)

        await fixture.model.send(calendar: TestSupport.calendar)?.value

        let entries = try fixture.home.entries()
        #expect(entries.map(\.amount) == [850])
        #expect(entries.map(\.source) == [.voice])
        #expect(entries.map(\.originalText) == ["ランチ 850円"])
        #expect(fixture.model.draft.isEmpty)
        #expect(fixture.model.draftSource == .text)
    }

    @Test("入力欄に打ちかけの文があれば、その後ろに書き起こしを足す")
    func transcriptAppendsToDraft() async throws {
        let fixture = try Fixture()
        fixture.model.draft = "ランチ"

        try await fixture.speak("850円")

        #expect(fixture.model.draft == "ランチ 850円")
        #expect(try fixture.home.entries().isEmpty)
    }

    @Test("直して送っても、声で入れた文なら入力元は声。入力欄を空にして打ち直したら、ひとこと入力")
    func sourceFollowsDraft() async throws {
        let fixture = try Fixture()
        try await fixture.speak("ランチ 800円")
        fixture.model.draft = "ランチ 850円"
        await fixture.model.send(calendar: TestSupport.calendar)?.value

        try await fixture.speak("コーヒー 400円")
        fixture.model.draft = ""
        fixture.model.draft = "カフェ 500"
        await fixture.model.send(calendar: TestSupport.calendar)?.value

        #expect(try fixture.home.entries().map(\.source) == [.voice, .text])
    }

    @Test("声で入れた文の記録を取り消すと、文が入力欄に戻り、送り直しても入力元は声のまま")
    func undoKeepsVoiceSource() async throws {
        let fixture = try Fixture()
        try await fixture.speak("ランチ 850円")
        await fixture.model.send(calendar: TestSupport.calendar)?.value

        fixture.model.undoLastRecord()

        #expect(fixture.model.draft == "ランチ 850円")
        #expect(fixture.model.draftSource == .voice)
        await fixture.model.send(calendar: TestSupport.calendar)?.value
        #expect(try fixture.home.entries().map(\.source) == [.voice])
    }

    @Test("読み取れなかった声の文は入力欄に戻り、送り直しても入力元は声のまま")
    func unreadableTranscriptKeepsVoiceSource() async throws {
        let fixture = try Fixture()
        try await fixture.speak("ランチ")

        await fixture.model.send(calendar: TestSupport.calendar)?.value

        #expect(fixture.model.showsNoAmountAlert)
        #expect(fixture.model.draft == "ランチ")
        #expect(fixture.model.draftSource == .voice)
    }

    @Test("書き起こしで質問を入れても、送るまで答えない（送ったら答える。声の入力は回数を数えない）")
    func spokenQuestionIsAnsweredOnlyWhenSent() async throws {
        let fixture = try Fixture()

        try await fixture.speak("今月カフェにいくら使った ？")

        #expect(fixture.model.draft == "今月カフェにいくら使った？")
        #expect(fixture.model.questions.isEmpty)
        #expect(fixture.home.freeQuestionsLeft == .limited(remaining: 10, limit: 10))

        await fixture.model.send(calendar: TestSupport.calendar)?.value
        #expect(fixture.model.questions.count == 1)
        #expect(fixture.home.freeQuestionsLeft == .limited(remaining: 9, limit: 10))
    }

    @Test("声の入力の間は、体験の終わりの案内を重ねて出さない")
    func trialEndedPremiumWaitsForVoiceInput() async throws {
        let voice = VoiceFixture()
        let purchases = await TestSupport.purchases([TestSupport.trial(startedDaysAgo: 15)])
        let home = try HomeModelTests.Fixture(purchases: purchases, voice: voice.model)
        defer { home.defaults.removePersistentDomain(forName: home.suiteName) }
        try await voice.startListening()
        try #require(voice.model.isActive)

        home.model.presentPremiumIfTrialEnded()
        #expect(home.model.premiumSheet == nil)

        voice.model.stop(.background)
        home.model.presentPremiumIfTrialEnded()
        #expect(home.model.premiumSheet != nil)
    }

    @Test("マイクの許可の確認を出している間も、体験の終わりの案内を重ねて出さない")
    func trialEndedPremiumWaitsForPermissionPrompt() async throws {
        let voice = VoiceFixture(permission: .undetermined)
        let gate = Gate()
        voice.microphone.requestGate = gate
        let purchases = await TestSupport.purchases([TestSupport.trial(startedDaysAgo: 15)])
        let home = try HomeModelTests.Fixture(purchases: purchases, voice: voice.model)
        defer { home.defaults.removePersistentDomain(forName: home.suiteName) }
        await voice.model.refreshAvailability()

        let starting = voice.model.toggle()
        #expect(await voice.eventually { voice.model.phase == .requestingPermission })
        // 許可の確認を閉じて前面に戻ったとき（scenePhase が active）に呼ばれる。
        home.model.presentPremiumIfTrialEnded()
        #expect(home.model.premiumSheet == nil)

        gate.open()
        await starting?.value
        #expect(voice.model.phase == .listening)
    }

    @Test("許可の確認の間にほかの画面が出たら、許可されても聞き始めない")
    func otherScreenDuringPermissionPromptPreventsListening() async throws {
        let voice = VoiceFixture(permission: .undetermined)
        let gate = Gate()
        voice.microphone.requestGate = gate
        let home = try HomeModelTests.Fixture(voice: voice.model)
        await voice.model.refreshAvailability()

        let starting = voice.model.toggle()
        #expect(await voice.eventually { voice.model.phase == .requestingPermission })
        home.model.presentSettings()
        // 画面はほかの画面を出したときに止める（`HomeView`）が、許可の確認の間は止めるものが無い。
        voice.model.stop(.user)
        gate.open()
        await starting?.value

        #expect(voice.model.phase == .idle)
        #expect(voice.transcriber.startCalls == 0)

        // 閉じたら、押せば聞ける。
        home.model.settings = nil
        await voice.model.toggle()?.value
        #expect(voice.model.phase == .listening)
    }

    @Test("ほかの画面を出しているかを、声の入力を止める判断に使える")
    func presentingOtherScreen() throws {
        let fixture = try Fixture()
        #expect(!fixture.model.isPresentingOtherScreen)

        fixture.model.presentSettings()
        #expect(fixture.model.isPresentingOtherScreen)
        fixture.model.settings = nil
        fixture.model.showsReceiptSourceChoice = true
        #expect(fixture.model.isPresentingOtherScreen)
    }
}
