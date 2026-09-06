#!/bin/bash
# SPDX-FileCopyrightText: 2026 mokume-metal
# SPDX-License-Identifier: MIT
#
# mokume への pin が上流の最新版から取り残されていないかを判定する (#12)。
#
#   check-mokume-pin.sh                          … Package.swift の pin と上流の最新版を比べる
#   check-mokume-pin.sh --compare <pin> <latest> … ネットワークを打たない純粋比較
#
# 終了コードで名乗る。**「遅れている」に 1 を割り当てない** — gh の失敗も set -u の
# 未定義も jq のパースミスも 1 で落ちるので、1 を「遅れている」にすると**あらゆる異常が
# 誤起票になる**:
#
#   0   追随している (最新版が pin の .upToNextMinor が許す範囲に入っている)
#   10  遅れている (範囲の外に新しい版が出ている)
#   20  major が上がった — 追随ではなく **pin 方針の見直し**が要る。.upToNextMinor は
#       mokume の ADR-0024 決定 9 が「0.x の間は」を理由に決めたものなので、1.0 が出たら
#       張り方そのものを決め直す
#   64  異常 (読み取り・引数・上流の応答)
#
# 判定 (このスクリプト) と発信 (report-mokume-update.sh) をファイルごと分けているのは、
# **手元で判定を打っただけで Issue が立たないようにするため**である (mokume の
# scripts/report-ruleset-drift.sh と同じ理由付け。単体テストのためではない)。
#
# 前提: Package.resolved は .gitignore 下にあり CI では使われない。つまり CI は毎回
# .upToNextMinor の範囲で最新を解決するので、**範囲内のパッチ更新は黙って取り込まれ、
# 追随の作業を要さない**。この検知が minor 越えだけを見るのはそのためで、誰かが
# Package.resolved を commit するとこの前提が崩れ、この検知は嘘になる。
#
# 呼び出しは .github/workflows/mokume-release-watch.yml、
# 検査は Tests/MokumeSyphonTests/MokumePinCheckTests.swift。
set -euo pipefail

# 上流。literal はこの 1 箇所だけで持つ (mokume の repo-slug.sh に当たるものは
# このリポジトリには無い。依存が 1 本しか無いので、置く実害がまだ出ていない)
readonly UPSTREAM_REPO="mokume-metal/mokume"
readonly MANIFEST="Package.swift"

readonly EXIT_OUTDATED=10
readonly EXIT_MAJOR_BUMP=20
readonly EXIT_ERROR=64

die() {
  echo "check-mokume-pin: $*" >&2
  exit "$EXIT_ERROR"
}

# "v0.7.0" / "0.7.0" → "0 7 0"。プレリリースとビルドメタデータは落とす。
# SwiftPM は下限がプレリリースでない限りプレリリースを解決しないので、比較には要らない
split_semver() {
  local raw="$1" version major minor patch
  version="${raw#v}"
  major="${version%%.*}"
  version="${version#*.}"
  minor="${version%%.*}"
  patch="${version#*.}"
  patch="${patch%%[-+]*}"

  case "$major" in '' | *[!0-9]*) die "版の綴りとして読めない: $raw" ;; esac
  case "$minor" in '' | *[!0-9]*) die "版の綴りとして読めない: $raw" ;; esac
  case "$patch" in '' | *[!0-9]*) die "版の綴りとして読めない: $raw" ;; esac
  # "0.7" のように 3 つ揃わない綴りは minor と patch が同じ切り出しになる
  case "$raw" in *.*.*) ;; *) die "版の綴りとして読めない: $raw" ;; esac

  printf '%s %s %s\n' "$major" "$minor" "$patch"
}

