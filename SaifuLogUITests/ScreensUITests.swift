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

        app.openSettings()

        // 月の予算（② のシート）。
        let budgetRow = app.element(AccessibilityID.Settings.budget)
        XCTAssertTrue(budgetRow.waitUntilHittable())
        XCTAssertTrue(budgetRow.waitForText(containing: "未設定"), budgetRow.label)
        budgetRow.tap()
        let budgetField = app.element(AccessibilityID.Budget.amountField)
        XCTAssertTrue(budgetField.waitUntilHittable())
        app.type("60000", into: AccessibilityID.Budget.amountField)
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
        app.type("推し活", into: AccessibilityID.Categories.nameField)
        let categorySave = app.element(AccessibilityID.Categories.saveButton)
        XCTAssertTrue(categorySave.waitUntilEnabled())
        categorySave.tap()
        XCTAssertTrue(name.waitForNonExistence(timeout: UITestTimeout.ui))
        // 作ったカテゴリは一覧の行（ボタン）で探す（作るシートの候補にも同じ名前があるが、保存するとシートは閉じる）。
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "推し活")).firstMatch.waitForExistence(timeout: UITestTimeout.ui))
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
        app.type("80000", into: AccessibilityID.Recurring.amountField)
        let memo = app.element(AccessibilityID.Recurring.memoField)
        XCTAssertTrue(memo.waitUntilHittable())
        app.type("家賃", into: AccessibilityID.Recurring.memoField)
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
            AccessibilityID.Settings.importCSV,
            AccessibilityID.Settings.help,
            AccessibilityID.Settings.privacyPolicy,
        ] {
            XCTAssertTrue(app.scrollToHittable(app.element(identifier)), "設定の行がありません: \(identifier)")
        }
    }

    /// 記録の CSV 書き出し: 期間を選ぶと書き出して共有の画面を出す（知らせは出ない）。共有の画面は閉じてみるが、閉じられたかは
    /// 確かめない（システムの別の画面で、CI では閉じられないことが続いたため）。
    @MainActor
    func testSettingsExportsCSVThroughShareSheet() {
        let app = launchApp(AppLaunch(seed: .demo))

        app.openSettings()

        let export = app.element(AccessibilityID.Settings.export)
        XCTAssertTrue(app.scrollToHittable(export))
        export.tap()
        app.tapHittableButton(labeled: "今月")

        // 共有の画面（システムのもの）が出ると、下の設定の画面はアプリの要素として読めなくなるか、書き出しの行が押せなくなる
        // （共有の画面を出している間は書き出しの行を止めている。`SettingsModel.sharedFile`）。共有の画面の中身はアプリの外の画面の
        // ことがあり（閉じるボタンがアプリの要素に出ないことがあった）、それが出たことはこの行で確かめる。
        XCTAssertTrue(Self.waitUntilCovered(export, timeout: UITestTimeout.launch), "共有の画面が出ません")
        // 覆ったのが書き出せなかった知らせ（アラート）なら、そこで失敗にする。
        let alert = app.alerts.firstMatch
        XCTAssertFalse(alert.exists, "共有の画面ではなく、知らせが出ました: \(alert.exists ? alert.label : "")")

        // 閉じる。閉じるボタンがアプリの要素にあれば押し（名前は共有の画面を出すシステムの言語で変わるので、日本語と英語の両方を
        // 探す）、無ければ、共有の画面の外（上の暗いところ）を押すか、下へ引いて閉じる。閉じきるまで、やり方を替えて試す。
        // 共有の画面の中身はアプリの外の画面で、閉じるボタンはアプリの要素に出ず、真ん中から引いても閉じなかったことがある。
        let window = app.windows.firstMatch
        let attempts: [(String, () -> Void)] = [
            ("上の暗いところを押す", {
                window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.1)).tap()
            }),
            ("上の方から下へ引く", {
                window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3))
                    .press(forDuration: 0.05, thenDragTo: window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.98)), withVelocity: .fast, thenHoldForDuration: 0)
            }),
            ("真ん中から下へ引く", {
                window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.55))
                    .press(forDuration: 0.05, thenDragTo: window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.98)), withVelocity: .fast, thenHoldForDuration: 0)
            }),
        ]
        for (name, attempt) in attempts where !export.isHittableNow {
            if let close = Self.waitForShareSheetCloseButton(in: app, timeout: 2) {
                close.tap()
            } else {
                print("共有の画面の閉じるボタンが見つからないので、\(name)")
                attempt()
            }
            _ = export.waitUntilHittable(timeout: 5)
        }
        // 閉じられたかは確かめない（ここまでで、書き出して共有の画面を出すところまでは確かめた）。共有の画面はシステムの別の画面で、
        // CI のシミュレータでは、どのやり方でも閉じないことが続いた（閉じたら書き出したファイルを消すことは `SettingsModelTests`
        // が確かめている）。閉じられなかったときは、何が出ていたかをログに残す。
        if !export.waitUntilHittable(timeout: UITestTimeout.ui) {
            print("共有の画面を閉じられませんでした（確かめない）。いまの画面:\n\(app.debugDescription)")
        }
    }

    /// 書き出しの行が、共有の画面に覆われる（要素として読めなくなるか、押せなくなる）まで待つ。覆われれば true。
    ///
    /// 行の写し（snapshot）で見る（あるかを見てから押せるかを読むと、その間に共有の画面が出て行が消えたときに、消えた要素を
    /// 読んだ失敗になるため）。
    @MainActor
    private static func waitUntilCovered(_ element: XCUIElement, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            guard let snapshot = try? element.snapshot(), snapshot.isEnabled else {
                return true
            }
            _ = element.waitForNonExistence(timeout: 0.5)
        } while Date() < deadline
        return false
    }

    /// 共有の画面の閉じるボタンが出るまで待つ。出なければ nil。
    @MainActor
    private static func waitForShareSheetCloseButton(in app: XCUIApplication, timeout: TimeInterval) -> XCUIElement? {
        let labels = ["閉じる", "Close"]
        let query = app.buttons.matching(NSPredicate(format: "label IN %@ OR identifier IN %@", argumentArray: [labels, labels]))
        return query.waitForHittableElement(timeout: timeout)
    }
}
