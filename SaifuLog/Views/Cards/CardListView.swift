import SaifuLogCore
import SwiftData
import SwiftUI

/// 設定の「カード」。登録したクレジットカードの一覧。カードごとに、締め日と引き落とし日、今の締めの利用額、次の引き落とし（日と額）を
/// 出す。行を押すとその締めの記録の一覧へ進み、「直す」でカードを直す。左へのスワイプで削除し、「編集」で並べ替える。
///
/// 状態と操作は `CardListModel` が持つ。ここは表示と、シート・確認・アラートの出し入れだけ。
struct CardListView: View {
    @Bindable var model: CardListModel

    @Environment(\.calendar) private var calendar

    var body: some View {
        List {
            cardSection
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .navigationTitle(Text(.cardsTitle))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if model.cards.count > 1 {
                ToolbarItem(placement: .topBarTrailing) {
                    EditButton()
                }
            }
        }
        .sheet(item: $model.editor) { editor in
            CardEditorSheet(model: editor)
        }
        .confirmationDialog(
            Text("「\(model.pendingDeletion?.card.name ?? "")」を削除しますか？"),
            isPresented: showsDeletionConfirmation,
            titleVisibility: .visible,
            presenting: model.pendingDeletion
        ) { deletion in
            Button("削除", role: .destructive) { model.confirmDeletion(deletion) }
        } message: { deletion in
            if deletion.entryCount > 0 {
                Text("このカードの記録 \(deletion.entryCount) 件は「現金・その他」になります。記録そのものは消えません。")
            } else {
                Text("記録は消えません。")
            }
        }
        .alert(
            model.failure == .load ? Text("読み込めませんでした") : Text("保存できませんでした"),
            isPresented: showsFailure
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("もう一度お試しください。")
        }
    }

    private var cardSection: some View {
        Section {
            ForEach(model.cards) { card in
                cardRow(card)
                    .swipeActions {
                        Button {
                            model.requestDeletion(card)
                        } label: {
                            Label("削除", systemImage: "trash")
                        }
                        .tint(Theme.dangerFill)
                        Button {
                            model.presentEditing(card)
                        } label: {
                            Label("直す", systemImage: "pencil")
                        }
                    }
                    .accessibilityAction(named: "直す") { model.presentEditing(card) }
                    .accessibilityAction(named: "削除") { model.requestDeletion(card) }
                    .accessibilityAction(named: "前へ移動") { model.moveEarlier(card) }
                    .accessibilityAction(named: "後ろへ移動") { model.moveLater(card) }
                    .listRowBackground(Theme.surface)
            }
            .onMove { model.move(fromOffsets: $0, toOffset: $1) }
            Button {
                model.presentCreation()
            } label: {
                Label("カードを登録", systemImage: "plus")
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .contentShape(.rect)
            }
            .disabled(!model.canCreate)
            .accessibilityHint("名前・締め日・引き落とし日を決めて、カードを登録します")
            .accessibilityIdentifier(AccessibilityID.Cards.addButton)
            .listRowBackground(Theme.surface)
        } footer: {
            // 説明はこの 1 つだけにする（使った日の支出として数えること・引き落としを記録しないことは、引き落としの文を
            // 送ったときの確認で伝える）。
            Group {
                if model.canCreate {
                    Text("「ランチ 850 楽天カードで」のように送ると、そのカードの記録になります。")
                } else {
                    Text("登録できるのは \(PaymentCard.maximumCount) 枚までです。")
                }
            }
            .foregroundStyle(Theme.inkSecondary)
        }
    }

    private func cardRow(_ card: PaymentCard) -> some View {
        NavigationLink {
            CardStatementDestination(list: model, card: card)
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Image(systemName: "creditcard")
                        .foregroundStyle(SettingsRowIcon.indigo)
                        .accessibilityHidden(true)
                    Text(verbatim: card.name)
                        .font(.headline)
                        .foregroundStyle(Theme.ink)
                    if card.isDefault {
                        Text("いつものカード")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Theme.inkSecondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(Theme.background, in: .capsule)
                    }
                }
                Text(verbatim: CardTexts.schedule(of: card))
                    .font(.footnote)
                    .foregroundStyle(Theme.inkSecondary)
                if let overview = model.overviews[card.id] {
                    LabeledContent {
                        Text(YenFormatter.string(from: overview.current.total))
                            .monospacedDigit()
                            .foregroundStyle(Theme.ink)
                    } label: {
                        Text("今の締め（\(CardTexts.period(overview.current.statement, calendar: calendar))）")
                            .foregroundStyle(Theme.inkSecondary)
                    }
                    .font(.subheadline)
                    if let next = overview.next {
                        LabeledContent {
                            Text(YenFormatter.string(from: next.total))
                                .monospacedDigit()
                                .fontWeight(.semibold)
                                .foregroundStyle(Theme.ink)
                        } label: {
                            Text("次の引き落とし（\(CardTexts.day(next.statement.paymentDate, calendar: calendar))）")
                                .foregroundStyle(Theme.inkSecondary)
                        }
                        .font(.subheadline)
                    }
                }
            }
            .padding(.vertical, 4)
        }
        .accessibilityElement(children: .combine)
        .accessibilityHint("この締めの記録の一覧を開きます")
        .accessibilityIdentifier(AccessibilityID.Cards.row)
    }

    private var showsDeletionConfirmation: Binding<Bool> {
        Binding(get: { model.pendingDeletion != nil }, set: { if !$0 { model.pendingDeletion = nil } })
    }

    private var showsFailure: Binding<Bool> {
        Binding(get: { model.failure != nil }, set: { if !$0 { model.failure = nil } })
    }
}

