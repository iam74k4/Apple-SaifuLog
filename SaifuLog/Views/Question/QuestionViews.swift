import SaifuLogCore
import SwiftUI

/// タイムラインの質問 1 つ。送った質問を記録の送信と同じく右寄せの自分の吹き出しで出し、その下に返事のカードを左寄せで出す
/// （記録の返事のカードと同じ見た目）。
///
/// 質問は保存しないので、長押しの「直す」「削除」は無い（アプリを開き直すと消える）。
struct QuestionExchangeView: View {
    let exchange: QuestionExchange
    /// 回答カードを押したときに、その月の月のまとめへ進む（今月・先月の答えのときだけ呼ぶ）。
    let openReport: (Date) -> Void
    /// 予算を決める画面を出す（予算が無くて答えられなかったとき）。
    let setBudget: () -> Void
    /// プレミアムのシートを出す（無料の回数を使い切ったとき）。
    let openPremium: () -> Void

    var body: some View {
        // 吹き出しと返事の間は、タイムラインの行どうしの間（12pt）と同じにする（記録の送信は吹き出しと返事が別の行）。
        VStack(spacing: 12) {
            UserMessageBubble(
                text: exchange.text,
                // 記録か質問か決められなかった文は、VoiceOver でも「質問」と読まない。下の案内が「記録か質問か分かりません
                // でした」と言うのに、吹き出しが質問と名乗ると食い違うため。
                accessibilityLabel: exchange.state == .unclear ? Text("送った文: \(exchange.text)") : Text("質問: \(exchange.text)")
            )
            QuestionReplyCard(state: exchange.state, openReport: openReport, setBudget: setBudget, openPremium: openPremium)
        }
    }
}

/// 質問への返事のカード（アプリからの返事として左寄せ。記録の返事のカードと同じ面）。
///
/// 答えたときは、大きな数字（コードが計算した値をそのまま）、期間とカテゴリの見出し、元になった件数、AI の一言（ある場合。
/// 数字の照合を通ったものか定型文）、無料の残りの回数（3 回以下のとき）を出す。今月・先月の答えは、押すとその月の月のまとめへ進む。
/// 山吹の塗りは使わない（塗りの主ボタンが無いため）。予算を超えた額は、注意の色にアイコンと語を添える（色だけに頼らない）。
private struct QuestionReplyCard: View {
    let state: QuestionExchange.State
    let openReport: (Date) -> Void
    let setBudget: () -> Void
    let openPremium: () -> Void

    var body: some View {
        content
            .foregroundStyle(Theme.ink)
            .replyCardSurface()
            .leadingReply()
    }

    @ViewBuilder
    private var content: some View {
        switch state {
        case .answering:
            HStack(spacing: 8) {
                ProgressView()
                    .accessibilityHidden(true)
                Text("計算しています…")
                    .foregroundStyle(Theme.inkSecondary)
            }
            .accessibilityElement(children: .combine)
        case .answered(let answer, let remark, let freeQuestionsLeft):
            AnswerContent(
                answer: answer, remark: remark, freeQuestionsLeft: freeQuestionsLeft,
                openReport: openReport, setBudget: setBudget
            )
        case .unreadable:
            NoticeContent(
                title: "質問を読めませんでした",
                message: "次のように聞いてみてください。答えられる期間は、今日・昨日・今週・先週・今月・先月・今年と、「直近7日」のような日数です。",
                examples: QuestionParser.examples
            )
        case .unclear:
            NoticeContent(
                title: "記録か質問か分かりませんでした",
                message: "金額と「残り」「予算」「合計」のような語が一緒に入っていたので、記録しませんでした。記録するときは金額と品目だけを、質問するときは「?」を付けて送ってください。"
            )
        case .limitReached:
            VStack(alignment: .leading, spacing: 8) {
                NoticeContent(
                    title: "今月の無料の質問を使い切りました",
                    message: "プレミアムなら、回数の制限なく質問できます。記録はこれまでどおり無料で、回数の制限なく続けられます。"
                )
                Button(action: openPremium) {
                    Text("プレミアムを見る")
                        .fontWeight(.semibold)
                        .foregroundStyle(Theme.accentText)
                        .frame(minHeight: 44)
                        .contentShape(.rect)
                }
                .accessibilityHint("無料との違いと購入の画面を開きます")
            }
        case .loadFailed:
            NoticeContent(title: "記録を読み込めませんでした", message: "もう一度お試しください。")
        }
    }
}

/// 答えの中身。今月・先月の答えは、カード全体を押すと月のまとめへ進む。
private struct AnswerContent: View {
    let answer: LedgerAnswer
    let remark: QuestionRemark?
    let freeQuestionsLeft: Int?
    let openReport: (Date) -> Void
    let setBudget: () -> Void

