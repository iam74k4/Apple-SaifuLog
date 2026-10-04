import Foundation

/// ショートカットのオートメーション（Apple Pay で払ったとき）から受け取った支払い。アプリを開いたときに記録にする。
struct CapturedPayment: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    /// 金額（円）。
    let amount: Int
    /// 店名（ウォレットの表記のまま）。
    let merchant: String
    /// 受け取った日時（払った日時）。
    let paidAt: Date
}

/// 受け取った支払いを、アプリを開くまで置いておく受け箱（アプリで 1 つ。docs/design.md §9 の Apple Pay の支払いの決め事）。
///
/// 支払いのオートメーションは、iPhone がロックされたまま（ウォレットで払った直後）に動くことが多い。記録の保存先は
/// NSFileProtectionComplete で守っていてロック中は読み書きできないので、受け取った支払い（金額・店名・日時）だけを、
/// ロック中でも書ける保護のクラス（起動してから最初にロックを解いた後。`completeUntilFirstUserAuthentication`）の小さな
/// ファイルに置き、次にアプリを開いたときにホームが記録にして消す（`HomeModel.importCapturedPayments`）。端末の外へは送らない。
@MainActor
final class PaymentInbox {
    /// アプリで使う受け箱。テストで使い捨ての場所のものに差し替える。
    static var shared = PaymentInbox()

    /// 支払いを受け取ったことの知らせ（アプリを開いているときは、すぐ記録にする）。
    static let didReceive = Notification.Name("SaifuLog.PaymentInbox.didReceive")

    /// 受け箱の置き場所（Application Support/PaymentInbox）。
    let directory: URL

    init(directory: URL = URL.applicationSupportDirectory.appending(path: "PaymentInbox", directoryHint: .isDirectory)) {
        self.directory = directory
    }

    private var fileURL: URL {
        directory.appending(path: "pending.json", directoryHint: .notDirectory)
    }

    /// 受け取った支払い（受け取った順）。読めない・無ければ空。
    func pending() -> [CapturedPayment] {
        (try? readPending()) ?? []
    }

    /// 読めない受け箱を空と扱って上書きしない。存在しない場合だけ空で返す。
    func readPending() throws -> [CapturedPayment] {
        let data: Data
        do { data = try Data(contentsOf: fileURL) }
        catch let error as CocoaError where error.code == .fileReadNoSuchFile { return [] }
        return try JSONDecoder().decode([CapturedPayment].self, from: data)
    }

    /// 金額や店名を残さず、受信したことだけを設定画面で確認するための日時。
    var lastReceivedAt: Date? {
        guard let data = try? Data(contentsOf: directory.appending(path: "last-received.json")) else { return nil }
        return try? JSONDecoder().decode(Date.self, from: data)
    }

    /// 支払いを足す。
    @discardableResult
    func append(amount: Int, merchant: String, paidAt: Date) throws -> CapturedPayment {
        let payment = CapturedPayment(id: UUID(), amount: amount, merchant: merchant, paidAt: paidAt)
        try write(readPending() + [payment])
        // 支払い本体の保存が正。状態表示だけの失敗で再送を促し、二重受信させない。
        if let data = try? JSONEncoder().encode(paidAt) {
            try? data.write(to: directory.appending(path: "last-received.json"), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        }
        NotificationCenter.default.post(name: Self.didReceive, object: nil)
        return payment
    }

    /// 記録にした支払いを消す。空になったらファイルごと消す（家計の中身を残しておかないため）。
    func remove(_ ids: Set<UUID>) throws {
        let remaining = try readPending().filter { !ids.contains($0.id) }
        if remaining.isEmpty {
            if FileManager.default.fileExists(atPath: fileURL.path) {
                try FileManager.default.removeItem(at: fileURL)
            }
        } else {
            try write(remaining)
        }
    }

    /// ロック中（最初にロックを解いた後）でも書ける保護のクラスで書く。アプリ全体の既定（NSFileProtectionComplete）では、
    /// ロック中に動くオートメーションから書けないため。アプリを一度も開く前は Application Support もまだ無く、途中のフォルダも
    /// この保護で作る（ロック中に Complete のフォルダは作れないため）。Application Support は、保存先を開いたときに Complete に
    /// 戻す（`StoreFileProtection`）。
    private func write(_ payments: [CapturedPayment]) throws {
        try FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true,
            attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication]
        )
        let data = try JSONEncoder().encode(payments)
        try data.write(to: fileURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }
}
