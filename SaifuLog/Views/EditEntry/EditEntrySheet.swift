import SaifuLogCore
import SwiftUI

/// ⑥ 直す。AI や辞書の読み取りが違っていた 1 件の記録を直して保存する、下から出すシート。
///
/// 状態と操作は `EditEntryModel` が持つ。ここは表示と、文字の大きさに合わせた出し方だけを受け持つ。
/// 直した内容があるときは、下へのスワイプでもキャンセルでも、捨ててよいかを確かめてから閉じる。
struct EditEntrySheet: View {
    @Bindable var model: EditEntryModel

    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @FocusState private var focusedField: Field?

    private enum Field: Hashable {
        case amount
        case memo
    }

    var body: some View {
        NavigationStack {
            form
                .navigationTitle("記録を直す")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("キャンセル", role: .cancel) {
                            if model.requestClose() { dismiss() }
                        }
                    }
                }
                .alert(
                    model.failure?.title ?? Text(verbatim: ""),
                    isPresented: showsFailure,
                    presenting: model.failure
                ) { _ in
                    Button("OK", role: .cancel) {}
                } message: { _ in
                    Text("保存に失敗しました。もう一度お試しください。")
                }
                .confirmationDialog(
                    "この記録を削除しますか？",
                    isPresented: $model.showsDeleteConfirmation,
                    titleVisibility: .visible
                ) {
                    Button("削除", role: .destructive) {
                        if model.delete() { dismiss() }
                    }
                } message: {
                    Text("\(model.deletionSummary)の記録を削除します。この操作は取り消せません。")
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
        // アクセシビリティサイズの文字では、半分の高さに金額の欄も収まらないので、最初から全体で出す。
        .presentationDetents(dynamicTypeSize.isAccessibilitySize ? [.large] : [.medium, .large])
        // 直した内容があるときは、下へのスワイプで黙って閉じない。止めたスワイプは確認に回す。
        .interactiveDismissDisabled(model.hasChanges)
        .background(SheetDismissAttemptObserver { model.showsDiscardConfirmation = true })
    }

    private var form: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if !model.originalText.isEmpty {
                    sentText
                }
                amountSection
                memoSection
                kindSection
                if !model.isIncome {
                    categorySection
                }
                dateSection
                deleteButton
            }
            .foregroundStyle(Theme.ink)
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Theme.background)
        // 保存のボタンは画面の下に置き続ける。金額の数字のキーボードには確定のキーが無いので、キーボードを出したまま
        // 押せる場所に置く（予算を決める画面と同じ）。
        .safeAreaInset(edge: .bottom, spacing: 0) {
            saveButton
                .padding(.horizontal)
                .padding(.vertical, 8)
                .background(Theme.background)
        }
    }

    /// 送った文。読み取りと見比べて、どこを直せばよいかを分かりやすくする。例の文と同じく訳さない（利用者が打った文）。
    private var sentText: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("送った文")
                .font(.footnote)
                .foregroundStyle(Theme.inkSecondary)
            Text(verbatim: model.originalText)
                .font(.subheadline)
        }
        .accessibilityElement(children: .combine)
    }

    /// 金額の入力欄。「¥」を前に置き、入れた数字は 3 桁ごとにカンマを入れて見せる。保存できない額なら、下に理由を出す。
    private var amountSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionLabel("金額")
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(verbatim: "¥")
                    .foregroundStyle(Theme.inkSecondary)
                    .accessibilityHidden(true)
                TextField(text: $model.amountText, prompt: Text(verbatim: "0").foregroundStyle(Theme.inkSecondary)) {
                    Text("金額（円）")
                }
                .keyboardType(.numberPad)
                .focused($focusedField, equals: .amount)
                .onChange(of: model.amountText) { model.normalizeAmountText() }
                .accessibilityHint(model.amountIssue?.message ?? Text(verbatim: ""))
            }
            .font(.title.bold())
            .monospacedDigit()
            .lineLimit(1)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .background(Theme.surface, in: .rect(cornerRadius: 16))
            // 「¥」や枠の余白を押しても入力欄にフォーカスが入るようにする（予算を決める画面と同じ）。
            .contentShape(.rect(cornerRadius: 16))
            .simultaneousGesture(TapGesture().onEnded { focusedField = .amount })
            // 入力欄の文字は縮められない（1 行のまま横にはみ出す）。最大の文字サイズでは桁の多い額が枠に
            // 収まらず、打った桁が見えなくなるので、大きさに上限を設ける。
            .dynamicTypeSize(...DynamicTypeSize.accessibility1)
            if let issue = model.amountIssue {
                // 保存できない理由は、注意の色だけでなくアイコンと文で伝える。
                Label {
                    issue.message
                } icon: {
                    Image(systemName: "exclamationmark.circle.fill")
                }
                .font(.footnote)
                .foregroundStyle(Theme.danger)
            }
        }
    }

    private var memoSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionLabel("品目")
            TextField(text: $model.memo, prompt: Text("空欄でもかまいません").foregroundStyle(Theme.inkSecondary)) {
                Text("品目")
            }
            .focused($focusedField, equals: .memo)
            .submitLabel(.done)
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .background(Theme.surface, in: .rect(cornerRadius: 16))
            .contentShape(.rect(cornerRadius: 16))
            .simultaneousGesture(TapGesture().onEnded { focusedField = .memo })
        }
    }

    /// 支出か収入か。AI が「もらった」「返金」などを読み違えたときに直せるようにする。
    ///
    /// アクセシビリティサイズの文字では縦に積む。横に並べて収まるかで選ぶ（ViewThatFits）と、選んだ側に付く
    /// チェックの印の幅までは見込まれず、「収 / 入」のように語の途中で折り返されるため。
    @ViewBuilder
    private var kindSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionLabel("種類")
            if dynamicTypeSize.isAccessibilitySize {
                VStack(spacing: 8) { kindChoices }
            } else {
                HStack(spacing: 8) { kindChoices }
            }
        }
    }

    @ViewBuilder
    private var kindChoices: some View {
        ChoiceChip(isSelected: !model.isIncome) {
            model.isIncome = false
        } label: {
            Text("支出")
        }
        ChoiceChip(isSelected: model.isIncome) {
            model.isIncome = true
        } label: {
            Text("収入")
        }
    }

    /// カテゴリ。8 種を色と記号つきで並べ、1 つを選ぶ。アクセシビリティサイズの文字では 1 列にする。
    private var categorySection: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionLabel("カテゴリ")
            LazyVGrid(columns: categoryColumns, spacing: 8) {
                ForEach(EntryCategory.allCases) { category in
                    ChoiceChip(isSelected: model.category == category) {
                        model.category = category
                    } label: {
                        CategoryLabel(category: category)
                    }
                }
            }
        }
    }

    private var categoryColumns: [GridItem] {
        let count = dynamicTypeSize.isAccessibilitySize ? 1 : 2
        return Array(repeating: GridItem(.flexible(), spacing: 8), count: count)
    }

    /// 日付。時刻は直さない（元の記録の時刻を残す）。今日より先の日付は、注意を出すだけで保存できる
    /// （払う予定の家賃のように、先の日付で記録することがあるため）。
    private var dateSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionLabel("日付")
            DatePicker(selection: $model.day, displayedComponents: .date) {
                Text("日付")
            }
            .labelsHidden()
            .frame(minHeight: 44)
            if model.isFutureDate {
                Label {
                    Text("今日より先の日付です。予定の記録でなければ、日付を確かめてください。")
                } icon: {
                    Image(systemName: "calendar.badge.exclamationmark")
                }
                .font(.footnote)
                .foregroundStyle(Theme.inkSecondary)
            }
        }
    }

    private var deleteButton: some View {
        Button(role: .destructive) {
            model.showsDeleteConfirmation = true
        } label: {
            Text("この記録を削除")
                .frame(maxWidth: .infinity, minHeight: 44)
                .contentShape(.rect)
        }
        .foregroundStyle(Theme.danger)
        .padding(.top, 8)
    }

    private var saveButton: some View {
        Button {
            if model.save() { dismiss() }
        } label: {
            Text("保存")
                .fontWeight(.semibold)
                // 押せるときは山吹の塗りの上なので墨（Theme の説明）。押せないときは灰色のガラスの上なので、
                // 補足の文字の色にする（予算を決める画面・送信ボタンと同じ）。
                .foregroundStyle(model.canSave ? Theme.onAccent : Theme.inkSecondary)
                .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.glassProminent)
        .tint(Theme.accentFill)
        .disabled(!model.canSave)
    }

    private var showsFailure: Binding<Bool> {
        Binding(get: { model.failure != nil }, set: { if !$0 { model.failure = nil } })
    }
}

