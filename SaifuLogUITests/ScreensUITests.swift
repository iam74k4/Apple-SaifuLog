import XCTest

/// ホームから行く画面（月の画面の内訳とカレンダー・設定とその先の一覧とシート・書き出し）を、画面を押して確かめる。
final class ScreensUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// 帯の数字から月の画面へ進み、切り替えでカレンダーにすると、選んだ日の記録が見える。
    @MainActor
    func testMonthCalendarShowsDayRecords() {
        let app = launchApp()

        app.send("ランチ 850")
        XCTAssertTrue(app.replyRow(containing: "ランチ").waitForExistence(timeout: UITestTimeout.ui))

        app.openMonthlyReport()
        app.showMonthCalendar()

        // UI テストの「いま」は 15 日（`UITestMode`）。記録の無い 14 日を選ぶと記録は無く、15 日を選ぶと記録の行が出る。
        let day14 = app.element(AccessibilityID.CalendarPage.day(14))
        XCTAssertTrue(day14.waitUntilHittable())
        day14.tap()
        let noRecords = app.element(labeled: "この日の記録はありません")
        XCTAssertTrue(noRecords.waitForExistence(timeout: UITestTimeout.ui))
        app.element(AccessibilityID.CalendarPage.day(15)).tap()
        XCTAssertTrue(noRecords.waitForNonExistence(timeout: UITestTimeout.ui))
        // 選んだ日の記録はカレンダーの下に出る。画面の下の端にかかっていれば、少し送る。
        let rows = app.replyRows(containing: "ランチ")
        if !rows.hasHittableElement {
            app.swipeUp(velocity: .slow)
        }
        XCTAssertTrue(rows.hasHittableElement, "選んだ日の記録の行が出ません")

        app.goBack()
        XCTAssertTrue(app.inputField.waitUntilHittable())
    }

    /// 帯の数字から月のまとめへ進み、戻るでホームに戻る。
    @MainActor
    func testMonthlyReportOpensFromBandAndGoesBack() {
        let app = launchApp(AppLaunch(seed: .demo))

        app.openMonthlyReport()

        let bar = app.navigationBars["月のまとめ"]
        app.goBack()
        XCTAssertTrue(bar.waitForNonExistence(timeout: UITestTimeout.ui))
        XCTAssertTrue(app.inputField.waitUntilHittable())
    }

    /// 月の画面の下のバーで前の月へ戻ると「今月」が出て、押すと今月に戻る（今月を見ている間は出さない）。
    @MainActor
    func testMonthlyReportSwitchesMonthsFromBottomBar() {
        let app = launchApp(AppLaunch(seed: .demo))

        app.openMonthlyReport()
        let title = app.element(AccessibilityID.Report.monthTitle)
        XCTAssertTrue(title.waitForExistence(timeout: UITestTimeout.ui))
        let currentTitle = title.label
        let thisMonth = app.element(AccessibilityID.Report.thisMonth)
        XCTAssertFalse(thisMonth.exists)
        let previous = app.element(AccessibilityID.Report.previousMonth)
        XCTAssertTrue(previous.waitUntilHittable())
        previous.tap()

        XCTAssertTrue(
            title.waitForLabel(notEqualTo: currentTitle), "前の月へ移りません。いまの画面:\n\(app.debugDescription)"
        )
        // 「今月」は下のバーのガラスの中にあり、手では押せるのに、XCUITest は上に重なる中身の層を見て押せないと判定することがある。
        // あることを確かめて、ボタンの真ん中を押す。
        XCTAssertTrue(thisMonth.waitForExistence(timeout: UITestTimeout.ui), "「今月」が出ません。いまの画面:\n\(app.debugDescription)")
        thisMonth.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertTrue(thisMonth.waitForNonExistence(timeout: UITestTimeout.ui))
        XCTAssertEqual(title.label, currentTitle)
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

    /// カード: 設定の「カード」でカードを登録し、「カードで」と書いて送った記録が、いつものカード（最初の 1 枚）の今の締めの
    /// 利用額に入る。カードの引き落としを書いた文は、記録する前に確かめる（「記録しない」なら記録しない）。
    @MainActor
    func testCardsRegisterAndCountCardRecords() {
        let app = launchApp()

        app.openSettings()
        let cardsRow = app.element(AccessibilityID.Settings.cards)
        XCTAssertTrue(app.scrollToHittable(cardsRow))
        cardsRow.tap()
        let add = app.element(AccessibilityID.Cards.addButton)
        XCTAssertTrue(add.waitUntilHittable())
        add.tap()
        let name = app.element(AccessibilityID.Cards.nameField)
        XCTAssertTrue(name.waitUntilHittable())
        app.type("楽天カード", into: AccessibilityID.Cards.nameField)
        let save = app.element(AccessibilityID.Cards.saveButton)
        XCTAssertTrue(save.waitUntilEnabled())
        save.tap()
        XCTAssertTrue(name.waitForNonExistence(timeout: UITestTimeout.ui))
        let row = app.element(AccessibilityID.Cards.row)
        XCTAssertTrue(row.waitForExistence(timeout: UITestTimeout.ui))
        XCTAssertTrue(row.label.contains("楽天カード"), row.label)
        app.goBack()
        app.goBack()

        app.send("ランチ 850 カードで")
        let reply = app.replyRow(containing: "ランチ")
        XCTAssertTrue(reply.waitForExistence(timeout: UITestTimeout.ui))

        // カードの引き落としは、記録する前に確かめる。
        app.send("クレカ引き落とし 50000")
        let skip = app.alerts.buttons["記録しない"]
        XCTAssertTrue(skip.waitForExistence(timeout: UITestTimeout.ui))
        skip.tap()
        XCTAssertTrue(app.element(labeled: "引き落としは記録していません").waitForExistence(timeout: UITestTimeout.ui))
        XCTAssertTrue(app.monthFigures.waitForValue(containing: "¥850"))

        app.openSettings()
        XCTAssertTrue(app.scrollToHittable(cardsRow))
        cardsRow.tap()
        XCTAssertTrue(row.waitForText(containing: "¥850"), row.label)
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
