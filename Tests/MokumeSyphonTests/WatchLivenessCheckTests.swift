// SPDX-FileCopyrightText: 2026 mokume-metal
// SPDX-License-Identifier: MIT

import Foundation
import Testing

/// `scripts/check-watch-liveness.sh` の判定を終了コードで固定する ([#16])。
///
/// この検査が守っているのは **`disabled_inactivity` が異常と混ざらないこと**である。
/// 「止まっている」に 1 を割り当てると `gh` の失敗も `set -u` の未定義も 1 で落ちるので、
/// **通信が切れた日に「検知が止まっている」と名乗る**ことになる。逆に、知らない綴りを
/// 「生きている」に倒すと、GitHub が state を増やした日から見張りが黙る — どちらも、
/// 見張りが見張りとして働かなくなる形である。
///
/// もう 1 つ固定しているのが、**人が止めた (`disabled_manually`) と GitHub が止めた
/// (`disabled_inactivity`) を分けて名乗る**こと。前者は「検知が要らなくなった」かもしれず、
/// 後者は必ず直すべき状態なので、同じ文面で報せると本当に直すべき赤が埋もれる。
///
/// ネットワークを打たない `--compare` だけを叩くので、GPU も認証も要らない。テストの
/// 入口は `swift test` (= `make ci-check`) のままで、**新しい機構は 1 つも足していない**。
///
/// [#16]: https://github.com/mokume-metal/mokume-syphon/issues/16
@Suite("検知の workflow が生きているかの判定")
struct WatchLivenessCheckTests {

    /// 判定スクリプトの在処。`MokumePinCheckTests` と同じ流儀で `#filePath` から辿る
    /// (`Tests/MokumeSyphonTests/` の 2 つ上)
    static let script = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("scripts/check-watch-liveness.sh")

    /// `--compare <state>` を打ち、終了コードだけを返す。
    /// 出力は捨てる — この検査が見るのは名乗り (終了コード) であって文面ではない
    static func compare(state: String) throws -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [script.path, "--compare", state]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        return process.terminationStatus
    }

    @Test("active なら 0 — 検知は生きている")
    func active() throws {
        let status = try Self.compare(state: "active")
        #expect(status == 0)
    }

    /// #16 が塞ぐ状態。GitHub が 60 日の無活動で止めたもので、活動が戻っても自分では
    /// 戻らないため、人が `gh workflow enable` を打つまで検知は死んだままになる
    @Test("GitHub が無活動で止めていたら 10 で名乗る")
    func disabledByInactivity() throws {
        let status = try Self.compare(state: "disabled_inactivity")
        #expect(status == 10)
    }

    @Test(
        "人が止めた・fork で無効なら 20 — 無活動での停止とは分けて名乗る",
        arguments: ["disabled_manually", "disabled_fork"])
    func stoppedOnPurpose(_ state: String) throws {
        let status = try Self.compare(state: state)
        #expect(status == 20)
    }

    @Test(
        "読めない state は異常として 64 — 「止まっている」と混ざらない",
        arguments: [
            // GitHub が state を増やした日に、知らない綴りを「生きている」と読んで黙らない
            "disabled_something_new",
            "ACTIVE",
            // workflow ごと消えた・引けなかったときに gh が返しうる形
            "deleted",
            "null",
            "",
        ])
    func unreadable(_ state: String) throws {
        let status = try Self.compare(state: state)
        #expect(status == 64)
    }
}
