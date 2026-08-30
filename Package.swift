// swift-tools-version: 6.2
// SPDX-FileCopyrightText: 2026 mokume-metal
// SPDX-License-Identifier: MIT

import Foundation
import PackageDescription

// mokume の最初の外部パッケージ。描いた絵を Syphon で他のアプリへ渡す。
//
// **本体と別のリポジトリに置くのは、バイナリ配布物を抱えるためである**
// (mokume の ADR-0001 原則 6 / ADR-0016 決定 7)。SwiftPM の binaryTarget は、
// その product を使わない利用者にも artifact をダウンロードさせるので、
// Syphon を使わない人に Syphon.xcframework を引かせないためにここへ分けている。

// 手元で焼いた成果物があればそれを使う (make setup)。無ければこのリポジトリの
// Release の資産を版で固定して引く。**上流の変更を、版を出す前に試せる**ようにする
// ための二段構えで、Frameworks/ は gitignore 済み。
//
// 注意: SwiftPM は manifest の評価結果を内容ハッシュでキャッシュし、ファイルの
// 出現・消失では無効化しない。焼いた直後・消した直後は `swift package purge-cache`
// を打つ (make setup / make clean-syphon がそこまでやる)。
let packageDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent().path
let localFramework = "Frameworks/Syphon.xcframework"
let hasLocalFramework = FileManager.default.fileExists(
    atPath: packageDirectory + "/" + localFramework)

// 版を出すまでは資産が無いので、そのときは手元で焼いたものだけが道になる。
// 最初の Release で url と checksum をここへ書き込む。
let syphon: Target =
    hasLocalFramework
    ? .binaryTarget(name: "Syphon", path: localFramework)
    : .binaryTarget(
        name: "Syphon",
        url:
            "https://github.com/mokume-metal/mokume-syphon/releases/download/v0.2.0/Syphon.xcframework.zip",
        checksum: "fb63d9522bf92a46e3a9463183366a4e7225a7b509569409a80821b084d68495")

let package = Package(
    name: "mokume-syphon",
    // 本体と同じ床 (mokume の ADR-0009)。本体より広く名乗る意味は無い
    platforms: [.macOS("26.0")],
    products: [
        .library(name: "MokumeSyphon", targets: ["MokumeSyphon"])
    ],
    dependencies: [
        // 0.x の間は minor で壊れうるので upToNextMinor で張る
        // (mokume の ADR-0024 決定 9)
        .package(
            url: "https://github.com/mokume-metal/mokume.git", .upToNextMinor(from: "0.4.0"))
    ],
    targets: [
        syphon,
        .target(
            name: "MokumeSyphon",
            dependencies: [.product(name: "mokume", package: "mokume"), "Syphon"],
            swiftSettings: .mokume),
        .testTarget(
            name: "MokumeSyphonTests", dependencies: ["MokumeSyphon", "Syphon"],
            swiftSettings: .mokume),
        // 例。product には含めない — 利用者へ配るものではなく、使い方を示すもの
        .executableTarget(
            name: "SendExample", dependencies: ["MokumeSyphon"], path: "Examples/Send",
            swiftSettings: .mokume),
        .executableTarget(
            name: "SendHeadlessExample", dependencies: ["MokumeSyphon"],
            path: "Examples/SendHeadless", swiftSettings: .mokume),
        .executableTarget(
            name: "ReceiveExample", dependencies: ["MokumeSyphon"], path: "Examples/Receive",
            swiftSettings: .mokume),
    ]
)

extension [SwiftSetting] {
    /// 本体と同じ言語設定 — スケッチの側から見て、この束だけ書き味が違うことが無いようにする。
    ///
    /// - Swift 6 言語モード (並行性の検査がエラーとして働く)
    /// - ターゲット単位の既定隔離を main actor に (mokume の ADR-0010 決定 1)。
    ///   差込口は本体の main actor 隔離された型を受けるので、ここが揃っていないと
    ///   準拠のたびに注釈が要る
    static var mokume: [SwiftSetting] {
        [.swiftLanguageMode(.v6), .defaultIsolation(MainActor.self)]
    }
}
