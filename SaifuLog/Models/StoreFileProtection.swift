import Foundation
import OSLog

/// 記録の保存先のファイルに、データ保護の Complete を明示して当てる（docs/design.md §5-4）。
///
/// SwiftData（Core Data）は、SQLite のファイルを作るときに保護クラスを自分で指定する。その既定は「最初のロック解除の後は
/// 読める」（`NSPersistentStoreFileProtectionKey` の既定。iOS SDK の NSPersistentStoreCoordinator.h）で、エンタイトルメントの
/// 既定の保護（Complete）は、保護を指定せずに作ったファイルにしか効かない。SwiftData の `ModelConfiguration` には保護クラスを
/// 渡す口が無いので、開いた直後にファイルへ明示して当てる。開くたびに当てるのは、-wal を SQLite が作り直すことがあるため。
enum StoreFileProtection {
    /// 当てるファイルの末尾。本体と -wal（書き込みの途中の記録で、記録の中身を含む）。
    ///
    /// -shm には当てない。SQLite がメモリに写して使う索引（-wal のどこに何があるか）で、記録の中身を含まない。Complete にすると、
    /// ロック中にアプリが裏で保存先に触れたとき（iCloud の取り込みなど）に、写したメモリを読めずにアプリが落ちるおそれがあるため。
    static let protectedSuffixes = ["", "-wal"]

    private static let logger = Logger(subsystem: "com.iam74k4.SaifuLog", category: "store")

    /// `storeURL` の保存先のファイルと、それを入れたフォルダに Complete を当てる。無いファイルは飛ばす。
    ///
    /// 当てられなくても止めない（保存先は開けている。次に開いたときにまた当てる）。理由は、ファイルの名前とエラーの番号だけを
    /// ログに残す（記録の中身は含まない）。
    /// - Parameter setProtection: 保護クラスを当てる処理。テストで、どのファイルに当てたかを集める。
    static func apply(
        toStoreAt storeURL: URL,
        setProtection: (URL) throws -> Void = { url in
            try FileManager.default.setAttributes(
                [.protectionKey: FileProtectionType.complete], ofItemAtPath: url.path(percentEncoded: false)
            )
        }
    ) {
        let folder = storeURL.deletingLastPathComponent()
        // フォルダにも当てる。後からこの中に保護を指定せずに作るファイルが、Complete を継ぐように（アプリを一度も開く前に
        // ロック中で Apple Pay の支払いを受け取ると、受け箱がこのフォルダを弱い保護で作る。`PaymentInbox`）。
        let files = protectedSuffixes.map {
            folder.appending(path: storeURL.lastPathComponent + $0, directoryHint: .notDirectory)
        }
        for url in [folder] + files where FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) {
            do {
                try setProtection(url)
            } catch {
                let error = error as NSError
                logger.error(
                    "保護クラスを当てられませんでした: \(url.lastPathComponent, privacy: .public) \(error.domain, privacy: .public) \(error.code)"
                )
            }
        }
    }
}
