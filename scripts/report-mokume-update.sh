#!/bin/bash
# SPDX-FileCopyrightText: 2026 mokume-metal
# SPDX-License-Identifier: MIT
#
# 上流 mokume が pin の範囲の外へ出たことを発信する (#12)。
#
#   report-mokume-update.sh [--dry-run] <いまの pin> <上流の最新版> <検査の判定> <検査のログ>
#
# --dry-run は投稿せず本文を標準出力へ出す (mokume の scripts/comment.sh と同じ口)。
# 読み取り (既存の Issue と印の照会) はそのまま行うので、**新規に起票する形になるのか
# 追記になるのかまで含めて**、発信する前に目で見られる。
#
#   検査の判定 …  pass       新しい版で make ci-check が通った
#                 fail       新しい版で落ちた。いまの pin では通った (新版が原因でありうる)
#                 fail-both  どちらでも落ちた (上流の版とは無関係な赤)
#
# 判定 (check-mokume-pin.sh) と発信 (ここ) をファイルごと分けているのは、**手元で判定を
# 打っただけで Issue が立たないようにするため**である (mokume の
# scripts/report-ruleset-drift.sh と同じ理由付け)。
#
# **どの契機でも起票してよい。** 写し元 (ruleset-drift) が push 契機で起票を控えたのは、
# 「定義を merge した直後にまだ適用していない」のが**正常な状態**だったからである。
# ここで検知するのは「上流が版を出したのにこちらが追随していない」で、これは正常な状態
# ではない — いつ気付いても直す必要があるので、契機で振る舞いを変えない。
#
# **Issue は 1 本に保つ。** 版ごとに立てると 0.5 / 0.6 / 0.7 で 3 本並ぶが、解消する行為は
# 「pin を 1 回張り替える」だけである。1 行為に 3 本は積み増しで、毎日鳴る狼になれば本物
# の起票まで反射で閉じられるようになる。新しい版が出たら同じ Issue へ追記する。
#
# **自動で閉じない。** 閉じるのは pin を張り替える PR の `Closes #N` である。
#
# 呼び出しは .github/workflows/mokume-release-watch.yml。
set -euo pipefail

readonly UPSTREAM_REPO="mokume-metal/mokume"
readonly REPO="mokume-metal/mokume-syphon"

# 重複起票を防ぐための固定タイトル。文言を変えると、変える前に立った Issue が
# 見つからなくなり二重に立つので、変えるときは open な分を先に畳む
readonly TITLE="chore: mokume の新しい版に追随する"

# 起票と同時に付ける印。完了条件 (下の「解消の判定」) を本文へ焼き込んでいるので、
# 議論を待たずに着手できる。**語彙は上流と同じ 1 種**で、ラベルが表すのは「完了条件が固まって
# いる」ことだけである (mokume の ADR-0031 決定 1。ここが揃える理由は ADR-0026 決定 1 の第 1 段)。
# 綴りが上流とずれると、渡した瞬間に gh issue create ごと失敗する (#14)
readonly VERIFY_LABEL="verify: triaged"

# 「いまどの版まで知らせたか」を機械が読む印。**散文からは読まない** — 本文の言い回しを
# 直した日に読めなくなり、同じ版で毎日コメントが増える。印は 1 箇所だけに持つ
readonly MARKER_HEAD="<!-- mokume-latest:"

# 本文に載せる上限。長すぎると Issue 本文の上限に当たって起票ごと失敗する
readonly MAX_LOG_LINES=120

die() {
  echo "report-mokume-update: $*" >&2
  exit 64
}

dry_run=false
if [ "${1:-}" = "--dry-run" ]; then
  dry_run=true
  shift
fi

current="${1:?いまの pin が必要}"
latest="${2:?上流の最新版が必要}"
verdict="${3:?検査の判定が必要}"
log="${4:?検査のログが必要}"

latest="${latest#v}"
[ -f "$log" ] || die "検査のログが無い: $log"
case "$verdict" in
  pass | fail | fail-both) ;;
  *) die "読めない判定: $verdict (pass / fail / fail-both のどれか)" ;;
