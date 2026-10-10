# Architecture and data boundaries

ZFHelper shares a Flutter UI and application layer between Android and Windows. Protocol interpretation and selection coordination live in a pure-Dart package. Dependencies are injected through constructors; [application configuration](../lib/app/app_configuration.dart) assembles the production graph.

## Ownership

| Location | Responsibility |
| --- | --- |
| [lib/app](../lib/app) | Dependency assembly, four-destination shell, startup restoration, lifecycle, exit handling, and coordinated account-data removal |
| [lib/ui](../lib/ui) | Views for rendering/interaction; ViewModels for page state; shared `AppTheme` and responsive layout rules |
| [lib/data/repositories](../lib/data/repositories) | Consistent cached business state, authenticated source access, identity projections, refresh/write sequencing, and removal semantics |
| [lib/data/storage](../lib/data/storage) | SQLite stores, account-scoped saved records, and application persistence codecs |
| [lib/platform](../lib/platform) | Secure storage, WebView/cookie handoff, selection runtime, widget/course-notification channels, and the Android package-installer handoff |
| [packages/zf_core](../packages/zf_core) | School/account/session ownership, injected transport contracts, protocol gateways, domain models, codecs, calendar rules, and selection coordination |
| [Android application](../android/app/src/main/kotlin/dev/zfhelper/app) | Shared Flutter engine, selection foreground-service host, offline widget host/provider/renderer, and course-notification planner/publisher |

Dio implements application network transport. SQLite stores business data; system secure storage holds authentication records and appearance. Web login uses official `flutter_inappwebview`. Actual dependency constraints/resolutions are recorded in the application/core pubspecs and lockfiles.

Do not add a forwarding-only layer to simple pages or duplicate network, session, cache, calendar, or selection loops.

## Schools, accounts, and sessions

`AuthRepository` owns the school directory, account identities, and account sessions. A school has a stable ID; editing its name/address does not replace that ID. Connection configuration is shared by the school's accounts. Renaming can preserve sessions; changing connection settings invalidates old sessions while retaining accounts and business data.

The selected browsing account is distinct from an authenticated network identity. Repositories project authentication changes into their saved account records through `AuthenticatedAcademicSource`. Cached account-label/selection writes remain retryable when storage fails. Selecting a cached account does not authenticate it, and selecting a school without accounts clears the current browsing selection.

Authenticated reads capture an identity for the entire request, including pagination, and verify that it is still current before publishing or saving. Account/session generations prevent late responses from overwriting new state. Account/school removal invalidates access, stops subsequent work, and clears corresponding stores; late responses must not recreate removed data.

## Persistence

SQLite files are placed in the application support directory. They are not credential-encryption databases.

| Content | Storage and scope |
| --- | --- |
| School directory, accounts, saved sessions, optional passwords, selected identity | Secure storage via `SecureLoginVault`, key `zfhelper.accounts.v2`; legacy records migrate without creating another session owner |
| Appearance | Secure storage via `SecureAppearanceStore`, key `zfhelper.appearance.v1`; application-wide and independent of accounts |
| Imported timetables, term catalogs, calendar/period settings, local adjustments | `zfhelper-timetable.sqlite3`; school/account with term-keyed records |
| Personal events and completion state | Same timetable database, account-scoped `events_payload`; independent of term |
| Grade snapshot and selected term filter | `zfhelper-grades.sqlite3`; school/account with school term information retained in the snapshot |
| Course rounds, snapshots, selected records, selection operations | `zfhelper-selection.sqlite3`; account scope plus term/round/teaching-class identity where applicable |
| Android widget and course-notification projection | One private `schedule_widget.json` snapshot; selected timetable account/term only, without credentials or personal events |
| Android course-notification preferences | Private `schedule_island` preferences for enablement, lead time, dismissal expiry, scheduling status, and errors; no second timetable cache |

SQLite stores serialize operations and use short-lived background isolates. Timetable schema v2 migrates v1 by adding event storage while preserving previous data. Grades and selection use schema v1. Unsupported schemas and malformed data produce explicit errors instead of clearing/recreating the database.

Repositories sequence writes and publish successfully persisted state. A failed write reports its own error without poisoning later explicit retries. Refresh failures retain previously saved business snapshots; school imports and local timetable changes are separate. Logout clears saved login information but retains offline business data. Removal cleans corresponding local records, not school-side enrollment.

## Timetable and agenda

Both views share `TimetableViewModel` and `ScheduleRepository`. The repository's effective timetable combines imported records, local edits, and hidden-entry semantics. Pure-Dart `ScheduleDay`/`ScheduleLesson` project courses for a date using the configured calendar and campus period times. Agenda dates and timetable browsing weeks are independent.

