import Foundation
import SaifuLogCore
import SwiftData

/// 確認前に金額や日付が変わった相手を消さないよう、ID と照合する値を一緒に保存する。
struct PaymentReviewEvidence: Codable {
    struct Record: Codable {
        let key: String
        let amount: Int
        let spentAt: Date
        let memo: String
        let source: String

        @MainActor init(_ entry: Entry) {
            if entry.reviewID.isEmpty { entry.reviewID = UUID().uuidString }
            key = entry.reviewID
            amount = entry.amount
            spentAt = entry.spentAt
            memo = entry.memo
            source = entry.sourceRawValue
        }

        @MainActor func matches(_ entry: Entry) -> Bool {
            entry.reviewID == key && !entry.isIncome && entry.amount == amount && entry.spentAt == spentAt
                && entry.memo == memo && entry.sourceRawValue == source
        }
    }

    let payment: Record
    let records: [Record]
    let earlierPayment: Bool
    let total: Int?

    @MainActor init(payment: Entry, records: [Entry], earlierPayment: Bool, total: Int?) {
        self.payment = Record(payment)
        self.records = records.map(Record.init)
        self.earlierPayment = earlierPayment
        self.total = total
    }

    func encoded() -> String {
        // 固定の値だけを持つ Codable。失敗した場合も空の確認で削除操作を作らない。
        (try? JSONEncoder().encode(self)).flatMap { String(data: $0, encoding: .utf8) } ?? ""
    }

    init?(json: String) {
        guard let data = json.data(using: .utf8), let value = try? JSONDecoder().decode(Self.self, from: data) else { return nil }
        self = value
    }

    @MainActor func resolve(context: ModelContext, catalog: CategoryCatalog) throws -> PaymentOverlapQuestion? {
        func find(_ snapshot: Record) throws -> Entry? {
            let key = snapshot.key
            let matches = try context.fetch(FetchDescriptor<Entry>(predicate: #Predicate { $0.reviewID == key }))
            // ID が重なった場合も、どれを消すか勝手に決めない。
            guard matches.count == 1, let entry = matches.first, snapshot.matches(entry) else { return nil }
            return entry
        }
        guard let paymentEntry = try find(payment), paymentEntry.source == .wallet, !records.isEmpty else { return nil }
        var matched: [Entry] = []
        for record in records {
            guard let entry = try find(record), entry.source != .wallet else { return nil }
            matched.append(entry)
        }
        let counterpart: String
        if earlierPayment {
            counterpart = String(localized: "\(paymentEntry.summaryText(in: catalog))（\(paymentEntry.spentAt.formatted(date: .omitted, time: .shortened)) に払った）")
        } else if let first = matched.first, first.source == .receipt, !first.originalText.isEmpty {
            counterpart = first.originalText
        } else if matched.count == 1, let first = matched.first {
            counterpart = first.summaryText(in: catalog)
        } else {
            counterpart = "\(matched.map { $0.memo.isEmpty ? $0.kindText(in: catalog) : $0.memo }.formatted(.list(type: .and))) \(YenFormatter.string(from: matched.reduce(0) { $0 + $1.amount }))"
        }
        return PaymentOverlapQuestion(kind: earlierPayment ? .earlierPayment(total: total) : .earlierRecord,
                                      paymentID: paymentEntry.persistentModelID, counterpart: counterpart,
                                      recordIDs: matched.map(\.persistentModelID))
    }
}

/// 確認画面は記録の控えを使う。同期で消された SwiftData オブジェクトを画面から読まないため。
struct EntryReviewItem: Identifiable {
    let id: PersistentIdentifier
    let memo: String
    let amount: Int
    let category: EntryCategory
    let spentAt: Date
    let needsCategory: Bool
    let overlap: PaymentOverlapQuestion?
}
