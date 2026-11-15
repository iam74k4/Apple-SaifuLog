import Foundation
import Observation
import SwiftData

/// 初回の案内（① ようこそ → ホーム）の状態と操作。
///
/// 画面（`OnboardingView`・`WelcomeView`）から切り離し、設定の置き場所（UserDefaults）を差し替えて
/// SaifuLogTests で確かめられるようにしている。
@MainActor
@Observable
final class OnboardingModel {
    /// 案内を終えた。終えたら呼び出し側（`AppRootView`）がホームに切り替える。
    private(set) var isCompleted = false

    @ObservationIgnored private let defaults: UserDefaults

    /// - Parameter defaults: 案内を終えたことを書く先。テストでは使い捨ての領域を渡す。
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
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

/// 記録が無いホーム（`EmptyTimelineView`）に出す入力の例。押すと入力欄に入る。差し替えるときはここだけを直す。
///
/// 入力の例は日本語のまま見せる（解析が日本語の入力を前提にしているため、訳さない）。どれも AI が無くてもキーワード辞書で
/// 同じように記録・回答できる書き方にしてあり、SaifuLogTests で確かめている（AI が使えない端末でも、例のとおりに書けば
/// 記録や質問ができるように）。前は初回の案内（①）にも同じような例を並べていたが、続けて同じ例を見せることになり、案内の
/// 例は押せそうに見えて押せなかったので、例はここだけにした。
enum HomeExamples {
    /// 記録の例。
    static let record = ["ランチ 850", "昨日 焼肉12000 4人で割り勘", "給料 25万"]
    /// 質問の例。
    static let question = ["今月カフェいくら?"]
    /// 月の予算を決める例（チャットの操作 `ChatCommand.setMonthlyBudget` に読める文）。
    static let budget = ["今月の予算を5万にして"]
}
