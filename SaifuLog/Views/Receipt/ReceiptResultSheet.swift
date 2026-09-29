import SaifuLogCore
import SwiftUI

/// ⑤ 読み取り結果。レシートを撮るか選ぶと下から出るシートで、読み取った品目を確かめて記録する。
///
/// 店名・日付（直せる）、品目の行（品名・金額・カテゴリを直せ、行ごとに外せる）、品目の合計とレシートの合計の照合、
/// 「品目ごとに記録」「まとめて 1 件で記録」の切り替え、「記録する」。合計が合わないときは黙って記録せず、確かめてから記録する。
/// 直した内容があるときは、下へのスワイプでも「閉じる」でも、捨ててよいかを確かめてから閉じる（⑥ 直すと同じ）。
/// 状態と操作は `ReceiptResultModel`。山吹の塗りは「記録する」のボタンにだけ使う。
struct ReceiptResultSheet: View {
    @Bindable var model: ReceiptResultModel

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("レシートの読み取り")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        // 取り消しのバナーの「閉じる」（英語は Dismiss）とは別のキーにする。英語ではシートを閉じるボタンは Close のため。
                        Button {
                            if model.requestClose() { dismiss() }
                        } label: {
                            Text(Self.closeTitle)
                        }
                    }
                }
                .alert("記録できませんでした", isPresented: $model.showsSaveFailure) {
                    Button("OK", role: .cancel) {}
                } message: {
                    Text("保存に失敗しました。もう一度お試しください。")
                }
                .confirmationDialog(
                    "合計が合いません",
                    isPresented: $model.showsMismatchConfirmation,
                    titleVisibility: .visible
                ) {
                    Button("品目の合計で記録する") { model.recordNow() }
                    Button("直すのを続ける", role: .cancel) {}
                } message: {
                    mismatchMessage
                }
                .confirmationDialog(
                    "直した内容を破棄しますか？",
                    isPresented: $model.showsDiscardConfirmation,
                    titleVisibility: .visible
                ) {
                    Button("破棄して閉じる", role: .destructive) { dismiss() }
                    Button("直すのを続ける", role: .cancel) {}
                }
        }
        .presentationDetents([.large])
        // 直した内容があるときは、下へのスワイプで黙って閉じない。止めたスワイプは確認に回す（画像は保存しないので、閉じると
        // 撮り直すしか戻す方法が無い）。記録したときと撮り直すときは HomeModel がシートを閉じるので、ここでは止まらない。
        .interactiveDismissDisabled(model.hasChanges)
        .background(SheetDismissAttemptObserver { model.showsDiscardConfirmation = true })
    }

    /// シートを閉じるボタンの名前（記録せずに閉じる）。
    static let closeTitle = LocalizedStringResource(
        "閉じる（レシートの読み取り）", defaultValue: "閉じる",
        comment: "レシートの読み取り結果のシート（⑤）の、記録せずにシートを閉じるボタン"
    )

    @ViewBuilder
    private var content: some View {
        switch model.state {
        case .reading:
            ReceiptReadingView()
        case .unreadable(let reason):
            ReceiptUnreadableView(reason: reason, source: model.source, retake: { model.retake() })
        case .ready:
            ReceiptReadyView(model: model)
        }
    }

    private var mismatchMessage: Text {
        let lines = YenFormatter.string(from: model.linesTotal)
        if let total = model.receiptTotal {
            return Text("レシートの合計は \(YenFormatter.string(from: total))、品目の合計は \(lines) です。品目の合計で記録しますか？")
        }
        return Text("品目の合計 \(lines) で記録しますか？")
    }
}

// MARK: - 読み取り中

