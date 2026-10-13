# Product scope and roadmap

ZFHelper is an Android-first Zhengfang academic-system client with Windows support. This document separates implemented behavior from planned work and acceptance gaps; shipping a feature is not a claim of compatibility with every school or of production-device validation.

## Implemented

### Navigation and settings

The main destinations are Timetable (default), Courses, Grades, and Settings. Timetable contains timetable and agenda views. Narrow windows use bottom navigation; wider windows use a sidebar and, where appropriate, split panes.

Settings has five subsections: Schools and accounts, Web portal, Appearance, Timetable, and Data and application. Timetable settings centralize import/update, term selection, local courses, calendar and period times, reschedule/cancellation/makeup history, view preferences, hidden-entry restoration, saved timetables, and widget management. Personal events are managed in agenda. There is no separate import-information screen or selection-task destination. Web portal opens the school portal in an in-app browser, seeding the selected account's saved cookies to reuse its session; no credentials are entered or stored there.

### Schools and authentication

- Users supply school names and academic-system URLs, with configurable endpoint paths and a separate web-login address when needed. No school or allowlist is preconfigured.
- Password/captcha login, web login, and cookie import are supported. A verified school identity is required before a session counts as connected.
- Schools can be added, edited, selected, and removed, each with multiple accounts; stable school IDs survive name/address edits.
- Valid saved sessions can be restored. Optional password saving is distinct from session persistence. Connection changes invalidate old sessions without deleting business data.
- Logout stops later work for that account, clears saved login information, and retains offline data. Account/school removal also clears that account's local data and does not withdraw courses at the school.

### Timetable, calendar, and period times

- Prefer actual school term options; allow manual academic-year/term selection when recognition is unavailable. Teaching dates require the first week's Monday or a current-week correction supplied by the user.
- Preserve odd/even and discontinuous weeks, multiple time/location segments, and courses without fixed periods. School restrictions and malformed responses are not empty timetables.
- The weekly grid supports week browsing, search, details, and local edits.
- During a class in the current teaching week, the header shows the course name and an end countdown in place of its semester label and still opens semester selection; other weeks and the time between classes keep the normal label. Current course cells are outlined without an in-cell status label.
- Course details offer rescheduling and cancellation for the clicked teaching week plus weekly occurrence details; makeup starts from the adjustment editor or history. Selections are whole courses, a continuous subset of periods, or a whole source day's courses, with an explicit target period range. A batch previews its arrangements and conflicts before one atomic save, and conflicts stay visible instead of overwriting another course. Makeup can copy the current or original arrangement while retaining existing lessons.
- Adjustment history retains cancelled occurrences and offers original-source makeup and restoration. Weekly details show original and effective arrangements, including cancelled weeks and rescheduled/makeup destinations; dates appear only when the calendar is known. School refreshes preserve local results and flag changed sources for review.
- Whole-term course editing uses the complete root arrangement, including weeks omitted by occurrence adjustments. Saving an edit, hiding a school arrangement, or deleting a local arrangement explicitly removes that root's occurrence adjustments. Stale edits and restore confirmations cannot overwrite newer changes.
- Teaching weeks support click, drag (mouse and touch long-press), and keyboard selection with current/all/odd/even shortcuts, plus text input for sparse or distant weeks. The selectable range follows the calendar and actual arrangements, not grid pagination.
- Smart period-time planning generates morning/afternoon/evening sections per campus from start times, period counts, and class/break lengths. A section uses regular breaks only, one fixed-position special break, or recurring special breaks (such as 5/10/5/10 minutes), and the page updates an editable preview as parameters change. It is not a standalone grouping-only entry.
- Campus choices include campuses found in timetable entries as well as period times. Without an explicitly saved campus selection, editing starts from generic times shared across campuses.
- Editing a period or break can shift later periods within the same section while preserving their existing lengths and gaps; other sections keep independent start times. Overlaps must be corrected before saving, and cross-day overflow is an explicit error rather than wrapping or clamping.
- Period-time edits are drafts with undo and restoration of school times; applying a generated preview changes the draft, and only saving calendar settings persists it.
- Calendar and timetable settings are school/account/term-scoped. School refreshes do not overwrite local additions or calendar settings; stale editors cannot overwrite newer settings.

### Agenda and personal events

- Courses are projected for the chosen date using teaching weeks and campus period times. Agenda date selection is independent of the browsed timetable week.
- Complete times give clock-based morning/afternoon/evening grouping and course states; incomplete times use period ordering and full period ranges rather than a guessed time-of-day label. Courses without periods remain distinguishable, and there is no separate pending-arrangements area.
- Today's agenda shows the next class, current-period end, or return from a class break as a countdown that refreshes on resume and starts no reminder service.
- Users can create, edit, and delete to-dos, activities, examinations, assignments, and other events with all-day or start/end times, location, and notes; to-dos and assignments support completion state.
- Events use the timetable database, are isolated by school/account, persist across terms, and work for an existing account without an imported timetable. Clearing timetable data preserves events; account/school removal deletes them. Stale edits cannot recreate deleted events or overwrite newer versions.

### Grades

Published grades are retrieved and saved as complete snapshots. Term selection, search, sorting, and filtering operate on saved records. Details and reference statistics retain textual grades, zero scores, makeup exams, retakes, missing fields, and original school term information.

