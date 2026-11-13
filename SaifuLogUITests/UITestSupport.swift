import XCTest

// UI テストの共通の部品。アプリは起動引数 -SaifuLogUITest で開き（アプリの `UITestMode`。DEBUG のビルドだけ）、要素は
// 名前（accessibilityIdentifier。`AccessibilityID`）で探す。待つときは決まった時間眠らず、要素の状態が変わるのを待つ。

/// UI テストで開くアプリの状態。アプリの `UITestMode` が起動引数を読む。
struct AppLaunch {
    /// 始めの記録（アプリの `UITestMode.Seed` と同じ値）。
    enum Seed: String {
        /// 記録も予算も無い。
        case empty
        /// 撮影用のデモと同じ架空の記録と予算（今月の記録が並ぶ）。
        case demo
    }

    var seed: Seed = .empty
    /// 初回の案内（① ようこそ）から始めるか。
    var firstRun = false
    /// ホームが出た後に、決まったレシートの読み取り結果（⑤）を開くか。
    var opensReceipt = false
    /// 文字の大きさ（`UIContentSizeCategory` の値。例: "UICTContentSizeCategoryAccessibilityXXXL"）。nil なら端末のまま。
    var contentSizeCategory: String?

    /// 起動引数。画面の言語と地域は日本語に決める（期待する文を日本語で書いているため。ランナーのシミュレータは英語のことが多い）。
    var arguments: [String] {
        var arguments = [
            "-SaifuLogUITest", "YES",
            "-SaifuLogUITestSeed", seed.rawValue,
            "-AppleLanguages", "(ja)",
            "-AppleLocale", "ja_JP",
        ]
        if firstRun {
            arguments += ["-SaifuLogUITestFirstRun", "YES"]
        }
        if opensReceipt {
            arguments += ["-SaifuLogUITestReceipt", "YES"]
        }
        if let contentSizeCategory {
            arguments += ["-UIPreferredContentSizeCategoryName", contentSizeCategory]
        }
        return arguments
    }
}

/// 待つ時間の上限（秒）。CI のランナーはシミュレータが遅く（アプリが落ち着くのを待つだけで数秒かかることがある）、10 秒では
/// 画面の切り替えが間に合わないことがあったので、手元よりかなり長めにする。待つのは条件が満たされるまでなので、通るときの
/// 時間は延びない。
enum UITestTimeout {
    /// 起動して最初の画面が出るまで。
    static let launch: TimeInterval = 60
    /// 送った文の返事・画面の切り替えなど。
    static let ui: TimeInterval = 20
}

/// アプリを開く。テストごとに開き直す（保存先はメモリの上なので、前のテストの記録は残らない）。
@MainActor
func launchApp(_ launch: AppLaunch = AppLaunch()) -> XCUIApplication {
    let app = XCUIApplication()
    app.launchArguments = launch.arguments
    app.launch()
    return app
}

