import SaifuLogCore
import SwiftUI

/// ⑧ 設定。必要なときだけ開く画面。ホームの帯の右上の歯車から横に進む。
///
/// プレミアム（⑨ のシートを開く・購入の復元）、月の予算（② のシートを開く）、週の始まり、iCloud で同期（既定はオフ）、
/// 家族と共有（家計の共有が有効なビルドだけ）、記録の CSV 書き出し、このアプリについて（プライバシーポリシー・ライセンス・版）を並べる。
///
/// 状態と操作は `SettingsModel` が持つ。ここは表示と、共有のシート・アラートの出し入れだけ。
/// 押せる行の名前は墨にし、操作のボタン（「CSV ファイルを書き出す」）だけ、ほかの画面のボタンと同じ tint（AccentColor。
/// §7 のとおり、ダークでは山吹の文字）にする。山吹の塗りは使わない（塗りの主ボタンが無い画面のため）。
struct SettingsView: View {
    @Bindable var model: SettingsModel

    /// 画面の暦（週の始まりを当てはめたもの）。書き出す期間を、ホームの今月と同じ月で区切るのに使う。
    @Environment(\.calendar) private var calendar
    /// アプリのロック（アプリで 1 つ。`SaifuLogApp` が渡す）。無ければ（プレビュー）ロックの節を出さない。
    @Environment(AppLock.self) private var appLock: AppLock?

