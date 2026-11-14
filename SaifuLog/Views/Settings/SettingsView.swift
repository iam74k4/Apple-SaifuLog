import SaifuLogCore
import SwiftUI
import UniformTypeIdentifiers

/// ⑧ 設定。必要なときだけ開く画面。ホームの帯の右上の歯車から横に進む。
///
/// 月の予算（② のシートを開く）、カテゴリ（覚えたカテゴリはその中）、くり返しの記録、iCloud で同期（既定はオフ）、
/// アプリのロック、記録の CSV 書き出し、このアプリについて（ヘルプ・プライバシーポリシー・版）を並べる。週の始まりは
/// 選ばせない（端末の設定のまま）。
///
/// 状態と操作は `SettingsModel` が持つ。ここは表示と、共有のシート・アラートの出し入れだけ。
/// 押せる行の名前は墨にし、操作のボタン（「CSV ファイルを書き出す」）だけ、ほかの画面のボタンと同じ tint（AccentColor。
/// §7 のとおり、墨か白の文字）にする。どの行にも頭の印（`SettingsRowIcon`）を付け、行を目で探しやすくする。塗りの主ボタンは
/// 置かない。
struct SettingsView: View {
    @Bindable var model: SettingsModel

    /// 画面の暦。書き出す期間を、ホームの今月と同じ月で区切るのに使う。
    @Environment(\.calendar) private var calendar
    /// アプリのロック（アプリで 1 つ。`SaifuLogApp` が渡す）。無ければ（プレビュー）ロックの節を出さない。
    @Environment(AppLock.self) private var appLock: AppLock?