esac

run_url=""
if [ -n "${GITHUB_RUN_ID:-}" ]; then
  run_url="${GITHUB_SERVER_URL:-https://github.com}/$REPO/actions/runs/$GITHUB_RUN_ID"
fi

# pin を張り替えたときに跨ぐことになる版。引けなくても発信は止めない (補助の情報で、
# 無くても「いまの pin」と「最新版」だけで着手できる)
intervening_releases() {
  local since
  since=$(gh api "repos/$UPSTREAM_REPO/releases/tags/v$current" --jq '.published_at' 2>/dev/null) || return 0
  [ -n "$since" ] || return 0
  gh api "repos/$UPSTREAM_REPO/releases" --paginate \
    --jq ".[] | select(.draft == false and .prerelease == false)
          | select(.published_at > \"$since\")
          | \"- [\(.tag_name)](\(.html_url)) — \(.published_at[0:10])\"" 2>/dev/null |
    sort -r || true
}

# 検査の結果を、読み手が最初に知りたい 1 行と、根拠のログに分けて書く
verdict_summary() {
  case "$verdict" in
    pass)
      echo "**pin を $latest に書き換えて \`make ci-check\` を回したところ緑だった。**"
      ;;
    fail)
      echo "**pin を $latest に書き換えると \`make ci-check\` が落ちる。** 同じ run で"
      echo "いまの pin ($current) では通っているので、**上流の新しい版が原因でありうる**。"
      ;;
    fail-both)
      echo "**pin を $latest に書き換えると \`make ci-check\` が落ちるが、いまの pin ($current)"
      echo "でも同じように落ちる。** 上流の版とは無関係な赤 (ランナーの Xcode や Syphon 側の"
      echo "変化) が混ざっているので、追随の可否はこの結果からは言えない。"
      ;;
  esac
}

# 本文とコメントの両方から印を拾い、**最後に現れたもの**を採る。1 つも読めなければ
# 空を返す — 呼び出し側はそのとき沈黙する (誤って同じ版で鳴らし続けるより黙るほうが安全)
recorded_marker() {
  local number="$1"
  gh issue view "$number" -R "$REPO" --json body,comments \
    --jq '[.body] + [.comments[].body] | .[]' 2>/dev/null |
    sed -n "s|.*${MARKER_HEAD} \([^ ]*\) -->.*|\1|p" |
    tail -n 1
}

