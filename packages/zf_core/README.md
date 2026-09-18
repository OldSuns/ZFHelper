# zf_core

The pure-Dart core of ZFHelper. It has no Flutter or platform-plugin dependency. Public APIs are exported through [lib/zf_core.dart](lib/zf_core.dart).

## Modules

| Directory | Responsibility |
| --- | --- |
| `src/auth/` | School connection configuration and URL recognition; account/session ownership; RSA, captcha, cookie-based authentication, authenticated reads, and persistence codecs |
| `src/academic/` | Zhengfang term/timetable and grade protocol gateways |
| `src/schedule/` | Terms, teaching calendars, timetable records, week notation, period-time planning, local adjustments, date projections, personal events, and codecs |
| `src/grades/` | Faithful grade records, term grouping, snapshots, codecs, and reference statistics |
| `src/selection/` | Course/teaching-class models and protocols; immediate enrollment and seat watching; persisted operations, interruption recovery, and result reconciliation |

Transport and storage implementations are injected by the application. Platform plugins, SQLite, WebView integration, foreground services, and widgets belong outside this package.

## Semantic boundaries

- `AccountScope` combines a stable school ID with an account ID. Data or operations must not acquire another account's ownership when the UI selection changes.
- `AuthRepository` owns authentication state and account sessions. Restoring a session must preserve the verified identity; authenticated reads must reject stale identity changes.
- `SelectionCoordinator` is the shared executor. Submission intent is persisted before a request; unknown results are reconciled with school-selected records. A response status alone cannot prove enrollment success.
- `CalendarWeek` represents a calendar week, not a teaching week. Teaching-week/date projections require configured calendar information.
- `recognizeSchoolAddress` recognizes an address; it does not establish connectivity, school identity, or a successful login.
- `PeriodTimePlan` owns generation, same-section shifts, and conflict validation. Consumers use actual `PeriodTime` values rather than maintaining separate display clocks.
- Grade statistics use supplied school values and disclose their participating records. They do not replace the school's official cumulative GPA or infer numeric values from textual grades.

## Development

Use Dart **>=3.13.0 <4.0.0**, as declared in [pubspec.yaml](pubspec.yaml). From this package directory:

```powershell
dart pub get
dart test test/src/schedule/period_time_plan_test.dart
```

Replace the example with the existing test relevant to your change. Run core tests under an outer runner with a **60-second hard timeout for the entire process tree**; the command above does not enforce that deadline by itself. A per-test `--timeout` is not a substitute.

See the root [development guide](../../docs/development.md) and [architecture](../../docs/architecture.md) for application integration and validation boundaries. Contributions follow [CONTRIBUTING.md](../../CONTRIBUTING.md); project code is licensed under [Apache-2.0](../../LICENSE).
