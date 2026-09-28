#!/usr/bin/env python3
"""App Store Connect API を CI から叩くための小さな道具（iOS 版）。

main へマージしたあとの「アップロード → 処理待ち → 審査提出 → 配信確認」を
人手を挟まずに進めるために使う。fastlane を丸ごと持ち込むほどの量ではないので、
必要な操作だけを置く。

    wait-build     アップロードしたビルドの処理が終わるのを待つ
    submit         バージョンにビルドを紐づけ、リリースノートを入れて審査に出す
    state          いま App Store 側がそのバージョンをどう扱っているかを表示する
    version-info   配信中（または指定した）版の版番号・状態・紐づいたビルド番号を表示する

認証は App Store Connect API キー（.p8）。次の環境変数を読む。

    ASC_API_KEY_ID      キー ID
    ASC_API_ISSUER_ID   Issuer ID
    ASC_API_KEY_P8      .p8 の中身そのもの（CI はこちら）
    ASC_API_KEY_PATH    .p8 のパス（ASC_API_KEY_P8 が無いときに読む。release.mk と共通）
    ASC_BUNDLE_ID       対象アプリのバンドル ID（--bundle-id でも渡せる）

依存は PyJWT（と cryptography）だけ。HTTP は標準ライブラリで足りる。
CI は scripts/requirements.txt（版とハッシュで固定）から入れる。
"""

import argparse
import http.client
import json
import os
import re
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

BASE = "https://api.appstoreconnect.apple.com"
PLATFORM = "IOS"

# 配信が始まった状態。ここに来たらタグを打ってよい。
# appVersionState では READY_FOR_DISTRIBUTION、旧 appStoreState では READY_FOR_SALE。
LIVE_STATES = {"READY_FOR_SALE", "READY_FOR_DISTRIBUTION"}
# 審査に出してから配信が始まるまでの、進行中の状態。App Store Connect は進行中の版を
# 1 つしか持てないので、この状態の版があるあいだは新しい版を作れない（POST は 409）。
IN_FLIGHT_STATES = {
    "WAITING_FOR_REVIEW",
    "IN_REVIEW",
    "WAITING_FOR_EXPORT_COMPLIANCE",
    "PENDING_CONTRACT",
    "ACCEPTED",
    "PENDING_APPLE_RELEASE",
    "PENDING_DEVELOPER_RELEASE",
    "PROCESSING_FOR_DISTRIBUTION",
    "PROCESSING_FOR_APP_STORE",
}
# 承認済み以降の状態。この版にはもう新しいビルドを送れない（Apple がアップロードを弾く）。
# release.yml は、タグが付く前（承認から tag-release が気づくまで）にこの状態の版を
# 見つけたら、アップロードせずに終える。
CLOSED_STATES = LIVE_STATES | {
    "ACCEPTED",
    "PENDING_APPLE_RELEASE",
    "PENDING_DEVELOPER_RELEASE",
    "PROCESSING_FOR_DISTRIBUTION",
    "PROCESSING_FOR_APP_STORE",
    "PREORDER_READY_FOR_SALE",
    "REPLACED_WITH_NEW_VERSION",
    "DEVELOPER_REMOVED_FROM_SALE",
    "REMOVED_FROM_SALE",
}
# 人が App Store Connect で操作しないと先に進まない状態。待っても変わらない。
STUCK_STATES = {
    "DEVELOPER_REJECTED",
    "REJECTED",
    "METADATA_REJECTED",
    "INVALID_BINARY",
    "DEVELOPER_REMOVED_FROM_SALE",
}
# ビルドの差し替えや版の書き換えができる状態。これ以外（審査待ち・審査中・
# 配信待ちなど）で触ると Apple は 409 を返すだけで、理由が分かりにくい。
# READY_FOR_REVIEW は「提出の入れ物に入ったが、まだ提出していない」状態で、前回の
# ジョブが提出の手前で落ちたときに残る。
EDITABLE_STATES = {
    "PREPARE_FOR_SUBMISSION",
    "READY_FOR_REVIEW",
    "DEVELOPER_REJECTED",
    "REJECTED",
    "METADATA_REJECTED",
    "INVALID_BINARY",
}