    @Environment(\.calendar) private var calendar
    @Environment(\.categoryCatalog) private var catalog

    /// その月の月のまとめへ進めるか（数えた期間が暦の月まるごとのとき）。
    private var opensReport: Bool {
        answer.period.isWholeMonth
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if opensReport {
                Button {
                    openReport(answer.interval.start)
                } label: {
                    summary
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(.rect)
                }
                // 文字の色は中で決めているので、tint に染めない形にする（押している間は薄くなる）。
                .buttonStyle(.plain)
                .accessibilityElement(children: .combine)
                .accessibilityHint("月のまとめを開きます")
            } else {
                summary
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityElement(children: .combine)
            }
            if answer.value == .noBudget {
                Button(action: setBudget) {
                    Text("予算を決める")
                        .fontWeight(.semibold)
                        .foregroundStyle(Theme.accentText)
                        .frame(minHeight: 44)
                        .contentShape(.rect)
                }
                .accessibilityHint("予算を決める画面を開きます")
            }
            if let freeQuestionsLeft {
                Text(verbatim: QuestionTexts.freeQuestionsLeft(freeQuestionsLeft))
                    .font(.footnote)
                    .foregroundStyle(Theme.inkSecondary)
            }
        }
    }

    /// 期間・見出し・数字・件数・一言。VoiceOver ではまとめて 1 つの要素として、この順に読ませる。
    private var summary: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(verbatim: QuestionTexts.periodText(for: answer, calendar: calendar))
                if opensReport {
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .accessibilityHidden(true)
                }
            }
            .font(.caption)
            .foregroundStyle(Theme.inkSecondary)
            Text(verbatim: QuestionTexts.title(for: answer.question, catalog: catalog))
                .font(.subheadline.weight(.semibold))
            headline
            details
            Text(verbatim: QuestionTexts.recordCount(answer.recordCount))
                .font(.caption)
                .foregroundStyle(Theme.inkSecondary)
            remarkView
        }
    }

    @ViewBuilder
    private var headline: some View {
        let text = QuestionTexts.headline(for: answer.value)
        if isOver {
            // 1 行に収まらなければ、アイコンを上に置いて額の行に幅を使わせる（折り返すと「¥」と数字の間で切れるため）。
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    overIcon
                    Text(verbatim: text)
                }
                .fixedSize()
                VStack(alignment: .leading, spacing: 4) {
                    overIcon
                    Text(verbatim: text)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                }
            }
            .font(.title.bold())
            .foregroundStyle(Theme.danger)
            .fixedSize(horizontal: false, vertical: true)
        } else if QuestionTexts.headlineIsFigure(answer.value) {
            Text(verbatim: text)
                .font(.largeTitle.bold())
                .monospacedDigit()
                // 金額は桁の途中で折り返さない。収まらなければ縮めて 1 行に収める。
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                // 高さは縮めさせない。縮められる文字だと、スタックが内訳の行（収まる形を選ぶ行）に先に高さを配り、
                // 幅が足りていても小さな文字になるため。
                .fixedSize(horizontal: false, vertical: true)
        } else {
            Text(verbatim: text)
                .font(.headline)
        }
    }

    private var overIcon: some View {
        Image(systemName: "exclamationmark.triangle.fill")
            .accessibilityHidden(true)
    }

    private var isOver: Bool {
        switch answer.value {
        case .budget(let status), .dailyAllowance(let status): status.isOver
        default: false
        }
    }

    /// 数字に添える内訳（いちばん多いカテゴリの名前、予算と使った額、残りの日数、カテゴリ別の行）。
    @ViewBuilder
    private var details: some View {
        switch answer.value {
        case .topCategory(let item?):
            HStack(spacing: 8) {
                CategoryIcon(category: item.category)
                catalog.label(for: item.category)
                Text(verbatim: item.percentText)
                    .foregroundStyle(Theme.inkSecondary)
                    .accessibilityLabel(Text(verbatim: item.spokenPercent))
            }
        case .breakdown(let breakdown):
            VStack(alignment: .leading, spacing: 4) {
                ForEach(breakdown.items) { item in
                    BreakdownLine(item: item)
                }
            }
        case .budget(let status), .dailyAllowance(let status):
            VStack(alignment: .leading, spacing: 2) {
                if case .dailyAllowance = answer.value, !status.isOver {
                    Text("のこり \(status.remainingDays) 日")
                }
                Text("予算 \(YenFormatter.string(from: status.budget))")
                Text("使った額 \(YenFormatter.string(from: status.spent))")
            }
            .font(.subheadline)
            .foregroundStyle(Theme.inkSecondary)
        case .noBudget:
            Text("月の予算を決めると、残りや1日あたりに使える額に答えられます。")
                .font(.subheadline)
                .foregroundStyle(Theme.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
        case .budgetNotApplicable:
            Text("いまの予算を決める前の月なので、予算の残りは分かりません（月ごとの予算は残していません）。")
                .font(.subheadline)
                .foregroundStyle(Theme.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
        default:
            EmptyView()
        }
    }

    @ViewBuilder
    private var remarkView: some View {
        switch remark {
        case .ai(let sentence):
            Label {
                Text(verbatim: sentence)
                    .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: "sparkles")
                    .accessibilityHidden(true)
            }
            .font(.subheadline)
            .foregroundStyle(Theme.ink)
            .padding(.top, 2)
        case .fixed:
            Text(QuestionTexts.fixedRemark)
                .font(.subheadline)
                .foregroundStyle(Theme.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 2)
        case nil:
            EmptyView()
        }
    }
}

