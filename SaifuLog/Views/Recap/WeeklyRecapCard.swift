import SaifuLogCore
import SwiftUI

/// ホームのタイムラインに出す「先週のふりかえり」のカード（アプリからの返事と同じく左寄せ）。
///
/// 見出しと期間、定型文（先週の支出と前の週との差）、AI の一言（プレミアムと体験中で、AI が使える端末だけ）、支出の多い
/// 3 つのカテゴリ、週の目安との比べ、予算についての案内（予算が無ければ「予算を決める」、あれば目安との差が大きいときだけ
/// 「予算を変更」）を出す。カードを押すと先週の内訳（横に進む）を開き、右上の「閉じる」で引っ込める（同じ週にはもう出さない）。
///
/// 山吹の塗りは使わない（塗りの主ボタンが無いため。回答カードと同じ）。「予算を決める」「予算を変更」は tint の文字。
/// VoiceOver では、見出しから目安との比べまでを 1 つのボタンとして読み（「先週の内訳を開きます」）、「閉じる」と予算の
/// ボタンは別の要素にする。
struct WeeklyRecapCard: View {
    let model: WeeklyRecapModel
    /// 先週の内訳を開く。
    let open: () -> Void
    /// カードを閉じる。
    let dismiss: () -> Void
    /// 予算を決める画面を出す。
    let setBudget: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        if let recap = model.recap {
            HStack(spacing: 0) {
                card(recap)
                // アプリからの返事として左に寄せ、右に余白を残す（アクセシビリティサイズの文字では幅を使わせる）。
                Spacer(minLength: dynamicTypeSize.isAccessibilitySize ? 0 : 40)
            }
        }
    }

    private func card(_ recap: WeeklyRecap) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if recap.isEmpty {
                // 記録が無かった週は、開く内訳が無いのでボタンにしない。
                summary(recap, opensDetail: false)
                    .accessibilityElement(children: .combine)
                Text(verbatim: RecapTexts.emptyWeekHint)
                    .font(.subheadline)
                    .foregroundStyle(Theme.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Button(action: open) {
                    summary(recap, opensDetail: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(.rect)
                }
                // 文字の色は中で決めているので、tint に染めない形にする（押している間は薄くなる）。
                .buttonStyle(.plain)
                .accessibilityLabel(Text(verbatim: RecapTexts.spokenSummary(
                    for: recap, remark: model.remark.state.sentence, calendar: model.calendar
                )))
                .accessibilityHint("先週の内訳を開きます")
            }
            budgetPrompt
        }
        .foregroundStyle(Theme.ink)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface, in: .rect(cornerRadius: 18))
        .overlay(alignment: .topTrailing) {
            closeButton
        }
        .accessibilityElement(children: .contain)
    }

    /// 見出し・期間・定型文・AI の一言・上位のカテゴリ・目安との比べ。
    private func summary(_ recap: WeeklyRecap, opensDetail: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(RecapTexts.title)
                        .font(.headline)
                        // 大きな文字でも見出しを省かずに折り返す（スタックの中で高さを詰められて「…」で切れないように）。
                        .fixedSize(horizontal: false, vertical: true)
                    if opensDetail {
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Theme.inkSecondary)
                            .accessibilityHidden(true)
                    }
                }
                Text(verbatim: model.periodTitle)
                    .font(.caption)
                    .foregroundStyle(Theme.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            // 右上の「閉じる」と重ならないよう、見出しの右を空けておく。
            .padding(.trailing, 36)
            Text(verbatim: RecapTexts.fixedSentence(for: recap))
                .fixedSize(horizontal: false, vertical: true)
            RecapRemarkView(state: model.remark.state)
            let top = recap.topCategories()
            if !top.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(top) { item in
                        BreakdownLine(item: item)
                    }
                }
            }
            if let pace = RecapTexts.paceComparison(for: recap) {
                Label {
                    Text(verbatim: pace.text)
                } icon: {
                    Image(systemName: pace.beyond > 0 ? "arrow.up.right" : pace.beyond < 0 ? "arrow.down.right" : "equal")
                }
                .labelStyle(TrendLabelStyle())
                .font(.footnote)
                .foregroundStyle(Theme.inkSecondary)
            }
        }
    }

    /// 予算についての案内。表示するだけで、予算は変えない（決めるのは予算を決める画面で保存したときだけ）。
    @ViewBuilder
    private var budgetPrompt: some View {
        switch model.budgetPrompt {
        case .setBudget(let suggestion)?:
            VStack(alignment: .leading, spacing: 4) {
                Divider()
                    .padding(.bottom, 4)
                if let suggestion {
                    suggestionText(suggestion, current: nil)
                } else {
                    Text("月の予算を決めると、週の目安と比べられます。")
                        .font(.subheadline)
                        .foregroundStyle(Theme.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                budgetButton(Text("予算を決める"))
            }
        case .changeBudget(let suggestion, let current)?:
            VStack(alignment: .leading, spacing: 4) {
                Divider()
                    .padding(.bottom, 4)
                suggestionText(suggestion, current: current)
                budgetButton(Text("予算を変更"))
            }
        case nil:
            EmptyView()
        }
    }

    private func suggestionText(_ suggestion: BudgetSuggestion, current: Int?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(verbatim: RecapTexts.suggestionText(suggestion))
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
            if let current {
                Text(verbatim: RecapTexts.currentBudget(current))
                    .font(.subheadline)
                    .monospacedDigit()
            }
            Text(verbatim: RecapTexts.suggestionBasis(suggestion))
                .font(.caption)
                .foregroundStyle(Theme.inkSecondary)
        }
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .combine)
    }

    private func budgetButton(_ title: Text) -> some View {
        Button(action: setBudget) {
            title
                .fontWeight(.semibold)
                .foregroundStyle(Theme.accentText)
                .frame(minHeight: 44)
                .contentShape(.rect)
        }
        .accessibilityHint("予算を決める画面を開きます")
    }

    /// 右上の「閉じる」。押せる範囲を 44pt 四方以上にする。
    private var closeButton: some View {
        Button(action: dismiss) {
            Image(systemName: "xmark")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.inkSecondary)
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(.rect)
        }
        .accessibilityLabel("先週のふりかえりを閉じる")
        .accessibilityHint("同じ週には、もう出しません")
    }
}
