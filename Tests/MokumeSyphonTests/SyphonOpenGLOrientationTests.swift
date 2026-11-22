// SPDX-FileCopyrightText: 2026 mokume-metal
// SPDX-License-Identifier: MIT

import Foundation
import MokumeHost
import OpenGL.GL3
import Syphon
import Testing
import mokume

@testable import MokumeSyphon

/// 上下の向きを、**OpenGL の受け手・送り手を錨にして**見る (#68)。
///
/// Syphon の相手の大半 (MadMapper / Resolume / VDMX …) は IOSurface を OpenGL で読み書きし、
/// **1 行目を絵の下端**として扱う。Metal の送受信どうしで往復させる検査
/// (``SyphonRoundTripTests`` / ``SyphonReceiveTests``) は、両端が同じ取り違えをしていても
/// 一致して緑になるので、向きについては何も言えない。ここでは片方を OpenGL に替え、
/// 規約をこちらの外に置く。
///
/// 絵は**上下非対称にする** — 中央の円のような上下対称の絵では、反転しても一致してしまう。
@Suite(
    "OpenGL の相手から見た上下の向き",
    .enabled(
        if: RenderDevice.isAvailable,
        "この世代のコマンド構造に対応した GPU が無い実行環境ではスキップする"),
    .serialized
)
struct SyphonOpenGLOrientationTests {

    /// 上端に帯を引くだけのスケッチ。上下を取り違えると帯が下へ行く。
    final class TopBandSketch: Sketch {
        var settings: SketchSettings {
            SketchSettings(width: 64, height: 48, title: "syphon orientation")
        }
        var plugins: [any Plugin] { Self.declared }
        nonisolated(unsafe) static var declared: [any Plugin] = []

        func draw() {
            background(.display(red: 0.2, green: 0.6, blue: 0.9))
            noStroke()
            fill(.display(red: 1, green: 0.3, blue: 0.1))
            rect(0, 0, width, height / 4)
        }
    }

    // MARK: - 送出 → OpenGL の受け手

    @Test("送出した絵を OpenGL の受け手が読むと、1 行目が下端の正立した絵になっている")
    func opengl_client_sees_upright_frame() throws {
        let plugin = SyphonPlugin(sending: "mokume test \(UUID().uuidString)")
        TopBandSketch.declared = [plugin]
        defer { TopBandSketch.declared = [] }

        try HeadlessRun.with(TopBandSketch()) { runtime in
            // 同じプロセスでは一覧に現れないので、素性から直に繋ぐ
            let description = try #require(
                advanceUntilPublished(runtime) { plugin.sender?.serverDescription },
                "60 フレーム進めてもサーバーが立たない")

            let gl = try #require(OpenGLContext(), "OpenGL の文脈を作れなかった")
            let client = SyphonOpenGLClient(
                serverDescription: description, context: gl.context, options: nil,
                newFrameHandler: nil)
            defer { client.stop() }

            var received: (width: Int, height: Int, bytes: [UInt8])?
            for _ in 0..<120 where received == nil {
                try runtime.advance()
                RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.01))
                received = autoreleasepool { client.newFrameImage().map(gl.read) }
            }

            let arrived = try #require(received, "繋いだのに 1 枚も届かなかった")
            let expected = try runtime.displayImage()

            #expect(arrived.width == expected.width)
            #expect(arrived.height == expected.height)
            // OpenGL の読み出しは 1 行目が下端。上端を原点にした絵と比べるため行を返す
            let upright = reversingRows(arrived.bytes, width: arrived.width, height: arrived.height)
            let mismatch = firstMismatch(upright, expected.bytes)
            #expect(
                mismatch == nil,
                """
                OpenGL の受け手から見た絵が送った絵と違う (上下が逆なら #68 の再発): \
                \(mismatch.map { "\($0.differing) バイトが不一致・最初は \($0.index) 番目" } ?? "")
                """)
        }
    }

    // MARK: - OpenGL の送り手 → 受け取り

    @Test("OpenGL の送り手が正立で送った絵を、正立のまま受け取る")
    func receiver_reads_opengl_frame_upright() throws {
        // 上端の 1/4 が赤・残りが青の不透明な絵 (左上原点)
        let width = 64
        let height = 48
        var expected = [UInt8]()
        for row in 0..<height {
            let pixel: [UInt8] = row < height / 4 ? [255, 0, 0, 255] : [0, 0, 255, 255]
            for _ in 0..<width { expected += pixel }
        }

        let gl = try #require(OpenGLContext(), "OpenGL の文脈を作れなかった")
        let server = SyphonOpenGLServer(
            name: "mokume test \(UUID().uuidString)", context: gl.context, options: nil)
        defer { server.stop() }
        // OpenGL のテクスチャは 1 行目が下端なので、行を返して載せる
        let texture = gl.makeRectangleTexture(
            width: width, height: height,
            bytes: reversingRows(expected, width: width, height: height))
        defer { gl.deleteTexture(texture) }

        let receiver = SyphonReceiver(serverDescription: server.serverDescription as [String: Any])
        try receiver.open()
        defer { receiver.close() }

        for _ in 0..<120 where receiver.received == nil {
            gl.publish(texture, width: width, height: height, on: server)
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.01))
            receiver.supply()
        }

        let arrived = try #require(receiver.received, "繋いだのに 1 枚も届かなかった")
        #expect(arrived.width == width)
        #expect(arrived.height == height)
        let mismatch = firstMismatch(arrived.bytes, expected)
        #expect(
            mismatch == nil,
            """
            OpenGL の送り手から受けた絵が元の絵と違う (上下が逆なら #68 の再発): \
            \(mismatch.map { "\($0.differing) バイトが不一致・最初は \($0.index) 番目" } ?? "")
            """)
    }
}

