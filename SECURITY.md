# セキュリティ / Security

## 日本語

### 報告の窓口

SaifuLog の脆弱性や、プライバシーに関わる問題（記録が端末の外へ送られている疑いなど）を
見つけたときは、**公開の Issues には書かず**、GitHub の非公開の報告窓口からお知らせください。

1. このリポジトリの **Security** タブを開く
2. **Report a vulnerability** を押す（直接開くなら
   https://github.com/iam74k4/SaifuLog-Apple/security/advisories/new ）
3. 内容を書いて送る

報告の内容は、開発者と報告した人だけが見られます。Issues は誰でも読めるため、脆弱性の
詳細や、個人情報・家計の記録は書き込まないでください。

### 対象

| 対象 | 例 |
|---|---|
| アプリ本体（`SaifuLog/`、`Packages/SaifuLogCore/`） | 記録が端末の外へ送られる、保存した記録がほかのアプリから読める、入力で落ちる・記録が壊れる |
| CI/CD（`.github/workflows/`、`release.mk`、`Makefile`） | App Store Connect の鍵（Environment `release` の Secrets）や、リポジトリへの書き込みの権限が漏れうる経路 |
| リリースの道具（`scripts/`） | `scripts/asc.py` や、その依存（`scripts/requirements.txt`）の問題 |

Apple の OS やフレームワーク（Foundation Models、SwiftData など）、GitHub 自体の脆弱性は、
それぞれ Apple と GitHub へ報告してください。

### 書いてほしいこと

- 何が起きるか（影響）と、再現の手順
- 確かめた環境（iOS の版と機種、アプリのバージョン、またはコミット）
- 分かれば、原因の場所や直し方の案

### 対応

個人で開発しているため、返信までに時間がかかることがあります。内容を確かめたうえで、直す
予定や公開の時期を相談します。修正を出すまでは、詳細を公開しないようお願いします。

対象の版は、App Store で配信中の最新の版と、`main`・`develop` の最新のコミットです。

---

## English

### Reporting

If you find a security vulnerability in SaifuLog, or a privacy problem (for example, a sign
that records leave the device), **please do not open a public issue.** Report it privately
through GitHub instead:

1. Open the **Security** tab of this repository
2. Click **Report a vulnerability**
   (or go to https://github.com/iam74k4/SaifuLog-Apple/security/advisories/new )
3. Describe the problem and submit

Only the developer and you can see the report. Issues are public, so please do not put
vulnerability details, personal information, or financial records there.

### Scope

- The app (`SaifuLog/`, `Packages/SaifuLogCore/`)
- CI/CD (`.github/workflows/`, `release.mk`, `Makefile`), including any way the App Store
  Connect key or write access to the repository could leak
- Release tools (`scripts/`), including `scripts/asc.py` and its dependencies

Vulnerabilities in Apple's operating systems and frameworks, or in GitHub itself, should be
reported to Apple or GitHub.

### What to include

- What happens (impact) and steps to reproduce
- Where you tested it (iOS version and device, app version or commit)
- If you know, where the cause is or how it could be fixed

### Response

This is a personal project, so replies may take some time. After confirming the report, we
will discuss the fix and when to disclose it. Please keep the details private until a fix is
released.

Supported versions: the latest version on the App Store, and the latest commits on `main` and
`develop`.
