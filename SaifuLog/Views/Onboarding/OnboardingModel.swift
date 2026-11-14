import Foundation
import Observation
import SwiftData

/// 初回の案内（① ようこそ → ホーム）の状態と操作。
///
/// 画面（`OnboardingView`・`WelcomeView`）から切り離し、設定の置き場所（UserDefaults）・AI の可否を差し替えて
/// SaifuLogTests で確かめられるようにしている。
@MainActor
@Observable
final class OnboardingModel {
    /// 案内を終えた。終えたら呼び出し側（`AppRootView`）がホームに切り替える。
    private(set) var isCompleted = false

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let currentAIStatus: @MainActor () -> OnDeviceAIStatus

    /// - Parameters:
    ///   - defaults: 案内を終えたことを書く先。テストでは使い捨ての領域を渡す。
    ///   - aiStatus: この端末でいま AI を使えるか。テストで差し替える。
    init(
        defaults: UserDefaults = .standard,
        aiStatus: @escaping @MainActor () -> OnDeviceAIStatus = { EntryParserFactory.aiStatus }
    ) {
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

    /// ① の「はじめる」。案内を終える。
    ///
    /// 終えたことを書いてから、ホームへの切り替えを知らせる。先に書くのは、切り替えの途中でアプリを終了されても、
    /// 次の起動で案内をやり直させないため。
    func start() {
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
    /// 2 つは記録の例、3 つ目は質問の例（記録も質問も同じ入力欄に打てることを、最初に見せるため）。どれも AI が無くても
    /// キーワード辞書で同じように記録・回答できる書き方にしてあり、SaifuLogTests で確かめている（AI が使えない端末の案内が
    /// 「上の例のような書き方なら、AI がなくても記録や質問ができる」と言うため）。
    /// 記録のされ方には、AI とキーワード辞書で変わりうるものを書かない。金額・日付・割り勘の人数・件数はコアが入力の
    /// 文と突き合わせるので同じになるが、カテゴリは品目が文に書かれていればモデルの答えを採るため、書かない
    /// （「ランチ」も、AI が使える端末では食費になるとは言い切れない）。質問の答え方は、期間とカテゴリを文からコードが読み、
    /// 「いくら」だけの文ではモデルが件数や内訳を選んでも支出の額で答え（`QuestionReading.resolved(with:)`）、数字もコードが
    /// 計算するので、AI の有無で変わらない。
    static let all: [WelcomeExample] = [
        WelcomeExample(text: "ランチ 850", result: "今日の日付で ¥850 を記録"),
        WelcomeExample(text: "昨日 焼肉12000 4人で割り勘", result: "昨日の日付で、1人分の ¥3,000 を記録"),
        WelcomeExample(text: "今月カフェいくら?", result: "今月のカフェの支出を答える（記録はしない）"),
    ]
}