    var body: some View {
        List {
            budgetSection
            learningSection
            recurringSection
            if model.showsICloudSync {
                iCloudSection
            }
            if let appLock {
                lockSection(appLock)
            }
            exportSection
            importSection
            aboutSection
        }
        // リストの地は画面の背景にし、行は面の色にする（ほかの画面と同じ地にそろえる）。
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .navigationTitle("設定")
        .navigationBarTitleDisplayMode(.inline)
        // ホームはナビゲーションバーを隠しているので、ここでは戻るボタンのために出す。
        .toolbar(.visible, for: .navigationBar)
        // ② はホームの帯から開くときと同じシートにする（用が済めば閉じる一時的な画面なので、横に進めない）。
        .sheet(item: $model.budgetSetup, onDismiss: { model.reloadBudget() }) { budgetSetup in
            BudgetSetupSheet(model: budgetSetup)
        }
        .alert(
            alertTitle,
            isPresented: showsExportAlert,
            presenting: model.exportAlert
        ) { _ in
            Button("OK", role: .cancel) {}
        } message: { alert in
            alertMessage(alert)
        }
        // iCloud 同期を切り替える前の説明。切り替えると記録を開き直す（この画面も作り直される）ので、何が起きるかを先に伝える。
        .alert(
            iCloudConfirmationTitle,
            isPresented: showsICloudConfirmation,
            presenting: model.iCloudSyncConfirmation
        ) { change in
            Button(role: change == .disable ? .destructive : nil) {
                model.confirmICloudSync(change)
            } label: {
                switch change {
                case .enable: Text("オンにする")
                case .disable: Text("オフにする")
                }
            }
            Button("キャンセル", role: .cancel) {}
        } message: { change in
            switch change {
            case .enable:
                Text("記録と予算を、あなたの iCloud（Apple）に保存し、同じ Apple アカウントでサインインしている端末どうしでそろえます。いまこの iPhone にある記録も iCloud に上がります。開発者は中身を見られません。\n\n記録と予算の中身は、この iPhone の中で暗号化してから iCloud に保存します。Apple の「高度なデータ保護」をオンにしていれば、エンドツーエンドで暗号化され、鍵はあなたの信頼できるデバイスだけが持ちます。オフのときは、鍵を Apple が管理する標準の暗号化です。\n\n切り替えると記録を開き直します。オフに戻しても、この iPhone の記録は残ります。")
            case .disable:
                Text("この iPhone の記録は残り、これからはこの iPhone の中だけに保存します。iCloud に保存した記録は iCloud に残り、ほかの端末とはそろわなくなります。\n\n切り替えると記録を開き直します。")
            }
        }
        // 切り替えようとしたら設定を書けなかった（切り替わっていない）。
        .alert("設定を保存できませんでした", isPresented: $model.showsICloudSyncSaveFailure) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("「iCloud で同期」は切り替わっていません。もう一度お試しください。")
        }
        // オンにしようとしたら iCloud を使えなかった。何をすればよいかを案内する（同期はオフのまま）。
        .alert(
            "iCloud を使えません",
            isPresented: showsICloudAccountAlert,
            presenting: model.iCloudAccountAlert
        ) { _ in
            Button("OK", role: .cancel) {}
        } message: { status in
            Text(verbatim: status.guidanceText ?? "")
        }
        // CSV から読み込むファイルを選ぶ。選べるのは CSV と、拡張子が .txt などになった文字のファイル（保存し直すと変わることが
        // あるため）。中身がこのアプリの書き出しの形かは、読んでから確かめる（`LedgerCSVReader`）。
        .fileImporter(isPresented: $model.showsImporter, allowedContentTypes: [.commaSeparatedText, .plainText]) { result in
            model.importFile(result, calendar: calendar)
        }
        // 読み込む前に、入れる件数と飛ばす件数を見てもらう（思っていたファイルと違ったときに、記録を黙って増やさないため）。
        .alert(
            importConfirmationTitle,
            isPresented: showsImportConfirmation,
            presenting: model.importPreview
        ) { preview in
            Button("読み込む") { model.confirmImport(preview) }
            Button("キャンセル", role: .cancel) { model.cancelImport() }
        } message: { preview in
            importConfirmationMessage(preview)
        }
        .alert(
            importAlertTitle,
            isPresented: showsImportAlert,
            presenting: model.importAlert
        ) { _ in
            Button("OK", role: .cancel) {}
        } message: { alert in
            importAlertMessage(alert)
        }
        // 書き出したファイルを共有のシートで渡し、閉じたらファイルを消す。
        .background(
            ShareSheetPresenter(
                fileURL: model.sharedFile?.url,
                onFinish: { sheetWasShown in model.finishSharing(sheetWasShown: sheetWasShown) }
            )
                .accessibilityHidden(true)
        )
        // 途中の書き出しとアカウントの確かめは、設定を閉じたときにやめる（`SettingsModel.close`。ここの onDisappear では
        // やめない。設定から「カテゴリ」などへ進んだだけでも呼ばれるため）。
        // 同期がオンのとき、iCloud をいまも使えるかを確かめる（使えなければ節の中に案内を出す）。
        .task { await model.refreshICloudAccountStatus() }
        // Face ID の登録やパスコードは設定の App で変わるので、開くたびに読み直す（描き直すたびには調べない）。
        .onAppear { appLock?.refreshMethod() }
        // iCloud で届いたほかの端末の変更（予算を変えた・カテゴリを作った・覚えたなど）で、月の予算と、この画面から進む一覧
        // （カテゴリ・覚えたカテゴリ・くり返しの記録）を読み直す。進んだ先の画面では読み直さない（設定の画面は進んだ先の下に
        // 残っていて、ここでも受け取るので、二度読むことになるため）。
        .onReceive(StoreChanges.remote) { _ in
            model.reloadBudget()
            model.categoryList.reload()
            model.recurringList.reload()
            model.learnedCategories.reload()
        }
    }

    // MARK: - 予算

    private var budgetSection: some View {
        Section {
            Button {
                model.presentBudgetSetup()
            } label: {
                LabeledContent {
                    budgetValue
                        .foregroundStyle(Theme.inkSecondary)
                        .monospacedDigit()
                        // 金額は桁の途中で折り返さない。
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                } label: {
                    Label {
                        // 予算を決める画面の入力欄の見出し（「月の予算」）とは別のキーにする。日本語は同じでも、英語では
                        // 設定の行の名前はほかの行と同じく語頭を大文字にし（Monthly Budget）、入力欄の見出しは文の形のまま
                        // （Monthly budget）にするため。
                        Text(LocalizedStringResource(
                            "月の予算（設定の行）", defaultValue: "月の予算",
                            comment: "設定の「予算」の節の行。押すと予算を決める画面を開く。右にいまの月の予算の額か「未設定」を出す"
                        ))
                        .foregroundStyle(Theme.ink)
                    } icon: {
                        SettingsRowIcon(symbolName: "yensign", fill: SettingsRowIcon.green)
                    }
                }
                .frame(minHeight: 44)
                .contentShape(.rect)
            }
            .accessibilityHint("予算を決める画面を開きます")
            .accessibilityIdentifier(AccessibilityID.Settings.budget)
            .listRowBackground(Theme.surface)
        } header: {
            sectionHeader("予算")
        }
    }

    private var budgetValue: Text {
        if let total = model.totalBudget {
            Text(verbatim: YenFormatter.string(from: total))
        } else {
            Text("未設定")
        }
    }

    // MARK: - カテゴリ

    /// カテゴリの一覧（作る・直す・削除する。修正の記憶（覚えたカテゴリ）の一覧もその中から）へ進む行。カテゴリの数を出す。
    private var learningSection: some View {
        Section {
            NavigationLink {
                CategoryListView(model: model.categoryList, learnedCategories: model.learnedCategories)
                    .onAppear { model.categoryList.reload() }
            } label: {
                LabeledContent {
                    // 記録の件数の「件」とは別のキーにする（英語ではカテゴリの数として訳すため）。
                    Text(LocalizedStringResource(
                        "%lld 件（カテゴリ）", defaultValue: "\(model.categoryList.catalog.all.count) 件",
                        comment: "設定の「カテゴリ」の行の右に出す、カテゴリの数（はじめからあるものと作ったもの）。%lld は数"
                    ))
                        .foregroundStyle(Theme.inkSecondary)
                        .monospacedDigit()
                } label: {
                    Label {
                        Text(.categoriesTitle)
                            .foregroundStyle(Theme.ink)
                    } icon: {
                        SettingsRowIcon(symbolName: "square.grid.2x2", fill: SettingsRowIcon.purple)
                    }
                }
                .frame(minHeight: 44)
            }
            .accessibilityHint("カテゴリの一覧を開きます。カテゴリを作ったり直したりできます")
            .accessibilityIdentifier(AccessibilityID.Settings.categories)
            .listRowBackground(Theme.surface)
        } header: {
            Text(.categoriesTitle)
                .foregroundStyle(Theme.inkSecondary)
        } footer: {
            sectionFooter("交際・ペット・子どもなど、カテゴリは作って増やせます。記録の返事でカテゴリを選んだり、直す画面でカテゴリを変えたりすると、同じ言葉を次からそのカテゴリで記録します。")
        }
    }

    // MARK: - くり返しの記録

    /// 家賃・サブスク・給料のように、毎月同じ記録の一覧へ進む行。決まりの数を出す。
    private var recurringSection: some View {
        Section {
            NavigationLink {
                RecurringListView(model: model.recurringList)
                    .onAppear { model.recurringList.reload() }
            } label: {
                LabeledContent {
                    // 記録の件数の「件」とは別のキーにする（英語では決まりの数として訳すため）。
                    Text(LocalizedStringResource(
                        "%lld 件（くり返しの記録）", defaultValue: "\(model.recurringList.rows.count) 件",
                        comment: "設定の「くり返しの記録」の行の右に出す、くり返しの記録の数。%lld は数"
                    ))
                        .foregroundStyle(Theme.inkSecondary)
                        .monospacedDigit()
                } label: {
                    Label {
                        Text(.recurringTitle)
                            .foregroundStyle(Theme.ink)
                    } icon: {
                        SettingsRowIcon(symbolName: "arrow.triangle.2.circlepath", fill: SettingsRowIcon.blue)
                    }
                }
                .frame(minHeight: 44)
            }
            .accessibilityHint("毎月同じ記録の一覧を開きます")
            .accessibilityIdentifier(AccessibilityID.Settings.recurring)
            .listRowBackground(Theme.surface)
        } header: {
            sectionHeader("毎月の記録")
        } footer: {
            // アプリは決めた日に裏で動かないので、「決めた日に自動で」とは書かない（決めた日を過ぎて開いたときに記録する）。
            sectionFooter("家賃・サブスク・給料のように毎月同じ記録を、決めた日を過ぎて最初にアプリを開いたときに記録します。")
        }
    }

    // MARK: - iCloud 同期

    private var iCloudSection: some View {
        Section {
            Toggle(isOn: iCloudSyncBinding) {
                HStack(spacing: 12) {
                    Label {
                        Text("iCloud で同期")
                            .foregroundStyle(Theme.ink)
                    } icon: {
                        SettingsRowIcon(symbolName: "icloud", fill: SettingsRowIcon.blue)
                    }
                    if model.isCheckingICloudAccount {
                        // iCloud のアカウントを確かめている間の印（たいていは一瞬）。
                        ProgressView()
                            .accessibilityHidden(true)
                    }
                }
            }
            .disabled(model.isCheckingICloudAccount)
            .frame(minHeight: 44)
            .accessibilityHint("記録と予算を、あなたの iCloud で同じ Apple アカウントの端末とそろえます")
            .accessibilityIdentifier(AccessibilityID.Settings.iCloudSync)
            .listRowBackground(Theme.surface)
            // オンなのに iCloud を使えない（サインアウトしたなど）。保存はできるが同期は止まっているので、それを伝える。
            if model.isICloudSyncEnabled, let paused = model.iCloudAccountStatus?.pausedText {
                Label {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("いまは同期していません")
                            .foregroundStyle(Theme.ink)
                        Text(verbatim: paused)
                            .font(.footnote)
                            .foregroundStyle(Theme.inkSecondary)
                    }
                } icon: {
                    Image(systemName: "exclamationmark.icloud")
                        .foregroundStyle(Theme.inkSecondary)
                }
                .accessibilityElement(children: .combine)
                .listRowBackground(Theme.surface)
            }
        } header: {
            sectionHeader("同期")
        } footer: {
            if model.isICloudSyncEnabled {
                // サインアウトの前にオフにすることだけは、記録が消えて見えることがあるので、オンの間ずっと書いておく。
                sectionFooter("記録と予算を、あなたの iCloud で同じ Apple アカウントの端末とそろえています。iCloud からサインアウトする前に、ここでオフにしてください（オンのままだと、この iPhone から記録が消えて見えることがあります）。")
            } else {
                sectionFooter("オンにすると、記録と予算をあなたの iCloud に保存し、同じ Apple アカウントの端末どうしでそろえます。オフのあいだは、この iPhone の中だけに保存します。")
            }
        }
    }

    /// トグルの値は、いま開いている保存先のまま。押されたら確かめと説明に進み、説明で「オンにする」「オフにする」を
    /// 押したときだけ切り替える（押しただけでトグルが動くと、やめたのに切り替わったように見えるため）。
    private var iCloudSyncBinding: Binding<Bool> {
        Binding(get: { model.isICloudSyncEnabled }, set: { model.requestICloudSync($0) })
    }

    private var iCloudConfirmationTitle: Text {
        switch model.iCloudSyncConfirmation {
        case .disable: Text("iCloud での同期をオフにしますか？")
        case .enable, nil: Text("iCloud で同期しますか？")
        }
    }

    private var showsICloudConfirmation: Binding<Bool> {
        Binding(get: { model.iCloudSyncConfirmation != nil }, set: { if !$0 { model.iCloudSyncConfirmation = nil } })
    }

    private var showsICloudAccountAlert: Binding<Bool> {
        Binding(get: { model.iCloudAccountAlert != nil }, set: { if !$0 { model.iCloudAccountAlert = nil } })
    }

    // MARK: - ロック

    /// 「Face ID でロック」（Face ID の無い端末では Touch ID・パスコード）。オンにするときもオフにするときも、その場で 1 回認証して
    /// から切り替える。
    private func lockSection(_ lock: AppLock) -> some View {
        // パスコードを設定していない端末ではオンにできない（解除できないロックにしない）。押してから断るより、先に押せなく
        // して理由を書く。オンのまま（後からパスコードを外した）なら、オフにはできるよう押せるままにする。
        let cannotEnable = lock.method == .unavailable && !lock.isEnabled
        return Section {
            Toggle(isOn: Binding(get: { lock.isEnabled }, set: { enabled in Task { await lock.setEnabled(enabled) } })) {
                Label {
                    lockTitle(lock.method)
                        .foregroundStyle(Theme.ink)
                } icon: {
                    SettingsRowIcon(symbolName: lockSymbol(lock.method), fill: SettingsRowIcon.green)
                }
            }
            .disabled(cannotEnable)
            .frame(minHeight: 44)
            .accessibilityHint("アプリを開くときに、ロックの解除を求めます")
            .accessibilityIdentifier(AccessibilityID.Settings.appLock)
            .listRowBackground(Theme.surface)
        } header: {
            sectionHeader("セキュリティ")
        } footer: {
            if cannotEnable {
                sectionFooter("iPhone の設定でパスコードを設定すると、使えるようになります。")
            } else {
                sectionFooter("オンにすると、アプリを開くときにロックの解除を求めます。アプリの切り替えの画面でも記録を隠します。")
            }
        }
        .alert(
            lockFailureTitle(lock.enableFailure),
            isPresented: Binding(get: { lock.enableFailure != nil }, set: { if !$0 { lock.enableFailure = nil } })
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            switch lock.enableFailure {
            case .passcodeNotSet: Text("iPhone の設定でパスコードを設定すると、使えるようになります。")
            case .disableNotAuthenticated: Text("ロックはオンのままです。もう一度お試しください。")
            case .notSaved: Text("ロックの設定は変わっていません。もう一度お試しください。")
            case .notAuthenticated, nil: Text("ロックはオフのままです。もう一度お試しください。")
            }
        }
    }

    private func lockTitle(_ method: AppLockMethod) -> Text {
        switch method {
        case .faceID: Text("Face ID でロック")
        case .touchID: Text("Touch ID でロック")
        case .opticID: Text("Optic ID でロック")
        case .passcode, .unavailable: Text("パスコードでロック")
        }
    }

    private func lockSymbol(_ method: AppLockMethod) -> String {
        switch method {
        case .faceID: "faceid"
        case .touchID: "touchid"
        case .opticID: "opticid"
        case .passcode, .unavailable: "lock"
        }
    }

    private func lockFailureTitle(_ failure: AppLock.EnableFailure?) -> Text {
        switch failure {
        case .passcodeNotSet: Text("パスコードが設定されていません")
        case .disableNotAuthenticated: Text("ロックをオフにできませんでした")
        case .notSaved: Text("設定を保存できませんでした")
        case .notAuthenticated, nil: Text("ロックをオンにできませんでした")
        }
    }

    // MARK: - 書き出し

    /// 書き出しは 1 行のメニューにする（押すと期間を選び、選んだらすぐ書き出す）。期間を選ぶ行と書き出すボタンを分けると、
    /// 期間を選んだだけで書き出したと思ったり、書き出すたびに 2 か所を触ったりするため。
    private var exportSection: some View {
        Section {
            Menu {
                Section("期間") {
                    ForEach(LedgerExportPeriod.allCases) { period in
                        Button {
                            model.export(period: period, calendar: calendar)
                        } label: {
                            periodLabel(period)
                        }
                    }
                }
            } label: {
                HStack(spacing: 12) {
                    Label {
                        if model.isExporting {
                            Text("書き出しています…")
                        } else {
                            Text("CSV ファイルを書き出す")
                        }
                    } icon: {
                        SettingsRowIcon(symbolName: "square.and.arrow.up", fill: SettingsRowIcon.gray)
                    }
                    Spacer(minLength: 0)
                    if model.isExporting {
                        // 1 万件でも画面は止めずに書き出す（書き出しはメインスレッドの外）。その間の印。
                        ProgressView()
                            .accessibilityHidden(true)
                    }
                }
                .frame(minHeight: 44)
                .contentShape(.rect)
            }
            .disabled(model.isExporting || model.sharedFile != nil)
            .accessibilityHint("書き出す期間を選びます。書き出したら、共有の画面で渡すアプリや保存先を選びます")
            .accessibilityIdentifier(AccessibilityID.Settings.export)
            .listRowBackground(Theme.surface)
        } header: {
            sectionHeader("記録を書き出す")
        } footer: {
            sectionFooter(
                "選んだ期間の記録を、Excel などの表計算ソフトで開ける CSV ファイルにします。渡す先は共有の画面であなたが選び、アプリが自動で送ることはありません。"
            )
        }
    }

    private func periodLabel(_ period: LedgerExportPeriod) -> Text {
        switch period {
        case .thisMonth: Text("今月")
        case .lastMonth: Text("先月")
        case .thisYear: Text("今年")
        case .all: Text("すべて")
        }
    }

    private var alertTitle: Text {
        switch model.exportAlert {
        case .empty: Text("書き出す記録がありません")
        case .failed, nil: Text("書き出せませんでした")
        }
    }

    private func alertMessage(_ alert: SettingsModel.ExportAlert) -> Text {
        switch alert {
        case .empty: Text("選んだ期間には記録がありません。期間を変えてお試しください。")
        case .failed: Text("もう一度お試しください。")
        }
    }

    private var showsExportAlert: Binding<Bool> {
        Binding(get: { model.exportAlert != nil }, set: { if !$0 { model.exportAlert = nil } })
    }

    // MARK: - 読み込み

    /// 書き出した CSV から記録を戻す（機種変更のときや、iCloud 同期を使わずに別の端末へ移すとき）。書き出しの節とは分ける
    /// （書き出しは 1 行のメニューで期間を選ぶ操作、読み込みはファイルを選ぶ操作で、行の押し方が違うため）。
    private var importSection: some View {
        Section {
            Button {
                model.requestImport()
            } label: {
                HStack(spacing: 12) {
                    Label {
                        if model.isImporting {
                            Text("読み込んでいます…")
                        } else {
                            Text("CSV から読み込む")
                        }
                    } icon: {
                        SettingsRowIcon(symbolName: "square.and.arrow.down", fill: SettingsRowIcon.gray)
                    }
                    Spacer(minLength: 0)
                    if model.isImporting {
                        ProgressView()
                            .accessibilityHidden(true)
                    }
                }
                .frame(minHeight: 44)
                .contentShape(.rect)
            }
            .disabled(model.isImporting || model.importPreview != nil)
            .accessibilityHint("このアプリで書き出した CSV ファイルを選んで、記録に戻します")
            .accessibilityIdentifier(AccessibilityID.Settings.importCSV)
            .listRowBackground(Theme.surface)
        } header: {
            sectionHeader("記録を読み込む")
        } footer: {
            sectionFooter(
                "このアプリで書き出した CSV ファイルから、記録を戻します（機種変更のときなど）。ファイルはこの iPhone の中で読み、すでにある同じ記録は 2 回入れません。"
            )
        }
    }

    private var importConfirmationTitle: Text {
        model.importPreview.map { Text("\($0.importCount) 件の記録を読み込みますか？") } ?? Text(verbatim: "")
    }

    private func importConfirmationMessage(_ preview: LedgerImporter.Preview) -> Text {
        if preview.duplicateCount == 0 && preview.unreadableCount == 0 {
            return Text("読み込んだ記録は、ホームとカレンダーの使った日のところに入ります。")
        }
        return Text("すでにある同じ記録 \(preview.duplicateCount) 件と、読めなかった行 \(preview.unreadableCount) 件は入れません。")
    }

    private var importAlertTitle: Text {
        switch model.importAlert {
        case .imported: Text("読み込みました")
        case .nothingToImport: Text("読み込める記録がありません")
        case .notSaifuLogCSV: Text("このアプリの CSV ではありません")
        case .tooLarge: Text("ファイルが大きすぎます")
        case .unreadable, nil: Text("ファイルを読めませんでした")
        case .saveFailed: Text("記録を入れられませんでした")
        }
    }

    private func importAlertMessage(_ alert: SettingsModel.ImportAlert) -> Text {
        switch alert {
        case .imported(let count):
            Text("\(count) 件の記録を足しました。")
        case .nothingToImport(let duplicates, let unreadable):
            Text("このファイルは、すでにある記録と同じもの（\(duplicates) 件）と、読めない行（\(unreadable) 件）だけでした。")
        case .notSaifuLogCSV:
            Text("設定の「CSV ファイルを書き出す」で作ったファイルを選んでください。列を変えたファイルは読めません。")
        case .tooLarge:
            Text("一度に読み込めるのは \(LedgerCSVReader.maximumRows) 件までです。")
        case .unreadable:
            Text("UTF-8 か Shift_JIS で保存した CSV ファイルを選んでください。")
        case .saveFailed:
            Text("記録は何も足していません。もう一度お試しください。")
        }
    }

    private var showsImportConfirmation: Binding<Bool> {
        Binding(get: { model.importPreview != nil }, set: { if !$0 { model.importPreview = nil } })
    }

    private var showsImportAlert: Binding<Bool> {
        Binding(get: { model.importAlert != nil }, set: { if !$0 { model.importAlert = nil } })
    }

    // MARK: - このアプリについて

    private var aboutSection: some View {
        Section {
            externalLink(
                "ヘルプ・お問い合わせ", symbolName: "questionmark", fill: SettingsRowIcon.blue, destination: SettingsModel.supportURL,
                identifier: AccessibilityID.Settings.help
            )
            externalLink(
                "プライバシーポリシー", symbolName: "hand.raised", fill: SettingsRowIcon.blue, destination: SettingsModel.privacyPolicyURL,
                identifier: AccessibilityID.Settings.privacyPolicy
            )
            LabeledContent {
                Text(verbatim: model.versionText)
                    .foregroundStyle(Theme.inkSecondary)
                    .monospacedDigit()
            } label: {
                Label {
                    Text("バージョン")
                        .foregroundStyle(Theme.ink)
                } icon: {
                    SettingsRowIcon(symbolName: "info", fill: SettingsRowIcon.gray)
                }
            }
            .frame(minHeight: 44)
            .listRowBackground(Theme.surface)
        } header: {
            sectionHeader("このアプリについて")
        } footer: {
            Text(verbatim: "© 2026 iam74k4")
                .foregroundStyle(Theme.inkSecondary)
        }
    }

    /// Safari で開くリンクの行。アプリの外へ出ることを、矢印の記号と VoiceOver の説明で示す。
    private func externalLink(
        _ title: LocalizedStringKey, symbolName: String, fill: Color, destination: URL, identifier: String
    ) -> some View {
        Link(destination: destination) {
            HStack(spacing: 12) {
                Label {
                    Text(title)
                        .foregroundStyle(Theme.ink)
                } icon: {
                    SettingsRowIcon(symbolName: symbolName, fill: fill)
                }
                Spacer(minLength: 0)
                Image(systemName: "arrow.up.forward.square")
                    .foregroundStyle(Theme.inkSecondary)
                    .accessibilityHidden(true)
            }
            .frame(minHeight: 44)
            .contentShape(.rect)
        }
        .accessibilityHint("Safari で開きます")
        .accessibilityIdentifier(identifier)
        .listRowBackground(Theme.surface)
    }

    // MARK: - 見出しと注記

    /// 節の見出し。システムの既定の色はこの地の上では薄く見えるので、補足の文字の色（コントラストを確かめた色）にする。
    private func sectionHeader(_ title: LocalizedStringKey) -> some View {
        Text(title)
            .foregroundStyle(Theme.inkSecondary)
    }

    private func sectionFooter(_ text: LocalizedStringKey) -> some View {
        Text(text)
            .foregroundStyle(Theme.inkSecondary)
    }
}

