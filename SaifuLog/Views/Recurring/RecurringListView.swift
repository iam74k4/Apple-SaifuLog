import SaifuLogCore
import SwiftData
import SwiftUI

/// 設定の「くり返しの記録」。家賃・サブスク・給料のように毎月同じ記録の一覧。行を押すと直せ、左へのスワイプでやめる。
///
/// 状態と操作は `RecurringListModel` が持つ。ここは表示と、シート・確認・アラートの出し入れだけ。
struct RecurringListView: View {
    @Bindable var model: RecurringListModel

    @Environment(\.categoryCatalog) private var catalog

    var body: some View {
        List {
            Section {
                if model.rows.isEmpty {
                    Text("まだありません。家賃・サブスク・給料のように毎月同じ記録を足すと、決めた日に自動で記録します。")
                        .foregroundStyle(Theme.inkSecondary)
                        .listRowBackground(Theme.surface)
                }
                ForEach(model.rows) { row in
                    rowView(row)
                        // やめる前に確かめる（破壊の役割にすると、確かめる前に行が消えて見えるので、色だけ付ける）。
                        .swipeActions {
                            Button {
                                model.requestDeletion(row)
                            } label: {
                                Label("やめる", systemImage: "trash")
                            }
                            .tint(Theme.dangerFill)
                        }
                        .accessibilityAction(named: "やめる") { model.requestDeletion(row) }
                        .listRowBackground(Theme.surface)
                }
                Button {
                    model.presentCreation()
                } label: {
                    Label("くり返しの記録を足す", systemImage: "plus")
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        .contentShape(.rect)
                }
                .accessibilityHint("金額と毎月の日を決めて、くり返しの記録を足します")
                .listRowBackground(Theme.surface)
            } footer: {
                Text("記録する日を過ぎて、最初にアプリを開いたときに記録し、ホームの返事でお知らせします。取り消すと、その月の分はもう記録しません。")
                    .foregroundStyle(Theme.inkSecondary)
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .navigationTitle(Text(.recurringTitle))
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $model.editor, onDismiss: { model.reload() }) { editor in
            RecurringEditorSheet(model: editor)
        }
        .confirmationDialog(
            deletionTitle,
            isPresented: showsDeletionConfirmation,
            titleVisibility: .visible,
            presenting: model.pendingDeletion
        ) { row in
            Button("やめる", role: .destructive) { model.confirmDeletion(row) }
        } message: { _ in
            Text("次の月から記録しなくなります。これまでに記録したものは残ります。")
        }
        .alert(
            model.failure == .load ? Text("読み込めませんでした") : Text("保存できませんでした"),
            isPresented: showsFailure
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("もう一度お試しください。")
        }
        // iCloud で届いたほかの端末のくり返しの記録も一覧に出す。
        .onReceive(StoreChanges.remote) { _ in model.reload() }
    }

    /// 1 行（印・品目・毎月の日とカテゴリ・次に記録する日・金額）。押すと直すシートを開く。
    private func rowView(_ row: RecurringListModel.Row) -> some View {
        Button {
            model.presentEditing(row)
        } label: {
            HStack(spacing: 12) {
                tile(row)
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: title(row))
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Theme.ink)
                    detail(row)
                        .font(.caption)
                        .foregroundStyle(Theme.inkSecondary)
                }
                Spacer(minLength: 8)
                Text(verbatim: row.isIncome ? YenFormatter.signedString(from: row.amount) : YenFormatter.string(from: row.amount))
                    .font(.body.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(row.isIncome ? Theme.income : Theme.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
            }
            .frame(minHeight: 44)
            .contentShape(.rect)
        }
        .accessibilityHint("金額や毎月の日を直します")
    }

    /// 見出し（品目。無ければカテゴリ名か「収入」）。
    private func title(_ row: RecurringListModel.Row) -> String {
        if !row.memo.isEmpty { return row.memo }
        return row.isIncome ? String(localized: "収入") : catalog.localizedName(for: row.category)
    }

    /// 「毎月25日・住居・次は11月25日」。
    private func detail(_ row: RecurringListModel.Row) -> Text {
        let kind = row.isIncome ? String(localized: "収入") : catalog.localizedName(for: row.category)
        let every = RecurringTexts.spokenEveryMonth(row.dayOfMonth)
        if let next = row.nextDate {
            return Text("\(every)・\(kind)・次は\(next.formatted(.dateTime.month().day()))")
        }
        return Text(verbatim: "\(every)・\(kind)")
    }

    private func tile(_ row: RecurringListModel.Row) -> some View {
        Image(systemName: row.isIncome ? "yensign" : catalog.symbolName(for: row.category))
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(Theme.onCategory)
            .frame(width: 32, height: 32)
            .background(row.isIncome ? Theme.income : catalog.color(for: row.category), in: .rect(cornerRadius: 9))
            // 印はダークでもライトの色で塗る（返事の行と同じ。白い記号を読めるように）。
            .environment(\.colorScheme, .light)
            .accessibilityHidden(true)
    }

    private var deletionTitle: Text {
        let name = model.pendingDeletion.map(title) ?? ""
        return Text("「\(name)」のくり返しの記録をやめますか？")
    }

    private var showsDeletionConfirmation: Binding<Bool> {
        Binding(get: { model.pendingDeletion != nil }, set: { if !$0 { model.pendingDeletion = nil } })
    }

    private var showsFailure: Binding<Bool> {
        Binding(get: { model.failure != nil }, set: { if !$0 { model.failure = nil } })
    }
}

extension LocalizedStringResource {
    /// 設定の「くり返しの記録」（行・一覧の画面の題名）。
    static let recurringTitle = LocalizedStringResource(
        "くり返しの記録", comment: "設定の行と、その一覧の画面の題名。家賃・サブスク・給料のように毎月同じ記録を、決めた日に自動で記録する"
    )
}

#Preview {
    if let container = try? ModelContainerFactory.makeInMemoryContainer() {
        let store = RecurringEntryStore(context: container.mainContext)
        let _ = try? store.create(
            RecurringDraft(amount: 80_000, memo: "家賃", isIncome: false, category: .other, dayOfMonth: 25),
            startMonth: RecurringMonth(containing: .now, timeZone: .current)
        )
        NavigationStack {
            RecurringListView(model: RecurringListModel(store: store))
        }
    }
}
