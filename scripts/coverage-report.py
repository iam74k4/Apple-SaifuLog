#!/usr/bin/env python3
"""テストのカバレッジを Markdown の表にする（make coverage-report）。

    python3 scripts/coverage-report.py --core-json <swift test のカバレッジの JSON> \
        --xcresult "アプリのテスト=build/TestResults/app-tests.xcresult" \
        --xcresult "UI テスト=build/TestResults/ui-tests.xcresult"

テストを COVERAGE=YES で動かした後に使う（Makefile）。結果ごとに、行の割合の合計と、置き場所（SaifuLog/・SaifuLogWidgets/・
コア）ごとの割合と、割合の低いファイルを並べる。テストのファイル自身は数えない。合否には使わない（テストの無いところを
見つけるための数字）ので、結果が無い・読めないときも、そのことを書いて 0 で終わる。

- コアのテスト: swift test --enable-code-coverage が書き出す JSON（llvm-cov export の形）。
- アプリのテストと UI テスト: xcodebuild -enableCodeCoverage YES の .xcresult を `xcrun xccov view --report --json` で読む。
  ウィジェットの拡張のソースは、ウィジェットのテスト（SaifuLogWidgetsTests）のバンドルに入れて動かすので、そのターゲットの
  中に出る。同じファイルがいくつかのターゲットに出るとき（アプリと拡張の両方に入れるファイル）は、割合の高い方を使う。

macOS のランナーに最初から入っている python3 で動くよう、標準ライブラリだけで書く。
"""

import argparse
import json
import os
import subprocess
import sys

# テストのファイル（数えない）。
TEST_DIRECTORIES = ("SaifuLogTests/", "SaifuLogUITests/", "SaifuLogWidgetsTests/", "Tests/")
# 置き場所の見出し（上から順に当てる）。
GROUPS = (
    ("Packages/SaifuLogCore/Sources/", "コア（Packages/SaifuLogCore）"),
    ("SaifuLogWidgets/", "ウィジェットの拡張（SaifuLogWidgets）"),
    ("SaifuLog/", "アプリ（SaifuLog）"),
)
# 割合の低いファイルとして並べる数と、並べるファイルの行の下限（数行だけのファイルは割合が揺れるので並べない）。
LOWEST = 15
MIN_LINES = 10


def relative(path):
    root = os.getcwd().rstrip("/") + "/"
    return path[len(root):] if path.startswith(root) else path


def is_test_file(path):
    return any(part in path for part in TEST_DIRECTORIES) or "/.build/" in path or "/DerivedData/" in path


def group_of(path):
    for prefix, title in GROUPS:
        if path.startswith(prefix):
            return title
    return None


def percent(covered, total):
    return f"{covered / total * 100:.1f}%" if total else "—"


def table(title, files):
    """files: {相対パス: (覆った行, 行)}。"""
    lines = [f"### {title}", ""]
    if not files:
        lines += ["数えるファイルがありません。", ""]
        return "\n".join(lines)
    covered = sum(c for c, _ in files.values())
    total = sum(t for _, t in files.values())
    lines += [f"合計: **{percent(covered, total)}**（{covered:,} / {total:,} 行）", ""]

    groups = {}
    for path, (c, t) in files.items():
        name = group_of(path) or "そのほか"
        gc, gt = groups.get(name, (0, 0))
        groups[name] = (gc + c, gt + t)
    lines += ["| 置き場所 | 割合 | 行 |", "|---|---:|---:|"]
    for name, (c, t) in sorted(groups.items(), key=lambda item: item[0]):
        lines.append(f"| {name} | {percent(c, t)} | {c:,} / {t:,} |")
    lines.append("")

    lowest = sorted(
        ((c / t, path, c, t) for path, (c, t) in files.items() if t >= MIN_LINES),
        key=lambda item: (item[0], -item[3]),
    )[:LOWEST]
    if lowest:
        lines += [f"割合の低いファイル（{MIN_LINES} 行以上）:", "", "| ファイル | 割合 | 行 |", "|---|---:|---:|"]
        for _, path, c, t in lowest:
            lines.append(f"| `{path}` | {percent(c, t)} | {c:,} / {t:,} |")
        lines.append("")
    return "\n".join(lines)


def core_files(path):
    """swift test の JSON（llvm-cov export）から、コアのソースのファイルごとの行を読む。"""
    with open(path, encoding="utf-8") as f:
        data = json.load(f)
    files = {}
    for export in data.get("data", []):
        for item in export.get("files", []):
            name = relative(item.get("filename", ""))
            if "Packages/SaifuLogCore/Sources/" not in name or is_test_file(name):
                continue
            lines = item.get("summary", {}).get("lines", {})
            total = lines.get("count", 0)
            if total:
                files[name[name.index("Packages/"):]] = (lines.get("covered", 0), total)
    return files


def xcresult_files(path):
    """.xcresult のカバレッジから、テストでないソースのファイルごとの行を読む（同じファイルは割合の高い方）。"""
    result = subprocess.run(
        ["xcrun", "xccov", "view", "--report", "--json", path], capture_output=True, text=True
    )
    if result.returncode != 0:
        raise RuntimeError(result.stderr.strip() or "xccov が失敗しました")
    data = json.loads(result.stdout)
    files = {}
    for target in data.get("targets", []):
        for item in target.get("files", []):
            name = relative(item.get("path", ""))
            total = item.get("executableLines", 0)
            if not total or is_test_file(name):
                continue
            covered = item.get("coveredLines", 0)
            if name not in files or covered / total > files[name][0] / files[name][1]:
                files[name] = (covered, total)
    return files


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--core-json", help="swift test --enable-code-coverage の JSON（swift test --show-codecov-path）")
    parser.add_argument("--xcresult", action="append", default=[], help="「見出し=パス」の形の .xcresult（いくつでも）")
    args = parser.parse_args()

    sections = ["## テストのカバレッジ", "", "テストの無いところを見つけるための数字（合否には使わない）。", ""]

    if args.core_json:
        title = "コアのテスト（swift test）"
        if os.path.exists(args.core_json):
            try:
                sections.append(table(title, core_files(args.core_json)))
            except (OSError, ValueError) as error:
                sections += [f"### {title}", "", f"読めません: {error}", ""]
        else:
            sections += [f"### {title}", "", f"結果がありません（{args.core_json}）。COVERAGE=YES で make test を動かしてください。", ""]

    for spec in args.xcresult:
        title, _, path = spec.partition("=")
        if not path:
            title, path = spec, spec
        if not os.path.exists(path):
            sections += [f"### {title}", "", f"結果がありません（{path}）。テストが途中で止まったか、COVERAGE=YES で動かしていません。", ""]
            continue
        try:
            sections.append(table(title, xcresult_files(path)))
        except (OSError, ValueError, RuntimeError) as error:
            sections += [f"### {title}", "", f"読めません: {error}", ""]

    print("\n".join(sections))
    return 0


if __name__ == "__main__":
    sys.exit(main())
