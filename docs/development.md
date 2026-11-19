# Development, builds, and validation

## Environment

The application declares Flutter **>=3.47.4** and Dart **^3.13.3** in [pubspec.yaml](../pubspec.yaml), and the [core package](../packages/zf_core/pubspec.yaml) accepts Dart **>=3.13.0 <4.0.0**. Use a Flutter SDK satisfying the application constraints; resolved dependencies are recorded in the lockfiles, not inferred from these minimums.

Android requires the Flutter Android toolchain, with API 33 (Android 13) as the application minimum; compile/target SDK and NDK follow Flutter, and Java/Kotlin bytecode targets Java 17. Windows builds require the Visual Studio C++ desktop/CMake toolchain, and web login requires WebView2 Runtime. Release builds use the pinned `windows-2022` GitHub Actions runner for compatibility with the official WebView plugin. Check local toolchains with `flutter doctor`.

## Run and build

From the repository root:

```powershell
$env:PUB_HOSTED_URL = 'https://pub.flutter-io.cn'
flutter pub get --enforce-lockfile
flutter devices
flutter run -d windows
```

Both committed lockfiles use `https://pub.flutter-io.cn`. Set `PUB_HOSTED_URL` to this source for local dependency restoration, matching all CI and release workflows. Strict restoration fails when the manifest, package source, or package hashes disagree with the lockfile. For an intentional dependency change, run `flutter pub get` in the root or `dart pub get` in the core package without `--enforce-lockfile`, then include the generated lockfile changes.

The application temporarily pins `jni` to `1.1.2` and `jni_flutter` to `1.0.4+1` for compatibility with `path_provider_android 2.3.1`. The `jni 1.2.0` / `jni_flutter 1.1.0` combination reproduced an application-directory lookup failure on Android. Revisit both pins together after verifying an upstream fix in an Android release build, including school entry and persistent storage initialization.

For Android, run `flutter run -d <device-id>` using an ID reported by `flutter devices`.

```powershell
flutter build windows --release
flutter build apk --debug
```

Ship the complete `build/windows/x64/runner/Release/` directory, not just its executable. The Android debug APK is `build/app/outputs/flutter-apk/app-debug.apk`. Debug packages are not a release-signing solution; configure signing and validate installation/upgrades separately before distribution.

## GitHub CI and releases

Pull requests and pushes to `main`, `dev`, and `LXY` run [.github/workflows/ci.yml](../.github/workflows/ci.yml), which restores both Dart packages with `--enforce-lockfile`, checks formatting, analyzes both packages, and runs their tests. This quality workflow does not package or upload installable artifacts. The LXY release workflow also calls it before building an APK. Release workflows enforce the application lockfile and build with `--no-pub` to reuse restored dependencies.

### Branch flow

Shared feature branches merge into `dev`; shared changes can reach `main` and `LXY` through separate pull requests. When LXY needs only part of `dev`, select the relevant commits and their dependencies. Preserve LXY identity, version, release notes, workflow rules, update channel, and AGENTS.md when resolving synchronization conflicts. LXY-specific changes stay on LXY. Ordinary stable tags must be reachable from `main`, ordinary pre-release tags from `dev`, and `lxy-vX.Y.Z` tags from `LXY`.

Prepare ordinary stable release commits on `dev` (version bump plus [RELEASE_NOTES.md](../RELEASE_NOTES.md)) and merge them into `main`. Prepare LXY release commits on `LXY`. The build number after `+` must exceed every published build across stable, pre-release, and LXY channels; inspect all published tags before allocating it. Coordinate releases across branches rather than publishing concurrently with the same build number. Ordinary in-app updates use GitHub `latest`; LXY uses its own filtered release list.

### LXY APK releases and installation

The LXY edition is displayed as `流星雨课表` and starts from the ordinary 0.2.3 release. Its initial release was `0.2.3+14`; the current version is recorded in `pubspec.yaml`. Recheck the global build number at publication time. It keeps application ID `dev.zfhelper.app`, the ordinary release signing identity, database paths, and secure-storage keys. Install its signed APK over the ordinary app without uninstalling. This retains existing data; school sessions may still expire independently. Any later schema change needs an explicit compatible migration. Returning to an ordinary build also needs a higher build number and compatible data schema.

