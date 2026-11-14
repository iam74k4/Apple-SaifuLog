import Foundation
import Testing
@testable import SaifuLogCore

@Suite("チャットの文で頼む操作")
struct ChatCommandReaderTests {
    private static func command(_ text: String) -> ChatCommand? {
        ChatCommandReader.command(in: text, now: Fixture.now, calendar: Fixture.calendar)
    }

    private static func command(_ kind: ChatCommandKind, _ text: String) -> ChatCommand? {
        ChatCommandReader.command(kind: kind, in: text, now: Fixture.now, calendar: Fixture.calendar)
    }

    @Test("決まりで読む操作", arguments: [
        ("それ日用品", ChatCommand.recategorize(.daily)),
        ("さっきの消して", .removeLast),
        ("今のなし", .removeLast),
        ("やっぱり取り消して", .removeLast),
        ("さっきの記録を削除", .removeLast),
        ("先ほどのを消して", .removeLast),
        ("さっきのキャンセル", .removeLast),
        ("無かったことにして", .removeLast),
        ("それ無しで", .removeLast),
        ("今月の予算を5万にして", .setMonthlyBudget(50_000)),
        ("予算5万", .setMonthlyBudget(50_000)),
        ("月の予算は12万円に設定", .setMonthlyBudget(120_000)),
        ("さっきのを900に直して", .changeAmount(900)),
        ("850じゃなくて950", .changeAmount(950)),
        ("金額を間違えた 1200", .changeAmount(1_200)),
        ("850円じゃなくて950円です", .changeAmount(950)),
        ("さっきの850じゃなくて950", .changeAmount(950)),
        // 前の記録を指す語は、記録か質問かの見分けと同じ語（前は「それ」「いまの」「さきほど」で書くと読めず、新しい記録になった）。
        ("それを900に直して", .changeAmount(900)),
        ("いまのを900に直して", .changeAmount(900)),
        ("さきほどのを900に変更", .changeAmount(900)),
        ("最後のを1000に変えて", .changeAmount(1_000)),
        ("あれ実は900円だった", .changeAmount(900)),
        // 金額と直す語と語尾だけの文は、前の記録を指す語が無くても直す文。
        ("900に直して", .changeAmount(900)),
        ("今月の予算を5万でお願いします", .setMonthlyBudget(50_000)),
        ("今月の予算は5万です", .setMonthlyBudget(50_000)),
        ("予算を5万にしといて", .setMonthlyBudget(50_000)),
    ])
    func readsCommands(text: String, command: ChatCommand) {
        #expect(Self.command(text) == command)
    }

    @Test("記録・質問・ほかの語が残る文は、操作にしない", arguments: [
        "ランチ 850",
        "今月の予算は?",
        "予算あといくら",
        "食費の予算3万",
        "来月の予算5万",
        "今月の予算5万超えた",
        "コーヒーいらない",
        "予算どうしよう5万",
        "修正テープ 200",
        "さっきの直して",
        "今のランチ 900",
        "",
    ])
    func ignoresOtherTexts(text: String) {
        #expect(Self.command(text) == nil)
    }

    // 以前は「じゃなくて」「前の」「変更」があれば、残りの語を見ずに直前の記録の金額を書き換えていた（「名前の変更 2500」で
    // 直前の記録が ¥2,500 になった）。
    @Test("品目や店の名前が残る文は、金額を直す文にしない", arguments: [
        "スタバじゃなくてドトール 400",
        "名前の変更 2500",
        "前のタイヤ変えて 20000",
        "出前の注文を変更 2000",
        "さっきのランチ900に直して",
        // 値引きの額が残る文は、どちらの額にするか決められないので読まない（記録か質問かの見分けでは直す文。AI に頼む）。
        "さっきのを1000円 100円引きに直して",
        "それぞれの変更手数料 500",
    ])
    func ignoresRecordLikeCorrections(text: String) {
        #expect(Self.command(text) == nil, "\(text)")
    }

    // 以前は「ポイント100じゃなくて200」の「ポイント100」を、前の記録を指す語とみなし、直前の記録の金額を ¥200 にしていた。
    @Test("「AじゃなくてB」の A にポイント・おつり・値引きの額があれば、金額を直す文にしない", arguments: [
        "ポイント100じゃなくて200",
        "おつり150じゃなくて250",
        "値引き100じゃなくて200",
    ])
    func ignoresNonAmountRestatements(text: String) {
        #expect(Self.command(text) == nil, "\(text)")
        #expect(Self.command(.changeAmount, text) == nil, "\(text)")
    }

    // 以前は「なし」「いらない」だけの文や「カテゴリなし」でも、直前の記録を消していた。
    @Test("消す語だけの文と、謝る語を添えた文は、直前の送信の記録を消す文", arguments: [
        "キャンセル", "削除", "消して", "取り消して", "すみません、さっきの消して", "ごめんなさい、今の取り消して",
    ])
    func readsBareRemovalWords(text: String) {
        #expect(Self.command(text) == .removeLast, "\(text)")
    }

