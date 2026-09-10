// SPDX-FileCopyrightText: 2026 mokume-metal
// SPDX-License-Identifier: MIT

import Foundation
import Testing
import mokume

@testable import MokumeSyphon

/// 受け取ったものが、**送られた絵そのもの**であることを見る。
///
/// 受け取りは送出と逆向きだが、確かめたいことは同じ 1 つである — **道の途中で絵が
/// 変わっていないこと**。成分の並べ替え・不透明度の割り戻し・原点のどれかが
/// 間違っていれば、ここが赤くなる。
///
/// 外のアプリから受ける確認 ([mokume#438] の完了条件 3) を置き換えるものではないが、
/// **壊れたときに気付ける唯一の自動検査**になる。
///
/// [mokume#438]: https://github.com/mokume-metal/mokume/issues/438
@Suite(
    "Syphon からの受け取り",
    .enabled(
        if: RenderDevice.isAvailable,
        "この世代のコマンド構造に対応した GPU が無い実行環境ではスキップする"),
    .serialized
)
struct SyphonReceiveTests {

    /// 送り手。**受けた絵と突き合わせる相手**になる。
    ///
    /// 一面を塗るので不透明である。**半透明を混ぜない**のは、mokume の送出が
    /// straight で送り、受け取りが Syphon の規約どおり乗算済みとして割り戻すため
    /// で、そこだけは往復しても元に戻らない (``SyphonReceiver/picture(from:)``)。
    final class FlatSketch: Sketch {
        var settings: SketchSettings {
            SketchSettings(width: 64, height: 48, title: "syphon receive")
        }
        var plugins: [any Plugin] { Self.declared }
        nonisolated(unsafe) static var declared: [any Plugin] = []

        func draw() {
            background(.display(red: 0.2, green: 0.6, blue: 0.9))
            fill(.display(red: 1, green: 0.3, blue: 0.1))
            circle(width / 2, height / 2, 20)
        }
    }

    // MARK: - 送った絵が、そのまま受け取れる

    @Test("受け取った絵が、送り手の組み込みの出口が出す絵と一致する")
    func received_frame_matches_sender_builtin_outlet() throws {
        let sending = SyphonPlugin(sending: "mokume test \(UUID().uuidString)")
        FlatSketch.declared = [sending]
        defer { FlatSketch.declared = [] }

        let runtime = try SketchRuntime(sketch: FlatSketch(), gpu: try RenderDevice())
        defer { runtime.closePlugins() }

        // サーバーは最初の絵が届いたときに立つ (装置を渡された絵から取るため)。
        // **何フレーム目かは上流の都合で動く**ので回数では待たない (#26)
        let description = try #require(
            advanceUntilPublished(runtime) { sending.sender?.serverDescription },
            "60 フレーム進めてもサーバーが立たない")

        // 一覧からは探さない。Syphon の公示は自分のプロセスへ返ってこない
        let receiver = SyphonReceiver(serverDescription: description)
        try receiver.open()
        defer { receiver.close() }

        for _ in 0..<120 where receiver.received == nil {
            try runtime.advance()
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.01))
            receiver.supply()
        }

        let arrived = try #require(receiver.received, "繋いだのに 1 枚も届かなかった")
        let expected = try runtime.target.encodeForDisplay()

        #expect(arrived.width == expected.width)
        #expect(arrived.height == expected.height)
        let mismatch = firstMismatch(arrived.bytes, expected.bytes)
        #expect(
            mismatch == nil,
            """
            受け取った絵が送り手の絵と違う \
            (向き・成分の並び・不透明度の扱いのどれかがずれている): \
            \(mismatch.map { "\($0.differing) バイトが不一致・最初は \($0.index) 番目" } ?? "")
            """)
    }

    // MARK: - 長く回しても増えない

    @Test("長く回しても、繋ぎ直さない")
    func long_run_keeps_one_client() throws {
        let sending = SyphonPlugin(sending: "mokume test \(UUID().uuidString)")
        FlatSketch.declared = [sending]
        defer { FlatSketch.declared = [] }

        let runtime = try SketchRuntime(sketch: FlatSketch(), gpu: try RenderDevice())
        defer { runtime.closePlugins() }

        let receiver = SyphonReceiver(
            serverDescription: try #require(
                advanceUntilPublished(runtime) { sending.sender?.serverDescription },
                "60 フレーム進めてもサーバーが立たない"))
        try receiver.open()
        defer { receiver.close() }

        for _ in 0..<300 {
            try runtime.advance()
            receiver.supply()
        }

        #expect(receiver.resourcesMade == 1, "フレームごとに繋ぎ直している")
        #expect(receiver.failure == nil, "300 フレームの間に転んだ: \(receiver.failure ?? "")")
    }

    // MARK: - 新しい絵が来ていないフレーム

    @Test("送り手が止まっても、最後に届いた絵が消えない")
    func last_frame_is_kept_when_nothing_new_arrives() throws {
        let sending = SyphonPlugin(sending: "mokume test \(UUID().uuidString)")
        FlatSketch.declared = [sending]
        defer { FlatSketch.declared = [] }

        let runtime = try SketchRuntime(sketch: FlatSketch(), gpu: try RenderDevice())
        defer { runtime.closePlugins() }

        let receiver = SyphonReceiver(
            serverDescription: try #require(
                advanceUntilPublished(runtime) { sending.sender?.serverDescription },
                "60 フレーム進めてもサーバーが立たない"))
        try receiver.open()
        defer { receiver.close() }

        for _ in 0..<120 where receiver.received == nil {
            try runtime.advance()
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.01))
            receiver.supply()
        }
        let arrived = try #require(receiver.received, "繋いだのに 1 枚も届かなかった")

        // 送り手を進めずに受け側だけ回す — 新しい絵は 1 枚も来ない
        for _ in 0..<10 { receiver.supply() }

        // 絵そのものを #expect に渡さない (食い違うと数万個の数字が出力へ流れる)
        let kept = try #require(receiver.received, "新しい絵が来ていないのに、前の 1 枚が失われた")
        #expect(
            firstMismatch(kept.bytes, arrived.bytes) == nil,
            "据え置かれたはずの絵が別物になっている")
    }
}