# App Store Connect の版番号とビルド番号の形（ピリオドで区切った 3 つまでの整数）。
NUMBER_PATTERN = re.compile(r"[0-9]+(\.[0-9]+){0,2}")

# 引数 --bundle-id か環境変数 ASC_BUNDLE_ID から main() で埋める。
BUNDLE_ID = None


def log(message):
    # 進捗は stderr へ出す。stdout は呼び出し側が値として読むため混ぜない。
    print(message, file=sys.stderr, flush=True)


def die(message):
    log(f"error: {message}")
    sys.exit(1)


# --- API ------------------------------------------------------------------


def private_key():
    """CI は Secret の中身をそのまま渡し、手元はファイルのパスを渡す。

    どちらでも動くようにしておくと、release.mk（xcodebuild はパスしか受け付けない）と
    同じ環境変数で手元から試せる。
    """
    inline = os.environ.get("ASC_API_KEY_P8")
    if inline:
        return inline
    path = os.environ.get("ASC_API_KEY_PATH")
    if path:
        try:
            with open(path, encoding="utf-8") as handle:
                return handle.read()
        except OSError as error:
            die(f"ASC_API_KEY_PATH の .p8 を読めません: {error}")
    return None


def token():
    """15 分で切れる ES256 の JWT を作る。

    Apple は有効期間が 20 分より長いものを拒む。ちょうど 20 分にすると、ランナーの時計が
    Apple より少し遅れているだけで「長すぎる」とみなされて 401 になるので、余裕を持たせる。
    iat を 1 分前にするのも同じ理由（時計が進んでいると「未来に発行された」扱いになる）。
    """
    # import をここまで遅らせるのは、PyJWT の無い手元でも --help や引数の確認が
    # できるようにするため。
    try:
        import jwt
    except ImportError:
        die("PyJWT が要ります: pip install --require-hashes -r scripts/requirements.txt")
    key_id = os.environ.get("ASC_API_KEY_ID")
    issuer = os.environ.get("ASC_API_ISSUER_ID")
    key = private_key()
    if not (key_id and issuer and key):
        die(
            "ASC_API_KEY_ID / ASC_API_ISSUER_ID と、"
            "ASC_API_KEY_P8（または ASC_API_KEY_PATH）が要ります。"
        )
    now = int(time.time())
    return jwt.encode(
        {"iss": issuer, "iat": now - 60, "exp": now + 15 * 60, "aud": "appstoreconnect-v1"},
        key,
        algorithm="ES256",
        headers={"kid": key_id, "typ": "JWT"},
    )