1. On `LXY`, increase its own X.Y.Z version for each new release, choose a build number above all published channels and the recipient's installed build, and update `RELEASE_NOTES.md` with only the new release notes.
2. Commit and push the branch after the agreed checks. Push an explicitly authorized `lxy-vX.Y.Z` tag matching that version; PRs and branch pushes produce no APK.
3. [release-lxy.yml](../.github/workflows/release-lxy.yml) runs quality checks, validates branch ancestry/tag/version/global build numbers, and builds only an Android APK. The `release` Environment must permit LXY release tags and contain all four existing signing secrets. Missing secrets fail; there is no unsigned fallback.
4. Publication attaches `zfhelper-lxy-X.Y.Z.apk` and its `.sha256`, uses LXY release notes, and explicitly sets `--latest=false`. It creates no AAB or Windows ZIP. Release visibility follows repository visibility, even though this edition is intended for one recipient.
5. Check the actual certificate and version code against the installed ordinary APK, then verify ordinary-to-LXY installation and a later LXY-to-LXY update on a device. Neither source tests nor a successful build proves those upgrade results.

LXY checks all pages of GitHub releases, filters to published non-prerelease `lxy-vX.Y.Z` tags, and selects the highest semantic version. Current-version notes and download assets stay within the selected tag. Lookup errors and missing APKs are explicit. `zfhelper-update-lxy.json` stores its check timestamps and notification state separately from the ordinary channel's `zfhelper-update.json`; business data and credentials continue to use their existing locations. The update page shows the active channel, and the app offers no channel switch.

### Stable releases

A stable release is created only by pushing a `vX.Y.Z` tag, and the workflow in [.github/workflows/release.yml](../.github/workflows/release.yml) requires the tag version to match the `X.Y.Z` part of `pubspec.yaml`; for example, `0.1.1+4` is released with tag `v0.1.1`.

1. On `dev`, update `pubspec.yaml` to `X.Y.Z+build` with a build number greater than every previously published tag, synchronize the displayed version in both READMEs, and update [RELEASE_NOTES.md](../RELEASE_NOTES.md).
2. Commit the version change, merge `dev` into `main` via pull request, and wait for CI to pass.
3. Push `vX.Y.Z` from that release commit on `main`.
4. Check the GitHub Release body, assets, and their `.sha256` files. The body starts with `RELEASE_NOTES.md`, followed by signing information, artifact checksums, and GitHub's generated Full Changelog.

### Pre-releases

A pre-release is created only by pushing a `vX.Y.Z-beta.N`, `vX.Y.Z-rc.N`, or `vX.Y.Z-dev.N` tag from a `dev` commit. The workflow in [.github/workflows/release-dev.yml](../.github/workflows/release-dev.yml) requires the tag to match the full `pubspec.yaml` version including the pre-release suffix; for example, `0.2.0-beta.1+5` is released with tag `v0.2.0-beta.1`.

1. On `dev`, update `pubspec.yaml` to `X.Y.Z-stage.N+build` with a build number greater than every previously published tag, and update [RELEASE_NOTES.md](../RELEASE_NOTES.md).
2. Commit the version change and wait for CI to pass.
3. Push `vX.Y.Z-stage.N` from that commit.
4. Check the GitHub pre-release body, assets, and their `.sha256` files. The body adds a pre-release notice stating that the build comes from `dev`, may be unstable, and is intended for testing only.

After the stable `vX.Y.Z` is released from `main`, the next pre-release on `dev` starts from the next version core, for example `vX.Y.(Z+1)-beta.1`, with a build number above all published channels, including LXY. Pre-releases are not offered through in-app update checks; pre-release users download new builds from the GitHub Releases page until a stable release overtakes their version. In-app version ordering uses a project-defined stage order `dev < beta < rc < stable`, accepts only these three stages, and rejects other suffixes such as `-alpha.1`; do not publish tags with other pre-release suffixes.

