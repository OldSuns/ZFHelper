# ZFHelper

[English](README.md) | [简体中文](README.zh-CN.md)

A Flutter/Dart client for the newer Zhengfang academic administration system. Android-first, with Windows support.

## Status

Version **0.1.1+1**, under development. The application UI is currently Simplified Chinese; English documentation does not imply an English UI. GitHub CI checks pull requests and `main`; version releases are built from `vX.Y.Z` tags. School compatibility and release readiness still require real-school and device acceptance.

## Features

| Area | Current capabilities |
| --- | --- |
| Timetable | Weekly timetable and date-based agenda, term/week selection, search, course details, local edits, and offline viewing |
| Courses | Available courses, teaching-class details and seat availability, selected records, immediate enrollment, manually started seat watching, and operation history |
| Grades | Retrieval of published grades, local term/search/sort/filter controls, record details, reference statistics, and offline storage |
| Settings | Schools and accounts, appearance, timetable import and management, calendar/period times, Android widget management, and local data information |

Users enter their own school name and academic-system URL; no school is preconfigured. Multiple schools and accounts are supported. Session persistence and optional password saving are separate choices.

Import or update a timetable in **Settings > Timetable**. Set the first teaching week's Monday or correct the current teaching week in calendar settings. Teaching dates are not guessed from the month. Period times can be generated per campus for morning, afternoon, and evening, previewed, adjusted, and explicitly saved.

The agenda combines timetable courses with local personal events: to-dos, activities, examinations, assignments, and other entries. Personal events are account-scoped and independent of the term.

Saved data remains available until explicitly updated or cleared; failed refreshes preserve previous data. Logout retains offline data, while removing an account or school clears its local data. Enrollment success is confirmed against school-selected records, not merely a successful HTTP response.

Appearance follows the system or uses persistent light/dark mode with Catppuccin Latte/Mocha colors.

## Platforms

| Target | Runtime and platform capabilities |
| --- | --- |
| Android 13+ (API 33) | Responsive UI, foreground-service-backed seat watching, and an offline home-screen timetable widget |
| Windows | Sidebar/split-pane layouts; selection operations run while the application process remains open; no Android widget |

Android background work is subject to notification permission, service limits, and power management. Widget refreshes are not precise course reminders. Interrupted operations require manual continuation or result verification after restart.

## Getting started

The application requires Flutter **>=3.47.4** and Dart **^3.13.3**, as declared in [pubspec.yaml](pubspec.yaml). Install the platform toolchain described in [development](docs/development.md).

From the repository root:

```powershell
flutter pub get
flutter devices
flutter run -d windows
```

For Android, use `flutter run -d <device-id>` with an ID from `flutter devices`. Windows web login requires WebView2 Runtime.

## Documentation

- [Product scope and roadmap](docs/requirements.md)
- [Architecture and data boundaries](docs/architecture.md)
- [Development, builds, and validation](docs/development.md)
- [Contributing](CONTRIBUTING.md)
- [Working agreement](AGENTS.md)
- [Pure-Dart core package](packages/zf_core/README.md)

## Limitations

- School variants are not universally compatible. Real-school login, timetable, grades, and enrollment-result comparisons remain acceptance work.
- Update checking and the GitHub action in the About dialog are disabled placeholders.
- ICS export, school examination-schedule retrieval, system course reminders, Live Updates, and couple timetables are not implemented. Manually entered examination events are supported.
- Scheduled auto-enrollment, cloud enrollment delegation, automatic withdrawal, and cross-device synchronization are outside the current scope.
- Production-device background behavior, signed-package installation, and upgrade flows still require acceptance. GitHub CI and unsigned release assets do not establish those results.

## License

Licensed under [Apache-2.0](LICENSE). Copyright 2026 [OldSuns](https://github.com/OldSuns). Third-party dependencies and vendored material retain their own licenses.