# シングルクォートの中のバッククォートは Markdown のコードスパンであって、
# 展開させたい式ではない
# shellcheck disable=SC2016
compose_body() {
  local marker_line="$MARKER_HEAD $latest -->"
  local releases
  releases="$(intervening_releases)"

  printf '%s\n\n' "$marker_line"

  printf '## 何が起きているか\n\n'
  printf '上流 mokume が **%s** を出している。`Package.swift` の pin は `.upToNextMinor(from: "%s")` なので、' "$latest" "$current"
  printf '解決できる範囲はその外にある — このままだと **mokume %s を使う人はこのパッケージを足せない** (#11 と同じ形の詰まり方)。\n\n' "$latest"

  if [ -n "$releases" ]; then
    printf '跨ぐことになる版:\n\n%s\n\n' "$releases"
  fi

  printf '## 動作チェック\n\n'
  verdict_summary
  printf '\n'

  printf '**ただし、CI が見ているのは送出ではない。** GitHub のランナーには GPU が無いので、'
  printf '送出を見る検査は Suite ごと飛んでいる (#1)。ここで分かるのは**ビルドと GPU 非依存の'
  printf '検査の結果**までで、実際に絵が出るかは手元でしか見られない。\n\n'

  printf '<details><summary>検査のログ (末尾 %s 行)</summary>\n\n```text\n' "$MAX_LOG_LINES"
  tail -n "$MAX_LOG_LINES" "$log"
  printf '```\n\n</details>\n\n'

  cat <<'BODY'
## どうなれば解消か

**手元で 3 つとも判定できる。**

1. `bash scripts/check-mokume-pin.sh` が緑 (`Package.swift` の pin が最新版を含む範囲にある)
2. **`README.md` の使用例は触らない** — あの 2 行は `Release` ワークフローが released 版から張る。
   `main` の値へ手で揃えると、README が名指しした released 版が要求する mokume と食い違い、
   **書いてあるとおりに写しても解決しなくなる** (#13 で実際に起きた)
3. **手元で `make ci-check` が緑** — CI の緑では送出を確かめられないため、ここだけは人の手が要る

張り替える PR に `Closes` でこの Issue を書く。**この Issue は自動では閉じない。**

**追随が利用者へ届くのは、次の版を出したときである。** 利用者が引くのは released 版なので、
merge しただけでは released 版は古い mokume に張られたまま残る — #11 はそれで、`main` を直して
close した後も詰まりは解消していなかった (#13)。
BODY

  if [ -n "$run_url" ]; then
    printf '\n検出した run: %s\n' "$run_url"
  fi
  printf '\n<sub>🤖 この Issue は .github/workflows/mokume-release-watch.yml が自動起票した (#12)。完了条件が本文で確定しているため `%s` も自動で付く</sub>\n' "$VERIFY_LABEL"
}

compose_followup() {
  printf '%s %s -->\n\n' "$MARKER_HEAD" "$latest"
  printf 'その後、上流が **%s** を出した。この Issue を立てた時点より新しい。\n\n' "$latest"
  printf '## 動作チェック\n\n'
  verdict_summary
  printf '\n'
  printf '<details><summary>検査のログ (末尾 %s 行)</summary>\n\n```text\n' "$MAX_LOG_LINES"
  tail -n "$MAX_LOG_LINES" "$log"
  printf '```\n\n</details>\n'
  if [ -n "$run_url" ]; then
    printf '\n検出した run: %s\n' "$run_url"
  fi
  printf '\n<sub>🤖 .github/workflows/mokume-release-watch.yml が追記した (#12)</sub>\n'
}

# 同じ内容で毎日立てない。GitHub の検索は前方一致や語での照合なので、返ってきたものを
# タイトル完全一致で絞ってから採る
existing=$(gh issue list -R "$REPO" --state open --search "\"$TITLE\" in:title" \
  --json number,title \
  --jq "[.[] | select(.title == \"$TITLE\")] | .[0].number // empty")

tmp=$(mktemp)
trap 'rm -f "$tmp"' EXIT

if [ -z "$existing" ]; then
  compose_body >"$tmp"
  if [ "$dry_run" = true ]; then
    printf 'report: --dry-run — 起票する形 (タイトル: %s / 型: Task / ラベル: %s)\n\n' "$TITLE" "$VERIFY_LABEL"
    cat "$tmp"
    exit 0
  fi
  url=$(gh issue create -R "$REPO" --title "$TITLE" --body-file "$tmp" \
    --type Task --label "$VERIFY_LABEL")
  echo "report: 起票した $url"
  exit 0
fi

recorded="$(recorded_marker "$existing")"

if [ -z "$recorded" ]; then
  # 本文もコメントも印を持たない = 人が書き換えたか、印の綴りが変わった。**黙る** —
  # 読めないまま鳴らすと、同じ版で毎日コメントが増える
  echo "report: #$existing に印が無いので追記しない (差分は run のログに残る)"
  exit 0
fi

if [ "$recorded" = "$latest" ]; then
  # 既に知らせてある版。**検査の判定が前回と変わっていても追記しない** — ランナーの
  # Xcode が上がって赤から緑へ動くだけで毎日鳴ることになる
  echo "report: #$existing は既に $latest を知らせている — 追記しない"
  exit 0
fi

compose_followup >"$tmp"
if [ "$dry_run" = true ]; then
  printf 'report: --dry-run — #%s へ %s → %s を追記する形\n\n' "$existing" "$recorded" "$latest"
  cat "$tmp"
  exit 0
fi
gh issue comment "$existing" -R "$REPO" --body-file "$tmp" >/dev/null
echo "report: #$existing へ $recorded → $latest を追記した"