private struct ReceiptReadingView: View {
    var body: some View {
        VStack(spacing: 16) {
            ProgressView()
                .controlSize(.large)
            Text("レシートを読み取っています…")
                .font(.headline)
            Text("画像はこの iPhone の中で読み取り、保存も送信もしません。")
                .font(.footnote)
                .foregroundStyle(Theme.inkSecondary)
                .multilineTextAlignment(.center)
        }
        .foregroundStyle(Theme.ink)
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.background)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - 読めなかった

/// 読めなかったときの案内と撮り直し。
private struct ReceiptUnreadableView: View {
    let reason: ReceiptUnreadableReason
    let source: ReceiptCaptureSource
    let retake: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Image(systemName: "doc.text.magnifyingglass")
                    .font(.system(size: 44))
                    .foregroundStyle(Theme.inkSecondary)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 8) {
                    Text("レシートを読み取れませんでした")
                        .font(.title3.bold())
                        .accessibilityAddTraits(.isHeader)
                    reasonText
                        .foregroundStyle(Theme.inkSecondary)
                }
                VStack(alignment: .leading, spacing: 10) {
                    if reason == .imageUnavailable {
                        // 画像を読み込めなかったときは、撮り方のこつではなく、読み込めなかった原因への手当てを出す。
                        if source == .photos {
                            tip("写真が iCloud にだけあるときは、インターネットにつながった状態で選び直してください。", systemImage: "icloud")
                        }
                    } else {
                        tip("明るい場所で、レシート全体が枠に入るように撮ってください。", systemImage: "sun.max")
                        tip("しわや折り目を伸ばし、影が入らないようにしてください。", systemImage: "hand.raised")
                        tip("金額の書かれたレシートの画像を選んでください。", systemImage: "photo")
                    }
                }
                Text("読み取れなかったときは、無料の回数を使いません。")
                    .font(.footnote)
                    .foregroundStyle(Theme.inkSecondary)
                // 閉じるのは左上の「閉じる」から（同じボタンを 2 つ並べない）。山吹は塗らない（記録するボタンにだけ使う）。
                Button(action: retake) {
                    retakeLabel
                        .fontWeight(.semibold)
                        .foregroundStyle(Theme.accentText)
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.bordered)
            }
            .foregroundStyle(Theme.ink)
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Theme.background)
    }

    private var reasonText: Text {
        switch reason {
        case .noText: Text("文字が見つかりませんでした。")
        case .noAmounts: Text("金額の書かれた行が見つかりませんでした。")
        case .imageUnavailable:
            switch source {
            case .camera: Text("撮った画像を読み込めませんでした。")
            case .photos: Text("写真を読み込めませんでした。")
            }
        }
    }

    private var retakeLabel: Text {
        switch source {
        case .camera: Text("撮り直す")
        case .photos: Text("写真を選び直す")
        }
    }

    private func tip(_ text: LocalizedStringKey, systemImage: String) -> some View {
        Label {
            Text(text)
        } icon: {
            Image(systemName: systemImage)
                .foregroundStyle(Theme.inkSecondary)
        }
        .font(.subheadline)
    }
}

// MARK: - 読み取れた

