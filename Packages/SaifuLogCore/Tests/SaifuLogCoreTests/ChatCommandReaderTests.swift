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
        ("今月の予算を5万にして", .setMonthlyBudget(50_000)),
        ("予算5万", .setMonthlyBudget(50_000)),
        ("月の予算は12万円に設定", .setMonthlyBudget(120_000)),
        ("さっきのを900に直して", .changeAmount(900)),
        ("850じゃなくて950", .changeAmount(950)),
        ("金額を間違えた 1200", .changeAmount(1_200)),
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

    @Test("AI が選んだ種類は、文に書かれた値で組み立てる")
    func buildsFromKind() {
        #expect(Self.command(.changeAmount, "あれ実は900円だった") == .changeAmount(900))
        #expect(Self.command(.setMonthlyBudget, "これからは予算を7万くらいで") == .setMonthlyBudget(70_000))
        #expect(Self.command(.recategorize, "あれは交通かな") == .recategorize(.transport))
        #expect(Self.command(.removeLast, "あれはなかったことで") == .removeLast)
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
}
