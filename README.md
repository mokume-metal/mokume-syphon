<!--
SPDX-FileCopyrightText: 2026 mokume-metal
SPDX-License-Identifier: MIT
-->

# mokume-syphon

[mokume](https://github.com/mokume-metal/mokume) で描いた絵を、**同じマシンの他のアプリへ毎フレーム渡す**。
映像ミキサ・プロジェクションマッピングの道具・配信ソフト (MadMapper / Resolume / VDMX / TouchDesigner / OBS など) は
[Syphon](https://github.com/Syphon/Syphon-Framework) に既に対応しているので、こちらが送り手になれば繋がる。

**mokume の最初の外部パッケージ**である ([mokume#438](https://github.com/mokume-metal/mokume/issues/438))。

## 使い方

`Package.swift` に 1 行足して、`import MokumeSyphon` し、`plugins` に 1 行書く。

```swift
// Package.swift
dependencies: [
    .package(url: "https://github.com/mokume-metal/mokume.git", .upToNextMinor(from: "0.3.0")),
    .package(url: "https://github.com/mokume-metal/mokume-syphon.git", .upToNextMinor(from: "0.1.0")),
],
targets: [
    .executableTarget(
        name: "MySketch",
        dependencies: [
            .product(name: "mokume", package: "mokume"),
            .product(name: "MokumeSyphon", package: "mokume-syphon"),
        ],
        swiftSettings: [.swiftLanguageMode(.v6), .defaultIsolation(MainActor.self)])
]
```

```swift
import MokumeSyphon
import mokume

@main
final class MySketch: Sketch {
    var settings: SketchSettings { SketchSettings(width: 1920, height: 1080, title: "Preview") }

    var plugins: [any Plugin] { [SyphonPlugin(sending: "MySketch")] }

    func draw() {
        background(.display(red: 0.06, green: 0.07, blue: 0.09))
        circle(width / 2, height / 2, 200 + sin(time) * 100)
    }
}
```

受け手の入力一覧に `MySketch` が現れる。

**書いてあれば効き、書いていなければ効かない。** 依存に足しただけでは何も起きず、`plugins` に
書いた束だけが差込口へ入る ([mokume の ADR-0024](https://github.com/mokume-metal/mokume/blob/main/docs/decisions/0024-extension-seams.md) 決定 5)。

### 窓を持たない実行でも送れる

`Examples/SendHeadless` が最短の形を示す。`Sketch` の既定の入口は必ず窓を開くので、
窓が要らないときは**フレームを進める入口を自分で叩く**。

```swift
let runtime = try SketchRuntime(sketch: MySketch(), gpu: try RenderDevice())
while … {
    try runtime.advance()
    RunLoop.current.run(until: Date(timeIntervalSinceNow: 1.0 / 60))
}
```

**`RunLoop` を回すのが要点である。** Syphon のサーバー公示とクライアントの接続は
distributed notification に乗るので、`sleep` で待つと絵は publish されているのに
**受け手の一覧に現れない**。

## 渡す絵について

渡すのは **mokume の組み込みの出口 (画像の書き出し・観測) が受け取るのとまったく同じ 1 枚**である
([ADR-0023](https://github.com/mokume-metal/mokume/blob/main/docs/decisions/0023-frame-stages-and-outputs.md) 決定 2 / 決定 4 の表)。
画素まで一致していることは検査が毎回見ている (`Tests/MokumeSyphonTests`)。

| | |
| --- | --- |
| 不透明度 | **保つ** |
| アルファ | **乗算を戻した straight** |
| 明るさ | 標準の範囲へ丸め済み・ディスプレイのエンコード済み・8 bit |

**受け手側は straight として合成すること。** Syphon の慣習は乗算済み (premultiplied) なので、
慣習どおりに合成すると**半透明のところだけ暗く出る**。ここで乗算し直さないのは、出口ごとに絵を
作り分けた瞬間に「出口は 1 点」が外から足した出口でだけ破れるためである
(判断の正典は mokume の ADR-0023 決定 4)。不透明な絵しか送らないなら関係しない。

## 開発

Syphon.xcframework は git にコミットしない ([mokume の ADR-0001](https://github.com/mokume-metal/mokume/blob/main/docs/decisions/0001-founding-principles.md) 原則 7)。
`Package.swift` は**手元で焼いたものがあればそれを、無ければ Release の資産を**使う。

```bash
make setup      # submodule を引き、Syphon.xcframework を焼く (Xcode.app が要る)
make ci-check   # CI と同じ検査。push 前に通す
make clean-syphon  # 手元の成果物を捨て、利用者と同じ経路 (Release の資産) に戻す
```

## なぜ本体と別のリポジトリなのか

SwiftPM の `binaryTarget` は、**その product を使わない利用者にも artifact をダウンロードさせる**。
本体の manifest に置くと、Syphon を使わない人まで xcframework を引くことになる
(mokume の ADR-0001 原則 6 / ADR-0016 決定 7)。

## ライセンス

このリポジトリのコードは MIT ([LICENSE](LICENSE))。再配布する Syphon Framework の帰属は
[THIRD_PARTY_LICENSES.md](THIRD_PARTY_LICENSES.md)。