    // 以前は消す語と「いらない」「やめて」「なし」を両方外してから残りを見たので、「削除はいらない」が直前の記録を消す文になった。
    @Test("消すことを打ち消す文は、消す文にしない（AI が消す操作を選んでも組み立てない）", arguments: [
        "削除はいらない",
        "取り消すのはやめて",
        "キャンセルはなしで",
        "取り消しは要らない",
        "消さないで",
        "削除しないで",
        "キャンセルしないで",
        "消してない",
        "さっきのは消さなくていい",
    ])
    func ignoresNegatedRemovals(text: String) {
        #expect(Self.command(text) == nil, "\(text)")
        #expect(Self.command(.removeLast, text) == nil, "\(text)")
    }

    @Test("消したことを言う文（過去の言い方）は、消す文にしない")
    func ignoresPastRemoval() {
        #expect(Self.command("それ削除した") == nil)
    }

    @Test("前の記録を指す語の無い「なし」や、カテゴリの「なし」は、消す文にしない", arguments: [
        "なし",
        "いらない",
        "やめて",
        "カテゴリなし",
        "それカテゴリなし",
        "分類いらない",
    ])
    func ignoresLooseRemovals(text: String) {
        #expect(Self.command(text) == nil, "\(text)")
    }

    @Test("月ではない期間や、予算の残り・超えた額の文は、月の予算にしない", arguments: [
        "年間の予算を60万にして",
        "週の予算1万",
        "12月の予算を5万にして",
        "予算の残り3万",
        "予算を5000オーバー",
        "1日の予算3000",
        // 前は「前の」を前の記録を指す語として外したので、前の月の予算の文で今月の予算を書き換えていた。
        "前の月の予算を5万にして",
        "前の月の予算は5万だった",
        "前月の予算を5万にして",
        "翌月の予算は5万",
        "次の月の予算を5万に設定",
        // 合計・ポイントの額は予算の額にしない。
        "今月の合計 3000円の予算",
        "予算 ポイント5000",
    ])
    func ignoresOtherBudgets(text: String) {
        #expect(Self.command(text) == nil, "\(text)")
        #expect(Self.command(.setMonthlyBudget, text) == nil, "\(text)")
    }

    @Test("過去の額を言う予算の文は、決まりでは月の予算にしない", arguments: [
        "予算は5万だった",
        "今月の予算は5万でした",
    ])
    func ignoresPastBudgets(text: String) {
        #expect(Self.command(text) == nil, "\(text)")
    }

    @Test("AI が選んだ種類は、文に書かれた値で組み立てる")
    func buildsFromKind() {
        // 決まりでは読めない（「くらい」「かも」が残る）が、記録か質問かの見分けで直す文になるので、AI に頼む文。
        #expect(Self.command("あれ、本当は900円くらいだったかも") == nil)
        #expect(Self.command(.changeAmount, "あれ、本当は900円くらいだったかも") == .changeAmount(900))
        #expect(Self.command(.setMonthlyBudget, "これからは予算を7万くらいで") == .setMonthlyBudget(70_000))
        #expect(Self.command(.recategorize, "あれは交通かな") == .recategorize(.transport))
        #expect(Self.command(.removeLast, "あれはなかったことで") == .removeLast)
        // 「じゃなくて」の前に金額があれば、品目が書かれていても後ろの金額にする（AI が選んだ操作は、画面が確かめてから行う）。
        #expect(Self.command(.changeAmount, "さっきのランチ、850じゃなくて950") == .changeAmount(950))
        #expect(Self.command(.changeAmount, "さっきのランチ900に直して") == .changeAmount(900))
        #expect(Self.command(.recategorize, "交通費じゃなくて食費かな") == .recategorize(.food))
    }

    @Test("AI が選んだ種類でも、値が文から読めなければ組み立てない")
    func needsValuesInText() {
        // 金額が 2 つあり、どちらに直すか分からない。
        #expect(Self.command(.changeAmount, "900か1000") == nil)
        #expect(Self.command(.changeAmount, "金額がちがう") == nil)
        // カテゴリが 2 つ書かれている。
        #expect(Self.command(.recategorize, "食費か日用品") == nil)
        #expect(Self.command(.setMonthlyBudget, "予算を決めたい") == nil)
        #expect(Self.command(.setMonthlyBudget, "食費の予算を3万") == nil)
        // 数字のある文は消さない。
        #expect(Self.command(.removeLast, "900のを消して") == nil)
        #expect(Self.command(.none, "それ日用品") == nil)
    }

    @Test("AI が選んだ種類でも、種類に合う語の無い文では組み立てない")
    func needsCuesForKind() {
        // 比べる文・店を直す文に、AI が金額を直す操作を選んでも、前の記録の金額は変えない。
        #expect(Self.command(.changeAmount, "今月の食費 3万超えた") == nil)
        #expect(Self.command(.changeAmount, "スタバじゃなくてドトール 400") == nil)
        #expect(Self.command(.changeAmount, "ランチ 900") == nil)
        // 消す語の無い文と、カテゴリの「なし」は消さない。
        #expect(Self.command(.removeLast, "それはランチ") == nil)
        #expect(Self.command(.removeLast, "カテゴリなしで") == nil)
    }
}
