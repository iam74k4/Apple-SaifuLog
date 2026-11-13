import XCTest

/// アクセシビリティの検査（`performAccessibilityAudit`）を主な画面にかけ、いちばん大きな文字でも主な操作に届くかを確かめる。
final class AccessibilityUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// ホーム・⑥ 直す・月のまとめ・設定・カレンダーに、アクセシビリティの検査をかける（見る種類は `auditAccessibility` の説明）。
    /// 記録が並んだ状態で見る（撮影用のデモと同じ記録）。
    @MainActor
    func testAccessibilityAuditsOnMainScreens() throws {
        let app = launchApp(AppLaunch(seed: .demo))
        XCTAssertTrue(app.inputField.waitUntilHittable(timeout: UITestTimeout.launch))

        // ホーム。
        try app.auditAccessibility()

        // ⑥ 直す（いちばん新しい記録の行から開く）。
        let rows = app.buttons.matching(identifier: AccessibilityID.Reply.row)
        XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: UITestTimeout.ui))
        guard let row = rows.allElementsBoundByIndex.last(where: { $0.isHittable }) else {
            XCTFail("押せる記録の行がありません")
            return
        }
        row.tap()
        let amount = app.element(AccessibilityID.EditEntry.amountField)
        XCTAssertTrue(amount.waitUntilHittable())
        try app.auditAccessibility()
        // 何も直していないので、確かめずに閉じる。
        app.navigationBars["記録を直す"].buttons["キャンセル"].tap()
        XCTAssertTrue(amount.waitForNonExistence(timeout: UITestTimeout.ui))

        // 月のまとめ。
        app.monthFigures.tap()
        let reportBar = app.navigationBars["月のまとめ"]
        XCTAssertTrue(reportBar.waitForExistence(timeout: UITestTimeout.ui))
        try app.auditAccessibility()
        app.goBack()
        XCTAssertTrue(reportBar.waitForNonExistence(timeout: UITestTimeout.ui))

        // 設定。
        let settingsButton = app.element(AccessibilityID.Home.settingsButton)
        XCTAssertTrue(settingsButton.waitUntilHittable())
        settingsButton.tap()
        let settingsBar = app.navigationBars["設定"]
        XCTAssertTrue(settingsBar.waitForExistence(timeout: UITestTimeout.ui))
        try app.auditAccessibility()
        app.goBack()
        XCTAssertTrue(settingsBar.waitForNonExistence(timeout: UITestTimeout.ui))

        // カレンダーのページ。
        app.showCalendarPage()
        try app.auditAccessibility()
    }
}

/// いちばん大きな文字（アクセシビリティサイズの最大）で開いても、主な操作（記録・取り消す・月のまとめ・設定）に届くか。
final class LargeTextUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testLargestTextKeepsMainActionsReachable() {
        let app = launchApp(AppLaunch(contentSizeCategory: "UICTContentSizeCategoryAccessibilityXXXL"))

        // 帯の設定と月のまとめ（キーボードを出す前。キーボードを出している間の帯は低い形になり、大きな文字では設定のボタンを
        // 出さないため。`SummaryHeader.isCompact`）。
        let settingsButton = app.element(AccessibilityID.Home.settingsButton)
        XCTAssertTrue(settingsButton.waitUntilHittable(timeout: UITestTimeout.launch))
        settingsButton.tap()
        XCTAssertTrue(app.navigationBars["設定"].waitForExistence(timeout: UITestTimeout.ui))
        XCTAssertTrue(app.element(AccessibilityID.Settings.budget).waitUntilHittable())
        app.goBack()

        XCTAssertTrue(app.monthFigures.waitUntilHittable())
        app.monthFigures.tap()
        let reportBar = app.navigationBars["月のまとめ"]
        XCTAssertTrue(reportBar.waitForExistence(timeout: UITestTimeout.ui))
        app.goBack()
        XCTAssertTrue(reportBar.waitForNonExistence(timeout: UITestTimeout.ui))

        // 記録して、返事の行と「取り消す」が出る。
        app.send("ランチ 850")
        XCTAssertTrue(app.replyRow(containing: "ランチ").waitForExistence(timeout: UITestTimeout.ui))
        XCTAssertTrue(app.element(AccessibilityID.Reply.undoButton).waitForExistence(timeout: UITestTimeout.ui))
        XCTAssertTrue(app.monthFigures.waitForValue(containing: "¥850"))
    }
}
