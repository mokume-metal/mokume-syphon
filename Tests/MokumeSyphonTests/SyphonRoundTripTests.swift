// SPDX-FileCopyrightText: 2026 mokume-metal
// SPDX-License-Identifier: MIT

import Foundation
import Metal
import Syphon
import Testing
import mokume

@testable import MokumeSyphon

/// 送出したものが、**実際に受け手から見えて・同じ絵である**ことを見る。
///
/// 受け手のアプリを立ち上げずに済ませるため、同じプロセスの中で Syphon の
/// クライアントを繋いで受ける。外のアプリで見る確認 ([#438] の完了条件 1) を
/// 置き換えるものではないが、**壊れたときに気付ける唯一の自動検査**になる。
///
/// [#438]: https://github.com/mokume-metal/mokume/issues/438
@Suite(
    "Syphon への送出",
    .enabled(
        if: RenderDevice.isAvailable,
        "この世代のコマンド構造に対応した GPU が無い実行環境ではスキップする"),
    .serialized
)
struct SyphonRoundTripTests {

    /// 一面を 1 色で塗るだけのスケッチ。**受けた絵と突き合わせる相手**になる。
    final class FlatSketch: Sketch {
        var settings: SketchSettings {
            SketchSettings(width: 64, height: 48, title: "syphon round trip")
        }
        var plugins: [any Plugin] { Self.declared }
        nonisolated(unsafe) static var declared: [any Plugin] = []

        func draw() {
            background(.display(red: 0.2, green: 0.6, blue: 0.9))
            fill(.display(red: 1, green: 0.3, blue: 0.1))
            circle(width / 2, height / 2, 20)
        }
    }

    // MARK: - 受け手から見える

    @Test("送出した絵が受け手から見え、組み込みの出口が出す絵と一致する")
    func published_frame_matches_builtin_outlet() throws {
        let plugin = SyphonPlugin(sending: "mokume test \(UUID().uuidString)")
        FlatSketch.declared = [plugin]
        defer { FlatSketch.declared = [] }

        let runtime = try SketchRuntime(sketch: FlatSketch(), gpu: try RenderDevice())
        defer { runtime.closePlugins() }

        // サーバーは最初のフレームで立つ (装置を渡された絵から取るため)
        try runtime.advance()

        // 一覧からは探さない。Syphon の公示は自分のプロセスへ返ってこないので、
        // **同じプロセスで受けるときはサーバーの素性から直に繋ぐ** (別プロセスから
        // 一覧に現れることは Examples/SendHeadless で確かめている)
        let description = try #require(
            plugin.sender?.serverDescription, "1 フレーム進めてもサーバーが立っていない")

        let device = try #require(MTLCreateSystemDefaultDevice())
        let client = SyphonMetalClient(
            serverDescription: description, device: device, options: nil, newFrameHandler: nil)
        defer { client.stop() }

        // 繋いでから、届くまで進める
        var received: (width: Int, height: Int, bytes: [UInt8])?
        for _ in 0..<120 where received == nil {
            try runtime.advance()
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.01))
            received = autoreleasepool { client.newFrameImage().map(Self.read) }
        }

        let arrived = try #require(received, "繋いだのに 1 枚も届かなかった")
        // 組み込みの出口が出す絵 (画像の書き出しと同じ道)
        let expected = try runtime.target.encodeForDisplay()

        #expect(arrived.width == expected.width)
        #expect(arrived.height == expected.height)
        // **バイト列そのものを #expect に渡さない。** 食い違ったときに数万個の数字が
        // 出力へ流れ、どこが違うのかがかえって読めなくなる。要約だけを比べる
        let mismatch = firstMismatch(arrived.bytes, expected.bytes)
        #expect(
            mismatch == nil,
            """
            受けた絵が組み込みの出口の絵と違う \
            (向き・成分の並び・出力段のどれかがずれている): \
            \(mismatch.map { "\($0.differing) バイトが不一致・最初は \($0.index) 番目" } ?? "")
            """)
    }

    // MARK: - 長く回しても増えない

    @Test("長く回しても、サーバーと発行口を作り直さない")
    func long_run_keeps_one_server() throws {
        let plugin = SyphonPlugin(sending: "mokume test \(UUID().uuidString)")
        FlatSketch.declared = [plugin]
        defer { FlatSketch.declared = [] }

        let runtime = try SketchRuntime(sketch: FlatSketch(), gpu: try RenderDevice())
        defer { runtime.closePlugins() }

        for _ in 0..<300 { try runtime.advance() }

        #expect(plugin.sender?.resourcesMade == 1, "フレームごとに置き場を作り直している")
        #expect(
            plugin.sender?.failure == nil,
            "300 フレームの間に転んだ: \(plugin.sender?.failure ?? "")")
    }

    // MARK: - 助け

    /// 受けたテクスチャを、突き合わせられる形 (左上原点・RGBA の並び) にする。
    ///
    /// Syphon が抱えるのは BGRA なので、**ここで並べ替える**。並べ替えが要ることは
    /// 送り手側の欠陥ではない (受け渡しの形式が決めている)。
    private static func read(_ texture: any MTLTexture) -> (
        width: Int, height: Int, bytes: [UInt8]
    ) {
        let width = texture.width
        let height = texture.height
        var bgra = [UInt8](repeating: 0, count: width * height * 4)
        bgra.withUnsafeMutableBytes { destination in
            texture.getBytes(
                destination.baseAddress!, bytesPerRow: width * 4,
                from: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0)
        }
        var rgba = bgra
        for index in stride(from: 0, to: bgra.count, by: 4) {
            rgba[index] = bgra[index + 2]
            rgba[index + 2] = bgra[index]
        }
        return (width, height, rgba)
    }
}

/// GPU を要さない検査。**門の外に置く** — 束の形を見るだけのものまで
/// `RenderDevice.isAvailable` の門の内側に置くと、GPU の無い CI では
/// **振る舞いについて何ひとつ確かめないまま緑になる** ([#1])。
///
/// [#1]: https://github.com/mokume-metal/mokume-syphon/issues/1
@Suite("束の形")
struct SyphonPluginShapeTests {
    @Test("名前をそのまま持つ")
    func plugin_keeps_name() {
        #expect(SyphonPlugin(sending: "mokume test").sendingName == "mokume test")
    }

    @Test("束の写しが増えても、出口は 1 つのまま")
    func copies_share_one_outlet() {
        let plugin = SyphonPlugin(sending: "mokume test")
        let copy = plugin
        // 値型なので写せてしまうが、写しごとにサーバーが立つと受け手の一覧が
        // 同じ名前で埋まる。出口は束を作った時点の 1 つを共有する
        #expect(plugin.sender === copy.sender)
    }
}
