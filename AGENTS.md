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
- 版を出すと `Package.swift` の `binaryTarget` の url と checksum が新しい Release の資産を指す。
  **書き換えは PR にする** — 自動で self-pin のコミットを積む形は、要ると分かってから足す

## 覚えておくこと (実測)

- **Syphon の公示は自分のプロセスへ返ってこない。** 別プロセスからは見えるが、
  同じプロセスで `SyphonServerDirectory` を引いても自分のサーバーは出てこない。
  同一プロセスで受ける検査は、サーバーの `serverDescription` から直に繋ぐ
- **窓を持たないプロセスでも公示は届く。** ただし `RunLoop` を回している間だけである
