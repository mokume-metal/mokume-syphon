// SPDX-FileCopyrightText: 2026 mokume-metal
// SPDX-License-Identifier: MIT

import MokumeSyphon
import mokume

/// 他のアプリが Syphon へ出している映像を受け取り、絵として貼る。
///
/// ```bash
/// swift run SendExample &     # 送り手 (映像ミキサや配信ソフトでもよい)
/// swift run ReceiveExample
/// ```
///
/// 繋ぐ先を選んでいないので**最初に見つかったもの**へ繋ぐ。相手はこちらより後に
/// 現れてよい — 現れるまでは待っている旨を描く。
@main
final class ReceiveExample: Sketch {
    var settings: SketchSettings {
        SketchSettings(width: 960, height: 540, title: "Receive Example")
    }

    /// **1 行で入る。** 送出もするなら `SyphonPlugin(sending:receiving:)` にする。
    let syphon = SyphonPlugin(receiving: nil)
    var plugins: [any Plugin] { [syphon] }

    /// 受けた映像を貼る面。**大きさが変わったときだけ作り直す** — 書き込みで絵の
    /// 大きさは変わらないので、送り元の解像度が変わったら作り直しが要る。
    private var video: Image?

    func draw() {
        background(.display(red: 0.06, green: 0.07, blue: 0.09))

        guard let picture = syphon.received else {
            fill(.display(red: 0.6, green: 0.6, blue: 0.65))
            text("送り手を待っています", 40, 40)
            return
        }

        if video?.width != picture.width || video?.height != picture.height {
            video = try? createImage(picture.width, picture.height)
        }
        guard let video else { return }
        video.write(picture)

        // 縦横の比を保ったまま、窓いっぱいに収める
        let source = (width: Float(video.width), height: Float(video.height))
        let scale: Float = min(width / source.width, height / source.height)
        let drawn = (width: source.width * scale, height: source.height * scale)
        image(video, (width - drawn.width) / 2, (height - drawn.height) / 2, drawn.width, drawn.height)
    }
}