/// 設定の行の頭の印（iOS の設定 App と同じ、色の付いた角丸の四角に記号）。行を目で探しやすくするための飾りなので読ませない。
///
/// 塗りはライトとダークで同じ濃い色にし、白い記号を載せる（カテゴリの丸と同じく、白い記号に 4:1 以上の濃さの色。
/// `Palette.category` のライトの値を使う）。
struct SettingsRowIcon: View {
    let symbolName: String
    let fill: Color

    @ScaledMetric(relativeTo: .body) private var size = 29

    var body: some View {
        Image(systemName: symbolName)
            .font(.system(size: size * 0.5, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(fill, in: .rect(cornerRadius: size * 0.24))
            .accessibilityHidden(true)
    }

    private static func fixed(_ value: UInt32) -> Color {
        ColorPair(light: value, dark: value).color
    }

    static let green = fixed(Palette.category(.daily).light)
    static let blue = fixed(Palette.category(.transport).light)
    static let purple = fixed(Palette.category(.entertainment).light)
    static let teal = fixed(Palette.category(.utilities).light)
    static let gray = fixed(Palette.category(.other).light)
}

#Preview {
    if let container = try? ModelContainerFactory.makeInMemoryContainer() {
        NavigationStack {
            SettingsView(model: SettingsModel(context: container.mainContext))
        }
    }
}
