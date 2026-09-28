#!/usr/bin/env python3
"""String Catalog（Localizable.xcstrings）とコードの文字列が食い違っていないかを確かめる。

    python3 scripts/check-strings.py --catalog <Localizable.xcstrings> --stringsdata-dir <Objects-normal>

make build が書き出した Debug の .stringsdata（コードの中の訳す文字列の一覧）を集め、使い捨てのコピーの
カタログに xcrun xcstringstool sync をかけて、次のどれかがあれば失敗する（make check-strings）。

- 足りないキー: コードで使っているのに、カタログに無い（Xcode で開くまで足されず、訳し漏れに気づけない）
- 使われていないキー: カタログにあるのに、コードで使っていない（直したつもりの訳が画面に出ない）
- en の無いキー: 英語の訳が無い（英語の画面に日本語がそのまま出る）
- 書式指定子の不一致: ja と en で %@ や %lld の数や種類が違う（落ちるか、別の値が出る）

コピーのファイル名は Localizable.xcstrings のままにする。表の名前（Localizable）はファイル名で決まり、
名前が違うと .stringsdata の文字列がすべて別の表のものとみなされるため。
診断画面（DEBUG と社内テスト用のビルドだけ）の文字列も数えるよう、Debug のビルドの .stringsdata を使う。

macOS のランナーに最初から入っている python3 で動くよう、標準ライブラリだけで書く。
"""

import argparse
import glob
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile

# printf の書式指定子（%@・%lld・%1$@ など）。「%%」は文字の % なので数えない。
SPECIFIER = re.compile(r"%(?:(\d+)\$)?[-+ 0#]*\d*(?:\.\d+)?(hh|h|ll|l|q|z|t|j|L)?([@dDiuUxXoOfFeEgGcCsSpaA])")


def specifiers(text):
    """文字列の中の書式指定子の種類を、並べ替えて返す（位置の指定 1$ は見ない。訳で語順が変わるため）。"""
    found = []
    for match in SPECIFIER.finditer(text.replace("%%", "")):
        length, conversion = match.group(2) or "", match.group(3)
        found.append(length + conversion)
    return sorted(found)


def string_values(localization, strict=True):
    """1 つの言語の訳の文字列を (文字列, 書式指定子をすべて含むべきか) の組ですべて返す（複数形などの分かれ道も）。

    複数形の「other」以外（英語の「one」など）は、数を書かずに「one day left」と訳してよいので、書式指定子が
    足りなくても食い違いとしない（多すぎるものだけ見る）。
    """
    values = []
    unit = localization.get("stringUnit")
    if unit and unit.get("value"):
        values.append((unit["value"], strict))
    for cases in localization.get("variations", {}).values():
        for name, case in cases.items():
            values.extend(string_values(case, strict and name == "other"))
    return values


def is_submultiset(part, whole):
    rest = list(whole)
    for item in part:
        if item not in rest:
            return False
        rest.remove(item)
    return True


def collect_stringsdata(directory):
    """ディレクトリの中の .stringsdata のうち、元のソースがまだあるものだけを返す。

    DerivedData を消さずにビルドし直すと、消したソースの .stringsdata が残り、使っていない文字列を
    使っているように見せるため、元のソースが無いものは除く。
    """
    paths = []
    for path in sorted(glob.glob(os.path.join(directory, "*", "*.stringsdata"))):
        try:
            with open(path, encoding="utf-8") as f:
                source = json.load(f).get("source", "")
        except (OSError, ValueError):
            continue
        if source and not os.path.exists(source):
            continue
        paths.append(path)
    return paths


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--catalog", required=True, help="確かめる Localizable.xcstrings")
    parser.add_argument("--stringsdata-dir", required=True, help="Debug のビルドの Objects-normal のディレクトリ")
    args = parser.parse_args()

    stringsdata = collect_stringsdata(args.stringsdata_dir)
    if not stringsdata:
        print(f"error: {args.stringsdata_dir} に .stringsdata がありません。先に make build を通してください。",
              file=sys.stderr)
        return 1

    with open(args.catalog, encoding="utf-8") as f:
        original = json.load(f)
    source_language = original.get("sourceLanguage", "ja")

    with tempfile.TemporaryDirectory() as work:
        # 表の名前はファイル名で決まるので、同じ名前のままコピーする。
        copy = os.path.join(work, os.path.basename(args.catalog))
        shutil.copyfile(args.catalog, copy)
        result = subprocess.run(
            ["xcrun", "xcstringstool", "sync", copy, "--stringsdata", *stringsdata],
            capture_output=True, text=True,
        )
        if result.returncode != 0:
            print(result.stdout + result.stderr, file=sys.stderr)
            print("error: xcstringstool sync に失敗しました。", file=sys.stderr)
            return 1
        with open(copy, encoding="utf-8") as f:
            synced = json.load(f)

    before = original.get("strings", {})
    after = synced.get("strings", {})
    problems = []

    for key in sorted(set(after) - set(before)):
        problems.append(f"足りないキー（コードで使っているがカタログに無い）: {key!r}")
    for key in sorted(before):
        entry = after.get(key)
        if entry is None or entry.get("extractionState") == "stale" or before[key].get("extractionState") == "stale":
            problems.append(f"使われていないキー（カタログにあるがコードで使っていない）: {key!r}")

    for key, entry in sorted(before.items()):
        if entry.get("shouldTranslate") is False:
            continue
        localizations = entry.get("localizations", {})
        english = string_values(localizations.get("en", {}))
        if not english:
            problems.append(f"en の訳が無いキー: {key!r}")
            continue
        # 開発言語の文は、訳を書いていなければキーそのもの。
        source = string_values(localizations.get(source_language, {})) or [(key, True)]
        expected = specifiers(key)
        for value, strict in source + english:
            found = specifiers(value)
            if found != expected if strict else not is_submultiset(found, expected):
                problems.append(
                    f"書式指定子が {source_language} と en で違うキー: {key!r}"
                    f"（{source_language}: {' '.join(expected) or 'なし'} / {value!r}: {' '.join(specifiers(value)) or 'なし'}）"
                )
                break

    if problems:
        print(f"error: {args.catalog} とコードの文字列が食い違っています（{len(problems)} 件）。", file=sys.stderr)
        for problem in problems:
            print(f"  - {problem}", file=sys.stderr)
        print("Xcode でカタログを開いて足りないキーを足し、使われていないキーを消し、en の訳を入れてください。",
              file=sys.stderr)
        return 1
    print(f"String Catalog の整合を確認しました（{len(before)} キー、.stringsdata {len(stringsdata)} 件）。")
    return 0


if __name__ == "__main__":
    sys.exit(main())