def api(method, path, body=None, params=None, attempts=4):
    """API を 1 回呼ぶ。一時的な失敗だけは少し待って呼び直す。

    wait-build は 1 時間近く API を叩き続けるので、途中で 1 回 500 や通信断が
    挟まっただけでジョブ全体が落ちると、やり直しのたびに待ち時間を捨てることになる。
    呼び直すのは「Apple 側で処理されていないと分かっている」ものに限る。
    429（混雑）はどのメソッドでも処理前に弾かれている。5xx と通信断は GET だけにする。
    POST を呼び直すと、提出の入れ物などが二重にできうるため。
    GET の 401 も 1 回だけ呼び直す。時計のずれなどで JWT が一度だけ弾かれることがあり、
    トークンは呼ぶたびに作り直すので、2 回目は通りうる。続けて 401 なら鍵の設定の誤り。
    """
    url = BASE + path
    if params:
        url += "?" + urllib.parse.urlencode(params)
    data = json.dumps(body).encode() if body is not None else None

    for attempt in range(1, attempts + 1):
        # JWT は 20 分で切れるので、呼ぶたびに作り直す。
        request = urllib.request.Request(url, data=data, method=method)
        request.add_header("Authorization", f"Bearer {token()}")
        request.add_header("Content-Type", "application/json")
        try:
            with urllib.request.urlopen(request, timeout=60) as response:
                raw = response.read()
                return json.loads(raw) if raw else {}
        except urllib.error.HTTPError as error:
            # Apple のエラーは本文にしか理由が書かれていない。捨てると原因が追えない。
            detail = error.read().decode(errors="replace")
            retryable = error.code == 429 or (
                method == "GET"
                and (error.code >= 500 or (error.code == 401 and attempt == 1))
            )
            if not retryable or attempt == attempts:
                raise ApiError(error.code, detail) from None
            log(f"HTTP {error.code}。{attempt * 15} 秒待って呼び直します（{method} {path}）。")
        # urllib が URLError に包むのは、リクエストを送る段階の失敗だけ。応答を待つ・読む段階
        # （getresponse / read）で接続を切られたときの RemoteDisconnected・ConnectionResetError・
        # IncompleteRead は包まれずにそのまま上がってくるので、ここで一緒に拾う。拾わないと、
        # wait-build が 1 時間近く待った末に、1 回の通信断でトレースバックを出して落ちる。
        # HTTPError は URLError の子なので、上の節を先に置いたままにする。
        except (
            urllib.error.URLError,
            http.client.HTTPException,
            ConnectionError,
            TimeoutError,
        ) as error:
            if method != "GET" or attempt == attempts:
                die(f"App Store Connect に繋がりません（{method} {path}）: {error}")
            log(f"通信に失敗しました（{error}）。{attempt * 15} 秒待って呼び直します。")
        time.sleep(attempt * 15)


class ApiError(Exception):
    def __init__(self, status, detail):
        super().__init__(f"HTTP {status}:\n{describe_errors(detail)}")
        self.status = status
        self.detail = detail


def describe_errors(detail):
    """Apple のエラー本文（JSON）を、人が読める行に直す。

    本当の理由は errors[].detail と、提出の段階では meta.associatedErrors（スクリーンショットや
    説明文の不足など、版にぶら下がる項目ごとのエラー）にしか書かれていない。JSON のまま
    1 行でログに出すと埋もれるので、1 件ずつ行に分ける。読めない形ならそのまま返す。
    """
    try:
        errors = json.loads(detail).get("errors") or []
    except (ValueError, AttributeError):
        return detail
    if not errors:
        return detail
    lines = []

    def add(error, indent):
        code = error.get("code", "")
        text = error.get("detail") or error.get("title") or ""
        pointer = (error.get("source") or {}).get("pointer")
        where = f"（{pointer}）" if pointer else ""
        lines.append(f"{indent}- {code}: {text}{where}")

    for error in errors:
        add(error, "")
        associated = (error.get("meta") or {}).get("associatedErrors") or {}
        for target, children in associated.items():
            lines.append(f"    {target}")
            for child in children:
                add(child, "      ")
    return "\n".join(lines)


def app_id():
    if not BUNDLE_ID:
        die("バンドル ID が要ります（--bundle-id か ASC_BUNDLE_ID）。")
    found = api("GET", "/v1/apps", params={"filter[bundleId]": BUNDLE_ID})["data"]
    if not found:
        die(
            f"バンドル ID {BUNDLE_ID} のアプリが見つかりません。"
            "App Store Connect にアプリレコードを作ってください（docs/release-flow.md）。"
        )
    return found[0]["id"]


# --- wait-build -----------------------------------------------------------


