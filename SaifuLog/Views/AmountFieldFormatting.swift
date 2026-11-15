import SwiftUI

extension View {
    /// 金額の入力欄の文を、入力欄を離れたときに見せる形（「60,000」）にそろえる。打っている間はそろえない。
    ///
    /// 前は文が変わるたびにそろえていた（`.onChange(of: text)` の中で文を書き換える）。SwiftUI は書き換えた文を次の画面の
    /// 更新で入力欄に戻すので、その間に打った次の文字が古い文で上書きされ、続けて速く打つと桁が落ちた（「60000」が「6,000」に
    /// なり、そのまま ¥6,000 で保存された。CI の UI テストで見つかった。0 を続けて押すときや、シートが上がる途中など画面が
    /// 忙しいときに起きる）。区切りの前で消すと区切りが戻って何も消えず、途中の桁を直すとカーソルが末尾へ飛ぶこともあった。
    /// 金額は区切りや全角の数字を無視して読む（`EntryAmountInput.amount(from:)`・`BudgetAmountInput.amount(from:)`）ので、
    /// 打っている間の文はそのままでよい。保存はいつも読み取った額で行う。
    ///
    /// - Parameters:
    ///   - isEditing: いまこの入力欄にフォーカスがあるか。
    ///   - normalize: 見せる形にそろえる（モデルの `normalize…Text`）。
    func formatsAmountAfterEditing(isEditing: Bool, normalize: @escaping () -> Void) -> some View {
        onChange(of: isEditing) { _, editing in
            if !editing { normalize() }
        }
    }
}
