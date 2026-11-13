import XCTest

/// ホームから行く画面（カレンダーのページ・月のまとめ・設定とその先の一覧とシート・書き出し）を、画面を押して確かめる。
final class ScreensUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// 会話を左へスワイプするとカレンダーのページが出て、月に使った額と、選んだ日の記録が見える。会話のボタンで戻れる。
    @MainActor
    func testCalendarPageShowsMonthSpendAndDayRecords() {
        let app = launchApp()

        app.send("ランチ 850")
        XCTAssertTrue(app.replyRow(containing: "ランチ").waitForExistence(timeout: UITestTimeout.ui))

        app.showCalendarPage()
        let spend = app.element(AccessibilityID.CalendarPage.monthSpend)
        XCTAssertTrue(spend.waitForLabel(containing: "¥850"))

        // UI テストの「いま」は 15 日（`UITestMode`）。記録の無い 14 日を選ぶと記録は無く、15 日を選ぶと記録の行が出る。
        let day14 = app.element(AccessibilityID.CalendarPage.day(14))
        XCTAssertTrue(day14.waitUntilHittable())
        day14.tap()
        let noRecords = app.element(labeled: "この日の記録はありません")
        XCTAssertTrue(noRecords.waitForExistence(timeout: UITestTimeout.ui))
        app.element(AccessibilityID.CalendarPage.day(15)).tap()
        XCTAssertTrue(noRecords.waitForNonExistence(timeout: UITestTimeout.ui))
        // 選んだ日の記録はカレンダーの下に出る。画面の下の端にかかっていれば、少し送る。会話のページの同じ行も残っていることが
        // あるので、押せる行があるかで見る。
        let rows = app.replyRows(containing: "ランチ")
        if !rows.hasHittableElement {
            app.swipeUp(velocity: .slow)
        }
        XCTAssertTrue(rows.hasHittableElement, "選んだ日の記録の行が出ません")

        app.element(AccessibilityID.CalendarPage.conversationButton).tap()
        XCTAssertTrue(app.inputField.waitUntilHittable())
        XCTAssertFalse(spend.isHittableNow)
    }

    /// 帯の数字から月のまとめへ進み、戻るでホームに戻る。
    @MainActor
    func testMonthlyReportOpensFromBandAndGoesBack() {
        let app = launchApp(AppLaunch(seed: .demo))

        let figures = app.monthFigures
        XCTAssertTrue(figures.waitUntilHittable(timeout: UITestTimeout.launch))
        figures.tap()

        let bar = app.navigationBars["月のまとめ"]
        XCTAssertTrue(bar.waitForExistence(timeout: UITestTimeout.ui))
        app.goBack()
        XCTAssertTrue(bar.waitForNonExistence(timeout: UITestTimeout.ui))
        XCTAssertTrue(app.inputField.waitUntilHittable())
    }

    /// 設定の行がそろい、月の予算を決める・カテゴリを作る・くり返しの記録を足すができる。
    ///
    /// 「iCloud で同期」と「ロック」は行があることだけを見る（押すと、シミュレータでは iCloud のアカウントの確かめや認証に進めないため）。
    /// ヘルプとプライバシーポリシーも行があることだけを見る（押すと Safari に移るため）。
    @MainActor
    func testSettingsRowsBudgetCategoryAndRecurring() {
        let app = launchApp()

        let settingsButton = app.element(AccessibilityID.Home.settingsButton)
        XCTAssertTrue(settingsButton.waitUntilHittable(timeout: UITestTimeout.launch))
        settingsButton.tap()
        XCTAssertTrue(app.navigationBars["設定"].waitForExistence(timeout: UITestTimeout.ui))

        // 月の予算（② のシート）。
        let budgetRow = app.element(AccessibilityID.Settings.budget)
        XCTAssertTrue(budgetRow.waitUntilHittable())
        XCTAssertTrue(budgetRow.waitForText(containing: "未設定"), budgetRow.label)
        budgetRow.tap()
        let budgetField = app.element(AccessibilityID.Budget.amountField)
        XCTAssertTrue(budgetField.waitUntilHittable())
        budgetField.tap()
        budgetField.typeText("60000")
        let budgetSave = app.element(AccessibilityID.Budget.saveButton)
        XCTAssertTrue(budgetSave.waitUntilEnabled())
        budgetSave.tap()
        XCTAssertTrue(budgetField.waitForNonExistence(timeout: UITestTimeout.ui))
        XCTAssertTrue(budgetRow.waitForText(containing: "¥60,000"), budgetRow.label)

        // カテゴリを作る。
        let categoriesRow = app.element(AccessibilityID.Settings.categories)
        XCTAssertTrue(categoriesRow.waitUntilHittable())
        categoriesRow.tap()
        let create = app.element(AccessibilityID.Categories.createButton)
        XCTAssertTrue(app.scrollToHittable(create))
        create.tap()
        let name = app.element(AccessibilityID.Categories.nameField)
        XCTAssertTrue(name.waitUntilHittable())
        name.tap()
        name.typeText("衣服")
        let categorySave = app.element(AccessibilityID.Categories.saveButton)
        XCTAssertTrue(categorySave.waitUntilEnabled())
        categorySave.tap()
        XCTAssertTrue(name.waitForNonExistence(timeout: UITestTimeout.ui))
        // 一覧の注記にも「衣服」の語があるので、行（ボタン）で探す。
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "衣服")).firstMatch.waitForExistence(timeout: UITestTimeout.ui))
        app.goBack()
        XCTAssertTrue(app.navigationBars["設定"].waitForExistence(timeout: UITestTimeout.ui))

        // くり返しの記録を足す。
        let recurringRow = app.element(AccessibilityID.Settings.recurring)
        XCTAssertTrue(recurringRow.waitUntilHittable())
        recurringRow.tap()
        let add = app.element(AccessibilityID.Recurring.addButton)
        XCTAssertTrue(add.waitUntilHittable())
        add.tap()
        let amount = app.element(AccessibilityID.Recurring.amountField)
        XCTAssertTrue(amount.waitUntilHittable())
        amount.tap()
        amount.typeText("80000")
        let memo = app.element(AccessibilityID.Recurring.memoField)
        XCTAssertTrue(memo.waitUntilHittable())
        memo.tap()
        memo.typeText("家賃")
        let recurringSave = app.element(AccessibilityID.Recurring.saveButton)
        XCTAssertTrue(recurringSave.waitUntilEnabled())
        recurringSave.tap()
        XCTAssertTrue(amount.waitForNonExistence(timeout: UITestTimeout.ui))
        // 一覧の案内にも「家賃」の語があるので、行（ボタン）で探す。
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "家賃")).firstMatch.waitForExistence(timeout: UITestTimeout.ui))
        app.goBack()
        XCTAssertTrue(app.navigationBars["設定"].waitForExistence(timeout: UITestTimeout.ui))

        // 残りの行（上から順に送って探す）。
        for identifier in [
            AccessibilityID.Settings.iCloudSync,
            AccessibilityID.Settings.appLock,
            AccessibilityID.Settings.export,
            AccessibilityID.Settings.help,
            AccessibilityID.Settings.privacyPolicy,
        ] {
            XCTAssertTrue(app.scrollToHittable(app.element(identifier)), "設定の行がありません: \(identifier)")
        }
    }

    /// 記録の CSV 書き出し: 期間を選ぶと共有の画面が出て、閉じると設定に戻る（書き出したファイルは閉じたら消す）。
    @MainActor
    func testSettingsExportsCSVThroughShareSheet() {
        let app = launchApp(AppLaunch(seed: .demo))

        let settingsButton = app.element(AccessibilityID.Home.settingsButton)
        XCTAssertTrue(settingsButton.waitUntilHittable(timeout: UITestTimeout.launch))
        settingsButton.tap()
        XCTAssertTrue(app.navigationBars["設定"].waitForExistence(timeout: UITestTimeout.ui))

        let export = app.element(AccessibilityID.Settings.export)
        XCTAssertTrue(app.scrollToHittable(export))
        export.tap()
        app.tapHittableButton(labeled: "今月")

        // 共有の画面（システムのもの）が出たら閉じる。閉じるボタンの名前は、共有の画面を出すシステムの言語で変わるので、
        // 日本語と英語の両方を探す。見つからなければ、書き出しの行が押せなくなった（共有の画面を出している。`SettingsModel.sharedFile`）
        // ことを確かめてから、下へ引いて閉じる。
        if let close = Self.waitForShareSheetCloseButton(in: app, timeout: UITestTimeout.launch) {
            close.tap()
        } else {
            XCTAssertTrue(export.waitUntilDisabled(timeout: 3), "共有の画面が出ません")
            let window = app.windows.firstMatch
            window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.55))
                .press(forDuration: 0.1, thenDragTo: window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.98)))
        }
        // 閉じると設定に戻り、書き出しの行をまた押せる（書き出したファイルは消してある）。
        XCTAssertTrue(export.waitUntilHittable(timeout: UITestTimeout.launch), "共有の画面が閉じません")
        XCTAssertTrue(export.waitUntilEnabled())
    }

    /// 共有の画面の閉じるボタンが出るまで待つ。出なければ nil。
    @MainActor
    private static func waitForShareSheetCloseButton(in app: XCUIApplication, timeout: TimeInterval) -> XCUIElement? {
        let labels = ["閉じる", "Close"]
        let query = app.buttons.matching(NSPredicate(format: "label IN %@ OR identifier IN %@", argumentArray: [labels, labels]))
        return query.waitForHittableElement(timeout: timeout)
    }
}
