// SPDX-FileCopyrightText: 2026 mokume-metal
// SPDX-License-Identifier: MIT

import Foundation
import Metal
import Syphon
import mokume

/// 出口 — フレーム 1 枚を Syphon のサーバーへ渡す。
///
/// 面に出る型ではない (束が中に持つ)。外から触るのは ``SyphonPlugin`` だけである。
final class SyphonSender: Outlet {
    private let name: String

    /// 立てたサーバー。**最初のフレームまで立てない** (下記)。
    private var server: SyphonMetalServer?
    /// Syphon へ渡すためだけのコマンドの発行口。**1 本を使い回す。**
    private var queue: (any MTLCommandQueue)?

    /// サーバーと発行口を作った回数。**フレーム数によらず 1 のままであること**が
    /// 「毎フレーム新しい置き場を確保しない」(mokume の [ADR-0023] 決定 5) の中身で、
    /// 検査はこの数を見る。
    ///
    /// [ADR-0023]: https://github.com/mokume-metal/mokume/blob/main/docs/decisions/0023-frame-stages-and-outputs.md
    private(set) var resourcesMade = 0

    private(set) var failure: String?

    /// 立てたサーバーの素性。**同じプロセスから受けるときはこれを使う。**
    ///
    /// Syphon の公示は distributed notification に乗るが、**自分のプロセスへは
    /// 返ってこない** (別プロセスからは見える。実測)。だから同一プロセスの検査は
    /// 一覧から探せず、ここから直に繋ぐ。
    var serverDescription: [String: Any]? {
        server.map { $0.serverDescription as [String: Any] }
    }

    init(name: String) {
        self.name = name
    }

    // MARK: - 差込口

    /// サーバーは ``open()`` では立てない。
    ///
    /// **`MTLDevice` を知る道が、渡される絵の中にしか無いためである。** 本体は
    /// 描画の土台を公開しておらず、下位の描画資源が面に出るのは
    /// `OutputFrame.texture` の 1 点だけである (mokume の [ADR-0024] 決定 8)。
    /// `MTLCreateSystemDefaultDevice()` で別に取ることもできるが、それは
    /// **本体が実際に描いている装置と同じとは限らない** — 違えば publish は
    /// 静かに壊れる。渡された絵から取れば、取り違えようがない。
    ///
    /// 立てるのが 1 フレーム遅れる代わりに、受け手には「描き始めたら現れる」形になる。
    ///
    /// [ADR-0024]: https://github.com/mokume-metal/mokume/blob/main/docs/decisions/0024-extension-seams.md
    func open() throws {}

    /// フレーム 1 枚を渡す。**投げない** ([ADR-0024] 決定 7)。
    ///
    /// 転んだ理由は ``failure`` へ置く。3 フレーム続けて置かれると本体がこの出口を
    /// 外し、外したことを診断に出す。直れば `nil` に戻すので数え直しも起きない。
    ///
    /// [ADR-0024]: https://github.com/mokume-metal/mokume/blob/main/docs/decisions/0024-extension-seams.md
    func receive(_ frame: OutputFrame) {
        // ObjC の一時オブジェクトが毎フレーム溜まらないようにする
        // (長く回しても資源が増え続けないこと。[ADR-0023] 決定 5)
        autoreleasepool {
            let texture = frame.texture
            guard let server = server(for: texture.device), let queue = queue else { return }
            guard let commands = queue.makeCommandBuffer() else {
                failure = "コマンドバッファを作れなかった"
                return
            }
            // 待ちは要らない。本体は絵を取り出す時点で GPU の完了を待っているので、
            // ここへ来た絵は既に確定している
            server.publishFrameTexture(
                texture, on: commands,
                imageRegion: NSRect(x: 0, y: 0, width: texture.width, height: texture.height),
                // 本体の絵は行 0 が上端 (書き出す PNG と同じ向き) なので、
                // Metal 座標では反転していない
                flipped: false)
            commands.commit()
            failure = nil
        }
    }

    /// 終わるときに畳む。**投げない。**
    func close() {
        server?.stop()
        server = nil
        queue = nil
    }

    // MARK: - 立てる

    /// サーバーを立てる (立っていればそれを返す)。
    private func server(for device: any MTLDevice) -> SyphonMetalServer? {
        if let server { return server }
        guard let queue = device.makeCommandQueue() else {
            failure = "コマンドの発行口を作れなかった"
            return nil
        }
        queue.label = "mokume.syphon.publish"
        let server = SyphonMetalServer(name: name, device: device, options: nil)
        self.queue = queue
        self.server = server
        resourcesMade += 1
        return server
    }
}
