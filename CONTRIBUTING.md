# Contributing to ZFHelper

Read the [English README](README.md) or [Chinese README](README.zh-CN.md), then the [product scope](docs/requirements.md). For ownership and contributor/agent constraints, see [architecture](docs/architecture.md) and [AGENTS.md](AGENTS.md).

## Setup

Install Flutter satisfying the root `pubspec.yaml` and the toolchain for Android 13+ or Windows. Windows web login requires WebView2 Runtime. From the root:

```powershell
flutter doctor
flutter pub get
flutter run -d windows
```

Use `flutter devices` and `flutter run -d <device-id>` for Android. Detailed build commands and output paths are in [development](docs/development.md).

## Changes and pull requests

- Start a focused branch from the base you intend to target. Keep each change tied to a concrete bug, agreed requirement, or documentation correction; discuss substantial product/architecture changes before implementing them.
- Follow existing View/ViewModel/Repository/core boundaries and constructor injection. Reuse existing helpers and installed dependencies; avoid unrelated refactors or generated-file churn.
- Use concise English commit messages. Do not include unrelated changes in a commit or pull request.
- Describe the problem, affected behavior, validation commands/results, and remaining limitations. Include screenshots when changing visible UI, but keep temporary captures/logs outside the repository.
- Update English documentation when behavior or interfaces change. Keep `README.zh-CN.md` aligned with `README.md`; do not treat planned features as implemented.

## Validation

Run the smallest relevant existing application or pure-Dart test. Use the non-writing format check and targeted static analysis for changed Dart paths, plus an affected-platform build when necessary. The [development guide](docs/development.md) provides commands and requires a **60-second hard process-tree timeout** for core tests.

For documentation-only changes, verify facts, Markdown structure, and relative links; tests and application builds are unnecessary solely for prose. Do not claim real-school or device success based on mocks, HTTP status, source inspection, or local builds. Report the revision, command, sample/device, result, and unverified scope.

No CI, release automation, or integration-test runner is assumed by this guide.

## Security, privacy, and protocol changes

- Never include passwords, cookies, tokens, student identifiers, personal timetables, or unredacted school responses in issues, logs, screenshots, fixtures, or commits. Use minimal sanitized samples.
- Keep certificate verification and trust-boundary validation enabled. Preserve old data on refresh/storage failure and surface actionable errors.
- Maintain school/account isolation, stale-response protection, the single authentication owner, and the single selection executor. Verify enrollment against school-selected records.
- School variants require evidence: inspect the relevant reference source/revision and school behavior without adding default schools or guessed universal rules. Real-school enrollment or destructive actions require explicit authorization.
- Respect third-party licenses before incorporating code or assets. Do not modify vendored skills or their licenses; reference material is not automatically covered by this project's [Apache-2.0 license](LICENSE).

## Bug reports

Include application/revision information, target OS/API, reproduction steps, expected/observed behavior, and sanitized errors. For layout/widget issues, include window/widget size and font scale. For school-specific behavior, state which facts were anonymously observed versus authenticated and which steps were not verified. Do not send account credentials.