def find_build(app, build_number, version):
    """アップロードしたビルドを探す。

    ASC では builds.version が CFBundleVersion（ビルド番号）で、
    preReleaseVersion.version が表示用バージョン。名前が紛らわしいので注意。

    必ず両方で絞る。ビルド番号だけで探すと、同じ番号を持つ別バージョンの
    古いビルド（例: 1.0 (101) と 1.0.1 (101)）を掴んでしまい、
    紐づけた版が INVALID_BINARY になる。将来 Mac 版などを同じアプリレコードに
    足したときに取り違えないよう、プラットフォームでも絞る。
    処理中のビルドがまだ一覧に出ていない間は None を返し、呼び出し側が待つ。
    """
    found = api(
        "GET",
        "/v1/builds",
        params={
            "filter[app]": app,
            "filter[version]": build_number,
            "filter[preReleaseVersion.version]": version,
            "filter[preReleaseVersion.platform]": PLATFORM,
            "sort": "-uploadedDate",
            "limit": 1,
        },
    )["data"]
    return found[0] if found else None


def cmd_wait_build(args):
    app = app_id()
    deadline = time.time() + args.timeout
    while True:
        build = find_build(app, args.build, args.version)
        if build is None:
            log(f"ビルド {args.version} ({args.build}) はまだ現れていません。")
        else:
            attributes = build["attributes"]
            state = attributes.get("processingState")
            log(f"processingState: {state}")
            if state == "VALID":
                # 輸出コンプライアンス（暗号の使用）が未回答だと、審査に出す段階で
                # 分かりにくい 409 になる。Info.plist の ITSAppUsesNonExemptEncryption で
                # 答えておけば、ここは自動で false になる。
                # ここで代わりに false と回答（PATCH）することもできるが、これは法的な
                # 申告なので、スクリプトが黙って答えるのではなく、リポジトリの
                # Info.plist に宣言として残す形にしている。
                if attributes.get("usesNonExemptEncryption") is None:
                    die(
                        "このビルドは輸出コンプライアンス（暗号の使用）が未回答です。"
                        "アプリの Info.plist に ITSAppUsesNonExemptEncryption = NO を入れる"
                        "（project.yml で設定する）か、App Store Connect の TestFlight で"
                        "このビルドに回答してから、失敗した submit ジョブを再実行してください。"
                    )
                print(build["id"])
                return
            if state in ("INVALID", "FAILED"):
                die(
                    f"ビルドの処理が {state} で終わりました。"
                    "App Store Connect か、Apple からのメールに理由が出ています。"
                )
        if time.time() >= deadline:
            die(
                f"{args.timeout} 秒待ちましたが処理が終わりませんでした。"
                "アップロード自体は終わっているので、App Store Connect で"
                "処理の終了を確認してから、失敗した submit ジョブだけを"
                "再実行してください（Re-run failed jobs）。"
            )
        time.sleep(args.interval)


# --- submit ---------------------------------------------------------------


def version_state(version):
    """appStoreState は 3.3 で非推奨。新しい appVersionState を先に見る。"""
    attributes = version["attributes"]
    return attributes.get("appVersionState") or attributes.get("appStoreState")


def find_version(app, version_string):
    found = api(
        "GET",
        f"/v1/apps/{app}/appStoreVersions",
        params={
            "filter[versionString]": version_string,
            "filter[platform]": PLATFORM,
            "limit": 1,
        },
    )["data"]
    return found[0] if found else None


def list_versions(app):
    """版番号を問わず、このアプリの iOS の版を並べる。

    状態での絞り込みは呼び出し側で行う（API 側のフィルタの対応状況に左右されない
    ようにするため）。
    """
    return api(
        "GET",
        f"/v1/apps/{app}/appStoreVersions",
        params={"filter[platform]": PLATFORM, "limit": 50},
    )["data"]


def first_in_states(versions, states):
    for version in versions:
        if version_state(version) in states:
            return version
    return None


def ensure_editable(version, version_string):
    state = version_state(version)
    if state in LIVE_STATES:
        die(
            f"{version_string} は既に配信済み（{state}）です。"
            "Config/Base.xcconfig の MARKETING_VERSION を上げてください。"
        )
    if state not in EDITABLE_STATES:
        # 審査中に main へ別の変更を入れると、ここに来る。審査中の版のビルドは
        # 差し替えられないので、黙って続けず、人に判断させる。
        die(
            f"{version_string} は {state} のため、ビルドを差し替えられません。"
            "審査中の版を差し替えたいときは、App Store Connect で審査から取り下げてから"
            "このジョブを再実行してください。差し替え不要なら、このままで構いません"
            "（アップロードしたビルドは TestFlight に残るだけです）。"
        )
    return state


