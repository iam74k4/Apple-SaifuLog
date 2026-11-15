import Foundation
import Observation
import SaifuLogCore
import SwiftData

/// 利用者が登録したクレジットカードの 1 行（名前・締め日・引き落とし日・いつものカード・並び）。docs/design.md §8-2。
///
/// 記録は ID だけを持つ（`Entry.cardID`）ので、名前や日付を変えても記録は書き換えない。作ったカテゴリ（`CustomCategory`）と同じく、
/// 最初から iCloud 同期の制約に合わせ（すべての項目に既定値、一意制約も関係も持たない）、同じ ID の行が重なったら書き込んだ日時の
/// 新しい行を採る。**項目はすべて CloudKit の暗号化フィールドにする**（理由は `Entry`）。どのカードを持っているかと締め日は、
/// 家計の中身にあたるため。
@Model
final class CreditCard {
    /// ID（UUID の小文字の文字列）。記録の `cardID` が指す。SwiftData の `id` と重ならない名前にする。
    @Attribute(.allowsCloudEncryption) var cardID: String = ""
    /// 名前（`PaymentCard.validateName` で確かめた形）。
    @Attribute(.allowsCloudEncryption) var name: String = ""
    /// 締め日（1〜31。31 と、その月に無い日は月末）。
    @Attribute(.allowsCloudEncryption) var closingDay: Int = 31
    /// 引き落とし日（1〜31。31 と、その月に無い日は月末）。
    @Attribute(.allowsCloudEncryption) var paymentDay: Int = 27
    /// 締めた月の何か月後に引き落とすか（1 = 翌月、2 = 翌々月）。
    @Attribute(.allowsCloudEncryption) var paymentMonthOffset: Int = 1
    /// いつものカードか（「カードで」と名前を書かずに書いた記録をこのカードにする）。1 枚だけにする（`CreditCardStore`）。
    @Attribute(.allowsCloudEncryption) var isDefault: Bool = false
    /// 並び（小さいほど前）。
    @Attribute(.allowsCloudEncryption) var sortOrder: Int = 0
    /// 作った日時。並びが同じときに前にする。
    @Attribute(.allowsCloudEncryption) var createdAt: Date = Date.now
    /// 最後に書いた日時。同じ ID の行が重なったときに、新しいほうを採る。
    @Attribute(.allowsCloudEncryption) var updatedAt: Date = Date.now

    init(card: PaymentCard, sortOrder: Int, createdAt: Date) {
        self.cardID = card.id
        self.name = card.name
        self.closingDay = card.closingDay
        self.paymentDay = card.paymentDay
        self.paymentMonthOffset = card.paymentMonthOffset
        self.isDefault = card.isDefault
        self.sortOrder = sortOrder
        self.createdAt = createdAt
        self.updatedAt = createdAt
    }

    var card: PaymentCard {
        PaymentCard(
            id: cardID, name: name, closingDay: closingDay, paymentDay: paymentDay,
            paymentMonthOffset: PaymentCard.monthOffsetRange.contains(paymentMonthOffset) ? paymentMonthOffset : 1,
            isDefault: isDefault
        )
    }

    /// 並びの順に並べ、同じ ID の行が重なっていれば書き込んだ日時の新しい行を採る（iCloud の行き違い）。ID の空の行は除く。
    /// いつものカードが 2 枚以上あれば（2 台で別々に決めた）、書き込んだ日時の新しい 1 枚だけにする。
    static func resolved(_ rows: [CreditCard]) -> [PaymentCard] {
        var latest: [String: CreditCard] = [:]
        for row in rows where !row.cardID.isEmpty {
            if let current = latest[row.cardID], current.updatedAt >= row.updatedAt { continue }
            latest[row.cardID] = row
        }
        let sorted = latest.values.sorted { lhs, rhs in
            if lhs.sortOrder != rhs.sortOrder { return lhs.sortOrder < rhs.sortOrder }
            if lhs.createdAt != rhs.createdAt { return lhs.createdAt < rhs.createdAt }
            return lhs.cardID < rhs.cardID
        }
        let defaultID = sorted.filter(\.isDefault).max { $0.updatedAt < $1.updatedAt }?.cardID
        return sorted.map { row in
            var card = row.card
            card.isDefault = row.cardID == defaultID
            return card
        }
    }
}

/// カードの読み書き。保存に失敗したら変更を巻き戻し、呼び出し側に知らせる（`CustomCategoryStore` と同じ）。
@MainActor
struct CreditCardStore {
    let context: ModelContext
    /// 変更を書き込む処理。テストで失敗させるために差し替えられるようにしている。
    var save: (ModelContext) throws -> Void = { try $0.save() }
    /// 作った日時・書いた日時の基準。テストで固定の日時にする。
    var now: () -> Date = { .now }
    /// 新しいカードの ID を作る。テストで決めた ID にする。
    var makeID: () -> String = { UUID().uuidString.lowercased() }

    /// いまのカード（並びの順）。
    func cards() throws -> [PaymentCard] {
        CreditCard.resolved(try context.fetch(FetchDescriptor<CreditCard>()))
    }

