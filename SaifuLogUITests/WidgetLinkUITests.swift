import XCTest

/// ウィジェットを押したとき（アプリを URL「saifulog://record」で開いたとき）に、会話の入力欄にフォーカスが入ってキーボードが出る。
/// 横に進んだ画面（設定）を出していたら閉じて会話に戻す（Siri の頼みと同じ受け箱。アプリの `WidgetLink`・`QuickActionInbox`）。
final class WidgetLinkUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    static let recordLink = URL(string: "saifulog://record")!

    @MainActor
    func testWidgetLinkOpensEntryField() {
        let app = launchApp()
        XCTAssertTrue(app.inputField.waitUntilHittable(timeout: UITestTimeout.launch))
        XCTAssertFalse(app.focusedInputField.exists, "開いた直後から入力欄にフォーカスがあります")

        app.openURL(Self.recordLink)

        XCTAssertTrue(
            app.focusedInputField.waitForExistence(timeout: UITestTimeout.ui),
            "URL で開いても入力欄にフォーカスが入りません。いまの画面:\n\(app.debugDescription)"
        )
    }

    @MainActor
    func testWidgetLinkClosesSettingsAndOpensEntryField() {
        let app = launchApp()
        app.openSettings()

        app.openURL(Self.recordLink)

        XCTAssertTrue(app.navigationBars["設定"].waitForNonExistence(timeout: UITestTimeout.ui), "設定が閉じません")
        XCTAssertTrue(
            app.focusedInputField.waitForExistence(timeout: UITestTimeout.ui),
            "設定から URL で開いても入力欄にフォーカスが入りません。いまの画面:\n\(app.debugDescription)"
        )
    }

    /// ほかの形の URL では何もしない（入力欄を開かない）。
    @MainActor
    func testOtherLinkDoesNothing() {
        let app = launchApp()
        XCTAssertTrue(app.inputField.waitUntilHittable(timeout: UITestTimeout.launch))

        app.openURL(URL(string: "saifulog://delete")!)

        XCTAssertTrue(app.inputField.waitUntilHittable())
        XCTAssertFalse(app.focusedInputField.waitForExistence(timeout: 3), "ほかの URL で入力欄が開きました")
    }
}
