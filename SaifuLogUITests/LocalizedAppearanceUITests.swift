import XCTest

/// 英語とダークの外観で、主な画面（ホーム・記録の返事・月のまとめ・設定・カレンダー）を開き、英語の見出しと、アクセシビリティの
/// 検査（要素の説明と押せる範囲。`auditAccessibility`）を確かめる。ほかの UI テストは日本語のライトで動かしているため。
final class LocalizedAppearanceUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testEnglishMainScreens() throws {
        try walkMainScreens(appearance: .light)
    }

    @MainActor
    func testEnglishDarkMainScreens() throws {
        try walkMainScreens(appearance: .dark)
    }

    @MainActor
    func testJapaneseDarkMainScreens() throws {
        try walkMainScreens(appearance: .dark, language: .japanese)
    }

    /// 外観を替えて（終わったらライトに戻す）、記録の並んだホームから主な画面を順に開き、最後に記録してカレンダーのページを出す
    /// （キーボードを出す前に横に進む画面を見る。キーボードを出している間は帯が低い形になるため）。
    @MainActor
    private func walkMainScreens(
        appearance: XCUIDevice.Appearance, language: AppLaunch.Language = .english
    ) throws {
        XCUIDevice.shared.appearance = appearance
        addTeardownBlock { @MainActor in
            XCUIDevice.shared.appearance = .light
        }
        let app = launchApp(AppLaunch(seed: .demo, language: language))
        XCTAssertTrue(app.inputField.waitUntilHittable(timeout: UITestTimeout.launch))

        // ホーム。帯の見出しが画面の言語になっている。
        XCTAssertEqual(app.monthFigures.label, language == .english ? "Spent This Month" : "今月使った額")
        try app.auditAccessibility()

        // 月のまとめ。
        app.openMonthlyReport(language: language)
        try app.auditAccessibility()
        app.goBack()
        XCTAssertTrue(app.navigationBars[language.reportTitle].waitForNonExistence(timeout: UITestTimeout.ui))

        // 設定。
        app.openSettings(language: language)
        try app.auditAccessibility()
        app.goBack()
        XCTAssertTrue(app.navigationBars[language.settingsTitle].waitForNonExistence(timeout: UITestTimeout.ui))

        // 記録すると、返事の見出しも画面の言語（入力の読み取りは日本語の文のまま）。
        app.send("ランチ 850")
        XCTAssertTrue(
            app.element(labeled: language == .english ? "Recorded" : "記録しました").waitForExistence(timeout: UITestTimeout.ui),
            "記録の返事が出ません。いまの画面:\n\(app.debugDescription)"
        )

        // カレンダーのページ（キーボードは、ページを替えると閉じる）。
        app.showCalendarPage()
        try app.auditAccessibility()
    }
}