/// GPU を要さない検査。**門の外に置く** — 束の形を見るだけのものまで
/// `RenderDevice.isAvailable` の門の内側に置くと、GPU の無い CI では
/// **振る舞いについて何ひとつ確かめないまま緑になる** ([#1])。
///
/// [#1]: https://github.com/mokume-metal/mokume-syphon/issues/1
@Suite("受け取る束の形")
struct SyphonReceivePluginShapeTests {

    @Test("送出だけの束は、出口だけを持つ")
    func sending_only_has_an_outlet() {
        let plugin = SyphonPlugin(sending: "mokume test")
        #expect(plugin.sender != nil)
        #expect(plugin.receiver == nil)
    }

    @Test("受け取りだけの束は、入り口だけを持つ")
    func receiving_only_has_an_inlet() {
        let plugin = SyphonPlugin(receiving: "camera")
        #expect(plugin.sender == nil)
        #expect(plugin.receiver != nil)
    }

    /// [mokume#438](https://github.com/mokume-metal/mokume/issues/438) の完了条件 7。
    ///
    /// **登録そのものは単体では見ていない。** 本体の `PluginRegistry` は外から
    /// 作れないので ([mokume#605](https://github.com/mokume-metal/mokume/issues/605))、
    /// ここで見るのは束が両方を持つことまでで、`plugins` の 1 行で両方が実際に効く
    /// ことは `Examples/Receive` を走らせて確かめる。
    @Test("1 つの束が、出口と入り口の両方を持つ")
    func one_plugin_carries_both_seams() {
        let plugin = SyphonPlugin(sending: "mokume test", receiving: "camera")
        #expect(plugin.sender != nil)
        #expect(plugin.receiver != nil)
        #expect(plugin.sendingName == "mokume test")
        #expect(plugin.receivingName == "camera")
    }

    @Test("繋ぐ先を選ばない受け取りと、受け取らない束は別物")
    func nameless_receiving_is_not_the_same_as_not_receiving() {
        // どちらも receivingName は nil になるので、名前だけでは分けられない
        #expect(SyphonPlugin(receiving: nil).receiver != nil)
        #expect(SyphonPlugin(sending: "mokume test").receiver == nil)
    }

    @Test("束の写しが増えても、出口と入り口は 1 つのまま")
    func copies_share_one_seam_each() {
        let plugin = SyphonPlugin(sending: "mokume test", receiving: nil)
        let copy = plugin
        // 値型なので写せてしまうが、写しごとに繋ぐと受け手の一覧が同じ名前で埋まり、
        // 受け側も同じ相手へ何本も繋ぐ
        #expect(plugin.sender === copy.sender)
        #expect(plugin.receiver === copy.receiver)
    }

    @Test("繋ぐ先が居なくても、入り口は外されない")
    func waiting_for_a_sender_is_not_a_failure() {
        let receiver = SyphonReceiver(name: "居ないサーバー \(UUID().uuidString)")
        for _ in 0..<100 { receiver.supply() }
        #expect(receiver.received == nil)
        // 転びとして数えられると 3 フレームで外され、後から現れた送り手に繋がらない
        #expect(receiver.failure == nil, "待っている状態が転びとして数えられている")
        #expect(receiver.resourcesMade == 0)
    }
}
