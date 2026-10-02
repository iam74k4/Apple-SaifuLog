import Testing
@testable import SaifuLogCore

@Suite("カテゴリ")
struct EntryCategoryTests {
    @Test("v1 は 8 種で、表示名の順も決まっている")
    func eightCategories() {
        #expect(EntryCategory.builtIns.map(\.displayName) == [
            "食費", "日用品", "交通", "カフェ", "娯楽", "光熱・通信", "医療", "その他",
        ])
    }

    @Test("保存に使う rawValue は重ならない")
    func rawValuesAreUnique() {
        let rawValues = EntryCategory.builtIns.map(\.rawValue)
        #expect(Set(rawValues).count == rawValues.count)
    }

    @Test("表示名からカテゴリに戻せる", arguments: EntryCategory.builtIns)
    func roundTripsDisplayName(category: EntryCategory) {
        #expect(EntryCategory(displayName: category.displayName) == category)
        #expect(!category.symbolName.isEmpty)
    }

    @Test("知らない表示名は nil")
    func unknownDisplayName() {
        #expect(EntryCategory(displayName: "収入") == nil)
    }

    @Test("キーワードからカテゴリを推定する", arguments: [
        ("ランチ", EntryCategory.food),
        ("らんち", .food),
        ("スーパーで買い物", .food),
        ("ドラッグストアで薬", .daily),
        ("風邪薬", .medical),
        ("Suicaチャージ", .transport),
        ("スタバ", .cafe),
        ("映画", .entertainment),
        ("電気代", .utilities),
        ("病院", .medical),
    ])
    func guessesCategory(text: String, expected: EntryCategory) {
        #expect(EntryCategory.guess(from: text) == expected)
    }

    @Test("短い語の誤爆は長い語が受け止める", arguments: [
        ("ガスト", EntryCategory.food),
        ("パンツ", .other),
        ("ネット通販", .other),
    ])
    func longerKeywordWins(text: String, expected: EntryCategory) {
        #expect(EntryCategory.guess(from: text) == expected)
    }

    @Test("英語の品目もカテゴリに当てる（大文字・複数形・数字や日本語に続けて書いても）", arguments: [
        ("dinner", EntryCategory.food),
        ("Lunch", .food),
        ("DINNER", .food),
        ("dinner500", .food),
        ("dinnerパーティー", .food),
        ("groceries", .food),
        ("snacks", .food),
        ("sandwiches", .food),
        ("McDonald's", .food),
        ("McDonald’s", .food),
        ("coffee", .cafe),
        ("iced tea", .cafe),
        ("Starbucks", .cafe),
        ("café", .cafe),
        ("taxi", .transport),
        ("bus", .transport),
        ("tolls", .transport),
        ("movies", .entertainment),
        ("Netflix", .entertainment),
        ("Disney+", .entertainment),
        ("electricity", .utilities),
        ("gas", .utilities),
        ("phone bill", .utilities),
        ("Wi-Fi", .utilities),
        ("pharmacy", .medical),
        ("dentist", .medical),
        ("toilet paper", .daily),
        ("batteries", .daily),
    ])
    func guessesEnglishItems(text: String, expected: EntryCategory) {
        #expect(EntryCategory.guess(from: text) == expected)
    }

    // 英語は語の中に別の短い語がよく入っている。文字の並びだけで当てると、黙って違うカテゴリになる。
    @Test("英語の語は、ほかの語の中にあれば当てない", arguments: [
        "business", "busy", "training", "teacher", "notebook", "iphone", "vegas", "welfare", "metropolitan",
    ])
    func englishKeywordsNeedWordBoundaries(text: String) {
        #expect(EntryCategory.guess(from: text) == .other)
    }

    @Test("英語でも、長い語のカテゴリを採る", arguments: [
        ("uber eats", EntryCategory.food),
        ("uber", .transport),
        ("gas station", .transport),
        ("Mobile Suica", .transport),
        ("mobile game", .entertainment),
        ("train", .transport),
    ])
    func longerEnglishKeywordWins(text: String, expected: EntryCategory) {
        #expect(EntryCategory.guess(from: text) == expected)
    }

    @Test("どれにも当たらなければその他")
    func fallsBackToOther() {
        #expect(EntryCategory.guess(from: "なにか") == .other)
        #expect(EntryCategory.guess(from: "") == .other)
    }

    @Test("質問のカテゴリは、キーワードか表示名に当たったときだけ（当たらなければ nil）")
    func matched() {
        #expect(EntryCategory.matched(in: "今月カフェいくら") == .cafe)
        #expect(EntryCategory.matched(in: "先月の食費") == .food)
        #expect(EntryCategory.matched(in: "その他にいくら") == .other)
        #expect(EntryCategory.matched(in: "今月いくら使った") == nil)
        // 記録の読み取り（guess）は表示名を見ない。
        #expect(EntryCategory.guess(from: "その他 肉 500") == .food)
    }
}
