// SPDX-FileCopyrightText: 2026 mokume-metal
// SPDX-License-Identifier: MIT

import mokume

/// 描いた絵を Syphon で他のアプリへ渡す束。
///
/// ```swift
/// import mokume
/// import MokumeSyphon
///
/// @main
/// final class MySketch: Sketch {
///     var plugins: [any Plugin] { [SyphonPlugin(sending: "mokume")] }
///
///     func draw() {
///         background(.display(red: 0.06, green: 0.07, blue: 0.09))
///         circle(width / 2, height / 2, 200)
///     }
/// }
/// ```
///
/// ## 書いてあれば効き、書いていなければ効かない
///
/// 依存に足しただけでは何も起きない。`plugins` に書いた束だけが差込口へ入る
/// (mokume の [ADR-0024] 決定 5)。読み込み時の副作用で勝手に登録する形は採らない —
/// 効いていることがコードのどこにも書かれていない状態を作らないためである。
///
/// ## 渡す絵は、組み込みの出口が受け取るのと同じ 1 枚
///
/// 出力段を通した後の絵で、不透明度は**割り戻し済み (straight)**、明るさは**標準の
/// 範囲へ丸め済み**である ([ADR-0023] 決定 4 の表)。
///
/// **Syphon の慣習は乗算済みなので、受け手側は straight として合成する必要がある。**
/// 乗算済みとして合成すると、半透明のところだけ暗く出る。ここで乗算し直さないのは、
/// 出口ごとに絵を作り分けた瞬間に「出口は 1 点」(同 決定 2) が外から足した出口でだけ
/// 破れるためである。
///
/// [ADR-0023]: https://github.com/mokume-metal/mokume/blob/main/docs/decisions/0023-frame-stages-and-outputs.md
/// [ADR-0024]: https://github.com/mokume-metal/mokume/blob/main/docs/decisions/0024-extension-seams.md
public struct SyphonPlugin: Plugin {
    /// 受け手のアプリに見える名前。
    public let sendingName: String

    /// 実際に渡す出口。**束を作った時点で作る** — 束の写しが増えても出口は 1 つで、
    /// 立てたサーバーが束の写しごとに増えることが無い。
    let sender: SyphonSender

    /// 送出する束を作る。
    ///
    /// - Parameter name: 受け手のアプリに見える名前。同じマシンで複数のスケッチを
    ///   走らせるなら、見分けが付く名前にする (一意である必要は無い)。
    public init(sending name: String) {
        self.sendingName = name
        self.sender = SyphonSender(name: name)
    }

    public func register(into registry: PluginRegistry) {
        registry.add(outlet: sender)
    }
}