Missing values are not zero. Reference weighted GPA uses valid school GPA values and positive credits, discloses participation, and does not replace official cumulative GPA or convert letter grades. Failure filtering uses the school's explicit pass status, not a universal 60-point rule.

### Courses and enrollment

Available courses, teaching classes, selected courses, and operation history are shown in Courses. Search/filter controls use the saved current-round list; seat availability may require teaching-class detail retrieval. Unknown availability is distinct from zero, and segmented schedules retain corresponding locations.

Immediate enrollment and manually started seat watching share one executor. An operation captures its school, account, term, round, and teaching class at creation, and switching the viewed account does not change it. Submission intent is saved before submission, and school-selected records determine success; unknown outcomes require reconciliation before resubmission.

Stopping an operation prevents later attempts but cannot retract a sent request or withdraw a course. Restart does not resubmit automatically: interrupted operations require manual continuation or verification. History includes all accounts; clearing ended history preserves active, paused, and unresolved operations.

Seat watching needs notification permission and an Android foreground service; on Windows the application process must stay open.

### Persistence and appearance

Timetables, grades, course snapshots, selected records, and operations are isolated by school/account with term/round scope where appropriate. Viewing saved data does not implicitly re-import it, failed explicit updates preserve old data and timestamps, and a newly selected round without a cache may need a query.

Appearance supports system, light, and dark modes across restarts with Catppuccin Latte/Mocha colors and a Mauve accent. Course accents are assigned deterministically by course name in first grid-appearance order, so an unchanged semester keeps each course the same color across grid, agenda, and details. Local data settings show actual saved content and read failures.

### Update checking

The app checks GitHub for the latest ZFHelper Release silently at startup, at most once per 24 hours. A new release is announced once per tag with a non-blocking notice, and the Data-and-application entry keeps a badge until a manual check confirms the app is current. Manual checks show release details and notes at any time.

On Android the APK is downloaded in-app with progress (mirror first, then the official asset URL) and handed to the system package installer, requesting the "install unknown apps" grant when missing. Windows keeps browser-based downloads. Failures are explicit and retryable, and the release page remains a fallback.

### Android timetable widget

The home-screen widget is a read-only offline projection of the selected timetable account and term, following application appearance and using the effective timetable, calendar, period times, and local adjustments. It excludes personal events and credentials, and is unavailable on Windows.

It adapts across four information densities as size and font scale allow: a current/next-course strip, a scrollable list for today or the next course day, today/tomorrow columns, and a seven-day summary. Course names take priority over timing, period, location, and teacher details, and course/date/day taps open the corresponding agenda date. Timetable, account, calendar, or appearance changes synchronize the snapshot; removal waits for snapshot cleanup and reports failures. System updates and inexact boundary alarms can be delayed by power management, so this is not a precise reminder service.

### Android course notifications

Settings > Timetable > Course Live Updates controls offline course reminders, disabled by default, using the same dated snapshot as the widget. Only courses with a configured calendar and complete period times participate. The lead time is configurable; notifications count down to class start, the current period's end, or the end of a break; overlapping courses keep separate notifications; and a dismissed course stays hidden until that occurrence ends, with an explicit restore action in settings.

Course notifications use Android 16 Live Updates exclusively and need no Xiaomi App ID. Settings distinguishes notification permission, channel importance, Android promotion permission, posted notifications, and the actual promotion flag, and warns actionably when the channel is at minimum importance without raising user-selected importance itself. A separate two-minute example can be posted and cleared without importing or changing a timetable. Android versions below 16 cannot enable reminders or post examples; disabling reminders and clearing notifications remain available.

Upgrading from the earlier selectable-template implementation removes the saved display mode and its course/example notifications before using Live Updates, while retaining reminder enablement, lead time, and dismissed-course records.

Notifications are removed at phase expiry and recomputed from the current snapshot on phase boundaries, application resume, boot, package replacement, and clock or timezone changes, including while Flutter is stopped. Failures are reported and keep the next course boundary for recovery. Disabling reminders, blocked notifications, or a lost snapshot cancels course notifications and their alarm, and account/term changes remove obsolete ones. Exact-alarm access is optional; without it transitions use inexact alarms, and revoking it removes scheduled exact alarms. Idle throttling, manufacturer background restrictions, a disabled auto-start, and force-stopping the app can all delay or suspend reminders. Windows has no notification adapter.

## Planned or awaiting acceptance

| Item | Status |
| --- | --- |
| Real-school login, timetable, grades, and enrollment results | Need comparison against actual school records |
| Android multi-account persistence, process recovery, background behavior, widget launchers, and restart behavior | Need production-device acceptance |
| Windows minimize/sleep behavior during selection | Needs acceptance beyond source inspection |
| GitHub CI checks and tag-triggered Android/Windows release builds | Configured in `.github/workflows/`; needs GitHub Actions acceptance |
| Android release signing and application upgrades | Signing secrets and production-device acceptance still required |

These entries retain the product direction without presenting it as working functionality or a delivery commitment. See [development](development.md) for recording evidence.

## Out of scope

Scheduled auto-enrollment, a separate task page, activation, account quotas, signature penalties, cloud enrollment delegation, automatic course withdrawal, ICS export, couple timetables, and cross-device synchronization are outside the current scope. Do not introduce them during unrelated maintenance.