private struct ReceiptReadyView: View {
    @Bindable var model: ReceiptResultModel

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if let notice = model.skippedPagesNotice {
                    // 読み取らなかったページがあることは、いちばん上に注意の色・アイコン・文で出す（色だけで伝えない）。
                    Label {
                        Text(verbatim: notice)
                    } icon: {
                        Image(systemName: "exclamationmark.triangle.fill")
                    }
                    .font(.subheadline)
                    .foregroundStyle(Theme.danger)
                }
                storeSection
                modeSection
                if model.mode == .single {
                    singleCategorySection
                }
                linesSection
                reconciliationSection
                Text("画像はこの iPhone の中で読み取り、保存も送信もしません。レシートの文字の全体も保存せず、記録には記録する品目（品名・金額・カテゴリ）と日付、店名と合計の要約だけを残します。")
                    .font(.footnote)
                    .foregroundStyle(Theme.inkSecondary)
            }
            .foregroundStyle(Theme.ink)
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Theme.background)
        // 記録のボタンは画面の下に置き続ける（金額の数字のキーボードには確定のキーが無いので、キーボードを出したまま押せるように）。
        .safeAreaInset(edge: .bottom, spacing: 0) {
            recordBar
                .padding(.horizontal)
                .padding(.vertical, 8)
                .background(Theme.background)
        }
    }

    // MARK: 店名と日付

    private var storeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                ReceiptSectionLabel("店名")
                TextField(text: $model.storeName, prompt: Text("店名（空欄でもかまいません）").foregroundStyle(Theme.inkSecondary)) {
                    Text("店名")
                }
                .submitLabel(.done)
                .padding(.horizontal, 16)
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .background(Theme.surface, in: .rect(cornerRadius: 16))
            }
            VStack(alignment: .leading, spacing: 6) {
                ReceiptSectionLabel("日付")
                DatePicker(selection: $model.day, displayedComponents: .date) {
                    Text("日付")
                }
                .labelsHidden()
                .frame(minHeight: 44)
            }
        }
    }

    // MARK: 記録のしかた

    private var modeSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            ReceiptSectionLabel("記録のしかた")
            if dynamicTypeSize.isAccessibilitySize {
                VStack(spacing: 8) { modeChoices }
            } else {
                HStack(spacing: 8) { modeChoices }
            }
        }
    }

    @ViewBuilder
    private var modeChoices: some View {
        ReceiptChoiceButton(isSelected: model.mode == .perItem) {
            model.mode = .perItem
        } label: {
            Text("品目ごとに記録")
        }
        ReceiptChoiceButton(isSelected: model.mode == .single) {
            model.mode = .single
        } label: {
            Text("まとめて1件で記録")
        }
    }

    private var singleCategorySection: some View {
        VStack(alignment: .leading, spacing: 6) {
            ReceiptSectionLabel("カテゴリ")
            ReceiptCategoryMenu(category: $model.singleCategory)
        }
    }

    // MARK: 品目

    private var linesSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            ReceiptSectionLabel("品目")
            VStack(spacing: 8) {
                ForEach($model.lines) { $line in
                    ReceiptLineRow(
                        line: $line,
                        displayName: model.displayName(of: line),
                        showsCategory: model.mode == .perItem,
                        setIncluded: { model.setIncluded($0, for: line.id) },
                        normalizeAmount: { model.normalizeAmountText(for: line.id) }
                    )
                }
            }
        }
    }

    // MARK: 照合

    private var reconciliationSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            totalRow(Text("品目の合計"), value: Text(verbatim: YenFormatter.string(from: model.linesTotal)))
            totalRow(
                Text("レシートの合計"),
                value: model.receiptTotal.map { Text(verbatim: YenFormatter.string(from: $0)) } ?? Text("読み取れませんでした")
            )
            statusLabel
            if case .mismatched(let difference) = model.reconciliation.status, difference > 0 {
                Button {
                    model.addDifferenceLine()
                } label: {
                    Text("差額 \(YenFormatter.string(from: difference)) を「税・その他」として足す")
                        // 操作のボタンは tint（AccentColor）の文字にする（まわりの墨の文字の色を引き継がせない）。
                        .foregroundStyle(Theme.accentText)
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        .contentShape(.rect)
                }
            }
        }
        .padding(16)
        .background(Theme.surface, in: .rect(cornerRadius: 16))
    }

    private func totalRow(_ label: Text, value: Text) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline) {
                label.foregroundStyle(Theme.inkSecondary)
                Spacer(minLength: 8)
                value.font(.headline).monospacedDigit()
            }
            VStack(alignment: .leading, spacing: 2) {
                label.foregroundStyle(Theme.inkSecondary)
                value.font(.headline).monospacedDigit()
            }
        }
        .accessibilityElement(children: .combine)
    }

    /// 照合の結果。合わないときは注意の色に、アイコンと文を添える（色だけで伝えない）。
    @ViewBuilder
    private var statusLabel: some View {
        switch model.reconciliation.status {
        case .matched:
            Label {
                Text("合計と合っています")
            } icon: {
                Image(systemName: "checkmark.circle.fill")
            }
            .foregroundStyle(Theme.ink)
        case .mismatched(let difference):
            Label {
                Text("合計が合いません（差 \(YenFormatter.string(from: abs(difference)))）")
            } icon: {
                Image(systemName: "exclamationmark.triangle.fill")
            }
            .foregroundStyle(Theme.danger)
        case .totalMissing:
            Label {
                Text("合計を読み取れませんでした。品目の合計で記録します。")
            } icon: {
                Image(systemName: "info.circle")
            }
            .foregroundStyle(Theme.inkSecondary)
        }
    }

    // MARK: 記録する

    private var recordBar: some View {
        VStack(spacing: 6) {
            if model.hasInvalidAmount {
                Label {
                    Text("金額が入っていない行があります。金額を入れるか、行を外してください。")
                } icon: {
                    Image(systemName: "exclamationmark.circle.fill")
                }
                .font(.footnote)
                .foregroundStyle(Theme.danger)
                .frame(maxWidth: .infinity, alignment: .leading)
            } else if model.recordCount > 0 {
                Text("記録する件数: \(model.recordCount)件（\(YenFormatter.string(from: model.linesTotal))）")
                    .font(.footnote)
                    .foregroundStyle(Theme.inkSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Button {
                model.requestRecord()
            } label: {
                Text("記録する")
                    .fontWeight(.semibold)
                    // 押せるときは山吹の塗りの上なので墨（Theme の説明）。押せないときは灰色のガラスの上なので補足の文字の色。
                    .foregroundStyle(model.canRecord ? Theme.onAccent : Theme.inkSecondary)
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.glassProminent)
            .tint(Theme.accentFill)
            .disabled(!model.canRecord)
        }
    }
}

// MARK: - 品目の行

/// 品目の 1 行。品名・金額・カテゴリを直せ、左の印で外す・戻す。
///
/// VoiceOver では、左の印を「牛乳 ¥198 食費」の 1 つの要素として読み、値に「記録する」「外した」、ダブルタップで外す・戻す。
/// 品名・金額・カテゴリの欄はそれぞれ別の要素として読む。
private struct ReceiptLineRow: View {
    @Binding var line: ReceiptResultModel.Line
    let displayName: String
    let showsCategory: Bool
    let setIncluded: (Bool) -> Void
    let normalizeAmount: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .center, spacing: 10) {
                    includeButton
                    TextField(text: $line.name, prompt: Text(verbatim: displayName).foregroundStyle(Theme.inkSecondary)) {
                        Text("品名")
                    }
                    .submitLabel(.done)
                    .strikethrough(!line.isIncluded)
                }
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: 8) { valueFields }
                } else {
                    HStack(spacing: 8) { valueFields }
                }
            }
            // 外した行は薄くし、取り消し線と「外した」の語でも示す（色だけで伝えない）。注記は薄くしない（読めるように）。
            .opacity(line.isIncluded ? 1 : 0.6)
            if let note {
                note
                    .font(.caption)
                    .foregroundStyle(Theme.inkSecondary)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface, in: .rect(cornerRadius: 16))
    }

    private var includeButton: some View {
        Button {
            setIncluded(!line.isIncluded)
        } label: {
            Image(systemName: line.isIncluded ? "checkmark.circle.fill" : "circle")
                .font(.title3)
                .foregroundStyle(line.isIncluded ? Theme.ink : Theme.inkSecondary)
                .frame(width: 44, height: 44)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(verbatim: spokenSummary))
        .accessibilityValue(line.isIncluded ? Text("記録する") : Text("外した"))
        .accessibilityHint(line.isIncluded ? Text("ダブルタップで記録から外します") : Text("ダブルタップで記録に戻します"))
        .accessibilityAction(named: line.isIncluded ? Text("外す") : Text("戻す")) { setIncluded(!line.isIncluded) }
    }

    @ViewBuilder
    private var valueFields: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(verbatim: "¥")
                .foregroundStyle(Theme.inkSecondary)
                .accessibilityHidden(true)
            TextField(text: $line.amountText, prompt: Text(verbatim: "0").foregroundStyle(Theme.inkSecondary)) {
                Text("金額（円）")
            }
            .keyboardType(.numberPad)
            .monospacedDigit()
            .onChange(of: line.amountText) { normalizeAmount() }
        }
        .font(.headline)
        .padding(.horizontal, 12)
        .frame(minWidth: 120, maxWidth: dynamicTypeSize.isAccessibilitySize ? .infinity : 160, minHeight: 44, alignment: .leading)
        .background(Theme.background, in: .rect(cornerRadius: 12))
        if showsCategory {
            ReceiptCategoryMenu(category: $line.category)
        }
    }

    /// 数量・値引き・軽減税率・外したことの注記。
    private var note: Text? {
        var parts: [String] = []
        if let quantity = line.quantity, let unitPrice = line.unitPrice {
            parts.append("\(quantity) × \(YenFormatter.string(from: unitPrice))")
        }
        if line.discount > 0 {
            parts.append(String(localized: "値引 \(YenFormatter.string(from: line.discount))"))
        }
        if line.isReducedTaxRate {
            parts.append(String(localized: "軽減税率"))
        }
        if !line.isIncluded {
            parts.append(String(localized: "外した"))
        }
        return parts.isEmpty ? nil : Text(verbatim: parts.joined(separator: " · "))
    }

    private var spokenSummary: String {
        var parts = [displayName]
        if let amount = line.amount { parts.append(YenFormatter.string(from: amount)) }
        if showsCategory { parts.append(String(localized: line.category.label)) }
        return parts.joined(separator: " ")
    }
}