# Package.swift から mokume への pin の下限を読む。**1 行だけ当たることを要求する** —
# 0 行なら綴りが変わったか依存が消えたということで、黙って「追随済み」に倒すと
# 検知が永久に鳴らなくなる
read_pin() {
  [ -f "$MANIFEST" ] || die "$MANIFEST が無い (リポジトリのルートで打つ)"

  local matches count
  matches=$(sed -n \
    's|.*'"${UPSTREAM_REPO//\//\\/}"'\.git".*\.upToNextMinor(from: "\([^"]*\)").*|\1|p' \
    "$MANIFEST")
  count=$(printf '%s' "$matches" | grep -c . || true)

  [ "$count" -eq 1 ] || die "$MANIFEST の $UPSTREAM_REPO への .upToNextMinor が $count 件 (1 件であるべき)"
  printf '%s\n' "$matches"
}

# 上流の最新版。**releases/latest を使う** — gh release list は draft と prerelease の
# 行も返すので、それらを定義上除いた 1 件が返るこちらを引く。
#
# なお SwiftPM が見るのは tag で、こちらが見るのは release である。tag だけ打って
# release を作らない版が出ると検知が漏れる — mokume の release.yml は tag と release を
# 必ず同じ 1 回で作る形なので今は一致しているが、依存していることは意識しておく
fetch_latest() {
  local tag
  tag=$(gh api "repos/$UPSTREAM_REPO/releases/latest" --jq '.tag_name') ||
    die "$UPSTREAM_REPO の最新版を引けない (認証・通信)"
  [ -n "$tag" ] || die "$UPSTREAM_REPO の最新版が空で返った"
  printf '%s\n' "$tag"
}

# pin が許すのは [X.Y.0, X.(Y+1).0)。**latest > pin の大小比較にしない** — それだと
# 0.4.0 pin に 0.4.3 が出た日に「遅れている」と誤検知する (範囲の中なので追随は要らない)
classify() {
  local pin="$1" latest="$2"
  local pin_major pin_minor latest_major latest_minor

  read -r pin_major pin_minor _ <<<"$(split_semver "$pin")"
  read -r latest_major latest_minor _ <<<"$(split_semver "$latest")"

  if [ "$latest_major" -lt "$pin_major" ] ||
    { [ "$latest_major" -eq "$pin_major" ] && [ "$latest_minor" -lt "$pin_minor" ]; }; then
    die "上流の最新版 ($latest) が pin ($pin) より古い — どちらかの読み取りを疑う"
  fi

  if [ "$latest_major" -gt "$pin_major" ]; then
    return "$EXIT_MAJOR_BUMP"
  fi
  if [ "$latest_minor" -gt "$pin_minor" ]; then
    return "$EXIT_OUTDATED"
  fi
  return 0
}

main() {
  local pin latest

  case "${1:-}" in
    --compare)
      [ $# -eq 3 ] || die "--compare は <pin> <latest> の 2 つを取る"
      pin="$2"
      latest="$3"
      ;;
    '')
      pin="$(read_pin)"
      latest="$(fetch_latest)"
      ;;
    *)
      die "読めない引数: $1"
      ;;
  esac

  # split_semver の die はサブシェルでは効かないので、ここで綴りを確かめてから分類へ渡す
  split_semver "$pin" >/dev/null
  split_semver "$latest" >/dev/null

  local status=0
  classify "$pin" "$latest" || status=$?

  local outdated=false
  case "$status" in
    0) echo "ok: pin $pin は上流の最新版 ${latest#v} を含む範囲にある" ;;
    "$EXIT_OUTDATED")
      outdated=true
      echo "outdated: pin $pin の範囲の外に ${latest#v} が出ている"
      ;;
    "$EXIT_MAJOR_BUMP")
      outdated=true
      echo "major-bump: 上流が ${latest#v} を出した。pin $pin の .upToNextMinor は"
      echo "            0.x を前提にした張り方なので、追随ではなく張り方の見直しが要る"
      ;;
  esac

  if [ -n "${GITHUB_OUTPUT:-}" ]; then
    {
      echo "current=$pin"
      echo "latest=${latest#v}"
      echo "outdated=$outdated"
    } >>"$GITHUB_OUTPUT"
  fi

  return "$status"
}

main "$@"