`ScheduleSettings.baseSnapshot` applies whole-term local entries and hidden school arrangements. `ScheduleOccurrenceOverride` then replaces one root arrangement in one source week with its complete list of remaining, rescheduled, and makeup parts; an empty list explicitly cancels that occurrence. Derived parts never become new owners. `sourceEntryId` is projection-only grouping information, while the override stores ownership and the original source evidence. The optional `occurrenceOverrides` settings JSON field needs no database schema migration and preserves existing records.

Occurrence editors capture school/account/term, source content, and the expected override, including its absence on a first edit. The existing repository write queue validates every selection against the latest baseline and saves a whole batch once. Restore removes only the reviewed override and never recreates old school data. Whole-term edits and deletions compare the complete root and its reviewed adjustments before replacing or removing them; restoring all school arrangements compares only the affected settings subset, preserving independent local courses and unrelated settings.

Import reconciliation reconnects changed source IDs only with a bidirectionally unique unchanged arrangement. Changed or missing sources retain their local parts, preserve the new school arrangements, and expose a derived review warning. Timetable, agenda, countdown, and Android widget all consume the same effective projection. Weekly details combine this projection with the original override evidence so cancellations remain reachable without a second timetable implementation.

`ScheduleCountdown` derives its state and next display boundary from dated lesson periods, including internal breaks and incomplete clocks. `TimetableViewModel.headerCountdown` exposes an ongoing class only in the current teaching week's timetable, replacing the semester control's contents while retaining its action. The existing date timer handles minute/second updates; second updates are active only while today's agenda or the ongoing header is visible and the app is resumed. Week navigation and date rollover update that visibility before scheduling the next clock refresh. `TeachingWeekSelector` emits immutable week sets and shares the course editor's parsed text state, with no second saved week selection.

Personal events are held in `StoredScheduleAccount.events`. Account-scoped write queues and edit-generation checks protect updates/deletions. Clearing timetables invalidates timetable edits but preserves personal events; removing an account also invalidates its event editors.

`PeriodTimePlan` centralizes campus/section generation, same-section shifting, and conflict validation. `PeriodTimesViewModel` holds an undoable draft. `PeriodTime` stores actual clocks; `ScheduleSettings.periodSections` stores campus and morning/afternoon/evening period ranges, not duplicate section-start times. Applying a generator preview changes only the draft; calendar settings are explicitly saved. Save-time source/settings checks reject stale edits. Optional settings JSON fields preserve older-record compatibility without another database schema migration.

## Selection and runtime

`CourseRepository` owns cached course state and the shared `SelectionCoordinator`, the only selection executor. Same-account submissions are serialized. Each operation captures its target account, school, term, round, and teaching class independently of page selection.

The coordinator persists intent before submission and verifies selected records afterward. A timeout/disconnection leaves an unresolved result requiring reconciliation. Stop prevents later attempts but cannot retract a sent request. On restart, in-flight submissions require verification and other interrupted work is paused; the runtime never creates or automatically resumes operations.

Android `ZfHelperApplication`, its Activity, and `SelectionForegroundService` share a lazy Flutter engine and the existing Dart repositories. The service maintains the existing executor's runtime with a foreground notification and CPU wake lock, releasing them on stop/timeout/destruction. Notification permission, foreground-service limits, and system interruptions constrain operation; failures remain visible. `START_NOT_STICKY` prevents the service from silently restarting school requests.

Windows uses process runtime: closing the app stops further attempts, and active-work exit handling first pauses/persists operations. Sleep/minimize/background acceptance is separate from implementation.

## Android widget

`ScheduleWidgetViewModel` listens to timetable and appearance changes, publishes through `ScheduleWidgetPlatform`, and projects the selected term's effective courses using the same date/calendar rules as the application. Snapshot synchronization follows account removal; cleanup failures are reported.

Kotlin `AppWidgetProvider` and responsive `RemoteViews` read the private snapshot and refresh without requiring a visible Flutter page or instantiating the lazy engine. Measured sizing rules select current/next, current-or-next-course-day list, today/tomorrow, or seven-day week-summary layouts using actual font metrics; the lowest width breakpoint also covers launcher-reported content widths below `minResizeWidth`. The Android host derives empty weekdays only from the dated snapshot and does not recalculate school calendar rules. Taps carry the selected date back to agenda. Periodic updates and inexact boundary alarms are offline refresh opportunities, not punctual notifications. Windows has no widget adapter.

## Android course notifications

`ScheduleIslandViewModel` manages native settings/status only. `ScheduleWidgetViewModel` remains the sole timetable snapshot publisher, including when no home-screen widget is installed. `ScheduleIslandPlatform` invokes `island.*` methods on the existing channel without replacing its incoming agenda-launch handler. The native host serializes publication, phase alarms, dismissal, and settings operations on the same executor. Publication waits for obsolete course notifications to be removed; normal notification display failures remain separate from widget synchronization, while a failed cleanup is reported to the caller. The `previewExpires` status field is derived from the active notification's monotonic expiry, translated to the current wall clock without persisted preview state. The ViewModel reads native status once just after that expiry, allowing for asynchronous system removal; clearing or replacing a preview cancels the previous timer, and disposal cancels pending refresh work. This timer neither posts notifications nor polls for their removal.