def find_or_create_version(app, version_string, release_type):
    version = find_version(app, version_string)
    if version is not None:
        state = ensure_editable(version, version_string)
        log(f"既存のバージョン {version_string} を使います（{state}）。")
        # リジェクト後の出し直しの前に ASC_RELEASE_TYPE を MANUAL へ変えても、作った時点の
        # releaseType のままだと、承認と同時に配信が始まってしまう。既存の版でも揃える
        # （ensure_editable を通ったので、編集できる状態にある）。
        current = version["attributes"].get("releaseType")
        if current != release_type:
            log(f"releaseType を {current} から {release_type} に変えます。")
            api(
                "PATCH",
                f"/v1/appStoreVersions/{version['id']}",
                body={
                    "data": {
                        "type": "appStoreVersions",
                        "id": version["id"],
                        "attributes": {"releaseType": release_type},
                    }
                },
            )
        return version["id"]

    versions = list_versions(app)
    # iOS はアプリレコードを作った時点で「1.0（提出準備中）」が自動でできる。
    # また App Store Connect は編集中の版を 1 つしか持てないため、それが残っていると
    # 新しい版の POST は失敗する。
    editable = first_in_states(versions, EDITABLE_STATES)
    if editable is not None:
        # 自動でできた 1.0 や、前の版の作りかけが残っている。新しく作ろうとすると
        # 失敗するので、その版の番号を書き換えて使う。
        old = editable["attributes"].get("versionString")
        log(
            f"編集中の版 {old}（{version_state(editable)}）を"
            f" {version_string} に書き換えて使います。"
        )
        api(
            "PATCH",
            f"/v1/appStoreVersions/{editable['id']}",
            body={
                "data": {
                    "type": "appStoreVersions",
                    "id": editable["id"],
                    "attributes": {
                        "versionString": version_string,
                        "releaseType": release_type,
                    },
                }
            },
        )
        return editable["id"]

    # 前の版の審査中に版を上げて main へマージすると、ここに来る。進行中の版があるあいだは
    # 新しい版を作れず、POST は理由の分かりにくい 409 で落ちるので、先に止めて次の手を示す。
    in_flight = first_in_states(versions, IN_FLIGHT_STATES)
    if in_flight is not None:
        old = in_flight["attributes"].get("versionString")
        die(
            f"前の版 {old} が {version_state(in_flight)} のため、{version_string} の版を作れません"
            "（App Store Connect は進行中の版を 1 つしか持てません）。"
            f"{old} の配信が始まるか、リジェクトされる（または審査から取り下げる）のを待ってから、"
            "失敗した submit ジョブを再実行してください（Re-run failed jobs）。"
            "アップロードしたビルドは TestFlight に残っているので、アップロードからやり直す必要はありません。"
            f"{old} のタグと GitHub Release は、配信が始まれば tag-release が付けます。"
        )

    log(f"バージョン {version_string} を作ります（releaseType={release_type}）。")
    created = api(
        "POST",
        "/v1/appStoreVersions",
        body={
            "data": {
                "type": "appStoreVersions",
                "attributes": {
                    "platform": PLATFORM,
                    "versionString": version_string,
                    "releaseType": release_type,
                },
                "relationships": {"app": {"data": {"type": "apps", "id": app}}},
            }
        },
    )
    return created["data"]["id"]


