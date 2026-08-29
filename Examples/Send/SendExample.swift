// SPDX-FileCopyrightText: 2026 mokume-metal
// SPDX-License-Identifier: MIT

import MokumeSyphon
import mokume

/// 窓に出しながら、同じ絵を Syphon で他のアプリへ渡す。
///
/// ```bash
/// swift run SendExample
/// ```
///
/// 受け手 (映像ミキサ・マッピングの道具・配信ソフト) の入力一覧に
/// **`mokume Send Example`** が現れる。
@main
final class SendExample: Sketch {
    var settings: SketchSettings {
        SketchSettings(width: 960, height: 540, title: "Send Example")
    }

    /// **1 行で入る。** 依存に足しただけでは効かず、ここに書いたものだけが効く。
    var plugins: [any Plugin] { [SyphonPlugin(sending: "mokume Send Example")] }

    func draw() {
        background(.display(red: 0.06, green: 0.07, blue: 0.09))
        fill(.display(red: 0.95, green: 0.45, blue: 0.2))
        let angle = time * 0.8
        circle(width / 2 + cos(angle) * 240, height / 2 + sin(angle) * 140, 120)
    }
}
