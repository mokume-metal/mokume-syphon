// SPDX-FileCopyrightText: 2026 mokume-metal
// SPDX-License-Identifier: MIT

import Foundation
import Testing

/// `scripts/check-mokume-pin.sh` の判定を終了コードで固定する ([#12])。
///
/// この検査が守っているのは **「遅れている」と「異常」が別の終了コードで名乗ること**
/// である。遅れている側に 1 を割り当てると、`gh` の失敗も `set -u` の未定義も jq の
/// パースミスも 1 で落ちるので、**あらゆる異常が「上流に取り残された」として自動起票
/// される**。鳴らない検知より、嘘を鳴らす検知のほうが悪い。
///
/// もう 1 つ固定しているのが**範囲包含であること**。`latest > pin` の大小比較にすると、
/// `0.4.0` に張ったまま `0.4.3` が出た日に追随を促してしまう — `.upToNextMinor` の
/// 範囲の中なので、その版は CI が黙って取り込んでおり、人がすることは無い。
///
/// ネットワークを打たない `--compare` だけを叩くので、GPU も認証も要らない。テストの
/// 入口は `swift test` (= `make ci-check`) のままで、**新しい機構は 1 つも足していない**。
///
/// [#12]: https://github.com/mokume-metal/mokume-syphon/issues/12
@Suite("mokume の pin の判定")
struct MokumePinCheckTests {

    /// 判定スクリプトの在処。リポジトリのルートは `Package.swift` と同じ流儀で
    /// `#filePath` から辿る (`Tests/MokumeSyphonTests/` の 2 つ上)
    static let script = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("scripts/check-mokume-pin.sh")

    /// `--compare <pin> <latest>` を打ち、終了コードだけを返す。
    /// 出力は捨てる — この検査が見るのは名乗り (終了コード) であって文面ではない
    static func compare(pin: String, latest: String) throws -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [script.path, "--compare", pin, latest]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        return process.terminationStatus
    }

    @Test(
        "範囲の中に収まる版では追随を促さない",
        arguments: [
            (pin: "0.4.0", latest: "0.4.3"),
            (pin: "0.7.0", latest: "0.7.0"),
            (pin: "0.4.0", latest: "v0.4.9"),
        ])
    func upToDate(_ testCase: (pin: String, latest: String)) throws {
        let status = try Self.compare(pin: testCase.pin, latest: testCase.latest)
        #expect(status == 0)
    }

    @Test(
        "minor を越えた版が出ていれば 10 で名乗る",
        arguments: [
            (pin: "0.4.0", latest: "0.5.0"),
            (pin: "0.4.0", latest: "0.7.0"),
            (pin: "0.4.0", latest: "v0.7.0"),
        ])
    func outdated(_ testCase: (pin: String, latest: String)) throws {
        let status = try Self.compare(pin: testCase.pin, latest: testCase.latest)
        #expect(status == 10)
    }

    /// `.upToNextMinor` は mokume の ADR-0024 決定 9 が「0.x の間は」を理由に決めた
    /// 張り方なので、1.0 が出たら追随ではなく**張り方そのものの見直し**になる
    @Test("major が上がったら 20 で名乗る (追随ではなく張り方の見直し)")
    func majorBump() throws {
        let status = try Self.compare(pin: "0.7.0", latest: "1.0.0")
        #expect(status == 20)
    }

    @Test(
        "読めない入力は異常として 64 — 「遅れている」と混ざらない",
        arguments: [
            (pin: "abc", latest: "0.7.0"),
            (pin: "0.7", latest: "0.7.0"),
            (pin: "0.7.0", latest: ""),
            // 上流が版を下げることは無い。起きたなら、どちらかの読み取りが壊れている
            (pin: "0.7.0", latest: "0.6.0"),
        ])
    func malformed(_ testCase: (pin: String, latest: String)) throws {
        let status = try Self.compare(pin: testCase.pin, latest: testCase.latest)
        #expect(status == 64)
    }
}