def set_whats_new(version_id, notes):
    """「このバージョンでの変更点」を全ロケール（ja / en）に入れる。

    CHANGELOG は日本語だけなので、en にも日本語が入る。アップデートの版では
    全ロケールでこの欄が必須で、空のままだと提出で弾かれるため、空よりはよいと
    割り切っている（英語のノートを持つ案は docs/release-flow.md の「この先やれること」）。

    アプリの最初のバージョンには変更点の欄が無く、Apple は 409 を返す。
    それは失敗ではないので警告にとどめる。
    """
    localizations = api(
        "GET", f"/v1/appStoreVersions/{version_id}/appStoreVersionLocalizations"
    )["data"]
    for localization in localizations:
        locale = localization["attributes"].get("locale")
        try:
            api(
                "PATCH",
                f"/v1/appStoreVersionLocalizations/{localization['id']}",
                body={
                    "data": {
                        "type": "appStoreVersionLocalizations",
                        "id": localization["id"],
                        "attributes": {"whatsNew": notes},
                    }
                },
            )
            log(f"リリースノートを入れました（{locale}）。")
        except ApiError as error:
            log(f"warning: {locale} のリリースノートを入れられませんでした: {error}")


def attach_build(version_id, build_id):
    api(
        "PATCH",
        f"/v1/appStoreVersions/{version_id}",
        body={
            "data": {
                "type": "appStoreVersions",
                "id": version_id,
                "relationships": {"build": {"data": {"type": "builds", "id": build_id}}},
            }
        },
    )
    log("ビルドをバージョンに紐づけました。")


def submit_for_review(app, version_id):
    """審査に出す。

    提出は 3 手に分かれている。提出物の入れ物（reviewSubmissions）を作り、
    そこにバージョンを入れ（reviewSubmissionItems）、最後に submitted=true にする。
    最後の一手を忘れると「作ったのに出ていない」状態になる。

    入れ物は 1 つのアプリ・プラットフォームにつき同時に 1 つしか開けない。
    前回のジョブが提出の手前で落ちたとき（READY_FOR_REVIEW）と、リジェクトされた
    入れ物（UNRESOLVED_ISSUES）が残っているときは、新しく作ると 409 になるので
    それを使い回す。リジェクト後の出し直しをこの経路で通したことはまだ無い
    （docs/release-flow.md の「リジェクトされたら」）。
    """
    existing = api(
        "GET",
        "/v1/reviewSubmissions",
        params={
            "filter[app]": app,
            "filter[platform]": PLATFORM,
            "filter[state]": "READY_FOR_REVIEW,UNRESOLVED_ISSUES",
            "limit": 1,
        },
    )["data"]
    if existing:
        submission_id = existing[0]["id"]
        state = existing[0]["attributes"].get("state")
        log(f"開いている入れ物（{state}）が残っていたので、それを使います。")
    else:
        submission_id = api(
            "POST",
            "/v1/reviewSubmissions",
            body={
                "data": {
                    "type": "reviewSubmissions",
                    "attributes": {"platform": PLATFORM},
                    "relationships": {"app": {"data": {"type": "apps", "id": app}}},
                }
            },
        )["data"]["id"]

    try:
        api(
            "POST",
            "/v1/reviewSubmissionItems",
            body={
                "data": {
                    "type": "reviewSubmissionItems",
                    "relationships": {
                        "reviewSubmission": {
                            "data": {"type": "reviewSubmissions", "id": submission_id}
                        },
                        "appStoreVersion": {
                            "data": {"type": "appStoreVersions", "id": version_id}
                        },
                    },
                }
            },
        )
    except ApiError as error:
        # 409 は「同じ版が既に入っている」とは限らない。スクリーンショットや説明文の不足など、
        # 提出に要るものが欠けているときも 409 で、本当の理由は本文にしか無い。理由を必ず
        # ログに出し、入れ物の中身を見て、この版が本当に入っているときだけ提出へ進む。
        if error.status != 409:
            raise
        log(f"入れ物にバージョンを入れられませんでした（HTTP 409）:\n{describe_errors(error.detail)}")
        if not submission_contains(submission_id, version_id):
            die(
                "入れ物にこのバージョンが入っていません。上の理由（App Store Connect の"
                "バージョンのページにも出ます）を解消してから、失敗した submit ジョブを"
                "再実行してください（Re-run failed jobs）。"
            )
        log("このバージョンは既に入れ物の中にありました。提出へ進みます。")

    api(
        "PATCH",
        f"/v1/reviewSubmissions/{submission_id}",
        body={
            "data": {
                "type": "reviewSubmissions",
                "id": submission_id,
                "attributes": {"submitted": True},
            }
        },
    )
    log("審査に提出しました。")


