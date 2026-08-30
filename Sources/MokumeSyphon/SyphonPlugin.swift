// SPDX-FileCopyrightText: 2026 mokume-metal
// SPDX-License-Identifier: MIT

import mokume

/// 描いた絵を Syphon で他のアプリへ渡し、他のアプリの映像を受け取る束。
///
/// ```swift
/// import mokume
/// import MokumeSyphon
///
/// @main
/// final class MySketch: Sketch {
///     let syphon = SyphonPlugin(sending: "MySketch", receiving: "Camera")
///     var plugins: [any Plugin] { [syphon] }
///
///     func draw() {
///         background(.display(red: 0.06, green: 0.07, blue: 0.09))
///         circle(width / 2, height / 2, 200)
///     }
/// }
/// ```
///
/// ## 1 つの束が、出口と入り口の両方へ入る
///
/// 送出 (出口) と受け取り (入り口) は mokume の別々の差込口だが、**書くのは
/// `plugins` の 1 行**である ([ADR-0024] 決定 3・4)。片方だけ要るなら
/// ``init(sending:)`` / ``init(receiving:)`` を使う。
///
/// ## 書いてあれば効き、書いていなければ効かない
///
/// 依存に足しただけでは何も起きない。`plugins` に書いた束だけが差込口へ入る
/// (同 決定 5)。読み込み時の副作用で勝手に登録する形は採らない —
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
    /// 受け手のアプリに見える名前。送出しないなら `nil`。
    public let sendingName: String?

    /// 繋ぐ先の名前。`nil` は「繋がない」あるいは「最初に見つかったものへ繋ぐ」で、
    /// どちらかは ``receiver`` が居るかで決まる。
    public let receivingName: String?

    /// 実際に渡す出口。**束を作った時点で作る** — 束の写しが増えても出口は 1 つで、
    /// 立てたサーバーが束の写しごとに増えることが無い。
    let sender: SyphonSender?

    /// 実際に受ける入り口。出口と同じ理由で、束を作った時点の 1 つを写しが共有する。
    let receiver: SyphonReceiver?

    /// 直近に届いた 1 枚。**受け取らない束と、まだ 1 枚も来ていない間は `nil`。**
    ///
    /// 絵にするのは呼ぶ側の仕事である — 面 (``mokume/Image``) を作れるのは
    /// `createImage(_:_:)` だけで、それはスケッチの持ち物だからである。
    /// **大きさが変わったときだけ作り直す**:
    ///
    /// <!-- example: 文脈 let syphon = SyphonPlugin(receiving: nil) -->
    /// ```swift
    /// func draw() {
    ///     guard let picture = syphon.received else { return }
    ///     if video?.width != picture.width || video?.height != picture.height {
    ///         video = try? createImage(picture.width, picture.height)
    ///     }
    ///     guard let video else { return }
    ///     video.write(picture)
    ///     image(video, 0, 0, width, height)
    /// }
    /// ```
    public var received: DisplayImage? { receiver?.received }

    /// 送出する束を作る。
    ///
    /// - Parameter name: 受け手のアプリに見える名前。同じマシンで複数のスケッチを
    ///   走らせるなら、見分けが付く名前にする (一意である必要は無い)。
    public init(sending name: String) {
        self.init(sending: name, receiving: nil, receives: false)
    }

    /// 受け取る束を作る。
    ///
    /// - Parameter name: 繋ぐ先の名前。`nil` なら**最初に見つかったもの**へ繋ぐ。
    ///   相手はこちらより後に現れてよい (現れるまで待つ)。
    public init(receiving name: String?) {
        self.init(sending: nil, receiving: name, receives: true)
    }

    /// 送出と受け取りの両方をする束を作る。
    ///
    /// - Parameters:
    ///   - sendingName: 受け手のアプリに見える名前。
    ///   - receivingName: 繋ぐ先の名前。`nil` なら最初に見つかったものへ繋ぐ。
    public init(sending sendingName: String, receiving receivingName: String?) {
        self.init(sending: sendingName, receiving: receivingName, receives: true)
    }

    /// 何を持つかを決める唯一の場所。
    ///
    /// `receives` を別に取るのは、**「繋ぐ先を選ばない受け取り」と「受け取らない」が
    /// どちらも `receivingName == nil` になる**ためである。名前だけでは分けられない。
    private init(sending sendingName: String?, receiving receivingName: String?, receives: Bool) {
        self.sendingName = sendingName
        self.receivingName = receivingName
        self.sender = sendingName.map { SyphonSender(name: $0) }
        self.receiver = receives ? SyphonReceiver(name: receivingName) : nil
    }

    public func register(into registry: PluginRegistry) {
        if let sender { registry.add(outlet: sender) }
        if let receiver { registry.add(inlet: receiver) }
    }
}
