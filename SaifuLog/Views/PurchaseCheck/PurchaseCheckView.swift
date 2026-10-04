import SaifuLogCore
import SwiftData
import SwiftUI

struct PurchaseCheckView: View {
    @Bindable var model: PurchaseCheckModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.calendar) private var calendar
    @Environment(\.scenePhase) private var scenePhase
    @FocusState private var editing: Bool

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    inputs
                    if model.loadFailed {
                        LoadFailedView(retry: { model.reload() })
                    } else if let analysis = model.analysis {
                        if analysis.outlook.budget == nil {
                            VStack(alignment: .leading, spacing: 12) {
                                Label("まずは月の予算から", systemImage: "wallet.bifold")
                                    .font(.headline)
                                Button("予算を決める") { model.showBudget() }.buttonStyle(.glassProminent).foregroundStyle(Theme.onAccent)
                            }.checkCard()
                        } else if let comparison = model.comparison {
                            comparisonCard(comparison, analysis: analysis)
                            if let projected = comparison.projectedWithPurchase {
                                choicesCard(analysis, projected: projected, comparison: comparison)
                            } else {
                                Label("記録が増えると、いつもの支出も組み替えられます", systemImage: "chart.bar.xaxis")
                                    .font(.subheadline).foregroundStyle(Theme.inkSecondary)
                            }
                            evidence(analysis)
                        } else {
                            Label("金額を入れると、ここで比べられます", systemImage: "chart.bar.xaxis")
                                .font(.subheadline).foregroundStyle(Theme.inkSecondary)
                                .frame(maxWidth: .infinity, minHeight: 100)
                        }
                    }
                }.padding()
                    .containerRelativeFrame(.horizontal)
            }
            #if DEBUG
            .defaultScrollAnchor(model.screenshotScrollsToBottom ? .bottom : nil)
            #endif
            .scrollEdgeEffectStyle(.hard, for: .top)
            .background(Theme.background)
            .foregroundStyle(Theme.ink)
            .navigationTitle("買う前チェック")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("閉じる") { dismiss() } }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("完了") { editing = false }
                }
            }
            .sheet(item: $model.premiumSheet) { PremiumSheet(model: $0) }
            .sheet(item: $model.budgetSetup, onDismiss: { model.reload() }) { BudgetSetupSheet(model: $0) }
        }
        .onAppear { model.reload(calendar: calendar) }
        .onChange(of: calendar) { _, value in model.reload(calendar: value) }
        .onReceive(NotificationCenter.default.publisher(for: ModelContext.didSave)) { _ in model.reload() }
        .onReceive(StoreChanges.remote) { model.reload() }
        .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in model.reload() }
        .onChange(of: scenePhase) { _, phase in if phase == .active { model.reload() } }
    }

    private var inputs: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("買うと、どう変わる？", systemImage: "bag")
                .font(.title2.bold())
            amountField("買いたいものの金額", text: $model.amountText, id: "purchase-check-amount", large: true)
            if !model.amountText.isEmpty, model.amount == nil {
                Text("1円以上、999,999,999,999円以下で入力してください。")
                    .font(.footnote).foregroundStyle(Theme.danger)
            }
            Divider()
            amountField("月末まで残しておく額", text: $model.reserveText, id: "purchase-check-reserve", large: false)
            if model.reserve == nil {
                Text("残しておく額は999,999,999,999円以下で入力してください。")
                    .font(.footnote).foregroundStyle(Theme.danger)
            }
        }.checkCard()
    }

    private func amountField(_ title: LocalizedStringResource, text: Binding<String>, id: String, large: Bool) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.caption).foregroundStyle(Theme.inkSecondary)
            HStack(alignment: .firstTextBaseline) {
                Text(verbatim: "¥").foregroundStyle(Theme.inkSecondary)
                TextField(text: text, prompt: Text(verbatim: "0")) { Text(title) }
                    .keyboardType(.numberPad)
                    .font(large ? .largeTitle.bold() : .title3.bold()).monospacedDigit()
                    .focused($editing)
                    .accessibilityIdentifier(id)
                    .onChange(of: text.wrappedValue) { _, value in
                        let formatted = EntryAmountInput.formatted(value)
                        if formatted != value { text.wrappedValue = formatted }
                    }
            }
        }
    }

    private func comparisonCard(_ result: PurchaseCheck.Comparison, analysis: PurchaseCheck) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("月末までに使える分").font(.headline)
            PurchaseComparisonBars(rows: [
                .init(title: "見送る", amount: result.withoutPurchase, symbol: "pause.circle"),
                .init(title: "買う", amount: result.withPurchase, symbol: "bag")
            ])
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: "calendar").accessibilityHidden(true)
                Text("買った後は1日 \(YenFormatter.string(from: result.dailyWithPurchase))")
                    .font(.subheadline.weight(.semibold))
            }
            if result.withPurchase < 0 {
                Label("買うと、確保したい額を下回ります", systemImage: "exclamationmark.circle")
                    .foregroundStyle(Theme.danger).font(.subheadline)
            }
            Divider()
            PurchaseBudgetStrip(outlook: analysis.outlook, reserve: model.reserve ?? 0)
            Text("固定費・残す額を確保済み。口座残高ではありません。")
                .font(.caption).foregroundStyle(Theme.inkSecondary)
        }.checkCard()
    }

    private func choicesCard(_ analysis: PurchaseCheck, projected: Int, comparison: PurchaseCheck.Comparison) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            Label("いつもの支出を、欲しいものへ", systemImage: "arrow.triangle.branch").font(.headline)
            if model.purchases.status.unlocksPremium, !analysis.habits.isEmpty {
                PurchaseCoverageRing(saved: comparison.adjustment, price: model.amount ?? 1)
                ForEach(analysis.habits) { habit in
                    PurchaseHabitCard(habit: habit, count: model.reduction(for: habit)) { model.setReduction($0, for: habit) }
                }
                Divider()
                Text("いつものペースで暮らしたら").font(.subheadline.weight(.semibold))
                PurchaseComparisonBars(rows: [
                    .init(title: "そのまま買う", amount: projected, symbol: "bag"),
                    .init(title: "組み替えて買う", amount: comparison.projectedWithAdjustment ?? projected, symbol: "arrow.triangle.branch")
                ])
            } else {
                Text("いつものペースで暮らしたら").font(.subheadline.weight(.semibold))
                PurchaseComparisonBars(rows: [
                    .init(title: "見送る", amount: comparison.projectedWithoutPurchase ?? 0, symbol: "pause.circle"),
                    .init(title: "買う", amount: projected, symbol: "bag")
                ])
                if analysis.habits.isEmpty {
                    Label("組み替えられるカフェ・娯楽の記録がまだありません", systemImage: "cup.and.saucer")
                        .font(.subheadline).foregroundStyle(Theme.inkSecondary)
                } else {
                    HStack(spacing: 12) {
                        Image(systemName: "cup.and.saucer.fill").font(.title2)
                        Image(systemName: "arrow.right").foregroundStyle(Theme.inkSecondary)
                        Image(systemName: "bag").font(.title2)
                        Spacer()
                        Image(systemName: "lock.fill").foregroundStyle(Theme.inkSecondary)
                    }.accessibilityHidden(true)
                    Button("支出の組み替えを試す") { model.showPremium() }.buttonStyle(.glassProminent).foregroundStyle(Theme.onAccent)
                    Text("プレミアムで回数を減らす案を比較")
                        .font(.caption).foregroundStyle(Theme.inkSecondary)
                }
            }
            Text("月末の余裕の目安。記録がない日は支出0円として試算。")
                .font(.caption).foregroundStyle(Theme.inkSecondary)
        }.checkCard()
    }

    private func evidence(_ analysis: PurchaseCheck) -> some View {
        DisclosureGroup("計算に使った記録") {
            VStack(alignment: .leading, spacing: 12) {
                moneyRow("今月の予算", analysis.outlook.budget ?? 0)
                moneyRow("記録済みの支出（先の日付も含む）", analysis.outlook.spent)
                moneyRow("未記録の固定費", analysis.outlook.plannedFixedTotal)
                ForEach(analysis.outlook.plannedFixed) { item in
                    HStack { Text(verbatim: item.memo); Spacer(); Text(verbatim: YenFormatter.string(from: item.amount)) }.font(.caption)
                }
                Text("今日を含む残り\(analysis.outlook.remainingDays)日で日割りします。収入は予算に足しません。")
                Text("残しておく額は、この試算だけで確保します。空欄は0円です。")
                Text("試算だけです。支出や予算は変更しません。")
                if let projected = analysis.projectedVariable {
                    moneyRow("これからの日々の支出見込み", projected)
                    Text("過去28日中\(analysis.historyDays)日の支出から、明日以降\(analysis.futureDays)日分を試算。記録のない日は0円として計算します。")
                    Text("今日これから使う分は含みません。固定費と先の日付で記録した支出は別に確保済みです。残しておく額を引いた目安で、実際の残高の予測ではありません。")
                    Text("回数の上限は過去28日の頻度、金額は中央値が基準です。節約分は将来の支出見込みだけから引き、今ある予算には足しません。")
                    ForEach(analysis.habits) { habit in
                        VStack(alignment: .leading) {
                            Text(verbatim: habit.name).fontWeight(.semibold)
                            Text("過去28日で\(habit.count)回・1回の目安 \(YenFormatter.string(from: habit.typicalAmount))")
                        }
                    }
                } else {
                    Text("いつもの支出の試算には、過去28日で7日以上、かつ14日以上前からの支出の記録が必要です。買い物前後の予算は上で比べられます。")
                }
                Text("カフェ・娯楽で同じ品目を3回以上記録すると、回数を減らした場合を試せます。月末までの回数の目安が1回未満の品目は出しません。")
                Button("予算を変更") { model.showBudget() }
            }.font(.footnote).foregroundStyle(Theme.inkSecondary).padding(.top, 12)
        }.checkCard()
    }

    private func moneyRow(_ title: LocalizedStringResource, _ amount: Int) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
            Text(verbatim: YenFormatter.string(from: amount)).font(.headline).monospacedDigit().foregroundStyle(Theme.ink)
        }.accessibilityElement(children: .combine)
    }
}

private extension View {
    func checkCard() -> some View {
        padding(16).frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.surface, in: .rect(cornerRadius: 20))
    }
}
