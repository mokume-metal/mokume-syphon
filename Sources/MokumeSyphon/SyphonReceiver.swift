// SPDX-FileCopyrightText: 2026 mokume-metal
// SPDX-License-Identifier: MIT

import Foundation
import Metal
import Syphon
import mokume

/// 入り口 — 他のアプリが Syphon へ出している映像を、フレームごとに 1 枚受け取る。
///
/// 面に出る型ではない (束が中に持つ)。外から触るのは ``SyphonPlugin`` だけである。
final class SyphonReceiver: Inlet {
    /// 繋ぐ先の名前。`nil` なら最初に見つかったものへ繋ぐ。
    private let serverName: String?

    /// 一覧を迂回して繋ぐ先 (``init(serverDescription:)`` で渡されたもの)。
    private let fixedDescription: [String: Any]?

    /// 繋いだクライアント。**相手が現れるまでは `nil`。**
    private var client: SyphonMetalClient?

    /// 直近に届いた 1 枚。**まだ 1 枚も来ていなければ `nil`。**
    ///
    /// 新しい絵が来ていないフレームでは**前の 1 枚が据え置かれる** — 送り手の
    /// フレームレートがこちらより低いのは普通のことで、来ていない旨を毎フレーム
    /// 返すと呼ぶ側が「絵が消える」対処を書くことになる。
    private(set) var received: DisplayImage?

    /// クライアントを作った回数。**相手が生きている限り 1 のままであること**が
    /// 「長く回しても資源が増え続けない」(mokume の [ADR-0023] 決定 5) の中身で、
    /// 検査はこの数を見る。相手が消えて現れ直せば増える (繋ぎ直しは正常な動き)。
    ///
    /// [ADR-0023]: https://github.com/mokume-metal/mokume/blob/main/docs/decisions/0023-frame-stages-and-outputs.md
    private(set) var resourcesMade = 0

    private(set) var failure: String?

    /// 一覧から探して繋ぐ入り口を作る。
    init(name: String?) {
        self.serverName = name
        self.fixedDescription = nil
    }

    /// 繋ぐ先の素性を直に渡して作る。**同じプロセスの中で受けるための入口である。**
    ///
    /// Syphon の公示は distributed notification に乗るが、**自分のプロセスへは
    /// 返ってこない** (別プロセスからは見える。実測)。つまり ``findServer()`` は
    /// 同じプロセスが立てたサーバーを決して見つけられない。検査が送出と受け取りを
    /// 同じプロセスで繋ぐには、一覧を迂回する道が要る。
    init(serverDescription: [String: Any]) {
        self.serverName = nil
        self.fixedDescription = serverDescription
    }

    // MARK: - 差込口

    /// 繋ぐのは ``open()`` では行わない。
    ///
    /// **相手はこちらより後に現れうる** — 受け手を先に立ち上げて、送り手を後から
    /// 起こすのは普通の順序である。開くときに繋ぎに行くと、その 1 回で見つからな
    /// かったものへ二度と繋がらない。
    func open() throws {}

    /// フレーム 1 枚を受け取る。**投げない** (mokume の [ADR-0024] 決定 7)。
    ///
    /// **繋ぐ先が居ないことは転びではない。** 待っている状態なので ``failure`` へは
    /// 置かない — 置くと 3 フレームで入り口ごと外され、後から現れた送り手に
    /// 繋がらなくなる。
    ///
    /// [ADR-0024]: https://github.com/mokume-metal/mokume/blob/main/docs/decisions/0024-extension-seams.md
    func supply() {
        // ObjC の一時オブジェクトが毎フレーム溜まらないようにする。
        // newFrameImage() が返すテクスチャもここで畳まれる
        autoreleasepool {
            guard let client = connected() else { return }
            // 新しい絵が来ていなければ読み戻さない。**据え置きが正しい**ので、
            // ここで received を nil に戻すことはしない
            guard client.hasNewFrame, let texture = client.newFrameImage() else { return }
            received = Self.picture(from: texture)
            failure = nil
        }
    }

    /// 終わるときに畳む。**投げない。**
    func close() {
        client?.stop()
        client = nil
    }

    // MARK: - 繋ぐ