@MainActor
extension XCUIApplication {
    /// 名前（accessibilityIdentifier）で、種類を問わずに最初の要素を探す。
    func element(_ identifier: String) -> XCUIElement {
        descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    /// 文（label）がちょうど `label` の要素（種類を問わない）。
    func element(labeled label: String) -> XCUIElement {
        descendants(matching: .any).matching(NSPredicate(format: "label == %@", label)).firstMatch
    }

    /// 文（label）に `text` を含む要素（種類を問わない）。
    func element(labelContaining text: String) -> XCUIElement {
        descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
    }

    var inputField: XCUIElement { element(AccessibilityID.Home.inputField) }
    var sendButton: XCUIElement { element(AccessibilityID.Home.sendButton) }
    var monthFigures: XCUIElement { element(AccessibilityID.Home.monthFigures) }

    /// 記録の行（返事のカードとカレンダーの選んだ日）のうち、文に `text` を含むもの。
    func replyRows(containing text: String) -> XCUIElementQuery {
        buttons.matching(identifier: AccessibilityID.Reply.row).matching(NSPredicate(format: "label CONTAINS %@", text))
    }

    func replyRow(containing text: String) -> XCUIElement {
        replyRows(containing: text).firstMatch
    }

    /// 入力欄に打って送る。
    func send(_ text: String, file: StaticString = #filePath, line: UInt = #line) {
        type(text, into: AccessibilityID.Home.inputField, file: file, line: line)
        XCTAssertTrue(
            sendButton.waitUntilEnabled(timeout: 5),
            "送信のボタンが押せません: \(text)（入力欄の値: \(String(describing: inputField.value))）", file: file, line: line
        )
        sendButton.tap()
    }

    /// 名前（identifier）の入力欄を押して、キーボードのフォーカスを入れる。その入力欄を返す。
    ///
    /// 押してもフォーカスが入らないことがある（CI で、初めてキーボードを出すときにアプリが 30 秒ほど落ち着かず、押した入力欄に
    /// フォーカスが入らないまま打って失敗した）。フォーカスが入るまで 3 回まで押し直す。`atEnd` なら入力欄の右の端を押す（押した
    /// 位置にカーソルが入るので、文の終わりから消せるように）。
    @discardableResult
    func focusField(
        _ identifier: String, atEnd: Bool = false, file: StaticString = #filePath, line: UInt = #line
    ) -> XCUIElement {
        let field = element(identifier)
        let focused = descendants(matching: .any)
            .matching(NSPredicate(format: "identifier == %@ AND hasKeyboardFocus == true", identifier))
            .firstMatch
        XCTAssertTrue(field.waitUntilHittable(timeout: UITestTimeout.launch), "入力欄が出ません: \(identifier)", file: file, line: line)
        for attempt in 1...3 {
            if atEnd {
                field.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
            } else {
                field.tap()
            }
            if focused.waitForExistence(timeout: 10) {
                // キーボードが出きる前に打つと、文字が落ちることがあった。出るまで待つ（ハードウェアキーボードの設定で出ない
                // シミュレータでは、待ちきってから打つ）。
                _ = keyboards.firstMatch.waitForExistence(timeout: 3)
                return field
            }
            print("入力欄にフォーカスが入らなかったので、押し直します（\(attempt) 回目）: \(identifier)")
        }
        XCTFail("入力欄にフォーカスが入りません: \(identifier)。いまの画面:\n\(debugDescription)", file: file, line: line)
        return field
    }

    /// 名前の入力欄を押して、文を打つ。入力欄が `shows`（省けば打った文。金額の欄は打つたびに「60,000」の形にそろえるので、
    /// その形を渡す）になったことを確かめる。
    ///
    /// CI の遅いシミュレータでは、打った文字が落ちることがあった（入力欄が出きる前の文字や、金額の欄で「60000」の 0 が 1 つ
    /// 落ちて「6,000」になった。打つたびに桁の区切りを入れて文を差し替えるので、続けて速く打つと間に合わない）。そうなったら
    /// 入力欄を空にして、1 文字ずつ（アプリが落ち着くのを待ちながら）打ち直す。3 回まで。
    func type(
        _ text: String, into identifier: String, shows expected: String? = nil, replacing: Bool = false,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        let expected = expected ?? text
        let field = element(identifier)
        for attempt in 1...3 {
            if attempt == 1 {
                if replacing {
                    clearText(in: identifier, file: file, line: line)
                } else {
                    focusField(identifier, file: file, line: line)
                    dismissKeyboardTipIfNeeded()
                }
                field.typeText(text)
            } else {
                print("入力欄が「\(expected)」になりませんでした（いまの値: \(String(describing: field.value))）。空にして 1 文字ずつ打ち直します（\(attempt) 回目）")
                clearText(in: identifier, file: file, line: line)
                for character in text {
                    field.typeText(String(character))
                }
            }
            if field.wait(until: NSPredicate(format: "value == %@", expected), timeout: 3) {
                return
            }
        }
        XCTFail(
            "入力欄が「\(expected)」になりません（いまの値: \(String(describing: field.value))）: \(identifier)", file: file, line: line
        )
    }

    /// 名前の入力欄の文を消してから打つ（`type(_:into:shows:replacing:)`）。
    func replaceText(
        in identifier: String, with text: String, shows expected: String? = nil, file: StaticString = #filePath, line: UInt = #line
    ) {
        type(text, into: identifier, shows: expected, replacing: true, file: file, line: line)
    }

    /// 名前の入力欄の文を消す。右の端を押して、文の終わりから消す。
    func clearText(in identifier: String, file: StaticString = #filePath, line: UInt = #line) {
        let field = focusField(identifier, atEnd: true, file: file, line: line)
        let current = (field.value as? String) ?? ""
        // 空の入力欄の値は案内の文（placeholder）になるので、消す数は多めでよい（空の欄で消しても何も起きない）。
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: current.count + 2))
    }

    /// 新しいシミュレータで初めてキーボードを出したときの案内（なぞって入力など）を閉じる。出ていなければ何もしない。
    /// 案内がキーボードを覆っていると、打った文字が入らないことがあるため。探すのは 1 回にする（CI では 1 回探すのに数秒かかる）。
    func dismissKeyboardTipIfNeeded() {
        let button = keyboards.buttons.matching(NSPredicate(format: "label IN %@", ["Continue", "続ける"])).firstMatch
        if button.exists, button.isHittable {
            button.tap()
        }
    }

    /// 文（label）が `label` のボタンのうち、押せるもの（画面に出ているもの）を押す。確認のダイアログのボタンなど、同じ文の
    /// ボタンが閉じかけのメニューにも残っていることがあるため、押せるものを待って選ぶ。
    func tapHittableButton(labeled label: String, timeout: TimeInterval = UITestTimeout.ui, file: StaticString = #filePath, line: UInt = #line) {
        let query = buttons.matching(NSPredicate(format: "label == %@", label))
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            for index in 0..<query.count {
                let button = query.element(boundBy: index)
                if button.exists, button.isHittable {
                    button.tap()
                    return
                }
            }
            // まだ出ていなければ、出るまで少し待つ（出ていれば待たずに返る）。
            _ = query.firstMatch.waitForExistence(timeout: 0.5)
        } while Date() < deadline
        XCTFail("押せる「\(label)」のボタンがありません", file: file, line: line)
    }

    /// 帯の右上の歯車から設定（⑧）を開く。開かなければ、いま出ている画面の要素の一覧を添えて失敗する（CI のログには
    /// 失敗の時点の画面が残らないので、何が出ていたかを追えるようにする）。
    ///
    /// CI のシミュレータでは、撮影用のデモの記録で開いたときに、歯車を押しても設定が開かないことや、月のまとめが開くことがあった
    /// （同じテストがほかの実行では通る。帯の数字と見出しは歯車と重なっておらず、原因は分かっていない。実機で確かめる）。
    /// そのときは、いまの画面をログに出し、月のまとめが開いていれば戻ってから、3 回まで押し直す。
    func openSettings(file: StaticString = #filePath, line: UInt = #line) {
        let button = element(AccessibilityID.Home.settingsButton)
        let bar = navigationBars["設定"]
        let report = navigationBars["月のまとめ"]
        XCTAssertTrue(button.waitUntilHittable(timeout: UITestTimeout.launch), "設定のボタンが押せません", file: file, line: line)
        for attempt in 1...3 {
            button.tap()
            if bar.waitForExistence(timeout: UITestTimeout.ui) {
                return
            }
            print("歯車を押しても設定が開きませんでした（\(attempt) 回目）。いまの画面:\n\(debugDescription)")
            if report.exists {
                print("月のまとめが開いたので、戻って押し直します。")
                goBack(file: file, line: line)
                _ = report.waitForNonExistence(timeout: UITestTimeout.ui)
            }
            guard button.waitUntilHittable(timeout: UITestTimeout.ui) else { break }
        }
        XCTFail("設定が開きません。いまの画面:\n\(debugDescription)", file: file, line: line)
    }

    /// ナビゲーションで一つ前の画面へ戻る。
    func goBack(file: StaticString = #filePath, line: UInt = #line) {
        let bar = navigationBars.firstMatch
        XCTAssertTrue(bar.waitForExistence(timeout: UITestTimeout.ui), "ナビゲーションバーがありません", file: file, line: line)
        let back = bar.buttons["BackButton"]
        if back.exists {
            back.tap()
        } else {
            bar.buttons.element(boundBy: 0).tap()
        }
    }

    /// 会話を左へスワイプして、カレンダーのページを出す。
    ///
    /// 画面の上の方（会話の行のあたり）をなぞる。真ん中からなぞると、キーボードを出しているときに入力欄の上から始まることがあり、
    /// 入力欄の操作（カーソルの移動）に取られうるため。
    func showCalendarPage(file: StaticString = #filePath, line: UInt = #line) {
        let spend = element(AccessibilityID.CalendarPage.monthSpend)
        for _ in 0..<3 where !spend.isHittableNow {
            let start = coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.35))
            let end = coordinate(withNormalizedOffset: CGVector(dx: 0.1, dy: 0.35))
            start.press(forDuration: 0.05, thenDragTo: end, withVelocity: .fast, thenHoldForDuration: 0)
            if spend.waitUntilHittable(timeout: 3) { return }
        }
        XCTAssertTrue(spend.isHittableNow, "カレンダーのページが出ません", file: file, line: line)
    }

    /// いま出ているリスト（設定など）を上へ送り、`element` が押せるところに出るまで送る。出なければ false。
    ///
    /// 画面の真ん中から送る（リストの要素を名前で選ぶと、ナビゲーションで奥にある前の画面のリストを選ぶことがあるため）。
    @discardableResult
    func scrollToHittable(_ element: XCUIElement, maxSwipes: Int = 10) -> Bool {
        var swipes = 0
        while !element.isHittableNow && swipes < maxSwipes {
            // ゆっくり送る（勢いで送ると、1 回で要素を通り過ぎて画面の上へ出てしまうため）。
            swipeUp(velocity: .slow)
            swipes += 1
        }
        return element.isHittableNow
    }

    /// アクセシビリティの検査（Xcode の Accessibility Inspector と同じもの）を、いま出ている画面にかける。
    ///
    /// 見るのは、要素の説明（VoiceOver が読む名前があるか）と、押せる範囲の大きさ。ほかの種類は見ない:
    /// - コントラスト: 色の組は `ThemeContrastTests` が値で確かめている。検査は画面の写しの色で測り、ガラス（Liquid Glass）の上の
    ///   文字は背景の中身で色が変わるため、同じ画面でも結果が揺れる。
    /// - Dynamic Type と文字の切れ: ホームの帯と入力欄、カレンダーの帯は、会話の場所を残すために文字の大きさに上限を設け、金額は
    ///   1 行に収めて縮める（どれも意図した形。大きな文字は `LargeTextUITests` が押せるかで確かめる）。
    /// - 要素の見つけやすさ・特性: 飾りの記号は読ませない（accessibilityHidden）作りで、検査が「見えるのに要素が無い」と数える。
    func auditAccessibility() throws {
        try performAccessibilityAudit(for: [.sufficientElementDescription, .hitRegion])
    }
}