    var body: some View {
        List {
            premiumSection
            budgetSection
            learningSection
            recurringSection
            calendarSection
            if model.showsICloudSync {
                iCloudSection
            }
            if let appLock {
                lockSection(appLock)
            }
            // 家族と共有（家計の共有が有効なビルドで、家計の保存先を開けたときだけ）。
            if let household = model.household {
                HouseholdSettingsSection(model: household)
            }
            exportSection
            aboutSection
        }
        // リストの地は画面の背景にし、行は面の色にする（ほかの画面と同じ墨 × 山吹の地にそろえる）。
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
        .sheet(item: $model.premiumSheet) { premium in
            PremiumSheet(model: premium)
        }
        // 「家族と共有」の節のシートと確認（節に付けると行ごとに付いてしまうので、リストに付ける）。
        .modifier(HouseholdSettingsPresentationsIfAvailable(model: model.household))
        .alert(
            alertTitle,
            isPresented: showsExportAlert,
            presenting: model.exportAlert
        ) { _ in
            Button("OK", role: .cancel) {}
        } message: { alert in
            alertMessage(alert)
        }
        // 購入の復元の結果（ホームと同じく、同じ画面に種類ごとのアラートを付ける）。
        .alert(
            model.purchaseAlert?.title ?? Text(verbatim: ""),
            isPresented: showsPurchaseAlert,
            presenting: model.purchaseAlert
        ) { _ in
            Button("OK", role: .cancel) {}
        } message: { alert in
            alert.message
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
        // 書き出したファイルを共有のシートで渡し、閉じたらファイルを消す。
        .background(
            ShareSheetPresenter(
                fileURL: model.sharedFile?.url,
                onFinish: { sheetWasShown in model.finishSharing(sheetWasShown: sheetWasShown) }
            )
                .accessibilityHidden(true)
        )
        .onDisappear {
            model.cancelExport()
            model.cancelICloudAccountCheck()
        }
        // 同期がオンのとき、iCloud をいまも使えるかを確かめる（使えなければ節の中に案内を出す）。
        .task { await model.refreshICloudAccountStatus() }
        // iCloud で届いたほかの端末の変更（予算を変えた・カテゴリを作った・覚えたなど）で、月の予算とカテゴリの行を読み直す。
        .onReceive(StoreChanges.remote) { _ in
            model.reloadBudget()
            model.categoryList.reload()
            model.recurringList.reload()
            model.learnedCategories.reload()
        }
        // 家計の共有の知らせ（共有をやめた・抜けた・消えたなど）。設定の画面を出している間は、ホームの下からはアラートを
        // 出せないので、ここで出す（節のシートや確認を出している間は、閉じてから出す）。
        .alert(
            model.household?.host.notice?.title ?? Text(verbatim: ""),
            isPresented: showsHouseholdNotice,
            presenting: model.household?.host.notice
        ) { _ in
            Button("OK", role: .cancel) {}
        } message: { notice in
            notice.message
        }
    }

    private var showsHouseholdNotice: Binding<Bool> {
        Binding(
            get: {
                guard let household = model.household else { return false }
                return household.host.notice != nil && household.canPresentNotice && model.budgetSetup == nil
                    && model.premiumSheet == nil
            },
            set: { if !$0 { model.household?.host.notice = nil } }
        )
    }

    // MARK: - プレミアム

    private var premiumSection: some View {
        Section {
            Button {
                model.presentPremium()
            } label: {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("サイフログ プレミアム")
                            .foregroundStyle(Theme.ink)
                        premiumRowDetail
                            .font(.subheadline)
                    }
                    .padding(.vertical, 4)
                } icon: {
                    SettingsRowIcon(symbolName: "sparkles", fill: Theme.accentFill, symbol: Theme.onAccent)
                }
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .contentShape(.rect)
            }
            .accessibilityHint("プレミアムでできることと購入の画面を開きます")
            .listRowBackground(Theme.surface)
            Button {
                model.restorePurchases()
            } label: {
                HStack(spacing: 12) {
                    Label {
                        Text("購入の復元")
                    } icon: {
                        SettingsRowIcon(symbolName: "arrow.clockwise", fill: SettingsRowIcon.gray)
                    }
                    Spacer(minLength: 0)
                    if model.purchases.isRestoring {
                        ProgressView()
                            .accessibilityHidden(true)
                    }
                }
                .frame(minHeight: 44)
                .contentShape(.rect)
            }
            .disabled(model.purchases.isRestoring || model.purchases.isPurchasing)
            .accessibilityHint("この Apple アカウントで購入したプレミアムを読み込みます")
            .listRowBackground(Theme.surface)
        } header: {
            sectionHeader("プレミアム")
        } footer: {
            sectionFooter("購入は Apple アカウントに記録されます。機種を変えたときなどにプレミアムが使えなければ、「購入の復元」をお試しください。")
        }
    }

    /// プレミアムの行の 2 行目。まだ体験していなければ体験を勧め（0 円で全部を試せることが、いちばんの案内になるため）、
    /// 体験中は残りの日数、体験の後は買い切りで増えること、購入済みは購入の形を出す。
    private var premiumRowDetail: Text {
        switch model.purchases.status {
        case .free:
            Text("14日間 無料で試せます").foregroundStyle(Theme.accentText)
        case .trialEnded:
            Text("買い切りで、レシートと質問が無制限に").foregroundStyle(Theme.accentText)
        case .trial(let days, _):
            Text("体験中 あと \(days) 日").foregroundStyle(Theme.inkSecondary)
        case .premium(.purchased):
            Text("購入済み").foregroundStyle(Theme.inkSecondary)
        case .premium(.familyShared):
            Text("ファミリー共有").foregroundStyle(Theme.inkSecondary)
        }
    }

    private var showsPurchaseAlert: Binding<Bool> {
        Binding(get: { model.purchaseAlert != nil }, set: { if !$0 { model.purchaseAlert = nil } })
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

    /// カテゴリの一覧（作る・直す・削除する）と、修正の記憶（覚えたカテゴリ）の一覧へ進む行。それぞれ数を出す。
    private var learningSection: some View {
        Section {
            NavigationLink {
                CategoryListView(model: model.categoryList)
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
            .listRowBackground(Theme.surface)
            NavigationLink {
                LearnedCategoriesView(model: model.learnedCategories)
                    .onAppear { model.learnedCategories.reload() }
            } label: {
                LabeledContent {
                    // 記録の件数の「件」とは別のキーにする（英語では記録ではなく言葉の数として訳すため）。
                    Text(LocalizedStringResource(
                        "%lld 件（覚えたカテゴリ）", defaultValue: "\(model.learnedCategories.rules.count) 件",
                        comment: "設定の「覚えたカテゴリ」の行の右に出す、覚えた言葉の数。%lld は数"
                    ))
                        .foregroundStyle(Theme.inkSecondary)
                        .monospacedDigit()
                } label: {
                    Label {
                        Text("覚えたカテゴリ")
                            .foregroundStyle(Theme.ink)
                    } icon: {
                        SettingsRowIcon(symbolName: "lightbulb", fill: SettingsRowIcon.teal)
                    }
                }
                .frame(minHeight: 44)
            }
            .accessibilityHint("覚えた言葉とカテゴリの一覧を開きます")
            .listRowBackground(Theme.surface)
        } header: {
            Text(.categoriesTitle)
                .foregroundStyle(Theme.inkSecondary)
        } footer: {
            sectionFooter("家賃・服・美容など、カテゴリは作って増やせます。記録の返事でカテゴリを選んだり、直す画面でカテゴリを変えたりすると、同じ言葉を次からそのカテゴリで記録します。")
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
            .listRowBackground(Theme.surface)
            NavigationLink {
                WalletCaptureView(model: model.walletCapture)
            } label: {
                Label {
                    Text(.walletCaptureTitle)
                        .foregroundStyle(Theme.ink)
                } icon: {
                    SettingsRowIcon(symbolName: "creditcard", fill: SettingsRowIcon.charcoal)
                }
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            }
            .accessibilityHint("Apple Pay で払ったときに自動で記録する方法を開きます")
            .listRowBackground(Theme.surface)
        } header: {
            sectionHeader("自動で記録")
        } footer: {
            sectionFooter("家賃・サブスク・給料のように毎月同じ記録と、Apple Pay の支払いを、アプリが記録してホームの返事でお知らせします。")
        }
    }

    // MARK: - 週の始まり

    private var calendarSection: some View {
        Section {
            SettingsPickerRow(
                title: "週の始まり",
                icon: SettingsRowIcon(symbolName: "calendar", fill: SettingsRowIcon.red),
                selection: $model.weekStart,
                value: weekStartLabel(model.weekStart)
            ) {
                ForEach(WeekStart.allCases) { option in
                    weekStartLabel(option).tag(option)
                }
            }
            .listRowBackground(Theme.surface)
        } header: {
            sectionHeader("カレンダー")
        } footer: {
            sectionFooter("カレンダーの週を何曜日から始めるかを選びます。")
        }
    }

    private func weekStartLabel(_ option: WeekStart) -> Text {
        switch option {
        case .system:
            // 端末の設定がどの曜日かを添える（地域によっては土曜始まりなどもある）。
            Text("端末の設定（\(SettingsModel.weekdayName(model.systemFirstWeekday))）")
        case .sunday, .monday:
            Text(verbatim: SettingsModel.weekdayName(option.firstWeekday ?? 1))
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
                sectionFooter("記録と予算を、あなたの iCloud に保存し、同じ Apple アカウントの端末どうしでそろえています。開発者は中身を見られません。同期されないときは、iCloud にサインインしているかと、iCloud の空き容量を確かめてください。iCloud からサインアウトする前に、ここでオフにしてください（オンのままサインアウトすると、同期した記録がこの iPhone から消えることがあります。iCloud には残ります）。オフにしても、この iPhone の記録は残ります。")
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

    /// 「Face ID でロック」（Face ID の無い端末では Touch ID・パスコード）。オンにするときは、その場で 1 回認証してから切り替える。
    private func lockSection(_ lock: AppLock) -> some View {
        Section {
            Toggle(isOn: Binding(get: { lock.isEnabled }, set: { enabled in Task { await lock.setEnabled(enabled) } })) {
                Label {
                    lockTitle(lock.method)
                        .foregroundStyle(Theme.ink)
                } icon: {
                    SettingsRowIcon(symbolName: lockSymbol(lock.method), fill: SettingsRowIcon.green)
                }
            }
            .frame(minHeight: 44)
            .accessibilityHint("アプリを開くときに、ロックの解除を求めます")
            .listRowBackground(Theme.surface)
        } header: {
            sectionHeader("セキュリティ")
        } footer: {
            sectionFooter("オンにすると、アプリを開くときにロックの解除を求めます。アプリの切り替えの画面でも記録を隠します。")
        }
        .alert(
            lockFailureTitle(lock.enableFailure),
            isPresented: Binding(get: { lock.enableFailure != nil }, set: { if !$0 { lock.enableFailure = nil } })
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            switch lock.enableFailure {
            case .passcodeNotSet: Text("iPhone の設定でパスコードを設定すると、使えるようになります。")
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
        case .notAuthenticated, nil: Text("ロックをオンにできませんでした")
        }
    }

    // MARK: - 書き出し

    private var exportSection: some View {
        Section {
            SettingsPickerRow(
                title: "期間",
                icon: SettingsRowIcon(symbolName: "calendar.badge.clock", fill: SettingsRowIcon.gray),
                selection: $model.exportPeriod,
                value: periodLabel(model.exportPeriod)
            ) {
                ForEach(LedgerExportPeriod.allCases) { period in
                    periodLabel(period).tag(period)
                }
            }
            .disabled(model.isExporting)
            .listRowBackground(Theme.surface)
            Button {
                model.export(calendar: calendar)
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
            .accessibilityHint("共有の画面で、渡すアプリや保存先を選びます")
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

    // MARK: - このアプリについて

    private var aboutSection: some View {
        Section {
            externalLink("ヘルプ・お問い合わせ", symbolName: "questionmark", fill: SettingsRowIcon.blue, destination: SettingsModel.supportURL)
            externalLink("プライバシーポリシー", symbolName: "hand.raised", fill: SettingsRowIcon.blue, destination: SettingsModel.privacyPolicyURL)
            externalLink("ライセンス", symbolName: "doc.text", fill: SettingsRowIcon.gray, destination: SettingsModel.licenseURL)
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
        _ title: LocalizedStringKey, symbolName: String, fill: Color, destination: URL
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
        .listRowBackground(Theme.surface)
    }

    // MARK: - 見出しと注記

    /// 節の見出し。システムの既定の色は温かい地の上で薄く見えるので、補足の文字の色（コントラストを確かめた色）にする。
    private func sectionHeader(_ title: LocalizedStringKey) -> some View {
        Text(title)
            .foregroundStyle(Theme.inkSecondary)
    }

    private func sectionFooter(_ text: LocalizedStringKey) -> some View {
        Text(text)
            .foregroundStyle(Theme.inkSecondary)
    }
}

/// 選ぶ行（週の始まり・書き出す期間）。名前と選んだ値が 1 行に収まれば横に並べ、収まらなければ値を名前の下に積んで折り返す。
///
/// 既定のメニューの Picker を使わないのは、値を 1 行に収めて途中を省くため。アクセシビリティサイズの文字では
/// 「端末の設定（日曜日）」が「端末…曜日）」になり、端末の設定がどの曜日かが読めなかった。行はメニューを開くボタンとして
/// 自前で組み、選ぶところだけ Picker にする（メニューの中の Picker は、選んでいるものに印の付いた選択肢の並びになる）。
private struct SettingsPickerRow<Value: Hashable, Options: View>: View {
    let title: LocalizedStringKey
    /// 行の頭の印。
    let icon: SettingsRowIcon
    @Binding var selection: Value
    /// 選んでいる値の表示。
    let value: Text
    @ViewBuilder let options: Options

    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Menu {
            Picker(selection: $selection) {
                options
            } label: {
                Text(title)
            }
        } label: {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) {
                    titleText
                    Spacer(minLength: 0)
                    // 値は縮めない（名前との幅の取り合いで値が省かれないように。収まらなければ下の積む形になる）。
                    valueLabel
                        .fixedSize(horizontal: true, vertical: false)
                }
                VStack(alignment: .leading, spacing: 4) {
                    titleText
                    valueLabel
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            // 折り返した行を左にそろえる。メニューのボタンの中の文字は、既定では折り返した行が中央にそろい、
            // 「Week / Starts On」のように行ごとに頭の位置がずれた（シミュレータの iOS 26.4 の AX5 で確かめた）。
            .multilineTextAlignment(.leading)
            .frame(minHeight: 44)
            .contentShape(.rect)
        }
        // 名前と値を 1 つの要素として読ませる（メニューを開くボタンであることは残る）。
        .accessibilityLabel(Text(title))
        .accessibilityValue(value)
    }

    private var titleText: some View {
        Label {
            Text(title)
                .foregroundStyle(Theme.ink)
        } icon: {
            icon
        }
    }

    /// 選んでいる値と、押すと選択肢が開くことを示す上下の矢印（既定のメニューの Picker と同じ形）。
    private var valueLabel: some View {
        HStack(spacing: 4) {
            value
            Image(systemName: "chevron.up.chevron.down")
                .imageScale(.small)
                .accessibilityHidden(true)
        }
        .foregroundStyle(Theme.inkSecondary)
        // 書き出しの途中で選べないときは薄くする（名前の色は変えない。既定の Picker と同じ）。
        .opacity(isEnabled ? 1 : 0.5)
    }
}

/// 設定の行の頭の印（iOS の設定 App と同じ、色の付いた角丸の四角に記号）。行を目で探しやすくするための飾りなので読ませない。
///
/// 塗りはライトとダークで同じ濃い色にし、白い記号を載せる（カテゴリの丸と同じく、白い記号に 4:1 以上の濃さの色。
/// `Palette.category` のライトの値を使う）。プレミアムの行だけ山吹の塗りに墨の記号にする（山吹は塗りにだけ使う決め事）。
struct SettingsRowIcon: View {
    let symbolName: String
    let fill: Color
    var symbol: Color = .white

    @ScaledMetric(relativeTo: .body) private var size = 29

    var body: some View {
        Image(systemName: symbolName)
            .font(.system(size: size * 0.5, weight: .semibold))
            .foregroundStyle(symbol)
            .frame(width: size, height: size)
            .background(fill, in: .rect(cornerRadius: size * 0.24))
            .accessibilityHidden(true)
    }

    private static func fixed(_ value: UInt32) -> Color {
        ColorPair(light: value, dark: value).color
    }

    static let green = fixed(Palette.category(.daily).light)
    static let blue = fixed(Palette.category(.transport).light)
    static let red = fixed(Palette.category(.food).light)
    static let purple = fixed(Palette.category(.entertainment).light)
    static let teal = fixed(Palette.category(.utilities).light)
    static let gray = fixed(Palette.category(.other).light)
    /// Apple Pay（ウォレット）の行。ウォレットの黒に寄せた墨。
    static let charcoal = fixed(0x3A3A3C)
    /// 家族と共有の行（柿。作ったカテゴリに選べる色と同じ値）。
    static let orange = fixed(Palette.customCategoryChoices[3].light)
}

#Preview {
    if let container = try? ModelContainerFactory.makeInMemoryContainer() {
        NavigationStack {
            SettingsView(model: SettingsModel(context: container.mainContext))
        }
    }
}