def submission_contains(submission_id, version_id):
    """提出の入れ物に、その版が既に入っているか。"""
    items = api(
        "GET",
        f"/v1/reviewSubmissions/{submission_id}/items",
        params={"include": "appStoreVersion", "limit": 200},
    )["data"]
    for item in items:
        related = (item.get("relationships") or {}).get("appStoreVersion") or {}
        if (related.get("data") or {}).get("id") == version_id:
            return True
    return False


def cmd_submit(args):
    app = app_id()
    version_id = find_or_create_version(app, args.version, args.release_type)
    attach_build(version_id, args.build_id)

    if args.notes_file:
        with open(args.notes_file, encoding="utf-8") as handle:
            notes = handle.read().strip()
        if notes:
            set_whats_new(version_id, notes)
        else:
            log("warning: リリースノートが空でした。App Store Connect で入れてください。")

    if args.no_submit:
        log("--no-submit のため、審査には出しません。")
        return
    submit_for_review(app, version_id)


# --- state ----------------------------------------------------------------


def cmd_state(args):
    version = find_version(app_id(), args.version)
    if version is None:
        if args.require_open:
            # 版がまだ無い = これから作る。ビルドはそのまま送ってよい。
            print("NOT_FOUND")
            log(f"まだ App Store Connect に {args.version} の版がありません。ビルドを送れます。")
            return
        if args.require_live:
            # 版がまだ無いのは、配信前のふつうの待ち時間。main へのマージから submit ジョブが版を
            # 作る（書き換える）までの間と、初回に ASC_AUTO_SUBMIT=false で手で提出するまでの間
            # （数日かかりうる）がこれにあたる。失敗（1）ではなく「まだ配信前」（2）で返し、
            # 配信を待つ判定（cron で回す通知など）が、その間ずっと失敗にならないようにする。
            # tag-release.yml は配信中の版を version-info --live で探すので、これは使っていない。
            print("NOT_FOUND")
            log(f"まだ App Store Connect に {args.version} の版がありません（提出前）。")
            sys.exit(2)
        die(f"バージョン {args.version} は App Store Connect にありません。")
    state = version_state(version)
    print(state)
    if args.require_live and state not in LIVE_STATES:
        hint = (
            "人の操作を待っています。App Store Connect を見てください。"
            if state in STUCK_STATES
            else "まだ配信前です。"
        )
        log(f"{args.version} は {state}。{hint}")
        sys.exit(2)
    if args.require_open and state in CLOSED_STATES:
        log(f"{args.version} は {state}（承認済み以降）。この版にはもう新しいビルドを送れません。")
        sys.exit(2)


# --- version-info ---------------------------------------------------------


def attached_build_number(version_id):
    """その版に紐づいているビルドのビルド番号（CFBundleVersion）。無ければ空文字。"""
    build = api("GET", f"/v1/appStoreVersions/{version_id}/build").get("data")
    return (build or {}).get("attributes", {}).get("version") or ""


