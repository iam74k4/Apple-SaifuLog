import SaifuLogCore
import SwiftUI

/// 入力欄の上の、よく使うひとこと（`QuickPhrases`）。押すとその文（「ランチ 850」）を入力欄に入れる。送るのは利用者
/// （額を直してから送れるように）。入力欄が空なら 2 回以上記録した品目を、打ち始めたら打った文字で始まる品目を出す。
///
/// 毎日の記録を、打たずに 2 回押すだけにするため（候補を押して、送信を押す）。キーボードを出していないときにも出す
/// （出していなければ、キーボードを開かずに送れる）。候補が無ければ何も出さない（タイムラインの場所を取らない）。
/// ボタンは横に送れる 1 行に並べる。
struct QuickPhraseBar: View {
    let phrases: [QuickPhrase]
    let pick: (QuickPhrase) -> Void

    var body: some View {
        if !phrases.isEmpty {
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(phrases) { phrase in
                        chip(phrase)
                    }
                }
                .padding(.horizontal)
            }
            .scrollIndicators(.hidden)
            // 候補の文字は入力欄と同じく大きさに上限を設ける（最大の文字では 1 つの候補が画面の幅を超え、1 つずつしか見えないため）。
            .dynamicTypeSize(...DynamicTypeSize.accessibility1)
            .accessibilityElement(children: .contain)
            .accessibilityLabel("よく使うひとこと")
        }
    }

    private func chip(_ phrase: QuickPhrase) -> some View {
        Button {
            pick(phrase)
        } label: {
            HStack(spacing: 6) {
                Text(verbatim: phrase.item)
                    .foregroundStyle(Theme.ink)
                Text(verbatim: YenFormatter.string(from: phrase.amount))
                    .monospacedDigit()
                    .foregroundStyle(phrase.isIncome ? Theme.income : Theme.inkSecondary)
            }
            .font(.subheadline)
            .lineLimit(1)
            .padding(.horizontal, 12)
            .frame(minHeight: 36)
            .background {
                Capsule()
                    .fill(Theme.surface)
                    .stroke(Theme.track, lineWidth: 1)
            }
            // 見た目は 36pt の高さにし、押せる範囲は上下の余白まで広げて 44pt にする。
            .padding(.vertical, 4)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(verbatim: "\(phrase.item) \(YenFormatter.string(from: phrase.amount))"))
        .accessibilityHint("入力欄に入れます")
    }
}

#Preview {
    QuickPhraseBar(
        phrases: [
            QuickPhrase(key: "ランチ", item: "ランチ", amount: 850, isIncome: false, count: 12, lastRecordedAt: .now),
            QuickPhrase(key: "コーヒー", item: "コーヒー", amount: 420, isIncome: false, count: 9, lastRecordedAt: .now),
            QuickPhrase(key: "バス", item: "バス", amount: 230, isIncome: false, count: 6, lastRecordedAt: .now),
        ],
        pick: { _ in }
    )
}
