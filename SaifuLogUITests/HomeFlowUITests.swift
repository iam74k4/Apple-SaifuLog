import XCTest

/// ホームの会話の流れ（初回の案内・ひとこと入力・取り消す・カテゴリの聞き返し・チャットの操作・質問・直す・削除・レシート）を、
/// 画面を押して確かめる。端末内 AI は使わない（アプリの `UITestMode`）ので、読み取りはキーワード辞書のとおりになる。
final class HomeFlowUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// 初回は ① ようこそを出し、「はじめる」で記録の無いホーム（入力の例の案内）へ進む。
    @MainActor
    func testFirstRunShowsWelcomeThenEmptyHome() {
        let app = launchApp(AppLaunch(firstRun: true))

        let start = app.element(AccessibilityID.Onboarding.startButton)
        XCTAssertTrue(start.waitUntilHittable(timeout: UITestTimeout.launch))
        XCTAssertTrue(app.element(labeled: "ひとことで家計簿").exists)
        start.tap()

        XCTAssertTrue(app.element(AccessibilityID.Home.emptyTimeline).waitForExistence(timeout: UITestTimeout.ui))
        XCTAssertTrue(app.inputField.waitUntilHittable())
        XCTAssertFalse(start.exists)
    }

    /// 記録したら返事のカード（「記録しました」と行）を出し、帯の額が増える。「取り消す」で行が消え、送った文が入力欄に戻る。
    @MainActor
    func testRecordShowsReplyAndUndoRestoresText() {
        let app = launchApp()

        app.send("ランチ 850")

        XCTAssertTrue(app.element(labeled: "記録しました").waitForExistence(timeout: UITestTimeout.ui))
        let row = app.replyRow(containing: "ランチ")
        XCTAssertTrue(row.waitForExistence(timeout: UITestTimeout.ui))
        XCTAssertTrue(row.label.contains("¥850"), row.label)
        XCTAssertTrue(row.label.contains("食費"), row.label)
        XCTAssertTrue(app.monthFigures.waitForValue(containing: "¥850"))

        let undo = app.element(AccessibilityID.Reply.undoButton)
        XCTAssertTrue(undo.waitUntilHittable())
        undo.tap()

        XCTAssertTrue(row.waitForNonExistence(timeout: UITestTimeout.ui))
        XCTAssertTrue(app.inputField.waitForValue(containing: "ランチ 850"))
        XCTAssertTrue(app.monthFigures.waitForValue(containing: "¥0"))
    }

    /// 辞書に当たらない品目は「その他」で記録して、返事でカテゴリを聞き返す。選ぶと記録のカテゴリが変わる。
    /// 直前の記録はチャットの文（「それ娯楽」）でも直せる。
    @MainActor
    func testUnknownItemAsksCategoryAndChatRecategorizes() {
        let app = launchApp()

        app.send("ユニクロ 3990")
        let daily = app.element(AccessibilityID.Reply.categoryChoice("daily"))
        XCTAssertTrue(daily.waitUntilHittable())
        daily.tap()
        XCTAssertTrue(daily.waitForNonExistence(timeout: UITestTimeout.ui))
        XCTAssertTrue(app.replyRow(containing: "ユニクロ").waitForLabel(containing: "日用品"))

        app.send("ジム 8000")
        XCTAssertTrue(app.element(AccessibilityID.Reply.categoryChoice("entertainment")).waitForExistence(timeout: UITestTimeout.ui))
        app.send("それ娯楽")

        XCTAssertTrue(app.element(labeled: "娯楽にしました").waitForExistence(timeout: UITestTimeout.ui))
        XCTAssertTrue(app.replyRow(containing: "ジム").waitForLabel(containing: "娯楽"))
        // チャットの文は記録にしない（今月の額は 2 件の合計のまま）。
        XCTAssertTrue(app.monthFigures.waitForValue(containing: "¥11,990"))
    }

    /// チャットの文で、直前の記録の金額を直す・消す、月の予算を決める。どれも記録にはせず、返事の知らせを出す。
    @MainActor
    func testChatCommandsChangeAmountRemoveAndSetBudget() {
        let app = launchApp()

        app.send("ランチ 850")
        XCTAssertTrue(app.replyRow(containing: "ランチ").waitForExistence(timeout: UITestTimeout.ui))
        app.send("さっきのを900に直して")
        XCTAssertTrue(app.element(labeled: "金額を直しました").waitForExistence(timeout: UITestTimeout.ui))
        XCTAssertTrue(app.replyRow(containing: "ランチ").waitForLabel(containing: "¥900"))
        XCTAssertTrue(app.monthFigures.waitForValue(containing: "¥900"))

        app.send("コーヒー 400")
        XCTAssertTrue(app.replyRow(containing: "コーヒー").waitForExistence(timeout: UITestTimeout.ui))
        app.send("さっきの消して")
        XCTAssertTrue(app.element(labeled: "削除しました").waitForExistence(timeout: UITestTimeout.ui))
        XCTAssertTrue(app.replyRow(containing: "コーヒー").waitForNonExistence(timeout: UITestTimeout.ui))
        XCTAssertTrue(app.replyRow(containing: "ランチ").exists)

        app.send("今月の予算を5万にして")
        XCTAssertTrue(app.element(labeled: "月の予算を決めました").waitForExistence(timeout: UITestTimeout.ui))
        // 予算の文は記録にしない（今月の額は直した ¥900 のまま）。
        XCTAssertTrue(app.monthFigures.waitForValue(containing: "¥900"))
        XCTAssertTrue(app.monthFigures.waitForValue(containing: "あと ¥49,100"))
    }

    /// 質問は記録せず、答えのカード（コードが計算した額）を出す。
    @MainActor
    func testQuestionShowsAnswerCard() {
        let app = launchApp()

        app.send("ランチ 850")
        XCTAssertTrue(app.replyRow(containing: "ランチ").waitForExistence(timeout: UITestTimeout.ui))
        app.send("今月いくら?")

        let summary = app.element(AccessibilityID.Reply.answerSummary)
        XCTAssertTrue(summary.waitForExistence(timeout: UITestTimeout.ui))
        XCTAssertTrue(summary.label.contains("¥850"), summary.label)
        // 質問は記録にしない（今月の額は ¥850 のまま）。
        XCTAssertTrue(app.monthFigures.waitForValue(containing: "¥850"))
        XCTAssertFalse(app.replyRow(containing: "いくら").exists)
    }

    /// 返事の行を押すと ⑥ 直すが開き、金額を直して保存できる。長押しのメニューの「削除」と確認で記録が消える。
    @MainActor
    func testEditFromReplyRowThenDeleteWithLongPress() {
        let app = launchApp()

        app.send("ランチ 850")
        guard let row = app.replyRows(containing: "ランチ").waitForHittableElement() else {
            XCTFail("返事の行が出ません")
            return
        }
        row.tap()

        let amount = app.element(AccessibilityID.EditEntry.amountField)
        XCTAssertTrue(amount.waitUntilHittable())
        app.replaceText(in: AccessibilityID.EditEntry.amountField, with: "1200")
        let save = app.element(AccessibilityID.EditEntry.saveButton)
        XCTAssertTrue(save.waitUntilEnabled())
        save.tap()

        XCTAssertTrue(amount.waitForNonExistence(timeout: UITestTimeout.ui))
        XCTAssertTrue(app.replyRow(containing: "ランチ").waitForLabel(containing: "¥1,200"))
        XCTAssertTrue(app.monthFigures.waitForValue(containing: "¥1,200"))

        guard let edited = app.replyRows(containing: "ランチ").waitForHittableElement() else {
            XCTFail("直した記録の行が出ません")
            return
        }
        edited.press(forDuration: 1.2)
        app.tapHittableButton(labeled: "削除")
        XCTAssertTrue(app.element(labeled: "この記録を削除しますか？").waitForExistence(timeout: UITestTimeout.ui))
        app.tapHittableButton(labeled: "削除")

        XCTAssertTrue(app.replyRow(containing: "ランチ").waitForNonExistence(timeout: UITestTimeout.ui))
        XCTAssertTrue(app.monthFigures.waitForValue(containing: "¥0"))
    }

    /// レシートの読み取り結果（⑤。決まった文字を読んだもの）から記録すると、ホームにレシートの吹き出しと返事が出る。
    @MainActor
    func testReceiptResultRecordsItems() {
        let app = launchApp(AppLaunch(opensReceipt: true))

        let record = app.element(AccessibilityID.Receipt.recordButton)
        XCTAssertTrue(record.waitForExistence(timeout: UITestTimeout.launch))
        XCTAssertTrue(record.waitUntilEnabled())
        record.tap()

        XCTAssertTrue(record.waitForNonExistence(timeout: UITestTimeout.ui))
        XCTAssertTrue(app.element(labelContaining: "サイフマート").waitForExistence(timeout: UITestTimeout.ui))
        XCTAssertTrue(app.element(labelContaining: "記録しました").exists)
        XCTAssertTrue(app.monthFigures.waitForValue(containing: "¥1,766"))
    }
}
