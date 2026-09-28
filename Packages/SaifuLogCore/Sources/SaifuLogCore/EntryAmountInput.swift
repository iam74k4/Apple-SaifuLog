import Foundation

/// 記録の金額の入力欄（記録を直すシート）の文字の扱いと、保存できる額かどうかの判定。
///
/// 入力欄は数字のキーボードだが、貼り付けや外付けのキーボードで数字以外や全角の数字も入りうる。
/// 読み取りと見せ方（「1,280」のように 3 桁ごとにカンマ）は予算の入力欄（`BudgetAmountInput`）とそろえる。
public enum EntryAmountInput {
    /// 記録できる最大の額（円）。ひとこと入力が金額として読む上限（`EntryScan`）と同じにしている。
    ///
    /// これより低くすると、ひとことで記録できた額の記録を開いたとき、金額を変えずにカテゴリや日付だけを
    /// 直すこともできなくなるため。
    public static let maximumAmount = 999_999_999_999

    /// 入力欄に残す桁数。上限の桁数より 1 桁多くまで残し、上限を超えたことを理由つきで知らせる。
    ///
    /// 上限の桁数で切ると、打った 13 桁目や貼り付けた長い数字の後ろが黙って消え、打ったつもりと違う額を
    /// 保存しかねないため。
    public static let maximumDigits = String(maximumAmount).count + 1

    /// 入力欄の文字から金額を読む。数字が 1 つも無ければ nil。
    public static func amount(from text: String) -> Int? {
        let digits = AmountInputDigits.extract(from: text, maximumDigits: maximumDigits)
        return digits.isEmpty ? nil : Int(digits)
    }

    /// 入力欄に見せる形にそろえる。数字以外を除き、先頭の 0 を落とし、3 桁ごとにカンマを入れる。
    public static func formatted(_ text: String) -> String {
        guard let amount = amount(from: text) else { return "" }
        return YenFormatter.grouped(UInt(amount))
    }

    /// 金額を入力欄の形にする。0 以下は空欄。
    public static func text(for amount: Int) -> String {
        amount > 0 ? formatted(String(amount)) : ""
    }

    /// 入力欄の金額を保存できるか。保存できれば額を、できなければ理由を返す。
    ///
    /// 支出も収入も正の数で持つ（種別で分ける）ので、0 円は保存しない。記録を消したいときは削除を使う。
    public static func validate(_ text: String) -> Result<Int, EntryAmountIssue> {
        guard let amount = amount(from: text) else { return .failure(.missing) }
        guard amount > 0 else { return .failure(.notPositive) }
        guard amount <= maximumAmount else { return .failure(.tooLarge) }
        return .success(amount)
    }
}

/// 記録の金額を保存できない理由。画面はこれを文にして入力欄の下に出す。
public enum EntryAmountIssue: Error, Sendable, Hashable {
    /// 数字が入っていない。
    case missing
    /// 0 円。
    case notPositive
    /// 記録できる最大の額（`EntryAmountInput.maximumAmount`）を超えている。
    case tooLarge
}
