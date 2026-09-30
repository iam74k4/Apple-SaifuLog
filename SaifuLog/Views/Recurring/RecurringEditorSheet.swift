import SaifuLogCore
import SwiftData
import SwiftUI

/// くり返しの記録を作る・直すシート。金額・品目・支出か収入か・カテゴリ・毎月の日を決める。
///
/// 状態と操作は `RecurringEditorModel` が持つ。見た目は ⑥ 直すのシートとそろえる（同じ欄の部品を使う）。
struct RecurringEditorSheet: View {
    @Bindable var model: RecurringEditorModel

    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.categoryCatalog) private var catalog
    @FocusState private var focusedField: Field?

    private enum Field: Hashable {
        case amount
        case memo
    }

    var body: some View {
        NavigationStack {
            form
                .navigationTitle(model.mode == .create ? Text("くり返しの記録を足す") : Text("くり返しの記録を直す"))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("キャンセル", role: .cancel) { dismiss() }
                    }
                }
                .alert(
                    model.failure == .delete ? Text("やめられませんでした") : Text("保存できませんでした"),
                    isPresented: showsFailure
                ) {
                    Button("OK", role: .cancel) {}
                } message: {
                    Text("もう一度お試しください。")
                }
                .confirmationDialog(
                    "このくり返しの記録をやめますか？",
                    isPresented: $model.showsDeleteConfirmation,
                    titleVisibility: .visible
                ) {
                    Button("やめる", role: .destructive) {
                        if model.delete() { dismiss() }
                    }
                } message: {
                    Text("次の月から記録しなくなります。これまでに記録したものは残ります。")
                }
        }
        .presentationDetents([.large])
        // 入れた内容を、下へのスワイプで黙って捨てない（直すシートと同じ。キャンセルは押せば閉じる）。
        .interactiveDismissDisabled(model.canSave)
    }

    private var form: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                amountSection
                memoSection
                kindSection
                if !model.isIncome {
                    categorySection
                }
                daySection
                scheduleSection
                if case .edit = model.mode {
                    deleteButton
                }
            }
            .foregroundStyle(Theme.ink)
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Theme.background)
        // 保存のボタンは画面の下に置き続ける（直すシート・予算を決める画面と同じ。数字のキーボードには確定のキーが無いため）。
        .safeAreaInset(edge: .bottom, spacing: 0) {
            saveButton
                .padding(.horizontal)
                .padding(.vertical, 8)
                .background(Theme.background)
        }
    }

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
            .contentShape(.rect(cornerRadius: 16))
            .simultaneousGesture(TapGesture().onEnded { focusedField = .amount })
            .dynamicTypeSize(...DynamicTypeSize.accessibility1)
            if let issue = model.amountIssue {
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
            TextField(text: $model.memo, prompt: Text("家賃・サブスク・給料 など").foregroundStyle(Theme.inkSecondary)) {
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

    private var categorySection: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionLabel("カテゴリ")
            LazyVGrid(columns: categoryColumns, spacing: 8) {
                ForEach(catalog.all) { category in
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

    /// 毎月の日（1〜31。31 は「月末」）。押すと日を選ぶメニューを開く。
    private var daySection: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionLabel("記録する日")
            Menu {
                Picker(selection: $model.dayOfMonth) {
                    ForEach(RecurringSchedule.dayRange, id: \.self) { day in
                        RecurringTexts.dayChoice(day).tag(day)
                    }
                } label: {
                    Text("記録する日")
                }
            } label: {
                HStack(spacing: 8) {
                    RecurringTexts.everyMonth(model.dayOfMonth)
                        .foregroundStyle(Theme.ink)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.up.chevron.down")
                        .imageScale(.small)
                        .foregroundStyle(Theme.inkSecondary)
                        .accessibilityHidden(true)
                }
                .padding(.horizontal, 16)
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .background(Theme.surface, in: .rect(cornerRadius: 16))
                .contentShape(.rect(cornerRadius: 16))
            }
            .accessibilityLabel(Text("記録する日"))
            .accessibilityValue(RecurringTexts.everyMonth(model.dayOfMonth))
            if (29...30).contains(model.dayOfMonth) {
                Text("その日が無い月は、月末に記録します。")
                    .font(.footnote)
                    .foregroundStyle(Theme.inkSecondary)
            }
        }
    }

    /// いつ記録するか（今月の分も記録するかの切り替えと、すぐ記録する分・次に記録する日）。
    private var scheduleSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            if model.showsThisMonthChoice {
                Toggle(isOn: $model.includesThisMonth) {
                    Text("今月の分も記録する")
                        .foregroundStyle(Theme.ink)
                }
                .tint(Theme.accentFill)
                .frame(minHeight: 44)
            }
            Label {
                VStack(alignment: .leading, spacing: 4) {
                    if let immediate = model.recordsImmediately {
                        Text("保存すると、\(immediate.formatted(.dateTime.month().day()))の分をすぐ記録します。")
                    }
                    if let next = model.nextDate {
                        Text("次は\(next.formatted(.dateTime.month().day()))に記録します。")
                    }
                    Text("記録する日を過ぎて、最初にアプリを開いたときに記録します。")
                        .foregroundStyle(Theme.inkSecondary)
                }
            } icon: {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .foregroundStyle(Theme.inkSecondary)
            }
            .font(.footnote)
            .accessibilityElement(children: .combine)
        }
    }

    private var deleteButton: some View {
        Button(role: .destructive) {
            model.showsDeleteConfirmation = true
        } label: {
            Text("このくり返しの記録をやめる")
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

/// くり返しの記録の画面の言葉（毎月の日）。
enum RecurringTexts {
    /// 「毎月25日」「毎月末」。
    static func everyMonth(_ day: Int) -> Text {
        day >= RecurringSchedule.dayRange.upperBound ? Text("毎月末") : Text("毎月\(day)日")
    }

    /// 日を選ぶメニューの 1 つ（「25日」「月末」）。
    static func dayChoice(_ day: Int) -> Text {
        day >= RecurringSchedule.dayRange.upperBound ? Text("月末") : Text("\(day)日")
    }

    /// 読み上げに使う「毎月25日」。
    static func spokenEveryMonth(_ day: Int) -> String {
        day >= RecurringSchedule.dayRange.upperBound ? String(localized: "毎月末") : String(localized: "毎月\(day)日")
    }
}

#Preview {
    if let container = try? ModelContainerFactory.makeInMemoryContainer() {
        Color.clear
            .sheet(isPresented: .constant(true)) {
                RecurringEditorSheet(model: RecurringEditorModel(
                    creating: RecurringDraft(amount: 80_000, memo: "家賃", isIncome: false, category: .other, dayOfMonth: 25),
                    store: RecurringEntryStore(context: container.mainContext), timeZone: .current
                ))
            }
    }
}
