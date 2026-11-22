// SPDX-FileCopyrightText: 2026 mokume-metal
// SPDX-License-Identifier: MIT

/// 2 つのバイト列の食い違いの要約 — 一致していれば `nil`。
///
/// **バイト列そのものを `#expect` に渡さない**ための助けである。食い違ったときに
/// 数万個の数字が出力へ流れると、どこが違うのかがかえって読めなくなる。
func firstMismatch(_ lhs: [UInt8], _ rhs: [UInt8]) -> (index: Int, differing: Int)? {
    guard lhs.count == rhs.count else { return (0, max(lhs.count, rhs.count)) }
    var first: Int?
    var differing = 0
    for index in lhs.indices where lhs[index] != rhs[index] {
        if first == nil { first = index }
        differing += 1
    }
    return first.map { ($0, differing) }
}

/// 行の順を逆にする (1 行 = `width * 4` バイト)。**上下の向きを付け替えるためだけに使う。**
///
/// 本体の絵は 1 行目が上端、Syphon の IOSurface と OpenGL は 1 行目が下端である (#68)。
func reversingRows(_ bytes: [UInt8], width: Int, height: Int) -> [UInt8] {
    let stride = width * 4
    var reversed = [UInt8]()
    reversed.reserveCapacity(bytes.count)
    for row in (0..<height).reversed() {
        reversed += bytes[(row * stride)..<((row + 1) * stride)]
    }
    return reversed
}
