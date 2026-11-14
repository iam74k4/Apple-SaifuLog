import Foundation
import SaifuLogCore
import SwiftData
import Testing
@testable import SaifuLog

/// 初回の案内（OnboardingModel）。出すかどうかの判定と、終えたときの設定。
/// メモリの上の保存先と、使い捨ての UserDefaults の領域で確かめる。
@MainActor
struct OnboardingModelTests {
    /// OnboardingModel と、その保存先・設定の置き場所・AI の可否の代わり。
    @MainActor
    final class Fixture {
        let context: ModelContext
        let defaults: UserDefaults
        var aiStatus = OnDeviceAIStatus.available
        private let suiteName = "OnboardingModelTests.\(UUID().uuidString)"

        init() throws {
            context = try TestSupport.makeContext()
            defaults = try #require(UserDefaults(suiteName: suiteName))
        }

        deinit {
            // deinit は MainActor の外で動くので、MainActor のプロパティの defaults ではなく、名前で消す。
            UserDefaults.standard.removePersistentDomain(forName: suiteName)
        }

        var budgetStore: BudgetStore {
            var store = BudgetStore(context: context)
            store.now = { TestSupport.now }
            return store
        }

        func makeModel() -> OnboardingModel {
            OnboardingModel(defaults: defaults, aiStatus: { [unowned self] in aiStatus })
        }

        var hasCompletedOnboarding: Bool {
            defaults.bool(for: AppSettings.hasCompletedOnboarding)
        }

        func needsOnboarding() -> Bool {
            OnboardingModel.needsOnboarding(defaults: defaults, context: context)
        }
    }

    // MARK: - 出すかどうか

    /// 初めて開いた（案内を終えておらず、記録も無い）ときだけ出す。出すと決めただけでは、終えたことにしない。
    @Test func showsOnFirstLaunch() throws {
        let fixture = try Fixture()

        #expect(fixture.needsOnboarding())
        #expect(!fixture.hasCompletedOnboarding)
        // 案内の途中でアプリを終了したら、次の起動でもまた出す。
        #expect(fixture.needsOnboarding())
    }

    @Test func hiddenAfterCompleted() throws {
        let fixture = try Fixture()
        fixture.defaults.set(true, for: AppSettings.hasCompletedOnboarding)

        #expect(!fixture.needsOnboarding())
    }

    /// 案内を終えていたら、記録があるかは読まない（起動のたびに保存先を数えない）。
    @Test func completedFlagSkipsRecordCheck() throws {
        let fixture = try Fixture()
        fixture.defaults.set(true, for: AppSettings.hasCompletedOnboarding)
        var checked = false

        let needs = OnboardingModel.needsOnboarding(defaults: fixture.defaults) {
            checked = true
            return false
        }

        #expect(!needs)
        #expect(!checked)
    }

    /// 案内を作る前から使っていて記録がある人には出さず、終えたことにしておく。
    @Test func hiddenWhenRecordsExist() throws {
        let fixture = try Fixture()
        try EntryStore(context: fixture.context).insert([TestSupport.entry()])

        #expect(!fixture.needsOnboarding())
        #expect(fixture.hasCompletedOnboarding)
    }

    /// 終えたことにしてあるので、その後に記録をすべて削除しても、次の起動で案内は出ない。
    @Test func staysHiddenAfterDeletingAllRecords() throws {
        let fixture = try Fixture()
        let store = EntryStore(context: fixture.context)
        let entry = TestSupport.entry()
        try store.insert([entry])
        #expect(!fixture.needsOnboarding())

        try store.delete([entry])

        #expect(!fixture.needsOnboarding())
    }

    /// 数えるのは記録だけで、予算は数えない。予算だけが決まっていて記録が無い端末には案内を出す。
    /// 出しても終えたことにはしない。
    @Test func showsWhenOnlyBudgetExists() throws {
        let fixture = try Fixture()
        try fixture.budgetStore.setAmount(150_000, for: .total)
        try #require(try fixture.budgetStore.plan() == BudgetPlan(total: 150_000))

        #expect(fixture.needsOnboarding())
        #expect(!fixture.hasCompletedOnboarding)
    }

