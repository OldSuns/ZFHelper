# Development, builds, and validation

## Environment

The application declares Flutter **>=3.47.4** and Dart **^3.13.3** in [pubspec.yaml](../pubspec.yaml). The [core package](../packages/zf_core/pubspec.yaml) accepts Dart **>=3.13.0 <4.0.0**. Use a Flutter SDK satisfying the application constraints; resolved dependencies are recorded in the lockfiles, not inferred from these minimums.

Android requires the Flutter Android toolchain. The application minimum is API 33 (Android 13); compile/target SDK and NDK follow Flutter, and Java/Kotlin bytecode targets Java 17. Windows builds require the Visual Studio C++ desktop/CMake toolchain; web login requires WebView2 Runtime. Check local toolchains with `flutter doctor`.

## Run and build

From the repository root:

```powershell
flutter pub get
flutter devices
flutter run -d windows
```

For Android, run `flutter run -d <device-id>` using an ID reported by `flutter devices`.

```powershell
flutter build windows --release
flutter build apk --debug
```

Ship the complete `build/windows/x64/runner/Release/` directory, not just its executable. The Android debug APK is `build/app/outputs/flutter-apk/app-debug.apk`. Debug packages are not a release-signing solution; configure signing and validate installation/upgrades separately before distribution.

## Targeted validation

Choose existing checks relevant to the change before expanding coverage. Do not repeatedly run whole suites or device smoke checks for unrelated documentation or formatting work. Resolve dependencies first when package configuration changes.

Application examples, run from the repository root:

```powershell
flutter test --no-pub test/ui/features/schedule/schedule_calendar_page_test.dart
flutter test --no-pub test/app_test.dart
```

For pure-Dart core checks, change to `packages/zf_core` and run:

```powershell
dart pub get
dart test test/src/schedule/period_time_plan_test.dart
```

The core command must be launched under an outer runner enforcing a **60-second hard deadline for the entire process tree**, terminating it if exceeded. Neither the command shown nor a per-test `--timeout` provides that guarantee. Use the execution environment's hard-timeout/process-tree control; no dedicated repository runner is assumed.

For modified Dart files, use the actual changed paths:

```powershell
dart format --output=none --set-exit-if-changed <changed-paths>
flutter analyze --no-pub <changed-paths>
```

`<changed-paths>` is a placeholder, not a literal command argument. `dart analyze` may be used within the core package for its modified files. Add a corresponding platform build only when the change affects that platform or requires compilation evidence.

Device checks are needed for platform-specific behavior such as WebView authentication, foreground-service permissions/interruption, persistence across restarts, widget rendering/launcher sizing, and tap-to-agenda handling. Real-school access and enrollment actions need explicit authorization; never use constructed responses as substitutes.

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

Keep source inspection, constructed-data tests, compilation, emulator checks, production-device behavior, and authenticated real-school results separate. A running service, HTTP 200, or successful debug build is not proof of successful enrollment. Documentation changes do not refresh historical acceptance results.

Current acceptance gaps include real-school authentication and business-data/result comparisons; Android multi-account persistence, process recovery and long-running/background behavior; launcher/widget restart behavior; Windows minimize/sleep behavior; and formal signing/upgrade workflows. Record newly executed evidence rather than carrying old build results forward as validation of the current revision.