// MARK: - 部品

/// カテゴリを選ぶメニュー（色と記号の丸と名前）。
private struct ReceiptCategoryMenu: View {
    @Binding var category: EntryCategory

    var body: some View {
        Menu {
            Picker(selection: $category) {
                ForEach(EntryCategory.allCases) { category in
                    Label {
                        Text(category.label)
                    } icon: {
                        Image(systemName: category.symbolName)
                    }
                    .tag(category)
                }
            } label: {
                Text("カテゴリ")
            }
        } label: {
            HStack(spacing: 8) {
                CategoryIcon(category: category)
                Text(category.label)
                    .foregroundStyle(Theme.ink)
                Spacer(minLength: 0)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption)
                    .foregroundStyle(Theme.inkSecondary)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(Theme.background, in: .rect(cornerRadius: 12))
            .contentShape(.rect(cornerRadius: 12))
        }
        .accessibilityLabel(Text("カテゴリ"))
        .accessibilityValue(Text(category.label))
    }
}

/// 欄の見出し。VoiceOver では見出しとして読ませる。
private struct ReceiptSectionLabel: View {
    let title: LocalizedStringKey

    init(_ title: LocalizedStringKey) {
        self.title = title
    }

    var body: some View {
        Text(title)
            .font(.subheadline)
            .foregroundStyle(Theme.inkSecondary)
            .accessibilityAddTraits(.isHeader)
    }
}

