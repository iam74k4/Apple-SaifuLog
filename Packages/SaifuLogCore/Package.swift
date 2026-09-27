// swift-tools-version: 6.2
import PackageDescription

// SaifuLogCore — 画面にも端末にも依存しない純粋なロジック（解析・金額の表記・集計）。
//
// FoundationModels / SwiftData / SwiftUI はここに入れない（アプリ側に置く）。
// CI の macOS ランナー上で `swift test` だけで回せるようにするため。
// 同じ理由で macOS の下限は低く保つ。
//
// tools-version を 6.2 にしているのは `.iOS(.v26)` が PackageDescription 6.2 で
// 入ったため。6.0 のままだと "'v26' is unavailable" でパッケージの読み込みに失敗する。
// 言語モードは Swift 6 のまま（strict concurrency も有効）。
let package = Package(
    name: "SaifuLogCore",
    platforms: [.iOS(.v26), .macOS(.v14)],
    products: [
        .library(name: "SaifuLogCore", targets: ["SaifuLogCore"]),
    ],
    targets: [
        .target(name: "SaifuLogCore"),
        .testTarget(name: "SaifuLogCoreTests", dependencies: ["SaifuLogCore"]),
    ]
)
