// SPDX-FileCopyrightText: 2026 mokume-metal
// SPDX-License-Identifier: MIT

import mokume

/// サーバーが立つまでフレームを進め、立ったら公示の内容を返す — 立たなければ `nil`。
///
/// **フレーム数を決め打ちにしないための助けである。**
///
/// `SyphonSender` はサーバーを `open()` では立てず、**最初の絵が届いたときに**立てる
/// (`MTLDevice` を知る道が、渡される絵の中にしか無いため)。その「最初の絵が届く」時機は
/// **上流の都合で動く** — mokume 0.7.1 は、フレームごとに CPU が GPU の完了を待たない
/// ようにするため、出口へ渡す絵を 1 フレーム遅らせた ([#26])。
///
/// 検査が `advance()` を 1 回打って公示を要求していたので、この変更で 4 件が落ちた。
/// **回数を 2 に増やすのでは同じことが次も起きる** — 待つ回数ではなく、
/// **待つ対象**で書く。
///
/// [#26]: https://github.com/mokume-metal/mokume-syphon/issues/26
func advanceUntilPublished(
    _ runtime: SketchRuntime, upTo limit: Int = 60, _ description: () -> [String: Any]?
) throws -> [String: Any]? {
    for _ in 0..<limit {
        try runtime.advance()
        if let description = description() { return description }
    }
    return nil
}
