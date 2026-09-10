#!/bin/bash
# SPDX-FileCopyrightText: 2026 mokume-metal
# SPDX-License-Identifier: MIT
#
# 上流の版を検知する workflow (mokume-release-watch.yml) が、まだ生きているかを判定する (#16)。
#
#   check-watch-liveness.sh                   … GitHub に問い合わせて state を読む
#   check-watch-liveness.sh --compare <state> … ネットワークを打たない純粋判定
#
# **public リポジトリの scheduled workflow は、60 日活動が無いと GitHub が自動で無効化する。**
# このリポジトリは版 2 つ・コミット 10 本ほどの低速なリポなので、60 日コミットが無い期間は
# 現実的に起こりうる。そして止まったことは無音である — #12 が塞ごうとした失敗 (上流の版に
# 取り残されたことに誰も気付かない) と**まったく同じ形**で、検知の機構自体が同じ穴に落ちる。
#
# 無効化には、#16 が前提に置いていたより悪い性質が 2 つある:
#
#   * **`workflow_dispatch` は生き残らない。** 止まるのは schedule だけでなく workflow
#     ファイルごとなので、手で起こす経路も同時に死ぬ。「人が思い出したときに押す」は網にならない
#   * **自分では戻らない。** 活動が戻っても GitHub は再有効化しない。人が押すまで死んだままで、
#     無活動の 60 日よりも**その後ずっと**のほうが穴として大きい
#
# 塞ぐのは後者である。前者 (無活動の間に上流の版を取り逃す) には外部の時計が要り、代償は
# 上流に cross-repo の token を置くこと — #16 の判断のとおり、そこまではしない。誰も触って
# いない 60 日の取り逃しは、戻ってきた瞬間に追いつけば実害にならない。**追いつけなくするのが
# 後者**であり、そちらは「止まったことを読む口が API にあるのに、このリポジトリの何も
# それを読んでいない」という、今日示せる穴である (mokume の ADR-0008 決定 1 の後者)。
#
# 終了コードで名乗る。**「止まっている」に 1 を割り当てない** — gh の失敗も set -u の未定義も
# jq のパースミスも 1 で落ちるので、1 を「止まっている」にすると**あらゆる異常が誤報になる**
# (check-mokume-pin.sh と同じ理由付け):
#
#   0   active — 生きている
#   10  disabled_inactivity — GitHub が無活動で止めた。#16 が塞ぐ状態
#   20  それ以外の停止 (disabled_manually / disabled_fork)。人の意図かもしれないので分ける
#   64  異常 (読み取り・認証・workflow が見つからない・読めない state)
#
# **見つからない (404 / deleted) を 64 に置く。** 検知そのものを意図して消したなら、この
# 見張りも一緒に消すのが筋であって、黙って緑になってよい状態ではない。
#
# 呼び出しは .github/workflows/watch-liveness.yml、
# 検査は Tests/MokumeSyphonTests/WatchLivenessCheckTests.swift。
set -euo pipefail

# 見張る対象。API は workflow をファイル名でも引ける
readonly WATCHED_WORKFLOW="mokume-release-watch.yml"

readonly EXIT_INACTIVITY=10
readonly EXIT_STOPPED=20
readonly EXIT_ERROR=64

die() {
  echo "check-watch-liveness: $*" >&2
  exit "$EXIT_ERROR"
}

# 自分のリポジトリ。Actions の中では GITHUB_REPOSITORY が入っているのでそれを使い、
# 手元で打つときだけ gh に聞く (認証の要る問い合わせを 1 回減らす)
current_repo() {
  if [ -n "${GITHUB_REPOSITORY:-}" ]; then
    printf '%s\n' "$GITHUB_REPOSITORY"
    return 0
  fi
  gh repo view --json nameWithOwner --jq '.nameWithOwner' ||
    die "リポジトリを特定できない (リポジトリの中で打つ・gh の認証)"
}

fetch_state() {
  local repo state
  repo="$(current_repo)"
  state=$(gh api "repos/$repo/actions/workflows/$WATCHED_WORKFLOW" --jq '.state') ||
    die "$WATCHED_WORKFLOW の状態を引けない (認証・通信・そもそも存在しない)"
  [ -n "$state" ] || die "$WATCHED_WORKFLOW の state が空で返った"
  printf '%s\n' "$state"
}

# **知らない綴りは 64 に倒す。** GitHub が state を増やしたときに、それを「生きている」と
# 読んで黙るのが一番悪い
classify() {
  case "$1" in
    active) return 0 ;;
    disabled_inactivity) return "$EXIT_INACTIVITY" ;;
    disabled_manually | disabled_fork) return "$EXIT_STOPPED" ;;
    *) die "読めない state: $1" ;;
  esac
}

main() {
  local state

  case "${1:-}" in
    --compare)
      [ $# -eq 2 ] || die "--compare は <state> の 1 つを取る"
      state="$2"
      ;;
    '')
      state="$(fetch_state)"
      ;;
    *)
      die "読めない引数: $1"
      ;;
  esac

  local status=0
  classify "$state" || status=$?

  case "$status" in
    0) echo "ok: $WATCHED_WORKFLOW は active — 上流の版の検知は生きている" ;;
    "$EXIT_INACTIVITY")
      echo "disabled-inactivity: $WATCHED_WORKFLOW を GitHub が無活動で止めている。"
      echo "                     止まっている間に出た上流の版は検知されていない。"
      echo "                     戻すには: gh workflow enable $WATCHED_WORKFLOW"
      echo "                     戻したら一度手で回す: gh workflow run $WATCHED_WORKFLOW"
      ;;
    "$EXIT_STOPPED")
      echo "stopped: $WATCHED_WORKFLOW が $state で止まっている。"
      echo "         人が止めたのなら、検知が要らなくなったということなので"
      echo "         workflow ごと消す (この見張りも一緒に消す)。そうでなければ:"
      echo "         gh workflow enable $WATCHED_WORKFLOW"
      ;;
  esac

  return "$status"
}

main "$@"