// MARK: - OpenGL の助け

/// 窓を持たない OpenGL の文脈。**検査で相手役を務めるためだけに使う** (束は OpenGL を持たない)。
private final class OpenGLContext {
    let context: CGLContextObj

    init?() {
        var attributes: [CGLPixelFormatAttribute] = [
            kCGLPFAOpenGLProfile,
            CGLPixelFormatAttribute(UInt32(kCGLOGLPVersion_3_2_Core.rawValue)),
            kCGLPFAAccelerated,
            CGLPixelFormatAttribute(0),
        ]
        var pixelFormat: CGLPixelFormatObj?
        var count: GLint = 0
        guard CGLChoosePixelFormat(&attributes, &pixelFormat, &count) == kCGLNoError,
            let pixelFormat
        else { return nil }
        defer { CGLDestroyPixelFormat(pixelFormat) }
        var context: CGLContextObj?
        guard CGLCreateContext(pixelFormat, nil, &context) == kCGLNoError, let context else {
            return nil
        }
        self.context = context
    }

    isolated deinit {
        CGLSetCurrentContext(nil)
        CGLDestroyContext(context)
    }

    /// 受けた絵を読み出す。**並びは OpenGL のまま (1 行目が下端・RGBA)。**
    ///
    /// `glGetTexImage` は使わない — IOSurface を裏に持つテクスチャでは中身を返さない
    /// (実測で先頭の数画素以外が 0 だった)。framebuffer に付けて `glReadPixels` で読む。
    func read(_ image: SyphonOpenGLImage) -> (width: Int, height: Int, bytes: [UInt8]) {
        CGLSetCurrentContext(context)
        let width = Int(image.textureSize.width)
        let height = Int(image.textureSize.height)
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let framebufferTarget = GLenum(GL_READ_FRAMEBUFFER)
        var framebuffer: GLuint = 0
        glGenFramebuffers(1, &framebuffer)
        glBindFramebuffer(framebufferTarget, framebuffer)
        glFramebufferTexture2D(
            framebufferTarget, GLenum(GL_COLOR_ATTACHMENT0), GLenum(GL_TEXTURE_RECTANGLE),
            image.textureName, 0)
        glPixelStorei(GLenum(GL_PACK_ALIGNMENT), 1)
        bytes.withUnsafeMutableBytes { destination in
            glReadPixels(
                0, 0, GLsizei(width), GLsizei(height), GLenum(GL_RGBA), GLenum(GL_UNSIGNED_BYTE),
                destination.baseAddress)
        }
        glBindFramebuffer(framebufferTarget, 0)
        glDeleteFramebuffers(1, &framebuffer)
        return (width, height, bytes)
    }

    /// 並びが OpenGL のまま (1 行目が下端・RGBA) のバイト列から、矩形テクスチャを作る。
    func makeRectangleTexture(width: Int, height: Int, bytes: [UInt8]) -> GLuint {
        CGLSetCurrentContext(context)
        let target = GLenum(GL_TEXTURE_RECTANGLE)
        var texture: GLuint = 0
        glGenTextures(1, &texture)
        glBindTexture(target, texture)
        glPixelStorei(GLenum(GL_UNPACK_ALIGNMENT), 1)
        bytes.withUnsafeBytes { source in
            glTexImage2D(
                target, 0, GL_RGBA8, GLsizei(width), GLsizei(height), 0, GLenum(GL_RGBA),
                GLenum(GL_UNSIGNED_BYTE), source.baseAddress)
        }
        glBindTexture(target, 0)
        return texture
    }

    func publish(_ texture: GLuint, width: Int, height: Int, on server: SyphonOpenGLServer) {
        CGLSetCurrentContext(context)
        server.publishFrameTexture(
            texture, textureTarget: GLenum(GL_TEXTURE_RECTANGLE),
            imageRegion: NSRect(x: 0, y: 0, width: width, height: height),
            textureDimensions: NSSize(width: width, height: height),
            // OpenGL の向きのまま載せたテクスチャなので、反転していない
            flipped: false)
        glFlush()
    }

    func deleteTexture(_ texture: GLuint) {
        CGLSetCurrentContext(context)
        var texture = texture
        glDeleteTextures(1, &texture)
    }
}