@MainActor
extension XCUIElementQuery {
    /// いま押せる要素が 1 つでもあるか。
    var hasHittableElement: Bool {
        allElementsBoundByIndex.contains { $0.exists && $0.isHittable }
    }

    /// 押せる要素が出るまで待ち、最初のものを返す。出なければ nil。
    ///
    /// 記録の行は、会話のページとカレンダーのページ（選んだ日の記録）の両方にあり、見えていない方のページの行も要素として
    /// 残っていることがある。押すときは、いま画面に出ている方を選ぶ。
    func waitForHittableElement(timeout: TimeInterval = UITestTimeout.ui) -> XCUIElement? {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if let element = allElementsBoundByIndex.first(where: { $0.exists && $0.isHittable }) {
                return element
            }
            _ = firstMatch.waitForExistence(timeout: 0.5)
        } while Date() < deadline
        return nil
    }
}

@MainActor
extension XCUIElement {
    /// いま押せるか（あって、画面に出ている）。
    var isHittableNow: Bool {
        exists && isHittable
    }

    /// 条件（NSPredicate の書式）が満たされるまで待つ。満たされれば true。
    func wait(until predicate: NSPredicate, timeout: TimeInterval = UITestTimeout.ui) -> Bool {
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: self)
        return XCTWaiter().wait(for: [expectation], timeout: timeout) == .completed
    }

    func waitUntilHittable(timeout: TimeInterval = UITestTimeout.ui) -> Bool {
        wait(until: NSPredicate(format: "exists == true AND hittable == true"), timeout: timeout)
    }

    func waitUntilEnabled(timeout: TimeInterval = UITestTimeout.ui) -> Bool {
        wait(until: NSPredicate(format: "exists == true AND enabled == true"), timeout: timeout)
    }

    func waitUntilDisabled(timeout: TimeInterval = UITestTimeout.ui) -> Bool {
        wait(until: NSPredicate(format: "exists == true AND enabled == false"), timeout: timeout)
    }

    /// 値（accessibilityValue。入力欄なら打った文）に `text` を含むまで待つ。
    func waitForValue(containing text: String, timeout: TimeInterval = UITestTimeout.ui) -> Bool {
        wait(until: NSPredicate(format: "value CONTAINS %@", text), timeout: timeout)
    }

    /// 文（label）に `text` を含むまで待つ。
    func waitForLabel(containing text: String, timeout: TimeInterval = UITestTimeout.ui) -> Bool {
        wait(until: NSPredicate(format: "label CONTAINS %@", text), timeout: timeout)
    }

    /// 文（label）か値（value）に `text` を含むまで待つ。設定の行のように、右に出す値を名前と分けて読む要素に使う。
    func waitForText(containing text: String, timeout: TimeInterval = UITestTimeout.ui) -> Bool {
        wait(until: NSPredicate(format: "label CONTAINS %@ OR (value != nil AND value CONTAINS %@)", text, text), timeout: timeout)
    }
}
