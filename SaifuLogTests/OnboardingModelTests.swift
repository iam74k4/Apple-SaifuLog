import Foundation
import SaifuLogCore
import SwiftData
import Testing
@testable import SaifuLog

/// 初回の案内（OnboardingModel）。出すかどうかの判定、終えたときの設定、② を飛ばしたとき。
/// メモリの上の保存先と、使い捨ての UserDefaults の領域で確かめる。
@MainActor
struct OnboardingModelTests {
    /// OnboardingModel と、その保存先・設定の置き場所・AI の可否の代わり。
    @MainActor
    final class Fixture {
        let context: ModelContext
        let defaults: UserDefaults
        var aiStatus = OnDeviceAIStatus.available
        private(set) var announcements: [String] = []
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
            OnboardingModel(
                budgetStore: budgetStore,
                defaults: defaults,
                aiStatus: { [unowned self] in aiStatus },
                announce: { [unowned self] in announcements.append($0) }
            )
        }

        var hasCompletedOnboarding: Bool {
            defaults.bool(for: AppSettings.hasCompletedOnboarding)
        }

        func needsOnboarding() -> Bool {
            OnboardingModel.needsOnboarding(defaults: defaults, context: context)
        }

        func budgetRows() throws -> [Budget] {
            try context.fetch(FetchDescriptor<Budget>())
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

    /// 数えるのは記録だけで、予算は数えない。予算だけが決まっていて記録が無い端末には案内を出す（design.md §9）。
    /// 出しても終えたことにはしない（② には決めた予算が入って開く）。
    @Test func showsWhenOnlyBudgetExists() throws {
        let fixture = try Fixture()
        try fixture.budgetStore.setAmount(150_000, for: .total)
        try #require(try fixture.budgetStore.plan() == BudgetPlan(total: 150_000))

        #expect(fixture.needsOnboarding())
        #expect(!fixture.hasCompletedOnboarding)
        let model = fixture.makeModel()
        #expect(model.budgetSetup.totalAmount == 150_000)
        #expect(model.budgetSetup.hadTotalBudget)
    }

    /// 記録があるかを読めなかったときは、案内を終えたかどうかだけで決める（終えたことにはしない）。
    @Test func showsWhenRecordCheckFails() throws {
        let fixture = try Fixture()

        let needs = OnboardingModel.needsOnboarding(defaults: fixture.defaults) { throw TestError() }

        #expect(needs)
        #expect(!fixture.hasCompletedOnboarding)
    }

    // MARK: - 進み方

    @Test func startShowsBudgetSetup() throws {
        // Fixture を変数に持っておく。モデルに渡した AI の可否と読み上げの関数は Fixture を unowned で参照するので、
        // 先に Fixture が解放されると、それらを呼んだときに落ちる。
        let fixture = try Fixture()
        let model = fixture.makeModel()
        #expect(!model.showsBudgetSetup)

        model.start()

        #expect(model.showsBudgetSetup)
        #expect(!model.isCompleted)
    }

    /// ② で予算を保存したら、予算を書き、案内を終える。
    @Test func savingBudgetCompletes() throws {
        let fixture = try Fixture()
        let model = fixture.makeModel()
        model.start()
        model.budgetSetup.selectQuickAmount(150_000)

        // BudgetSetupView の保存のボタンと同じ順（保存できたら onFinish）。
        #expect(model.budgetSetup.save())
        model.finishBudgetSetup()

        #expect(model.isCompleted)
        #expect(fixture.hasCompletedOnboarding)
        #expect(try fixture.budgetStore.plan() == BudgetPlan(total: 150_000))
        #expect(fixture.announcements.first?.contains("¥150,000") == true)
        // 終えたので、次の起動では出さない。
        #expect(!fixture.needsOnboarding())
    }

    /// ② を「あとで」で飛ばしても案内を終える。予算は書かない。
    @Test func skippingBudgetCompletes() throws {
        let fixture = try Fixture()
        let model = fixture.makeModel()
        model.start()
        model.budgetSetup.totalText = "150,000"

        model.skipBudgetSetup()

        #expect(model.isCompleted)
        #expect(fixture.hasCompletedOnboarding)
        #expect(try fixture.budgetRows().isEmpty)
        #expect(fixture.announcements.isEmpty)
        #expect(!fixture.needsOnboarding())
    }

    /// ② の保存に失敗したら、案内を終えない（保存の画面に残り、もう一度保存するか「あとで」を選べる）。
    @Test func budgetSaveFailureKeepsOnboarding() throws {
        let fixture = try Fixture()
        var store = fixture.budgetStore
        store.save = { _ in throw TestError() }
        let model = OnboardingModel(budgetStore: store, defaults: fixture.defaults, aiStatus: { .available }, announce: { _ in })
        model.start()
        model.budgetSetup.selectQuickAmount(150_000)

        if model.budgetSetup.save() { model.finishBudgetSetup() }

        #expect(model.budgetSetup.showsSaveFailure)
        #expect(!model.isCompleted)
        #expect(!fixture.hasCompletedOnboarding)
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

    /// ようこその例は、AI が無くてもキーワード辞書で書いたとおりに記録できる（AI が使えない端末の案内が
    /// 「上の例のような書き方なら記録できる」と言うため）。例を差し替えたら、ここも合わせる。
    /// 確かめるのは記録のされ方に書いたもの（金額・日付・割り勘の人数・件数）だけ。カテゴリは AI が使える端末では
    /// モデルの答えになりうるので、記録のされ方に書かず、ここでも確かめない。
    @Test func examplesAreRecordableWithoutAI() async throws {
        let parser = RuleBasedParser(calendar: TestSupport.calendar, now: { TestSupport.now })
        let examples = WelcomeExample.all
        try #require(examples.count == 3)

        let lunch = try await parser.parse(examples[0].text)
        #expect(lunch.map(\.amount) == [850])
        #expect(lunch.map(\.daysAgo) == [0])

        let yakiniku = try await parser.parse(examples[1].text)
        #expect(yakiniku.map(\.amount) == [3_000])
        #expect(yakiniku.map(\.daysAgo) == [1])
        #expect(yakiniku.map(\.splitCount) == [4])

        let shopping = try await parser.parse(examples[2].text)
        #expect(shopping.map(\.amount) == [2_480, 1_200])
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
