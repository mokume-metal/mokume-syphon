<!--
SPDX-FileCopyrightText: 2026 mokume-metal
SPDX-License-Identifier: MIT
-->

# 第三者の素材

このリポジトリが再配布する第三者の素材は **1 つだけ** — Syphon Framework をコンパイルした
`Syphon.xcframework` である。git にはコミットせず ([mokume の ADR-0001](https://github.com/mokume-metal/mokume/blob/main/docs/decisions/0001-founding-principles.md) 原則 7)、
**GitHub Release の資産として配って `Package.swift` の `binaryTarget` が引く**。
ソースは `Vendor/Syphon-Framework` submodule で、`scripts/build-syphon.sh` が焼く。

## Syphon Framework

- 出どころ: <https://github.com/Syphon/Syphon-Framework>
- 固定しているコミット: `71351d4` (2025-10-06)
- 著作権: Copyright 2010 bangnoise (Tom Butterworth) & vade (Anton Marini). All rights reserved.
- ライセンス: **BSD-3-Clause** (下記のとおり、上流の中で告知が 2 通りある)

### 上流の告知は 2 通りある

| どこ | 条項 |
| --- | --- |
| リポジトリの `License.txt` | **3 条項** (第 3 条 = Syphon Project の名前による推奨の禁止) |
| 各ソースファイルの先頭 | **2 条項** (第 3 条が無い) |

**このリポジトリは 3 条項として扱う。** 配るのはソースではなく、全ファイルを束ねてコンパイル
した 1 つのバイナリで、その全体に対する上流の宣言は `License.txt` である。3 条項を守れば
2 条項も満たすので、片方だけを選んで狭く名乗る理由が無い。

`LICENSES/` に置くのは `BSD-3-Clause.txt` だけである。2 条項は 3 条項から第 3 条を
除いたものなので、3 条項の全文が 2 条項の全文を含んでいる — 同じ本文を 2 つ置くと
どちらが正かを言えなくなる。

### `License.txt` (上流のリポジトリ全体)

```
Syphon Framework License:

Copyright 2010 bangnoise (Tom Butterworth) & vade (Anton Marini).
All rights reserved.

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are met:

* Redistributions of source code must retain the above copyright
notice, this list of conditions and the following disclaimer.

* Redistributions in binary form must reproduce the above copyright
notice, this list of conditions and the following disclaimer in the
documentation and/or other materials provided with the distribution.

* Neither the name of the Syphon Project nor the names of its contributors
may be used to endorse or promote products derived from this software
without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDERS BE LIABLE FOR ANY
DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
(INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
(INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
```

Metal 系のファイル (`SyphonMetalServer` / `SyphonMetalClient` ほか) は
Copyright 2020-2023 Maxime Touroute & Philippe Chaurand (www.millumin.com),
bangnoise (Tom Butterworth) & vade (Anton Marini) を併記している。条項は上と同じ
BSD 系で、こちらは 2 条項である。