`ScheduleIslandPlan` consumes the snapshot's actual dates and complete period intervals. It never projects teaching weeks again or infers missing clocks. Each course occurrence has a school/account/term/date/course identity, while each phase has a deadline-specific token. `ScheduleIslandController` reconciles independent notifications against the current plan and schedules one next-boundary alarm separately from the widget's inexact refresh alarm. It arms that boundary before posting, so display-error cleanup removes course notifications without discarding the recovery opportunity. Disabling reminders, blocked notifications, unavailable snapshots, and legacy migration still cancel the alarm as well. Boot/resume/time-change recovery rebuilds the plan rather than trusting a persisted "already sent" flag. App/channel block-state broadcasts use the same reconciliation and re-read actual permissions; unrelated channel events are ignored. Minimum channel importance is diagnosed separately from permission to post ordinary notifications. Broadcast work uses `goAsync()` and finishes on the shared executor. Settings links to application information for firmware auto-start and battery restrictions, which can prevent these broadcasts from reaching the process.

`ScheduleIslandNotification` creates Android 16 Live Updates with a neutral icon tint. It requests promotion using the documented extra available with compile SDK 36 and negotiates the initial Android 16 colorized shape versus the newer explicit-opt-in shape with `hasPromotableCharacteristics()`. Platform countdowns and notification expiry limit stale display without keeping a foreground service alive. Timeout delete intents are distinguished from manual dismissal using both the phase deadline and a notification-specific monotonic expiry; clock changes rebuild timers. Notification taps retain source identity through to the final agenda navigation check, and example notifications never publish timetable data.

The platform contract has no presentation-mode field. Before reconciliation, configuration, or preview, the controller removes the legacy `mode` preference on the shared executor. It clears only this feature's course/example notifications and boundary alarm before committing removal of that marker, preserving enablement, lead time, and dismissal records. Failed cleanup or persistence remains an explicit error. Older Android versions can still disable reminders and clear previews.

Reminder display/settings errors are recorded separately from widget snapshot errors, so a notification failure cannot delete the shared projection. A failed snapshot publication invalidates both consumers without blocking independent reminder settings or preview cleanup. Reference evidence includes [NexioSchedule at `2daf4c3`](https://github.com/HaoZai000/NexioSchedule/tree/2daf4c387ecf298cc78df85004db88bb8d68fb7e), [HyperBridge at `e19ede1`](https://github.com/D4vidDf/HyperBridge/tree/e19ede13b87150028d89d31106ed898660e4c145), and [Android Live Updates](https://developer.android.com/develop/ui/views/notifications/live-update). Firmware acceptance remains distinct from these API contracts.

## Protocol evidence and third-party material

- The main protocol reference is [znjhahaha/zhengfang-apk](https://github.com/znjhahaha/zhengfang-apk). [zf-to-ics](https://github.com/zaochih/zf-to-ics) provides cross-checks; [shangkeschedule](https://github.com/qiqqqqq517/shangkeschedule) informs interface/platform comparisons. Their implementations are clues, not a universal Zhengfang contract.
- [NexioSchedule](https://github.com/HaoZai000/NexioSchedule) at `2daf4c387ecf298cc78df85004db88bb8d68fb7e` informed occurrence editing, teaching-week selection, today's countdown, and weekly detail interactions. Its AGPL-3.0 source/assets were not incorporated; the Flutter/Dart implementation uses ZFHelper's own models and persistence. AI import and WebDAV are excluded.
- When adapting a protocol, inspect the relevant source and record the revision actually used. Confirm paths, term options, required fields, school restrictions, and result semantics against evidence instead of freezing a copied field catalog in documentation.
- A public page/script or one school's behavior does not establish authenticated access, enablement, term dates, or compatibility at another school. School samples must not become defaults.
- Reference period-time behavior must not introduce clock clamping/wrapping, overwrite intentional gaps, or create a second display-time model. Keep generation and conflict semantics explicit.
- `zhengfang-apk` is GPLv3 and `shangkeschedule` is Apache-2.0; a project license does not relicense their code. Check licensing before incorporating material, including sources without a clear license. Reference use alone is not proof of copying or license compatibility.
- Vendored Flutter/Dart agent skills retain their own [Flutter license](../.agents/vendor/flutter-agent-plugins/LICENSE) and [Dart license](../.agents/vendor/flutter-agent-plugins/DART-LICENSE). Their pinned versions/hashes are recorded in [the skill lock record](../.agents/flutter-skills.lock.json), not duplicated here.

Constructed-data checks and builds do not establish successful real-school login or enrollment. Record acceptance evidence as described in [development](development.md).
