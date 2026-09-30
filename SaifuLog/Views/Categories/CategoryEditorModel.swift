import Foundation
import Observation
import SaifuLogCore

/// カテゴリを作る・直す画面（シート）の状態と操作。名前・記号・色を決めて保存する。
///
/// ホームの返事の聞き返し（「＋ カテゴリを作る」。作ったらその記録のカテゴリにする）と、設定の「カテゴリ」（作る・直す）から開く。
/// 画面（`CategoryEditorSheet`）から切り離し、保存先と読み上げを差し替えて SaifuLogTests で確かめられるようにしている。
@MainActor
@Observable
final class CategoryEditorModel: Identifiable {
    /// 作るか、どのカテゴリを直すか。
    enum Mode: Equatable {
        case create
        case edit(EntryCategory)
    }

    /// よく使うカテゴリの候補（名前と記号）。作るときに押すと、名前と記号を入れる。家計簿でよく分ける費目のうち、組み込みの 8 種に
    /// 無いもの（家賃・服・美容・交際費などが「その他」に入らないように）。名前は画面の言語の文字列で入れる（作った後は利用者の名前）。
    static let presets: [(name: LocalizedStringResource, symbolName: String)] = [
        ("住居", "house"),
        ("衣服", "tshirt"),
        ("美容", "scissors"),
        ("交際", "wineglass"),
        ("教育", "graduationcap"),
        ("車", "car"),
        ("ペット", "pawprint"),
        ("趣味", "gamecontroller"),
        ("旅行", "airplane"),
        ("保険", "building.columns"),
        ("贈り物", "gift"),
        ("ジム", "dumbbell"),
    ]

    /// 色の名前（VoiceOver が読む。`Palette.customCategoryChoices` と同じ順）。
    static func colorName(_ index: Int) -> LocalizedStringResource {
        switch index {
        case 0: "群青"
        case 1: "蘇芳"
        case 2: "常盤"
        case 3: "柿"
        case 4: "桔梗"
        case 5: "鉄紺"
        case 6: "海松"
        case 7: "薔薇"
        case 8: "栗"
        default: "墨"
        }
    }

    /// 記号の名前（VoiceOver が読む。`CategoryCatalog.symbolChoices` の記号）。
    static func symbolLabel(_ symbol: String) -> LocalizedStringResource {
        switch symbol {
        case "tshirt": "シャツ"
        case "scissors": "はさみ"
        case "house": "家"
        case "gift": "贈り物"
        case "graduationcap": "学帽"
        case "pawprint": "足あと"
        case "car": "車"
        case "dumbbell": "ダンベル"
        case "heart": "ハート"
        case "gamecontroller": "ゲーム"
        case "book": "本"
        case "airplane": "飛行機"
        case "leaf": "葉"
        case "bag": "かばん"
        case "wineglass": "グラス"
        case "music.note": "音符"
        case "camera": "カメラ"
        case "wrench.and.screwdriver": "工具"
        case "building.columns": "建物"
        default: "きらめき"
        }
    }

    let mode: Mode
    /// 名前の入力欄。
    var name: String {
        didSet { issue = nil }
    }
    var symbolName: String
    var colorIndex: Int
    /// 保存しようとしたときの名前の問題（入力欄の下に出す）。直し始めたら消す。
    private(set) var issue: CategoryNameIssue?
    /// 保存に失敗した（アラートを出す）。
    var showsSaveFailure = false

    @ObservationIgnored private let store: CustomCategoryStore
    @ObservationIgnored private let catalog: CategoryCatalog
    @ObservationIgnored private let announce: @MainActor (String) -> Void
    @ObservationIgnored private let didSave: @MainActor (EntryCategory) -> Void

    /// - Parameters:
    ///   - catalog: 開いた時点のカテゴリの一覧（名前の重なりを見る。直すときは今の名前・記号・色を入れる）。
    ///   - didSave: 保存できたあとに、作った（直した）カテゴリを渡して呼ぶ（ホームは聞き返した記録のカテゴリにする）。
    init(
        mode: Mode,
        store: CustomCategoryStore,
        catalog: CategoryCatalog,
        announce: @escaping @MainActor (String) -> Void = { VoiceOver.announce($0) },
        didSave: @escaping @MainActor (EntryCategory) -> Void = { _ in }
    ) {
        self.mode = mode
        self.store = store
        self.catalog = catalog
        self.announce = announce
        self.didSave = didSave
        if case .edit(let category) = mode, let info = catalog.info(for: category) {
            name = info.name
            symbolName = info.symbolName
            colorIndex = info.colorIndex
        } else {
            name = ""
            symbolName = CategoryCatalog.symbolChoices[0]
            // 作ったカテゴリどうしの色が重なりにくいよう、作った数の次の色から始める。
            colorIndex = catalog.customs.count % Palette.customCategoryChoices.count
        }
    }

    /// 保存できるか（名前が空でない。長さや重なりは保存するときに確かめて、入力欄の下に知らせる）。
    var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// まだ使っていない候補（同じ名前のカテゴリが無いもの）。作るときだけ出す。
    var availablePresets: [(name: String, symbolName: String)] {
        guard mode == .create else { return [] }
        return Self.presets
            .map { (String(localized: $0.name), $0.symbolName) }
            .filter { if case .success = catalog.validateName($0.0) { true } else { false } }
    }

    /// 候補を選ぶ（名前と記号を入れる）。
    func choosePreset(name: String, symbolName: String) {
        self.name = name
        self.symbolName = symbolName
    }

    /// 保存する。保存できたら true（呼び出し側がシートを閉じる）。名前が使えなければ `issue` に理由を入れて false。
    @discardableResult
    func save() -> Bool {
        let category: EntryCategory
        do {
            switch mode {
            case .create:
                category = try store.create(name: name, symbolName: symbolName, colorIndex: colorIndex)
            case .edit(let editing):
                try store.update(editing, name: name, symbolName: symbolName, colorIndex: colorIndex)
                category = editing
            }
        } catch let error as CategoryNameIssue {
            issue = error
            return false
        } catch {
            showsSaveFailure = true
            return false
        }
        let saved = name.trimmingCharacters(in: .whitespacesAndNewlines)
        switch mode {
        case .create: announce(String(localized: "カテゴリ「\(saved)」を作りました"))
        case .edit: announce(String(localized: "カテゴリ「\(saved)」を直しました"))
        }
        didSave(category)
        return true
    }
}
