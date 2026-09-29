import Foundation
import SaifuLogCore
import Testing
@testable import SaifuLog

/// 声の入力の状態の移り変わり（VoiceInputModel）。書き起こし・マイクの許可・時計を差し替えて確かめる（シミュレータではマイクの声を
/// 流せないため）。
@MainActor
struct VoiceInputModelTests {
    // MARK: - 使えるか

    @Test("調べるまではマイクのボタンを出さず、日本語の経路があれば出す")
    func availabilityIsCheckedBeforeShowingMicrophone() async {
        let fixture = VoiceFixture()
        #expect(!fixture.model.isAvailable)

        await fixture.model.refreshAvailability()

        #expect(fixture.model.isAvailable)
        #expect(fixture.model.availability?.route == .speechTranscriber)
    }

    @Test("日本語の経路が無い端末では、マイクのボタンを出さず、押しても何もしない")
    func unavailableDeviceDoesNothing() async {
        let fixture = VoiceFixture(permission: .undetermined)
        fixture.transcriber.availabilityResult = .unavailable

        await fixture.model.refreshAvailability()
        await fixture.model.toggle()?.value

        #expect(!fixture.model.isAvailable)
        #expect(fixture.model.phase == .idle)
        #expect(fixture.microphone.requestCalls == 0)
        #expect(fixture.transcriber.startCalls == 0)
    }