def cmd_version_info(args):
    """tag-release.yml が、タグを打つ版とコミットを決めるのに使う。

    main のバージョンではなく App Store Connect で配信中の版を見るのは、前の版の審査中に
    次の版を main へ入れたときも、前の版に印を付けるため。ビルド番号は、どのコミットの
    ビルドが配信されたかを逆算する（release.yml の実行番号から作っている）のに使う。

    出力は $GITHUB_OUTPUT にそのまま足せる key=value の行。Apple から来た値を形も
    確かめずにシェルへ渡さないよう、ここで版とビルド番号と状態の書式を確かめる。
    版が無ければ（配信中の版がまだ無い初回の配信前など）終了コード 2。
    """
    app = app_id()
    if args.live:
        version = first_in_states(list_versions(app), LIVE_STATES)
        missing = "配信中の版はまだありません。"
    else:
        version = find_version(app, args.version)
        missing = f"App Store Connect に {args.version} の版がありません。"
    if version is None:
        log(missing)
        sys.exit(2)

    version_string = version["attributes"].get("versionString") or ""
    state = version_state(version) or ""
    build = attached_build_number(version["id"])
    if not NUMBER_PATTERN.fullmatch(version_string):
        die(f"版番号「{version_string}」が X.Y.Z の形ではありません。")
    if build and not NUMBER_PATTERN.fullmatch(build):
        die(f"ビルド番号「{build}」がピリオド区切りの整数ではありません。")
    if not re.fullmatch(r"[A-Z_]+", state):
        die(f"版の状態「{state}」を読めません。")
    print(f"version={version_string}")
    print(f"state={state}")
    print(f"build={build}")


# --- entry ----------------------------------------------------------------


def main():
    global BUNDLE_ID

    parser = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter
    )
    parser.add_argument(
        "--bundle-id",
        default=os.environ.get("ASC_BUNDLE_ID"),
        help="対象アプリのバンドル ID（既定: 環境変数 ASC_BUNDLE_ID）",
    )
    sub = parser.add_subparsers(dest="command", required=True)

    wait = sub.add_parser("wait-build", help="ビルドの処理が終わるのを待つ")
    wait.add_argument("--version", required=True, help="表示用バージョン（0.1.0 など）")
    wait.add_argument("--build", required=True, help="ビルド番号（CFBundleVersion）")
    wait.add_argument("--timeout", type=int, default=3600)
    wait.add_argument("--interval", type=int, default=60)
    wait.set_defaults(func=cmd_wait_build)

    submit = sub.add_parser("submit", help="ビルドを紐づけて審査に出す")
    submit.add_argument("--version", required=True)
    submit.add_argument("--build-id", required=True)
    submit.add_argument("--notes-file")
    # SCHEDULED は配信日時（earliestReleaseDate）も要るので受け付けない。
    submit.add_argument(
        "--release-type",
        default="AFTER_APPROVAL",
        choices=["AFTER_APPROVAL", "MANUAL"],
        help="AFTER_APPROVAL: 審査を通ったら自動で配信 / MANUAL: 自分で配信開始を押す",
    )
    submit.add_argument(
        "--no-submit",
        action="store_true",
        help="バージョンの用意までで止める（審査には出さない）",
    )
    submit.set_defaults(func=cmd_submit)

    state = sub.add_parser("state", help="バージョンの状態を表示する")
    state.add_argument("--version", required=True)
    require = state.add_mutually_exclusive_group()
    require.add_argument(
        "--require-live",
        action="store_true",
        help="配信中でなければ（版がまだ無い提出前も含めて）終了コード 2 で終わる",
    )
    require.add_argument(
        "--require-open",
        action="store_true",
        help="承認済み以降（この版にはもうビルドを送れない）なら終了コード 2 で終わる。版がまだ無ければ 0",
    )
    state.set_defaults(func=cmd_state)

    info = sub.add_parser(
        "version-info",
        help="版の版番号・状態・紐づいたビルド番号を key=value の行で表示する",
    )
    target = info.add_mutually_exclusive_group(required=True)
    target.add_argument("--live", action="store_true", help="いま配信中の版")
    target.add_argument("--version", help="この版番号の版")
    info.set_defaults(func=cmd_version_info)

    args = parser.parse_args()
    BUNDLE_ID = args.bundle_id
    try:
        args.func(args)
    except ApiError as error:
        die(str(error))


if __name__ == "__main__":
    main()