/// 内訳の 1 行（色と記号の丸・名前・金額・割合）。1 行に収まらなければ金額を名前の下に積み、それでも収まらなければ
/// 割合を金額の下に積む（縮めて読めなくしない）。アクセシビリティサイズの文字では、名前と金額に幅を使わせるため丸を省く
/// （記録の返事の行の印と同じ。名前はいつも出る）。先週のふりかえりのカードの上位のカテゴリでも使う。
struct BreakdownLine: View {
    let item: CategoryBreakdown.Item

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.categoryCatalog) private var catalog

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            if !dynamicTypeSize.isAccessibilitySize {
                CategoryIcon(category: item.category)
            }
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    name
                    Spacer(minLength: 8)
                    HStack(alignment: .firstTextBaseline, spacing: 8) { amount; percent }
                        // 横に並べるときは縮めない（縮めると収まったことになり、金額が小さな文字になるため）。
                        .fixedSize()
                }
                VStack(alignment: .leading, spacing: 2) {
                    name
                    HStack(alignment: .firstTextBaseline, spacing: 8) { amount; percent }
                        .fixedSize()
                }
                VStack(alignment: .leading, spacing: 2) {
                    name
                    amount
                    percent
                }
            }
        }
        .font(.subheadline)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(catalog.label(for: item.category))
        .accessibilityValue(Text(verbatim: item.spokenValue))
    }

    private var name: some View {
        catalog.label(for: item.category)
    }

    private var amount: some View {
        Text(verbatim: YenFormatter.string(from: item.amount))
            .monospacedDigit()
            // 金額は桁の途中で折り返さない（収まらなければ縮める）。
            .lineLimit(1)
            .minimumScaleFactor(0.5)
    }

    private var percent: some View {
        Text(verbatim: item.percentText)
            .monospacedDigit()
            .foregroundStyle(Theme.inkSecondary)
    }
}

/// 答えられなかったときの案内（見出し・文・質問の例）。
private struct NoticeContent: View {
    let title: LocalizedStringResource
    let message: LocalizedStringResource
    var examples: [String] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(Theme.inkSecondary)
                // 説明の文は省かずに折り返す（スタックの中で高さを詰められて「…」で切れないように）。
                .fixedSize(horizontal: false, vertical: true)
            if !examples.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    // 例の文は日本語のまま見せる（解析が日本語の入力を前提にしているため、訳さない）。
                    ForEach(examples, id: \.self) { example in
                        Text(verbatim: example)
                            .font(.subheadline.weight(.semibold))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Theme.background, in: .rect(cornerRadius: 12))
                            .accessibilityLabel(Text("入力例: \(example)"))
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#Preview("答え") {
    let answer = LedgerAnswer(
        question: LedgerQuestion(period: .thisMonth, metric: .categoryExpense, category: .cafe),
        period: .thisMonth,
        interval: Calendar.current.dateInterval(of: .month, for: .now)!,
        recordCount: 5,
        value: .amount(3_200)
    )
    ScrollView {
        VStack(spacing: 12) {
            QuestionExchangeView(
                exchange: QuestionExchange(
                    text: "今月カフェいくら?", askedAt: .now,
                    state: .answered(answer, remark: .ai("今月のカフェは¥3,200でした。"), freeQuestionsLeft: 3)
                ),
                openReport: { _ in }, setBudget: {}, openPremium: {}
            )
            QuestionExchangeView(
                exchange: QuestionExchange(text: "去年の食費は?", askedAt: .now, state: .unreadable),
                openReport: { _ in }, setBudget: {}, openPremium: {}
            )
            QuestionExchangeView(
                exchange: QuestionExchange(text: "今月の食費は?", askedAt: .now, state: .limitReached),
                openReport: { _ in }, setBudget: {}, openPremium: {}
            )
            QuestionExchangeView(
                exchange: QuestionExchange(text: "スーパー 残り 500", askedAt: .now, state: .unclear),
                openReport: { _ in }, setBudget: {}, openPremium: {}
            )
        }
        .padding()
    }
    .background(Theme.background)
}
