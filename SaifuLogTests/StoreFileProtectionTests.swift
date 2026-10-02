import Foundation
import Testing
@testable import SaifuLog

/// 保存先のファイルに Complete を当てる処理（`StoreFileProtection`）。どのファイルに当て、どれに当てないかを確かめる。
/// シミュレータはデータ保護を効かせないので、実際の保護クラスは実機の診断画面で確かめる（docs/design.md §5-4）。
struct StoreFileProtectionTests {
    static func makeFolder(files: [String]) throws -> URL {
        let folder = URL.temporaryDirectory.appending(path: "StoreFileProtectionTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for name in files {
            try Data().write(to: folder.appending(path: name, directoryHint: .notDirectory))
        }
        return folder
    }

    /// 本体と -wal とフォルダに当て、-shm には当てない（記録の中身を含まず、Complete にするとロック中に落ちるおそれがあるため）。
    @Test func protectsStoreWalAndFolderButNotShm() throws {
        let folder = try Self.makeFolder(files: ["default.store", "default.store-wal", "default.store-shm"])
        defer { try? FileManager.default.removeItem(at: folder) }
        var protected: [String] = []

        StoreFileProtection.apply(toStoreAt: folder.appending(path: "default.store")) { protected.append($0.lastPathComponent) }

        #expect(protected == [folder.lastPathComponent, "default.store", "default.store-wal"])
    }

    /// まだ無いファイル（-wal を SQLite がまだ作っていない）は飛ばす。
    @Test func skipsMissingFiles() throws {
        let folder = try Self.makeFolder(files: ["default.store"])
        defer { try? FileManager.default.removeItem(at: folder) }
        var protected: [String] = []

        StoreFileProtection.apply(toStoreAt: folder.appending(path: "default.store")) { protected.append($0.lastPathComponent) }

        #expect(protected == [folder.lastPathComponent, "default.store"])
    }

    /// 当てられなくても止めず、残りのファイルにも当てる（保存先は開けているので、次に開いたときにまた当てる）。
    @Test func keepsGoingWhenOneFails() throws {
        let folder = try Self.makeFolder(files: ["default.store", "default.store-wal"])
        defer { try? FileManager.default.removeItem(at: folder) }
        var attempted: [String] = []

        StoreFileProtection.apply(toStoreAt: folder.appending(path: "default.store")) { url in
            attempted.append(url.lastPathComponent)
            if url.lastPathComponent == "default.store" { throw TestError() }
        }

        #expect(attempted == [folder.lastPathComponent, "default.store", "default.store-wal"])
    }

    /// 保存先を開くと（アプリと同じ `ModelContainerFactory.makeContainer` で）、開いたファイルに当てる。開けたまま使える。
    @MainActor
    @Test func openingTheStoreKeepsItUsable() throws {
        let folder = try Self.makeFolder(files: [])
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appending(path: "default.store", directoryHint: .notDirectory)

        let container = try ModelContainerFactory.makeContainer(url: url, cloudKitDatabase: .none)
        container.mainContext.insert(TestSupport.entry())
        try container.mainContext.save()

        #expect(FileManager.default.fileExists(atPath: url.path(percentEncoded: false)))
    }
}