    /// 記録があるかを読めなかったときは、案内を終えたかどうかだけで決める（終えたことにはしない）。
    @Test func showsWhenRecordCheckFails() throws {
        let fixture = try Fixture()

        let needs = OnboardingModel.needsOnboarding(defaults: fixture.defaults) { throw TestError() }

        #expect(needs)
        #expect(!fixture.hasCompletedOnboarding)
    }

    // MARK: - 進み方

    /// 「はじめる」で案内を終える（予算は聞かない）。終えたので、次の起動では出さない。
    @Test func startCompletes() throws {
        // Fixture を変数に持っておく。モデルに渡した AI の可否の関数は Fixture を unowned で参照するので、
        // 先に Fixture が解放されると、それを呼んだときに落ちる。
        let fixture = try Fixture()
        let model = fixture.makeModel()
        #expect(!model.isCompleted)

        model.start()

        #expect(model.isCompleted)
        #expect(fixture.hasCompletedOnboarding)
        #expect(try fixture.budgetStore.plan() == BudgetPlan())
        #expect(!fixture.needsOnboarding())
    }

    /// AI の可否は覚えておかず、読むたびに確かめる（案内を見ている間に Apple Intelligence をオンにしても変わる）。
    @Test func aiStatusIsReadEachTime() throws {
        let fixture = try Fixture()
        fixture.aiStatus = .appleIntelligenceNotEnabled
        let model = fixture.makeModel()
        #expect(model.aiStatus == .appleIntelligenceNotEnabled)

        fixture.aiStatus = .available

        #expect(model.aiStatus == .available)
    }

    // MARK: - 入力の例

    /// ようこその例は、AI が無くてもキーワード辞書で書いたとおりに記録・回答できる（AI が使えない端末の案内が
    /// 「上の例のような書き方なら、AI がなくても記録や質問ができる」と言うため）。例を差し替えたら、ここも合わせる。
    /// 確かめるのは記録のされ方に書いたもの（金額・日付・割り勘の人数・件数、質問なら記録しないことと何を答えるか）だけ。
    /// カテゴリは AI が使える端末ではモデルの答えになりうるので、記録のされ方に書かず、ここでも確かめない。
    @Test func examplesAreRecordableWithoutAI() async throws {
        let parser = RuleBasedParser(calendar: TestSupport.calendar, now: { TestSupport.now })
        let examples = WelcomeExample.all
        try #require(examples.count == 3)

        func intent(_ text: String) -> InputIntent {
            InputIntentClassifier.classify(text, now: TestSupport.now, calendar: TestSupport.calendar)
        }

        #expect(intent(examples[0].text) == .record)
        let lunch = try await parser.parse(examples[0].text)
        #expect(lunch.map(\.amount) == [850])
        #expect(lunch.map(\.daysAgo) == [0])

        #expect(intent(examples[1].text) == .record)
        let yakiniku = try await parser.parse(examples[1].text)
        #expect(yakiniku.map(\.amount) == [3_000])
        #expect(yakiniku.map(\.daysAgo) == [1])
        #expect(yakiniku.map(\.splitCount) == [4])

        // 3 つ目は質問。記録にはならず、今月のカフェの支出として答える。
        #expect(intent(examples[2].text) == .question)
        #expect(QuestionParser.question(from: examples[2].text, now: TestSupport.now, calendar: TestSupport.calendar)
            == LedgerQuestion(period: .thisMonth, metric: .categoryExpense, category: .cafe))
    }

    /// 例と AI の案内の文は、英語の表に訳がある（String Catalog のキーと食い違うと、英語の画面に日本語が出る）。
    @Test func welcomeTextsAreLocalized() throws {
        let english = try LocalizationTests.bundle(for: "en")
        let resources = WelcomeExample.all.map(\.result)
            + OnDeviceAIStatus.allCases.flatMap { [$0.title, $0.message] }

        for resource in resources {
            let key = resource.key
            #expect(english.localizedString(forKey: key, value: nil, table: nil) != key, "\(key) の英語の訳が無い")
        }
    }
}