    @Test("経路は SpeechTranscriber を先に、日本語に対応しなければ DictationTranscriber、どちらも無ければ無し")
    func routeChoice() {
        #expect(
            VoiceRoute.choose(speechTranscriber: .installed, dictation: .installed)
                == VoiceAvailability(route: .speechTranscriber, model: .installed)
        )
        // SpeechTranscriber のモデルが入っていなくても、DictationTranscriber に替えずにダウンロードを案内する（新しいモデルを使うため）。
        #expect(
            VoiceRoute.choose(speechTranscriber: .needsDownload, dictation: .installed)
                == VoiceAvailability(route: .speechTranscriber, model: .needsDownload)
        )
        #expect(
            VoiceRoute.choose(speechTranscriber: nil, dictation: .installed)
                == VoiceAvailability(route: .dictationTranscriber, model: .installed)
        )
        #expect(VoiceRoute.choose(speechTranscriber: nil, dictation: nil) == .unavailable)
    }

    // MARK: - 待機 → 許可 → 聞く → 途中 → 確定 → 止める

    @Test("許可を求めて聞き始め、途中の文を薄く出し、確定で置き換え、止めたら入力欄へ入れて待機に戻る")
    func fullFlow() async throws {
        let fixture = VoiceFixture(permission: .undetermined)
        fixture.transcriber.finalsOnStop = [.final("ランチ 850円。", 0, 1.4)]

        try await fixture.startListening()

        #expect(fixture.microphone.requestCalls == 1)
        #expect(fixture.transcriber.startCalls == 1)
        #expect(fixture.model.phase == .listening)
        #expect(fixture.model.isActive)
        // VoiceOver の読み上げを読み終えてから聞き始める。
        #expect(fixture.waitedAnnouncements == ["声の入力を始めます"])

        fixture.transcriber.emit(.segment(.volatile("ランチ 8", 0, 0.8)))
        #expect(await fixture.eventually { fixture.model.transcript.volatileText == "ランチ 8" })
        #expect(fixture.model.preview(prefix: "") == .init(settled: "", tentative: "ランチ 8"))

        fixture.model.toggle()
        #expect(fixture.transcriber.stopCalls == 1)
        #expect(await fixture.eventually { fixture.model.phase == .idle })

        #expect(fixture.inserted == ["ランチ 850円"])
        #expect(fixture.model.transcript.isEmpty)
        #expect(!fixture.model.isActive)
        #expect(fixture.announcements.last == "声の入力を終えました。入力欄: ランチ 850円")
        #expect(fixture.transcriber.cancelCalls == 0)
    }

    @Test("聞いている間の文は、入力欄に打ちかけの文の後ろに続けて出す")
    func previewFollowsDraft() async throws {
        let fixture = VoiceFixture()
        try await fixture.startListening()

        fixture.transcriber.emit(.segment(.final("850円、", 0, 1)))
        fixture.transcriber.emit(.segment(.volatile("コーヒー", 1, 1.5, finalizedThrough: 1)))
        #expect(await fixture.eventually { fixture.model.transcript.volatileText == "コーヒー" })

        #expect(fixture.model.preview(prefix: "ランチ") == .init(settled: "ランチ 850円、", tentative: "コーヒー"))
    }

    @Test("音の大きさを出し、止めたら 0 に戻す")
    func levelUpdates() async throws {
        let fixture = VoiceFixture()
        try await fixture.startListening()

        fixture.transcriber.emit(.level(0.6))
        #expect(await fixture.eventually { fixture.model.level == 0.6 })

        fixture.model.stop(.user)
        #expect(fixture.model.level == 0)
    }

    // MARK: - 許可

    @Test("許可が無ければ、聞かずに設定を開く案内を出す（許可は求め直さない）")
    func deniedPermissionShowsGuidance() async throws {
        let fixture = VoiceFixture(permission: .denied)

        try await fixture.startListening()

        #expect(fixture.model.showsPermissionAlert)
        #expect(fixture.microphone.requestCalls == 0)
        #expect(fixture.transcriber.startCalls == 0)
        #expect(fixture.model.phase == .idle)
    }

    @Test("許可を求めて断られたら、聞かずに設定を開く案内を出す")
    func rejectedPermissionShowsGuidance() async throws {
        let fixture = VoiceFixture(permission: .undetermined, grantsOnRequest: false)

        try await fixture.startListening()

        #expect(fixture.microphone.requestCalls == 1)
        #expect(fixture.model.showsPermissionAlert)
        #expect(fixture.transcriber.startCalls == 0)
        #expect(fixture.model.phase == .idle)
    }

    // MARK: - 自動で止める

    @Test("話し終えて 2 秒たったら止め、確定を待ってから入力欄へ入れる")
    func stopsAfterSilence() async throws {
        let fixture = VoiceFixture()
        fixture.transcriber.finalsOnStop = [.final("コーヒー 400円", 0, 1.2)]
        try await fixture.startListening()

        fixture.advance(1)
        fixture.transcriber.emit(.segment(.volatile("コーヒー 400", 0, 1)))
        #expect(await fixture.eventually { !fixture.model.transcript.isEmpty })
        fixture.advance(1.9)
        fixture.model.tick()
        #expect(fixture.model.phase == .listening)

        fixture.advance(0.1)
        fixture.model.tick()

        #expect(fixture.transcriber.stopCalls == 1)
        #expect(await fixture.eventually { fixture.model.phase == .idle })
        #expect(fixture.inserted == ["コーヒー 400円"])
    }

    @Test("話し始めずに 6 秒たったら止め、入力欄には何も入れずに知らせる")
    func stopsWithoutSpeech() async throws {
        let fixture = VoiceFixture()
        try await fixture.startListening()

        fixture.advance(5.9)
        fixture.model.tick()
        #expect(fixture.model.phase == .listening)
        fixture.advance(0.1)
        fixture.model.tick()

        #expect(await fixture.eventually { fixture.model.phase == .idle })
        #expect(fixture.inserted.isEmpty)
        #expect(fixture.model.notice == .nothingHeard)
        #expect(fixture.announcements.last == VoiceInputModel.Notice.nothingHeard.message)
    }

    @Test("話し続けていても 30 秒で止める")
    func stopsAtMaximumDuration() async throws {
        let fixture = VoiceFixture()
        fixture.transcriber.finalsOnStop = []
        try await fixture.startListening()

        for second in 1...29 {
            fixture.advance(1)
            fixture.transcriber.emit(.segment(.volatile(String(repeating: "あ", count: second), 0, Double(second))))
            #expect(await fixture.eventually { fixture.model.transcript.volatileText.count == second })
            fixture.model.tick()
        }
        #expect(fixture.model.phase == .listening)

        fixture.advance(1)
        fixture.model.tick()

        #expect(fixture.transcriber.stopCalls == 1)
        #expect(await fixture.eventually { fixture.model.phase == .idle })
        // 確定が出し直されなくても、聞き取れた途中の文を入れる。
        #expect(fixture.inserted == [String(repeating: "あ", count: 29)])
    }

    @Test("止めた後に確定が返らなくても、上限の後に聞き取れた分を入れて終える")
    func finishingTimesOut() async throws {
        let fixture = VoiceFixture()
        fixture.transcriber.finalsOnStop = nil
        try await fixture.startListening()
        fixture.transcriber.emit(.segment(.volatile("ランチ 850", 0, 1)))
        #expect(await fixture.eventually { !fixture.model.transcript.isEmpty })

        fixture.model.stop(.user)
        #expect(fixture.model.phase == .finishing)
        fixture.finishingTimeoutGate.open()

        #expect(await fixture.eventually { fixture.model.phase == .idle })
        #expect(fixture.transcriber.cancelCalls == 1)
        #expect(fixture.inserted == ["ランチ 850"])
    }

    // MARK: - 割り込み・裏へ・失敗

    @Test("電話・Siri・ほかのアプリの音声で止められたら、確定を待たずに聞き取れた分を入れる")
    func interruptionEndsImmediately() async throws {
        let fixture = VoiceFixture()
        try await fixture.startListening()
        fixture.transcriber.emit(.segment(.final("ランチ", 0, 0.5)))
        fixture.transcriber.emit(.segment(.volatile(" 850円", 0.5, 1, finalizedThrough: 0.5)))

        fixture.transcriber.emit(.interrupted)

        #expect(await fixture.eventually { fixture.model.phase == .idle })
        #expect(fixture.transcriber.cancelCalls == 1)
        #expect(fixture.transcriber.stopCalls == 0)
        #expect(fixture.inserted == ["ランチ 850円"])
    }

    @Test("アプリが裏に回ったら、確定を待たずに聞き取れた分を入れて止める")
    func backgroundEndsImmediately() async throws {
        let fixture = VoiceFixture()
        try await fixture.startListening()
        fixture.transcriber.emit(.segment(.volatile("タクシー 1980", 0, 1)))
        #expect(await fixture.eventually { !fixture.model.transcript.isEmpty })

        fixture.model.stop(.background)

        #expect(fixture.model.phase == .idle)
        #expect(fixture.transcriber.cancelCalls == 1)
        #expect(fixture.inserted == ["タクシー 1980"])
    }

    @Test("確定を待っている間に裏へ回ったら、待たずに締めくくる")
    func backgroundWhileFinishing() async throws {
        let fixture = VoiceFixture()
        fixture.transcriber.finalsOnStop = nil
        try await fixture.startListening()
        fixture.transcriber.emit(.segment(.volatile("ランチ 850", 0, 1)))
        #expect(await fixture.eventually { !fixture.model.transcript.isEmpty })
        fixture.model.stop(.user)
        #expect(fixture.model.phase == .finishing)

        fixture.model.stop(.background)

        #expect(fixture.model.phase == .idle)
        #expect(fixture.inserted == ["ランチ 850"])
    }

    @Test("書き起こしが失敗しても、聞き取れた分は入れる。何も無ければ失敗を知らせる")
    func failureKeepsHeardText() async throws {
        let heard = VoiceFixture()
        try await heard.startListening()
        heard.transcriber.emit(.segment(.volatile("ランチ", 0, 1)))
        heard.transcriber.emit(.failed)
        #expect(await heard.eventually { heard.model.phase == .idle })
        #expect(heard.inserted == ["ランチ"])

        let silent = VoiceFixture()
        try await silent.startListening()
        silent.transcriber.endStream()
        #expect(await silent.eventually { silent.model.phase == .idle })
        #expect(silent.inserted.isEmpty)
        #expect(silent.model.notice == .failed)
    }

    @Test("始められなければ、待機に戻って知らせる")
    func startFailure() async throws {
        let fixture = VoiceFixture()
        fixture.transcriber.startError = .noInput

        try await fixture.startListening()

        #expect(fixture.model.phase == .idle)
        #expect(fixture.model.notice == .failed)
        #expect(fixture.announcements == [VoiceInputModel.Notice.failed.message])
    }

    @Test("始めている途中で止めたら、始め終えたところで取りやめる")
    func stopWhilePreparing() async throws {
        let fixture = VoiceFixture()
        let gate = Gate()
        fixture.announcementGate = gate
        await fixture.model.refreshAvailability()

        let starting = fixture.model.toggle()
        #expect(await fixture.eventually { fixture.model.phase == .preparing })
        fixture.model.toggle()
        #expect(fixture.model.phase == .idle)
        gate.open()
        await starting?.value

        #expect(fixture.transcriber.startCalls == 0)
        #expect(fixture.model.phase == .idle)
        #expect(fixture.inserted.isEmpty)
    }

    @Test("書き起こしを始める途中で止めたら、すぐ取りやめを頼み、戻るまでマイクのボタンを効かなくする")
    func stopWhileStartingTranscriber() async throws {
        let fixture = VoiceFixture()
        let gate = Gate()
        fixture.transcriber.startGate = gate
        await fixture.model.refreshAvailability()

        let starting = fixture.model.toggle()
        #expect(await fixture.eventually { fixture.transcriber.startsInFlight == 1 })
        #expect(fixture.model.phase == .preparing)
        fixture.model.stop(.user)

        #expect(fixture.model.phase == .idle)
        // マイクを開く前に取りやめさせる（`VoiceTranscribing.start()` の決め事）。
        #expect(fixture.transcriber.cancelCalls == 1)
        #expect(fixture.model.isStartPending)
        #expect(!fixture.model.canStart)
        // 戻るまでは押しても始めない。
        #expect(fixture.model.toggle() == nil)

        gate.open()
        await starting?.value

        #expect(fixture.transcriber.startCalls == 1)
        #expect(fixture.transcriber.cancelCalls == 1)
        #expect(fixture.model.phase == .idle)
        #expect(fixture.model.canStart)
        #expect(fixture.model.notice == nil)
        #expect(fixture.inserted.isEmpty)
    }

    @Test("取りやめに応えずに始め終えた書き起こしは、戻ったところでやめる")
    func startReturningAfterStopIsCancelled() async throws {
        let fixture = VoiceFixture()
        let gate = Gate()
        fixture.transcriber.startGate = gate
        fixture.transcriber.ignoresCancelWhileStarting = true
        await fixture.model.refreshAvailability()

        let starting = fixture.model.toggle()
        #expect(await fixture.eventually { fixture.transcriber.startsInFlight == 1 })
        fixture.model.stop(.background)
        #expect(fixture.transcriber.cancelCalls == 1)

        gate.open()
        await starting?.value

        #expect(fixture.transcriber.cancelCalls == 2)
        #expect(fixture.model.phase == .idle)
        #expect(fixture.model.canStart)
        #expect(fixture.inserted.isEmpty)
    }

    @Test("書き起こしを始める途中で止めて押し直しても、前の回を始め終えるまで次の回を始めない")
    func restartAfterStopWhileStartingDoesNotOverlap() async throws {
        let fixture = VoiceFixture()
        let gate = Gate()
        fixture.transcriber.startGate = gate
        await fixture.model.refreshAvailability()

        let first = fixture.model.toggle()
        #expect(await fixture.eventually { fixture.transcriber.startsInFlight == 1 })
        fixture.model.stop(.user)
        #expect(fixture.model.toggle() == nil)
        #expect(fixture.transcriber.startCalls == 1)

        gate.open()
        await first?.value
        try #require(fixture.model.canStart)
        await fixture.model.toggle()?.value

        #expect(fixture.transcriber.startCalls == 2)
        #expect(fixture.transcriber.maxConcurrentStarts == 1)
        #expect(fixture.model.phase == .listening)
        // 次の回は前の回に壊されずに聞ける。
        fixture.transcriber.emit(.segment(.volatile("ランチ", 0, 0.5)))
        #expect(await fixture.eventually { fixture.model.transcript.volatileText == "ランチ" })
        fixture.transcriber.finalsOnStop = [.final("ランチ 850円", 0, 1)]
        fixture.model.stop(.user)
        #expect(await fixture.eventually { fixture.model.phase == .idle })
        #expect(fixture.inserted == ["ランチ 850円"])
    }

    @Test("書き起こしを始める途中でホームの画面が片づけられても、取りやめて入力欄には入れない")
    func cancelWhileStartingTranscriber() async throws {
        let fixture = VoiceFixture()
        let gate = Gate()
        fixture.transcriber.startGate = gate
        await fixture.model.refreshAvailability()

        let starting = fixture.model.toggle()
        #expect(await fixture.eventually { fixture.transcriber.startsInFlight == 1 })
        fixture.model.cancel()
        #expect(fixture.model.phase == .idle)
        #expect(!fixture.model.canStart)

        gate.open()
        await starting?.value

        #expect(fixture.transcriber.cancelCalls == 1)
        #expect(fixture.model.phase == .idle)
        #expect(fixture.model.canStart)
        #expect(fixture.model.notice == nil)
        #expect(fixture.inserted.isEmpty)
    }

    @Test("許可の確認の間にほかの画面が出たら、許可されても聞き始めない")
    func otherScreenDuringPermissionPrompt() async throws {
        let fixture = VoiceFixture(permission: .undetermined)
        let gate = Gate()
        fixture.microphone.requestGate = gate
        var covered = false
        fixture.model.isCoveredByOtherScreen = { covered }
        await fixture.model.refreshAvailability()

        let starting = fixture.model.toggle()
        #expect(await fixture.eventually { fixture.model.phase == .requestingPermission })
        covered = true
        // 画面はほかの画面を出したときに止める（`HomeView`）が、許可の確認の間は止めるものが無い。
        fixture.model.stop(.user)
        gate.open()
        await starting?.value

        #expect(fixture.model.phase == .idle)
        #expect(fixture.transcriber.startCalls == 0)
        #expect(fixture.model.downloadConfirmation == nil)
    }

    @Test("やめたら（ホームの画面が片づけられたら）、入力欄には入れない")
    func cancelDoesNotInsert() async throws {
        let fixture = VoiceFixture()
        try await fixture.startListening()
        fixture.transcriber.emit(.segment(.volatile("ランチ 850", 0, 1)))
        #expect(await fixture.eventually { !fixture.model.transcript.isEmpty })

        fixture.model.cancel()
        await fixture.settle()

        #expect(fixture.model.phase == .idle)
        #expect(fixture.transcriber.cancelCalls == 1)
        #expect(fixture.inserted.isEmpty)
    }

    @Test("締めくくった後に届いた前の回の知らせは使わない")
    func staleEventsAreIgnored() async throws {
        let fixture = VoiceFixture()
        try await fixture.startListening()
        fixture.transcriber.emit(.segment(.volatile("タクシー", 0, 0.5)))
        #expect(await fixture.eventually { fixture.model.transcript.volatileText == "タクシー" })

        // 流した知らせをモデルが受け取る前に（間で待たずに）締めくくる。AsyncStream は、流れを終えた後も溜まった知らせを渡すので、
        // 受け取りの Task は締めくくった後にこれらを受け取る（回の番号で捨てなければ、書き起こしや表示が変わる）。
        fixture.transcriber.emit(.segment(.final("ランチ 850円", 0, 1)))
        fixture.transcriber.emit(.level(0.9))
        fixture.transcriber.emit(.failed)
        fixture.model.stop(.background)
        await fixture.settle()

        #expect(fixture.model.phase == .idle)
        #expect(fixture.model.transcript.isEmpty)
        #expect(fixture.model.level == 0)
        #expect(fixture.model.notice == nil)
        #expect(fixture.inserted == ["タクシー"])
    }

    @Test("止めてすぐ次の回を始めても、前の回の知らせと流れの終わりは次の回に効かない")
    func staleEventsDoNotAffectNextRound() async throws {
        let fixture = VoiceFixture()
        try await fixture.startListening()
        let firstRound = fixture.model.session
        fixture.model.stop(.background)
        try await fixture.startListening()
        try #require(fixture.model.phase == .listening)
        try #require(fixture.model.session != firstRound)

        // 前の回の受け取りの Task が、次の回を始めた後に動いた場面。Task の順番はテストで決められないので、受け取った知らせの
        // 扱いを前の回の番号で直接呼ぶ。
        fixture.model.eventsDidEnd(session: firstRound)
        #expect(fixture.model.phase == .listening)

        fixture.model.handle(.segment(.final("ランチ 850円", 0, 1)), session: firstRound)
        fixture.model.handle(.level(0.9), session: firstRound)
        fixture.model.handle(.interrupted, session: firstRound)
        fixture.model.handle(.failed, session: firstRound)

        #expect(fixture.model.phase == .listening)
        #expect(fixture.model.transcript.isEmpty)
        #expect(fixture.model.level == 0)
        #expect(fixture.model.notice == nil)
        #expect(fixture.inserted.isEmpty)

        // 次の回の知らせは使う。
        fixture.transcriber.emit(.segment(.volatile("コーヒー", 0, 0.5)))
        #expect(await fixture.eventually { fixture.model.transcript.volatileText == "コーヒー" })
    }

    // MARK: - モデルのダウンロード

    @Test("モデルが無ければ確かめてからダウンロードし、進みを出し、入れ終えたら知らせる（自動では聞き始めない）")
    func downloadsModelAfterConfirmation() async throws {
        let fixture = VoiceFixture()
        fixture.transcriber.availabilityResult = VoiceAvailability(route: .speechTranscriber, model: .needsDownload)

        try await fixture.startListening()

        #expect(fixture.model.downloadConfirmation == .init(onExpensiveNetwork: false))
        #expect(fixture.transcriber.installCalls == 0)

        let task = fixture.model.confirmDownload()
        // 押したらすぐ進みを出す（0 から）。
        #expect(fixture.model.phase == .downloading(progress: 0))
        await task.value

        #expect(fixture.model.downloadConfirmation == nil)
        #expect(fixture.transcriber.installCalls == 1)
        #expect(fixture.model.availability?.model == .installed)
        #expect(fixture.model.phase == .idle)
        #expect(fixture.model.notice == .modelReady)
        #expect(fixture.transcriber.startCalls == 0)
    }

    @Test("モバイル回線か低データモードなら、確認で Wi‑Fi をすすめる")
    func downloadConfirmationOnExpensiveNetwork() async throws {
        let fixture = VoiceFixture(expensiveNetwork: true)
        fixture.transcriber.availabilityResult = VoiceAvailability(route: .dictationTranscriber, model: .needsDownload)

        try await fixture.startListening()

        #expect(fixture.model.downloadConfirmation == .init(onExpensiveNetwork: true))
        fixture.model.declineDownload()
        #expect(fixture.model.downloadConfirmation == nil)
        #expect(fixture.transcriber.installCalls == 0)
    }

    @Test("許可が無ければ、モデルのダウンロードも案内しない")
    func deniedPermissionSkipsDownload() async throws {
        let fixture = VoiceFixture(permission: .denied)
        fixture.transcriber.availabilityResult = VoiceAvailability(route: .speechTranscriber, model: .needsDownload)

        try await fixture.startListening()

        #expect(fixture.model.showsPermissionAlert)
        #expect(fixture.model.downloadConfirmation == nil)
    }

    @Test("端末にもう入っている（ほかのアプリが入れた）モデルは、確かめずに枠を取って聞き始める")
    func onDeviceModelIsReservedWithoutConfirmation() async throws {
        let fixture = VoiceFixture()
        fixture.transcriber.availabilityResult = VoiceAvailability(route: .speechTranscriber, model: .needsReservation)

        try await fixture.startListening()

        #expect(fixture.model.downloadConfirmation == nil)
        #expect(fixture.transcriber.installCalls == 1)
        #expect(fixture.model.availability?.model == .installed)
        #expect(fixture.model.phase == .listening)
    }

    @Test("枠を取れなければ、ダウンロードの確認に回す")
    func failedReservationAsksToDownload() async throws {
        let fixture = VoiceFixture()
        fixture.transcriber.availabilityResult = VoiceAvailability(route: .speechTranscriber, model: .needsReservation)
        fixture.transcriber.failsInstall = true

        try await fixture.startListening()

        #expect(fixture.model.downloadConfirmation == .init(onExpensiveNetwork: false))
        #expect(fixture.model.availability?.model == .needsDownload)
        #expect(fixture.transcriber.startCalls == 0)
    }

    @Test("OS がもうダウンロードしていれば、確かめずに進みを出して待つ")
    func alreadyDownloadingSkipsConfirmation() async throws {
        let fixture = VoiceFixture()
        fixture.transcriber.availabilityResult = VoiceAvailability(route: .speechTranscriber, model: .downloading)

        try await fixture.startListening()

        #expect(fixture.model.downloadConfirmation == nil)
        #expect(fixture.transcriber.installCalls == 1)
        #expect(fixture.model.notice == .modelReady)
    }

    @Test("モデルを入れられなければ知らせる")
    func downloadFailure() async throws {
        let fixture = VoiceFixture()
        fixture.transcriber.availabilityResult = VoiceAvailability(route: .speechTranscriber, model: .needsDownload)
        fixture.transcriber.failsInstall = true
        try await fixture.startListening()

        await fixture.model.confirmDownload().value

        #expect(fixture.model.phase == .idle)
        #expect(fixture.model.notice == .downloadFailed)
        #expect(fixture.announcements.last == VoiceInputModel.Notice.downloadFailed.message)
    }

    @Test("始めるときにモデルが消えていたら、入れ直しを案内する")
    func missingModelAtStartAsksToDownload() async throws {
        let fixture = VoiceFixture()
        fixture.transcriber.startError = .modelNotInstalled

        try await fixture.startListening()

        #expect(fixture.model.phase == .idle)
        #expect(fixture.model.availability?.model == .needsDownload)
        #expect(fixture.model.downloadConfirmation == .init(onExpensiveNetwork: false))
    }
}
