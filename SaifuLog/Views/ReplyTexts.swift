import Foundation
import SaifuLogCore

/// ホームのタイムラインの、送信へのアプリの返事（`RecordedReplyCard`）に添える文。数字はどれもコードが計算したもの
/// （AI には書かせない。docs/design.md §3-4・§9）で、AI が使えない端末でも同じ文になる。
enum ReplyTexts {
    /// 解析がメモに書き足した説明（`EntryMemoNote`）を、返事の行の下に添える文にする（「¥12,000 を4人で割り勘。立て替えた ¥9,000 は
    /// メモに残しました。」）。
    ///
    /// メモ（保存する形）は変えないので、⑥ のメモの欄と CSV には説明が書かれたまま残る。「メモに残しました」はそのことを指す。
    static func note(for note: EntryMemoNote) -> String {
        switch note.kind {
        case .split(let split):
            let total = YenFormatter.string(from: split.total)
            // 立て替えた額が 0 になるのは、総額が人数より少ないとき（¥1 を 2 人で割る）だけ。0 円の立て替えは書かない。
            guard split.advance > 0 else {
                return String(
                    localized: "\(total) を\(split.count)人で割り勘。",
                    comment: "ホームの返事の行の下の文（割り勘で、立て替えた額が無いとき）。%1$@ は総額、%2$lld は人数（2 以上）"
                )
            }
            return String(
                localized: "\(total) を\(split.count)人で割り勘。立て替えた \(YenFormatter.string(from: split.advance)) はメモに残しました。",
                comment: "ホームの返事の行の下の文（割り勘）。%1$@ は総額、%2$lld は人数（2 以上）、%3$@ はほかの人の分として立て替えた額（あとで返ってくる額）。メモ（直す画面のメモの欄）には「焼肉（4人で割り勘・総額 ¥12,000・立替 ¥9,000）」のように書いてある"
            )
        case .perPerson(let count?):
            return String(
                localized: "\(count)人で割り勘の1人分として記録しました。",
                comment: "ホームの返事の行の下の文。「1人3000」のように 1 人分として書かれた額を、割らずにそのまま記録したとき。%lld は割り勘の人数（2 以上）"
            )
        case .perPerson(nil):
            return String(
                localized: "1人分として記録しました。",
                comment: "ホームの返事の行の下の文。「ひとり3000」のように 1 人分として書かれた額を、割らずにそのまま記録したとき（割り勘の人数は書かれていない）"
            )
        }
    }
}
