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