/// 欄の見出し。VoiceOver では見出しとして読ませ、見出しの移動で欄をたどれるようにする。
private struct SectionLabel: View {
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

/// 選べるものの 1 つ（種類・カテゴリ）。選んだものは枠と印で示す（色だけに頼らない）。
///
/// 山吹は保存のボタンの塗りにだけ使うので、選んだ印には使わない（墨の枠とチェックの印にする）。
private struct ChoiceChip<Content: View>: View {
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
        // 選んだことは VoiceOver にも「選択中」と読ませる。
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// カテゴリの色の丸と名前（記録の吹き出しの横の丸と同じ色と記号）。
private struct CategoryLabel: View {
    let category: EntryCategory

    @ScaledMetric(relativeTo: .body) private var iconSize = 24

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: category.symbolName)
                .font(.system(size: iconSize * 0.5, weight: .semibold))
                .foregroundStyle(Theme.onCategory)
                .frame(width: iconSize, height: iconSize)
                .background(Theme.color(for: category), in: .circle)
                // 丸はダークでもライトの色で塗る（EntryBubble と同じ理由）。
                .environment(\.colorScheme, .light)
                .accessibilityHidden(true)
            Text(category.label)
        }
    }
}

private extension EditEntryModel.Failure {
    var title: Text {
        switch self {
        case .save: Text("直した内容を保存できませんでした")
        case .delete: Text("削除できませんでした")
        }
    }
}

extension EntryAmountIssue {
    /// 金額を保存できない理由の文。
    var message: Text {
        switch self {
        case .missing: Text("金額を入れてください。")
        case .notPositive: Text("¥1 以上の金額にしてください。")
        case .tooLarge: Text("\(YenFormatter.string(from: EntryAmountInput.maximumAmount)) までの金額にしてください。")
        }
    }
}

#Preview("支出") {
    if let container = try? ModelContainerFactory.makeInMemoryContainer() {
        let entry = Entry(
            amount: 850, isIncome: false, category: .food, memo: "ランチ",
            spentAt: .now, source: .text, originalText: "ランチ 850"
        )
        let _ = container.mainContext.insert(entry)
        Color.clear
            .sheet(isPresented: .constant(true)) {
                EditEntrySheet(model: EditEntryModel(
                    entry: entry, store: EntryStore(context: container.mainContext), calendar: .current
                ))
            }
    }
}
