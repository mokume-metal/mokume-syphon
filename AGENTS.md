<!--
SPDX-FileCopyrightText: 2026 mokume-metal
SPDX-License-Identifier: MIT
-->

# AGENTS.md

**規約の正典は [mokume の AGENTS.md](https://github.com/mokume-metal/mokume/blob/main/AGENTS.md) である。**
Issue の起こし方・分類・コメントの置き場・コミットと PR の書式・機構を足す順序 (実害 → Issue → 機構)
は、あちらを読んで同じように振る舞う。**ここには写しを置かない** —
写せばドリフトし、どちらが正かを言えなくなる ([ADR-0001](https://github.com/mokume-metal/mokume/blob/main/docs/decisions/0001-founding-principles.md) 原則 9)。

このファイルが持つのは、**このリポジトリだけで違うこと**だけである。

## 違うこと

| | mokume | ここ |
| --- | --- | --- |
| 設計判断の正典 | `docs/decisions/` の ADR | **持たない。** 判断は mokume の ADR に従い、従えない事情ができたら mokume 側に Issue を立てる |
| 検査 | `make ci-check` (14 本) | `make ci-check` (**build / test / reuse lint の 3 本**)。足すのは実害が出てから |
| PR の identity | App identity 必須 | **同じ**。承認が要る変更は誰の手であれ App の identity で作る |
| バイナリ | 1 つもコミットしない | **同じ。** `Syphon.xcframework` は Release の資産で配り、git には入れない |

## Syphon.xcframework の扱い

- ソースは `Vendor/Syphon-Framework` submodule。**上流には手を入れない**
- 焼くのは `scripts/build-syphon.sh` (`make setup`)。出来上がりは `Frameworks/` (gitignore 済み)
- `Package.swift` は**手元の成果物があればそれを優先**し、無ければ Release の資産を
  `binaryTarget(url:checksum:)` で引く。上流の変更を、版を出す前に試せるようにするため
- **焼いた直後・消した直後は `swift package purge-cache`** を打つ (`make setup` / `make clean-syphon`
  がそこまでやる)。SwiftPM は manifest の評価結果を内容ハッシュでキャッシュし、
  ファイルの出現・消失では無効化しない

## 版の張り方

- mokume への pin は **`.upToNextMinor`** (0.x の間は minor で壊れうる。mokume の ADR-0024 決定 9)
- **版を出すのは `Release` ワークフロー 1 本** (`workflow_dispatch` で tag を渡す)。焼く・pin を
  張り替える・tag を打つを**同じ 1 回で**やる。`xcodebuild` の出力はビット単位では再現しないので、
  焼き直せば checksum は変わる — 「焼いてから後で PR で書き換える」形にすると、
  **その tag の `Package.swift` が壊れたまま**になり、それを引くのは利用者である
- **`README.md` の使用例に書かれた 2 つの pin も `Release` が張る。手で直さない。**
  あそこが説明しているのは**利用者が自分の `Package.swift` に書く 2 行**で、利用者が引くのは
  released 版である。`main` の値へ揃えると、README が名指しした released 版が要求する mokume と
  食い違い、**書いてあるとおりに写しても解決しなくなる** ([#13](https://github.com/mokume-metal/mokume-syphon/issues/13) で実際に起きた)
- **pin を張り替えて merge しただけでは、利用者には何も届かない。** 利用者が引くのは released 版
  なので、追随を届けるには版を出すところまでが 1 つの仕事である
  ([#11](https://github.com/mokume-metal/mokume-syphon/issues/11) はそこで止まっていた)

## CI の緑が意味しないこと

**GitHub のランナーには、この世代のコマンド構造に対応した GPU が無い。** だから送出そのものを
見る検査 (Syphon のクライアントを繋いで絵を突き合わせるもの) は **CI では 1 本も走らない** —
`RenderDevice.isAvailable` が false になり、Suite ごと飛ぶ。

**それを実際に走らせるのは、手元の `make ci-check` だけである。** push の前に打つのは作法ではなく、
**CI が代わりに見てくれない部分を見る唯一の機会**だからである ([#1](https://github.com/mokume-metal/mokume-syphon/issues/1))。

GPU を要さない検査 (束の形) は門の外に置いてあるので、そちらは CI でも走る。

## 覚えておくこと (実測)

- **Syphon の公示は自分のプロセスへ返ってこない。** 別プロセスからは見えるが、
  同じプロセスで `SyphonServerDirectory` を引いても自分のサーバーは出てこない。
  同一プロセスで受ける検査は、サーバーの `serverDescription` から直に繋ぐ
- **窓を持たないプロセスでも公示は届く。** ただし `RunLoop` を回している間だけである
- **別プロセス間の受け取りを手で確かめるときは、送り手も受け手もターミナルから起こす。**
  エージェントのシェルから起こしたプロセスでは、**公示は一覧に出て接続も張れる** (`isValid` は
  true・`SyphonMessageSender` も作れる) **のに、フレームが 1 枚も来ない** — `hasNewFrame` が
  false のままで、サーバーから `UpdateSurfaceID` が返っていない。ターミナル起動どうしなら
  受け取れる ([#9](https://github.com/mokume-metal/mokume-syphon/issues/9) で実測)。
  自動検査が同じプロセスの中で送受信するのは、この足枷とは別に**公示が自分へ返らない**ためである
