import Foundation
import Observation
import SwiftData

/// 初回の案内（① ようこそ → ② 予算を決める → ③ ホーム）の状態と操作。
///
/// 画面（`OnboardingView`・`WelcomeView`）から切り離し、設定の置き場所（UserDefaults）・予算の保存先・AI の可否を
/// 差し替えて SaifuLogTests で確かめられるようにしている。
@MainActor
@Observable
final class OnboardingModel {
    /// ② 予算を決める画面を出しているか（① の「はじめる」で進み、戻ると false に戻る）。
    var showsBudgetSetup = false
    /// 案内を終えた。終えたら呼び出し側（`AppRootView`）がホームに切り替える。
    private(set) var isCompleted = false
    /// ② の状態と操作。① に戻ってから進み直しても入れた額が残るよう、案内の間は同じものを使う。
    let budgetSetup: BudgetSetupModel

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let currentAIStatus: @MainActor () -> OnDeviceAIStatus

    /// - Parameters:
    ///   - defaults: 案内を終えたことを書く先。テストでは使い捨ての領域を渡す。
    ///   - aiStatus: この端末でいま AI を使えるか。テストで差し替える。
    ///   - announce: VoiceOver に読み上げさせる（② の保存のとき）。テストで読み上げる文を集める。
    init(
        budgetStore: BudgetStore,
        defaults: UserDefaults = .standard,
        aiStatus: @escaping @MainActor () -> OnDeviceAIStatus = { EntryParserFactory.aiStatus },
        announce: @escaping @MainActor (String) -> Void = { VoiceOver.announce($0) }
    ) {
        self.budgetSetup = BudgetSetupModel(store: budgetStore, announce: announce)
        self.defaults = defaults
        self.currentAIStatus = aiStatus
    }

    /// この端末でいま AI を使えるか。
    ///
    /// 覚えておかずに読むたびに確かめる。案内を見ている間にも、設定で Apple Intelligence をオンにしたり、モデルの
    /// ダウンロードが済んだりして変わるため（Foundation Models の `SystemLanguageModel` は Observable なので、
    /// 画面の描画の中で読めば、変わったときに描き直される）。
    var aiStatus: OnDeviceAIStatus {
        currentAIStatus()
    }

    /// ① の「はじめる」。② 予算を決める へ進む。
    func start() {
        showsBudgetSetup = true
    }

    /// ② で予算を保存した（`BudgetSetupView` の `onFinish`）。案内を終える。
    func finishBudgetSetup() {
        complete()
    }

    /// ② の「あとで」。予算を決めずに案内を終える。予算はホームの帯からいつでも決められる。
    func skipBudgetSetup() {
        complete()
    }

    /// 案内を終えたことを書いてから、ホームへの切り替えを知らせる。先に書くのは、切り替えの途中でアプリを
    /// 終了されても、次の起動で案内をやり直させないため。
    private func complete() {
        guard !isCompleted else { return }
        defaults.set(true, for: AppSettings.hasCompletedOnboarding)
        isCompleted = true
    }
}

// MARK: - 初回の案内を出すか

extension OnboardingModel {
    /// 初回の案内を出すか。保存先を開いて最初の画面を出すときに一度だけ呼ぶ。
    ///
    /// 案内を終えていなくても、記録が 1 件でもあれば出さず、終えたことにしておく。案内を作る前の版から使っている人に、
    /// 使い方の例を見せ直さないため。終えたことにしておかないと、あとで記録をすべて削除した後の起動で案内が出てしまう。
    /// 記録があるかを読めなかったときは、案内を終えたかどうかだけで決める（案内が出るだけで、記録には触れない）。
    static func needsOnboarding(defaults: UserDefaults, hasRecords: () throws -> Bool) -> Bool {
        guard !defaults.bool(for: AppSettings.hasCompletedOnboarding) else { return false }
        guard (try? hasRecords()) == true else { return true }
        defaults.set(true, for: AppSettings.hasCompletedOnboarding)
        return false
    }

    /// 保存先に記録があるかを見て、初回の案内を出すかを決める。
    static func needsOnboarding(defaults: UserDefaults = .standard, context: ModelContext) -> Bool {
        needsOnboarding(defaults: defaults) {
            try context.fetchCount(FetchDescriptor<Entry>()) > 0
        }
    }
}

// MARK: - 入力の例

/// ようこそ（①）に出す入力の例。
struct WelcomeExample: Identifiable, Sendable {
    /// 入力欄に打つ文。日本語のまま見せる（解析が日本語の入力を前提にしているため、訳さない）。
    let text: String
    /// どう記録されるか。
    let result: LocalizedStringResource

    var id: String { text }
}

extension WelcomeExample {
    /// 出す例。差し替えるときはここだけを直す。
    ///
    /// 質問の機能ができたら、3 つ目を質問の例（「今月カフェいくら?」）に差し替える。それまでは記録の例だけにする
    /// （まだできないことを例に出さない）。どれも AI が無くてもキーワード辞書で同じように記録できる書き方にしてあり、
    /// SaifuLogTests で確かめている（AI が使えない端末の案内が「上の例のような書き方なら記録できる」と言うため）。
    /// 記録のされ方には、AI とキーワード辞書で変わりうるものを書かない。金額・日付・割り勘の人数・件数はコアが入力の
    /// 文と突き合わせるので同じになるが、カテゴリは品目が文に書かれていればモデルの答えを採るため、書かない
    /// （「ランチ」も、AI が使える端末では食費になるとは言い切れない）。
    static let all: [WelcomeExample] = [
        WelcomeExample(text: "ランチ 850", result: "今日の日付で ¥850 を記録"),
        WelcomeExample(text: "昨日 焼肉12000 4人で割り勘", result: "昨日の日付で、1人分の ¥3,000 を記録"),
        WelcomeExample(text: "スーパー2480とドラッグ1200", result: "2件に分けて記録"),
    ]
}