    /// カードを登録する。名前を確かめ（`PaymentCard.validateName`）、いちばん後ろに並べる。登録したカードを返す。
    /// 最初の 1 枚は、いつものカードにする（「カードで」と書いた記録を、そのカードにするため）。
    @discardableResult
    func create(_ draft: PaymentCard) throws -> PaymentCard {
        let cards = try cards()
        guard cards.count < PaymentCard.maximumCount else { throw CreditCardError.tooMany }
        var card = draft
        card.id = makeID()
        card.name = try PaymentCard.validateName(draft.name, among: cards).get()
        card.isDefault = draft.isDefault || cards.isEmpty
        let rows = try context.fetch(FetchDescriptor<CreditCard>())
        if card.isDefault { clearDefault(in: rows) }
        let order = (rows.map(\.sortOrder).max() ?? -1) + 1
        context.insert(CreditCard(card: card, sortOrder: order, createdAt: now()))
        try commit()
        return card
    }

    /// 名前・締め日・引き落とし日・いつものカードを変える（記録は ID を指しているので書き換えない）。
    func update(_ card: PaymentCard) throws {
        let validated = try PaymentCard.validateName(card.name, among: try cards(), editing: card.id).get()
        let all = try context.fetch(FetchDescriptor<CreditCard>())
        let rows = all.filter { $0.cardID == card.id }
        guard !rows.isEmpty else { throw CreditCardError.notFound }
        if card.isDefault { clearDefault(in: all.filter { $0.cardID != card.id }) }
        for row in rows {
            row.name = validated
            row.closingDay = card.closingDay
            row.paymentDay = card.paymentDay
            row.paymentMonthOffset = card.paymentMonthOffset
            row.isDefault = card.isDefault
            row.updatedAt = now()
        }
        try commit()
    }

    /// 並びを変える（`ids` の順に並べ直す）。
    func reorder(_ ids: [String]) throws {
        for row in try context.fetch(FetchDescriptor<CreditCard>()) {
            guard let index = ids.firstIndex(of: row.cardID), row.sortOrder != index else { continue }
            row.sortOrder = index
            row.updatedAt = now()
        }
        try commit()
    }

    /// そのカードの記録の件数（削除の確認に出す）。
    func entryCount(of id: String) throws -> Int {
        try context.fetchCount(FetchDescriptor<Entry>(predicate: #Predicate { $0.cardID == id }))
    }

    /// カードを消す。そのカードの記録とくり返しの記録は「現金・その他」（カードなし）にしてから、1 回で書き込む
    /// （消したカードを指す記録を残さないため。残すと、ほかの端末で同じ ID のカードを作り直したように見えることがある）。
    func delete(_ id: String) throws {
        let entries = try context.fetch(FetchDescriptor<Entry>(predicate: #Predicate { $0.cardID == id }))
        let rules = try context.fetch(FetchDescriptor<RecurringEntry>(predicate: #Predicate { $0.cardID == id }))
        let rows = try context.fetch(FetchDescriptor<CreditCard>(predicate: #Predicate { $0.cardID == id }))
        for entry in entries {
            entry.cardID = ""
        }
        for rule in rules {
            rule.cardID = ""
            rule.updatedAt = now()
        }
        for row in rows {
            context.delete(row)
        }
        try commit {
            _ = try? context.fetch(FetchDescriptor<Entry>(predicate: #Predicate { $0.cardID == id }))
            _ = try? context.fetch(FetchDescriptor<RecurringEntry>(predicate: #Predicate { $0.cardID == id }))
        }
    }

    private func clearDefault(in rows: [CreditCard]) {
        for row in rows where row.isDefault {
            row.isDefault = false
            row.updatedAt = now()
        }
    }

    /// 書き込めなかった変更は取り消す（`CustomCategoryStore` と同じ理由。画面と保存先を食い違わせないため）。
    private func commit(afterRollback: () -> Void = {}) throws {
        do {
            try save(context)
        } catch {
            context.rollback()
            // iOS 26 では rollback だけだと、画面が持つ値が変更後のまま残る。保存済みの値を読み直す。
            _ = try? context.fetch(FetchDescriptor<CreditCard>())
            afterRollback()
            throw error
        }
    }
}

/// カードの読み書きの失敗（名前の確かめは `CardNameIssue`）。
enum CreditCardError: Error, Equatable {
    /// 登録できる数（`PaymentCard.maximumCount`）に届いている。
    case tooMany
    /// 変えようとしたカードが無い（ほかの端末で消した）。
    case notFound
}

/// いまのカードの一覧。ホームが 1 つ持ち（`CategoryCatalogModel` と同じ）、設定・直す画面・まとめに渡す。
///
/// 保存先に書き込まれたとき・iCloud で取り込んだとき・カードを登録したり直したりしたときに読み直す（`reload()`）。読めなければ前の
/// 一覧のまま（カードが無くても記録できるため）。
@MainActor
@Observable
final class CardCatalogModel {
    private(set) var cards: [PaymentCard] = []

    @ObservationIgnored let store: CreditCardStore

    init(store: CreditCardStore) {
        self.store = store
        reload()
    }

    /// 保存先から読み直す。変わっていなければ書き換えない（描き直しを起こさないため）。
    func reload() {
        guard let cards = try? store.cards(), cards != self.cards else { return }
        self.cards = cards
    }

    func card(id: String) -> PaymentCard? {
        guard !id.isEmpty else { return nil }
        return cards.first { $0.id == id }
    }
}
