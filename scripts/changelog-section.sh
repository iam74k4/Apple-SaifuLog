#!/bin/sh
# CHANGELOG.md から「## [X.Y.Z]」の節だけを取り出して標準出力に書く。
#
# 審査に出すときのリリースノート（release.yml）と、GitHub Release の本文
# （tag-release.yml）の両方で使う。二か所で別々に書くと、片方だけ直したときに食い違う。
#
#   ./scripts/changelog-section.sh 0.1.0                 GitHub Release 用（Markdown のまま）
#   ./scripts/changelog-section.sh --plain 0.1.0         App Store 用（Markdown の記号を外す）
#   ./scripts/changelog-section.sh 0.1.0 path/to/CHANGELOG.md
#
# --plain を分けているのは、App Store の「このバージョンでの変更点」が Markdown を
# 表示しないため。「### 追加」や「**太字**」の記号がそのまま利用者に見えてしまう。
# 箇条書きの「- 」は平文でも読めるので残す。
#
# ubuntu のランナー（mawk / GNU sed）と macOS（BSD awk / BSD sed）の両方で動くよう、
# POSIX sh と、両者に共通する awk / sed の書き方だけを使う。

set -eu

plain=0
if [ "${1:-}" = "--plain" ]; then
  plain=1
  shift
fi

version="${1:?usage: changelog-section.sh [--plain] <version> [changelog]}"
changelog="${2:-CHANGELOG.md}"

if [ ! -f "$changelog" ]; then
  echo "error: $changelog がありません。" >&2
  exit 1
fi

# 節を取り出す。
extract() {
  awk -v ver="$version" '
    # 目的の見出しに入ったら拾い始める。見出しそのもの（日付を含む）は要らない。
    # 版の中の「.」は正規表現だと任意の 1 文字になるので、文字どおりに比べる。
    index($0, "## [" ver "]") == 1 { found = 1; next }
    # 次の見出しで止める。
    /^## \[/ { found = 0 }
    # 末尾のリンク定義（[x]: url）は節の中身ではないので、そこでも止める。
    /^\[[^]]*\]: / { found = 0 }
    found
  ' "$changelog"
}

# App Store 向けに Markdown の記号を外す。CHANGELOG の書き方の約束（太字・リンク・
# バッククォートを使わない）を破っても、利用者に記号が見えないようにする保険。
to_plain() {
  sed -E \
    -e 's/^#{3,}[[:space:]]+//' \
    -e 's/\*\*//g' \
    -e 's/`//g' \
    -e 's/\[([^]]*)\]\([^)]*\)/\1/g'
}

extract |
  if [ "$plain" -eq 1 ]; then to_plain; else cat; fi |
  # 前後の空行を落とす。App Store のリリースノートは空行から始まると不格好。
  sed -e '/./,$!d' |
  awk '
    { lines[NR] = $0 }
    END {
      last = NR
      while (last > 0 && lines[last] ~ /^[[:space:]]*$/) last--
      for (i = 1; i <= last; i++) print lines[i]
    }
  '