    /// 繋がっているクライアント (繋がっていなければ探して繋ぐ)。
    ///
    /// **装置は `MTLCreateSystemDefaultDevice()` で取る。** 送出の側 (``SyphonSender``)
    /// では装置を渡された絵から取らねばならなかった — publish するテクスチャが本体の
    /// 描いている装置のものだからで、取り違えれば静かに壊れる。**受け取りではその
    /// 条件が無い。** 受けたテクスチャはここで CPU へ読み戻して ``DisplayImage`` にし、
    /// GPU へ戻すのは本体 (`Image.write`) の仕事なので、こちらの装置が本体の装置と
    /// 違っても出る絵は変わらない。入り口は `OutputFrame` を受け取らない
    /// (mokume の [ADR-0024] 決定 1) が、**それで困らないのはこの非対称のため**である。
    ///
    /// [ADR-0024]: https://github.com/mokume-metal/mokume/blob/main/docs/decisions/0024-extension-seams.md
    private func connected() -> SyphonMetalClient? {
        if let client, client.isValid { return client }
        // 相手が消えていれば畳んでから探し直す
        if client != nil {
            client?.stop()
            client = nil
        }
        guard let description = findServer() else { return nil }
        guard let device = MTLCreateSystemDefaultDevice() else {
            failure = "Metal の装置が取れなかった"
            return nil
        }
        let client = SyphonMetalClient(
            serverDescription: description, device: device, options: nil, newFrameHandler: nil)
        guard client.isValid else { return nil }
        self.client = client
        resourcesMade += 1
        return client
    }

    /// 繋ぐ先を探す。名前を持たなければ最初に見つかったもの。
    private func findServer() -> [String: Any]? {
        if let fixedDescription { return fixedDescription }
        let directory = SyphonServerDirectory.shared()
        let servers =
            serverName.map { directory.servers(matchingName: $0, appName: nil) }
            ?? directory.servers
        return servers.first
    }

    // MARK: - 絵にする

    /// 受けたテクスチャを、本体が絵にできる形 (``DisplayImage``) にする。
    ///
    /// | 何を | どうするか | なぜ |
    /// | --- | --- | --- |
    /// | 成分の並び | BGRA → RGBA | Syphon が抱えるのは BGRA |
    /// | 不透明度 | 乗算済み → 割り戻す | ``DisplayImage`` の定義が straight |
    /// | 原点 | そのまま | Syphon のテクスチャは行 0 が上端 |
    ///
    /// ## mokume 同士の往復では、半透明のところだけ値が動く
    ///
    /// **mokume の送出は straight のまま送っている** — 出口ごとに絵を作り分けた
    /// 瞬間に「出口は 1 点」(mokume の [ADR-0023] 決定 2) が外から足した出口でだけ
    /// 破れるためである。一方 Syphon の規約は乗算済みなので、**受ける側は規約に
    /// 従う**しかない (相手は mokume とは限らない)。不透明なところ (ほとんどの
    /// 送り手はそう) では割り戻しは何もしないので、実際に食い違うのは
    /// mokume → mokume で半透明を送ったときだけである。
    ///
    /// [ADR-0023]: https://github.com/mokume-metal/mokume/blob/main/docs/decisions/0023-frame-stages-and-outputs.md
    private static func picture(from texture: any MTLTexture) -> DisplayImage {
        let width = texture.width
        let height = texture.height
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        bytes.withUnsafeMutableBytes { destination in
            texture.getBytes(
                destination.baseAddress!, bytesPerRow: width * 4,
                from: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0)
        }
        for index in stride(from: 0, to: bytes.count, by: 4) {
            let blue = bytes[index]
            let alpha = bytes[index + 3]
            bytes[index] = unpremultiplied(bytes[index + 2], alpha)
            bytes[index + 1] = unpremultiplied(bytes[index + 1], alpha)
            bytes[index + 2] = unpremultiplied(blue, alpha)
        }
        return DisplayImage(width: width, height: height, bytes: bytes)
    }

    /// 乗算済みの 1 成分を割り戻す。**完全に不透明なら何もしない。**
    private static func unpremultiplied(_ value: UInt8, _ alpha: UInt8) -> UInt8 {
        guard alpha != 255 else { return value }
        guard alpha != 0 else { return 0 }
        return UInt8(min(255, (Int(value) * 255 + Int(alpha) / 2) / Int(alpha)))
    }
}