/// 締めの記録の画面を、進んだときに 1 回だけ作る（一覧を描き直すたびに記録を読み直さないため）。
private struct CardStatementDestination: View {
    let list: CardListModel
    let card: PaymentCard
    @State private var model: CardStatementModel?

    var body: some View {
        Group {
            if let model {
                CardStatementView(model: model)
            } else {
                Theme.background
            }
        }
        .onAppear {
            if model == nil { model = list.statementModel(for: card) }
        }
    }
}

/// カードの 1 回分の締めの記録。締めの期間・引き落とし日・合計と、その締めで払う記録を並べる。前後の締めへ送れる。
struct CardStatementView: View {
    @Bindable var model: CardStatementModel

    @Environment(\.calendar) private var calendar
    @Environment(\.categoryCatalog) private var catalog

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                if model.entries.isEmpty {
                    Text("この締めのカードの記録はありません")
                        .foregroundStyle(Theme.inkSecondary)
                        .padding(.vertical, 24)
                } else {
                    VStack(spacing: 0) {
                        ForEach(model.entries) { entry in
                            if entry.persistentModelID != model.entries.first?.persistentModelID {
                                Divider()
                            }
                            CategoryEntryRow(
                                entry: entry, today: model.today, calendar: calendar,
                                edit: { model.presentEdit(entry, calendar: calendar, catalog: catalog) },
                                requestDelete: { model.requestDelete(entry, catalog: catalog) }
                            )
                        }
                    }
                    .padding(.horizontal, 16)
                    .background(Theme.surface, in: .rect(cornerRadius: 16))
                }
            }
            .foregroundStyle(Theme.ink)
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollEdgeEffectStyle(.hard, for: .top)
        .background(Theme.background)
        .navigationTitle(Text(verbatim: model.card.name))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { statementSwitcher }
        .sheet(item: $model.editing) { editing in
            EditEntrySheet(model: editing)
        }
        .confirmationDialog(
            "この記録を削除しますか？",
            isPresented: showsDeletionConfirmation,
            titleVisibility: .visible,
            presenting: model.pendingDeletion
        ) { pending in
            Button("削除", role: .destructive) { model.delete(pending) }
        } message: { pending in
            Text("\(pending.summary)の記録を削除します。この操作は取り消せません。")
        }
        .alert("削除できませんでした", isPresented: $model.showsDeleteFailure) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("保存に失敗しました。もう一度お試しください。")
        }
    }

    /// 締めの合計と引き落とし日・件数（締めの期間は下のバーの題）。
    @ViewBuilder
    private var header: some View {
        if let summary = model.summary {
            VStack(alignment: .leading, spacing: 4) {
                Text(YenFormatter.string(from: summary.total))
                    .font(.largeTitle.weight(.bold))
                    .monospacedDigit()
                Text("\(CardTexts.day(summary.statement.paymentDate, calendar: calendar))に引き落とし・\(summary.count) 件")
                    .font(.subheadline)
                    .foregroundStyle(Theme.inkSecondary)
            }
            .accessibilityElement(children: .combine)
        }
    }

    /// 下に浮くバーの締め送り（月の画面の月送りと同じ形。ガラスは中身ではなくバーに置く）。
    @ToolbarContentBuilder
    private var statementSwitcher: some ToolbarContent {
        ToolbarItem(placement: .bottomBar) {
            HStack(spacing: 4) {
                Button(action: model.showPrevious) {
                    Image(systemName: "chevron.left")
                        .frame(width: 44, height: 44)
                        .contentShape(.rect)
                }
                .accessibilityLabel(Text("前の締め"))
                if let summary = model.summary {
                    Text(verbatim: CardTexts.period(summary.statement, calendar: calendar))
                        .font(.headline)
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .padding(.horizontal, 8)
                        .accessibilityAddTraits(.isHeader)
                }
                Button(action: model.showNext) {
                    Image(systemName: "chevron.right")
                        .frame(width: 44, height: 44)
                        .contentShape(.rect)
                }
                .disabled(!model.canShowNext)
                .accessibilityLabel(Text("次の締め"))
            }
        }
        ToolbarSpacer(.flexible, placement: .bottomBar)
    }

    private var showsDeletionConfirmation: Binding<Bool> {
        Binding(get: { model.pendingDeletion != nil }, set: { if !$0 { model.pendingDeletion = nil } })
    }
}

extension LocalizedStringResource {
    /// 設定の「カード」（行・一覧の画面の題名）。
    static let cardsTitle = LocalizedStringResource(
        "カード（設定）", defaultValue: "カード",
        comment: "設定の行と、その一覧の画面の題名。登録したクレジットカードを並べ、登録する・直す・削除する"
    )
}

#Preview {
    if let container = try? ModelContainerFactory.makeInMemoryContainer() {
        let store = CreditCardStore(context: container.mainContext)
        let _ = try? store.create(PaymentCard(id: "", name: "楽天カード", closingDay: 31, paymentDay: 27))
        let _ = try? store.create(PaymentCard(id: "", name: "JCB", closingDay: 15, paymentDay: 10))
        NavigationStack {
            CardListView(model: CardListModel(cards: CardCatalogModel(store: store), context: container.mainContext))
        }
    }
}
