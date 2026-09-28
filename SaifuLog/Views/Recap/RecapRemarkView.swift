import SwiftUI

/// ふりかえり（先週のふりかえりのカード・月のまとめ）の AI の一言。書いている間は進行中の印、書けたら一言を出す（添えないときは
/// 何も出さない）。
///
/// 一言は墨の文字にし、AI が書いたことはきらめきの記号で示す（家計への質問の回答カードの一言と同じ）。記号は VoiceOver では
/// 読ませない（一言の文だけを読む）。
struct RecapRemarkView: View {
    let state: RecapRemarkModel.State

    var body: some View {
        switch state {
        case .none:
            EmptyView()
        case .writing:
            HStack(spacing: 8) {
                ProgressView()
                    .accessibilityHidden(true)
                Text("ひとことを書いています…")
                    .foregroundStyle(Theme.inkSecondary)
            }
            .font(.subheadline)
            .accessibilityElement(children: .combine)
        case .written(let sentence):
            Label {
                Text(verbatim: sentence)
                    .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: "sparkles")
                    .accessibilityHidden(true)
            }
            .font(.subheadline)
            .foregroundStyle(Theme.ink)
        }
    }
}

extension RecapRemarkModel.State {
    /// 照合を通った一言（書いている間と添えないときは nil）。
    var sentence: String? {
        if case .written(let sentence) = self { return sentence }
        return nil
    }
}
