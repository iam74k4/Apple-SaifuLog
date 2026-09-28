import SaifuLogCore
import SwiftUI

/// タイムラインの 1 件。自分が送ったメッセージのように右寄せの吹き出しで出す。
struct EntryBubble: View {
    let entry: Entry
    /// 今日。日付に年を添えるかの基準にする。
    let today: Date
    /// 削除を求める（確認は呼び出し側で出す）。
    let requestDelete: () -> Void

    @Environment(\.calendar) private var calendar
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .body) private var iconSize = 28

    /// アクセシビリティサイズの文字では、横に並べると品目も金額も数文字の幅に押し込まれ、
    /// 「¥8 / 50」「ラン / チ」のように桁や語の途中で折り返される。そのときは 1 行に収まらない行を縦に積む。
    private var stacksVertically: Bool {
        dynamicTypeSize.isAccessibilitySize
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            // 縦に積むときは左の余白と右のアイコンをやめ、吹き出しに画面の幅を使わせる。
            Spacer(minLength: stacksVertically ? 0 : 40)
            bubble
            if !stacksVertically {
                icon
            }
        }
        // VoiceOver では 1 件を 1 つの要素として、品目・金額・カテゴリ・日付の順に読ませる。
        .accessibilityElement(children: .combine)
        // 長押しのメニューは VoiceOver から見つけにくいので、削除を操作の一覧にも出す。
        .accessibilityAction(named: "削除", requestDelete)
    }

    private var bubble: some View {
        VStack(alignment: .trailing, spacing: 6) {
            AdaptiveRow(stacksWhenNeeded: stacksVertically, horizontal: HStackLayout(alignment: .firstTextBaseline, spacing: 8)) {
                title
                    .multilineTextAlignment(.trailing)
                Text(verbatim: amountText)
                    .font(.headline)
                    .monospacedDigit()
                    .foregroundStyle(entry.isIncome ? Theme.income : .primary)
                    // 金額は桁の途中で改行させない。収まらなければ縮めて 1 行に収める。
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    // 横に並べるときは金額に先に幅を取らせ、品目の側を折り返させる。
                    .layoutPriority(1)
            }
            AdaptiveRow(stacksWhenNeeded: stacksVertically, horizontal: HStackLayout(spacing: 6)) {
                // メモが空のときは見出しがカテゴリ名なので、ここでは繰り返さない
                // （同じ語が 2 回表示され、VoiceOver でも 2 回読まれるため）。
                if !entry.memo.isEmpty {
                    kindLabel
                }
                Text(entry.spentAt, format: dateFormat)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Theme.bubble, in: .rect(cornerRadius: 18))
        .contentShape(.contextMenuPreview, .rect(cornerRadius: 18))
        .contextMenu {
            Button("削除", systemImage: "trash", role: .destructive, action: requestDelete)
        }
    }

    private var icon: some View {
        Image(systemName: entry.isIncome ? "yensign" : entry.category.symbolName)
            .font(.system(size: iconSize * 0.5, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: iconSize, height: iconSize)
            .background(tint, in: .circle)
            // 丸はダークモードでもライトの色（濃い色）で塗る。ダークの色は暗い地の上の文字用に明るくしてあり、
            // 白い記号を載せるとコントラストが 2:1 前後まで落ちるため。
            .environment(\.colorScheme, .light)
            .accessibilityHidden(true)
    }

    /// メモが空なら（品目が書かれていなければ）カテゴリ名を見出しにする。
    @ViewBuilder
    private var title: some View {
        if entry.memo.isEmpty {
            kindLabel
        } else {
            Text(verbatim: entry.memo)
        }
    }

    @ViewBuilder
    private var kindLabel: some View {
        if entry.isIncome {
            Text("収入")
        } else {
            Text(entry.category.label)
        }
    }

    private var amountText: String {
        entry.isIncome ? YenFormatter.signedString(from: entry.amount) : YenFormatter.string(from: entry.amount)
    }

    private var dateFormat: Date.FormatStyle {
        entry.showsYear(today: today, calendar: calendar) ? .dateTime.year().month().day() : .dateTime.month().day()
    }

    private var tint: Color {
        entry.isIncome ? Theme.income : Theme.color(for: entry.category)
    }
}

/// 横に並べる行。`stacksWhenNeeded` のときは、1 行に収まらなければ縦に積む（吹き出しの右端に揃える）。
///
/// 文字が大きいときも一律に縦に積むと、「食費 9月28日」のように 1 行に収まるものまで行が増え、
/// 画面に出る記録が減るため、収まるかどうかで選ぶ。
private struct AdaptiveRow<Content: View>: View {
    let stacksWhenNeeded: Bool
    let horizontal: HStackLayout
    @ViewBuilder let content: Content

    var body: some View {
        if stacksWhenNeeded {
            ViewThatFits(in: .horizontal) {
                horizontal { content }
                VStackLayout(alignment: .trailing, spacing: 2) { content }
            }
        } else {
            horizontal { content }
        }
    }
}

extension Entry {
    /// 日付に年を添えるか。今年でない記録を年なしで出すと今年の記録に見え、今月の合計に
    /// 入っていない理由が利用者に分からないため。
    func showsYear(today: Date, calendar: Calendar) -> Bool {
        !calendar.isDate(spentAt, equalTo: today, toGranularity: .year)
    }

    /// 種別の名前（「収入」かカテゴリ名）。
    var kindText: String {
        isIncome ? String(localized: "収入") : String(localized: category.label)
    }

    /// 削除の確認に出す「ランチ ¥850」。品目が無ければ種別の名前にする（吹き出しの見出しと同じ）。
    var summaryText: String {
        "\(memo.isEmpty ? kindText : memo) \(YenFormatter.string(from: amount))"
    }
}
