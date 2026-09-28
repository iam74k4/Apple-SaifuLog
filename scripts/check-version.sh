#!/bin/sh
# アプリのバージョン（Config/Base.xcconfig の MARKETING_VERSION）を扱う。
#
#   ./scripts/check-version.sh            CHANGELOG.md の先頭の ## [X.Y.Z] と一致するか確かめる
#   ./scripts/check-version.sh --print    MARKETING_VERSION だけを標準出力に書く
#
#   --xcconfig <path>   読む xcconfig（既定: Config/Base.xcconfig）
#   --changelog <path>  読む CHANGELOG（既定: CHANGELOG.md）
#
# バージョンの正は xcconfig の 1 か所だけにしている。CI（build.yml）、提出（release.yml）、
# タグ打ち（tag-release.yml）、make version がすべてここを通るので、読み方が 1 つに揃う。
# 各所で別々に grep すると、書式を少し変えたときに片方だけ読めなくなる。
#
# 一致を確かめるのは、CHANGELOG の節がそのまま App Store のリリースノートと
# GitHub Release の本文になるため。ずれたまま提出すると、別の版のノートが載る。
#
# ubuntu のランナー（tag-release.yml）でも動くよう、POSIX sh と sed / grep だけで書く。

set -eu

root=$(cd "$(dirname "$0")/.." && pwd)
xcconfig="$root/Config/Base.xcconfig"
changelog="$root/CHANGELOG.md"
mode=check

usage() {
  echo "usage: check-version.sh [--print] [--xcconfig <path>] [--changelog <path>]" >&2
  exit 2
}

while [ $# -gt 0 ]; do
  case "$1" in
    --print) mode=print ;;
    --xcconfig) [ $# -ge 2 ] || usage; xcconfig=$2; shift ;;
    --changelog) [ $# -ge 2 ] || usage; changelog=$2; shift ;;
    -h | --help) usage ;;
    *) usage ;;
  esac
  shift
done

# メッセージの中のパスはリポジトリからの相対にする。CI のランナーでは絶対パスが
# 長く、肝心のファイル名が読みにくい。
rel() {
  case "$1" in
    "$root"/*) printf '%s' "${1#"$root"/}" ;;
    *) printf '%s' "$1" ;;
  esac
}

# GitHub Actions では注釈（::error::）にすると、ログを開かなくても
# PR の画面に理由が出る。手元ではふつうのエラー表示にする。
err() {
  if [ "${GITHUB_ACTIONS:-}" = "true" ]; then
    echo "::error title=check-version::$1"
  else
    echo "error: $1" >&2
  fi
}

if [ ! -f "$xcconfig" ]; then
  err "$(rel "$xcconfig") がありません。"
  exit 1
fi

# 「MARKETING_VERSION = 0.1.0 // コメント」の形から値だけを取り出す。
# 条件付きの MARKETING_VERSION[sdk=...] は対象外（使わない前提）。
defs=$(sed -n 's/^[[:space:]]*MARKETING_VERSION[[:space:]]*=[[:space:]]*\([^[:space:]/;]*\).*/\1/p' "$xcconfig")
count=$(printf '%s\n' "$defs" | grep -c . || true)

if [ "$count" -eq 0 ]; then
  err "$(rel "$xcconfig") に MARKETING_VERSION がありません。"
  exit 1
fi
# xcconfig は後の行が前の行を上書きする。2 つあると、人が読む値と
# Xcode が使う値が食い違いやすいので、1 つにさせる。
if [ "$count" -gt 1 ]; then
  err "$(rel "$xcconfig") に MARKETING_VERSION が $count 個あります。1 つにしてください。"
  exit 1
fi

version=$defs

# App Store は「ピリオドで区切った 3 つまでの整数」しか受け付けない。
# $(VAR) の参照などが入っていると、ここで読めてもアップロードで弾かれる。
if ! printf '%s\n' "$version" | grep -Eq '^[0-9]+(\.[0-9]+){0,2}$'; then
  err "MARKETING_VERSION の値「${version}」は X.Y.Z の形ではありません。"
  exit 1
fi

if [ "$mode" = print ]; then
  printf '%s\n' "$version"
  exit 0
fi

if [ ! -f "$changelog" ]; then
  err "$(rel "$changelog") がありません。"
  exit 1
fi

# 数字で始まる最初の見出しを拾う。先頭の「## [未リリース]」は版ではないので飛ばす。
latest=$(grep -m1 -o '^## \[[0-9][^]]*\]' "$changelog" | sed 's/^## \[//; s/\]$//' || true)

echo "MARKETING_VERSION: $version"
echo "CHANGELOG:         ${latest:-（見出しなし）}"

if [ -z "$latest" ]; then
  err "$(rel "$changelog") にバージョンの見出し（## [X.Y.Z]）がありません。"
  exit 1
fi
if [ "$version" != "$latest" ]; then
  err "バージョンが食い違っています（MARKETING_VERSION=$version / CHANGELOG=${latest}）。Config/Base.xcconfig か CHANGELOG.md の先頭の見出しを合わせてください。"
  exit 1
fi

echo "OK: バージョンは一致しています。"
