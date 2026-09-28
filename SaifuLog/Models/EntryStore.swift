import SwiftData

/// 記録の保存と削除。保存に失敗したら変更を巻き戻し、呼び出し側に知らせる。
///
/// 失敗を捨てると、保存できていないのに「記録しました」と読み上げたり、消したはずの記録が
/// 次の起動で戻ってきたりする。呼び出し側は throw を受けて利用者に知らせる。
@MainActor
struct EntryStore {
    let context: ModelContext
    /// 変更を書き込む処理。テストで失敗させるために差し替えられるようにしている。
    var save: (ModelContext) throws -> Void = { try $0.save() }

    func insert(_ entries: [Entry]) throws {
        for entry in entries {
            context.insert(entry)
        }
        try commit()
    }

    func delete(_ entries: [Entry]) throws {
        for entry in entries {
            context.delete(entry)
        }
        try commit()
    }

    /// 書き込めなかった変更は取り消す。残しておくと、画面には出たまま次の自動保存で
    /// 黙って書き込まれたり、書き込まれずに消えたりして、画面と保存先が食い違うため。
    private func commit() throws {
        do {
            try save(context)
        } catch {
            context.rollback()
            throw error
        }
    }
}