/// 選べるもの（記録のしかた）。選んだものは墨の枠とチェックの印で示す（色だけに頼らない。山吹は記録するボタンの塗りにだけ使う）。
private struct ReceiptChoiceButton<Content: View>: View {
    let isSelected: Bool
    let action: () -> Void
    @ViewBuilder let label: Content

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                label
                    .frame(maxWidth: .infinity, alignment: .leading)
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.body.weight(.semibold))
                        .accessibilityHidden(true)
                }
            }
            .foregroundStyle(Theme.ink)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(Theme.surface, in: .rect(cornerRadius: 12))
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(isSelected ? Theme.ink : .clear, lineWidth: 2)
            }
            .contentShape(.rect(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

#Preview("読み取れた") {
    let model = ReceiptResultModel(source: .photos, readAt: .now, calendar: .current, record: { _ in .recorded }, retake: {})
    let _ = model.load(.read(ReceiptLineScanner.scan(
        """
        イオン 渋谷店
        ※牛乳 ¥198
        ティッシュ ¥298
        合計 ¥496
        """.split(separator: "\n").map { ReceiptTextLine(String($0)) },
        now: .now, calendar: .current
    )))
    Color.clear
        .sheet(isPresented: .constant(true)) {
            ReceiptResultSheet(model: model)
        }
}