The ordinary release workflows build an Android AAB, Android APK, and a ZIP containing the complete Windows release directory. Android signing uses the protected `release` Environment secrets `ANDROID_KEYSTORE_BASE64`, `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS`, and `ANDROID_KEY_PASSWORD`: all four configured signs the Android assets, none configured publishes ordinary assets marked `unsigned` for testing only, and partial configuration fails. LXY always requires all four. Unsigned assets are not official distribution or upgrade evidence. Workflows never store signing material in the repository and clean temporary signing files after the build.

Verify a downloaded asset with `Get-FileHash <file> -Algorithm SHA256` on PowerShell or `sha256sum <file>` on Unix. A successful workflow, signed package, installation, and upgrade are separate acceptance evidence; none proves real-school compatibility or production-device background behavior.

## Targeted validation

Choose existing checks relevant to the change before expanding coverage. Do not repeatedly run whole suites or device smoke checks for unrelated documentation or formatting work, and resolve dependencies first when package configuration changes.

Application examples, run from the repository root:

```powershell
flutter test --no-pub test/ui/features/schedule/schedule_calendar_page_test.dart
flutter test --no-pub test/app_test.dart
```

For pure-Dart core checks, change to `packages/zf_core` and run:

```powershell
$env:PUB_HOSTED_URL = 'https://pub.flutter-io.cn'
dart pub get --enforce-lockfile
dart test test/src/schedule/period_time_plan_test.dart
```

The core command must be launched under an outer runner enforcing a **60-second hard deadline for the entire process tree**, terminating it if exceeded. Neither the command shown nor a per-test `--timeout` provides that guarantee. Use the execution environment's hard-timeout/process-tree control; no dedicated repository runner is assumed.

For modified Dart files, use the actual changed paths:

```powershell
dart format --output=none --set-exit-if-changed <changed-paths>
flutter analyze --no-pub <changed-paths>
```

`<changed-paths>` is a placeholder, not a literal command argument, and `dart analyze` may be used within the core package for its modified files. Add a corresponding platform build only when the change affects that platform or requires compilation evidence. Device checks are needed for platform-specific behavior such as WebView authentication, foreground-service permissions/interruption, persistence across restarts, widget rendering/launcher sizing, and tap-to-agenda handling. Real-school access and enrollment actions need explicit authorization; never use constructed responses as substitutes.

## Documentation checks

For documentation-only changes:

- Confirm factual descriptions against the affected source/configuration before the final structural check.
- Check repository-relative file/directory links and Markdown heading anchors, including English/Chinese README links.
- Check balanced code fences and consistent terminology; remove links to deleted files rather than creating empty placeholders.
- Review only the documentation scope and preserve unrelated working-tree changes. No dependency resolution, application tests, or platform build is required solely for prose changes.

English is the canonical maintenance language; keep [README.zh-CN.md](../README.zh-CN.md) aligned with the root [README.md](../README.md). Temporary screenshots, logs, and diagnostic scripts belong in the system temporary directory; do not delete files used by active debug sessions.

## Evidence and acceptance

Use a compact record when reporting validation:

| Field | Record |
| --- | --- |
| Revision | Commit ID and any relevant uncommitted scope |
| Command | Exact command and working directory |
| Input/environment | Constructed sample, school comparison, OS/API, device/launcher, font scale, or other relevant conditions |
| Result | Pass/fail and a concise observed outcome |
| Not covered | Platforms, network actions, school data, device recovery, or release scenarios not exercised |

Keep source inspection, constructed-data tests, compilation, emulator checks, production-device behavior, and authenticated real-school results separate. A running service, HTTP 200, or successful debug build is not proof of successful enrollment, and documentation changes do not refresh historical acceptance results.

Current acceptance gaps include real-school authentication and business-data/result comparisons; Android multi-account persistence, process recovery, and long-running/background behavior; launcher/widget restart behavior; Windows minimize/sleep behavior; and formal signed-package installation/upgrade workflows. CI, automated builds, and unsigned release assets do not close these gaps. Record newly executed evidence rather than carrying old build results forward as validation of the current revision.
