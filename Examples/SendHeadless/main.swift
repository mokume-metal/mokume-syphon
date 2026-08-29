// SPDX-FileCopyrightText: 2026 mokume-metal
// SPDX-License-Identifier: MIT

import Foundation
import MokumeSyphon
import mokume

// 窓を 1 つも開かずに Syphon へ渡す。
//
// ```bash
// swift run SendHeadlessExample 30    # 30 秒だけ回す (既定 60 秒)
// ```
//
// ## なぜ `@main` を使わないか
//
// `Sketch` の既定の入口 (`SketchApplication`) は必ず窓を開く。窓は要らないので、
// **フレームを進める入口 (`SketchRuntime.advance()`) を自分で叩く**。本体は
// 「進める判断」と「窓」を分けてあるので、描かれる中身はこちらでも変わらない。
//
// ## `RunLoop` を回すのが要点
//
// Syphon のサーバー公示とクライアントの接続は mach ポート越しの通知に乗る。
// **run loop を回さないプロセスは、絵を publish していても受け手の一覧に現れない。**
// フレームの間隔を `sleep` で待つと、ちょうどそれが起きる。

final class HeadlessSketch: Sketch {
    var settings: SketchSettings {
        SketchSettings(width: 960, height: 540, frameRate: 60, title: "Send Headless Example")
    }

    var plugins: [any Plugin] { [SyphonPlugin(sending: "mokume Send Headless Example")] }

    func draw() {
        background(.display(red: 0.05, green: 0.08, blue: 0.07))
        fill(.display(red: 0.3, green: 0.9, blue: 0.6))
        let angle = time * 1.2
        circle(width / 2 + cos(angle) * 200, height / 2 + sin(angle * 1.7) * 120, 90)
    }
}

let seconds = Double(CommandLine.arguments.dropFirst().first ?? "") ?? 60

do {
    let runtime = try SketchRuntime(sketch: HeadlessSketch(), gpu: try RenderDevice())
    let interval = 1.0 / Double(runtime.sketch.settings.frameRate)
    let deadline = Date(timeIntervalSinceNow: seconds)
    print("Syphon へ \(seconds) 秒ぶん送る (窓は開かない)")
    while Date() < deadline {
        try runtime.advance()
        // 待つ間も run loop を回す。sleep で待つと受け手から見えない
        RunLoop.current.run(until: Date(timeIntervalSinceNow: interval))
    }
    // 差込口を畳んでから終わる。畳まないままプロセスが消えても実害は無いが、
    // 「閉じるまでが差込口の寿命」を例で示しておく
    runtime.closePlugins()
    print("終わった (\(runtime.frameCount) フレーム)")
} catch {
    FileHandle.standardError.write(Data("走らせられなかった: \(error)\n".utf8))
    exit(1)
}
