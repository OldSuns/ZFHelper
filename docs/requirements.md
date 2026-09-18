# Product scope and roadmap

ZFHelper is an Android-first Zhengfang academic-system client with Windows support. This document separates implemented behavior from planned features and acceptance work. Implementation does not imply compatibility with every school or production-device validation.

## Implemented

### Navigation and settings

The main destinations are Timetable, Courses, Grades, and Settings, with Timetable as the default. Timetable contains timetable and agenda views. Narrow windows use bottom navigation; wider windows use a sidebar and, where appropriate, split panes.

Settings has four subsections: Schools and accounts, Appearance, Timetable, and Data and application. Timetable import/update, term selection, local courses, calendar/period times, view preferences, hidden-entry restoration, saved timetables, and widget management are centralized in timetable settings. Personal events are managed in agenda. There is no separate import-information screen or selection-task destination.

### Schools and authentication

- Users supply school names and academic-system URLs, with configurable endpoint paths and a separate web-login address when needed. No school or allowlist is preconfigured.
- Password/captcha login, web login, and cookie import are supported. A verified school identity is required before treating a session as connected.
- Schools can be added, edited, selected, and removed; each school can have multiple accounts. Stable school IDs survive name/address edits.
- Saved sessions can be restored when valid. Optional password saving is distinct from session persistence. Connection changes invalidate old school sessions without deleting business data.
- Logout stops subsequent work for that account, clears saved login information, and retains offline data. Account/school removal also clears its local data and does not withdraw courses at the school.

### Timetable, calendar, and period times

- Prefer actual school term options; allow manual academic-year/term selection when recognition is unavailable. Teaching dates require the first week's Monday or a current-week correction supplied by the user.
- Preserve odd/even and discontinuous weeks, multiple time/location segments, and courses without fixed periods. School restrictions and malformed responses are not empty timetables.
- The weekly grid supports week browsing, search, details, and local edits. A week with no weekend arrangements uses five columns; otherwise it retains seven.
- Smart period-time planning generates morning/afternoon/evening sections per campus from start times, period counts, class/break lengths, and optional recurring long breaks. It previews and edits generated times; it is not a standalone grouping-only entry.
- Editing a period or break can shift later periods within the same section while preserving their existing lengths and gaps. Other sections retain independent start times. Overlaps must be corrected before saving; cross-day overflow is an explicit error rather than wrapping or clamping.
- Period-time edits are drafts with undo and restoration of school times. Applying a generated preview changes the draft; only saving calendar settings persists it. Timetable, agenda, and the widget consume the same effective times.
- Calendar and timetable settings are school/account/term-scoped. School refreshes do not overwrite local additions or calendar settings; stale editors cannot overwrite newer settings.

### Agenda and personal events

- Courses are projected for the chosen date using teaching weeks and campus period times. Agenda date selection is independent of the browsed timetable week.
- Complete times support clock-based morning/afternoon/evening grouping and course states. Incomplete times use period ordering and full period ranges rather than guessing time-of-day labels. Courses without periods remain distinguishable; there is no separate pending-arrangements area.
- Users can create, edit, and delete to-dos, activities, examinations, assignments, and other events with all-day or start/end times, location, and notes. To-dos and assignments support completion state.
- Events use the timetable database, are isolated by school/account, and persist across terms. They work for an existing account without an imported timetable. Clearing timetable data preserves events; account/school removal deletes them. Stale edits cannot recreate deleted events or overwrite newer versions.

### Grades

Published grades are retrieved and saved as complete snapshots. Term selection, search, sorting, and filtering operate on saved records. Details and reference statistics retain textual grades, zero scores, makeup exams, retakes, missing fields, and original school term information.

Missing values are not zero. Reference weighted GPA uses valid school GPA values and positive credits, discloses participation, and does not replace official cumulative GPA or convert letter grades. Failure filtering uses the school's explicit pass status, not a universal 60-point rule.

### Courses and enrollment

Available courses, teaching classes, selected courses, and operation history are shown in Courses. Search/filter controls use the saved current-round list; seat availability may require teaching-class detail retrieval. Unknown availability is distinct from zero, and segmented schedules retain corresponding locations.

Immediate enrollment and manually started seat watching share one executor. An operation captures its school, account, term, round, and teaching class at creation; switching the viewed account does not change it. Submission intent is saved before submission, and school-selected records determine success. Unknown outcomes require reconciliation before resubmission.

Stopping an operation prevents subsequent attempts; it cannot retract an already sent request and does not withdraw a course. Restart does not automatically submit again: interrupted operations require manual continuation or verification. History includes all accounts; clearing ended history preserves active, paused, and unresolved operations.

Android seat watching uses notification permission and a foreground service; Windows requires the application process to remain open. System interruptions must remain visible.

### Persistence and appearance

Timetables, grades, course snapshots, selected records, and operations are isolated by school/account with term/round scope where appropriate. Viewing saved data does not implicitly re-import it. Explicit updates preserve old data and timestamps when they fail. Newly selected rounds without a cache may need a query.

Appearance supports system, light, and dark modes across restarts, with Catppuccin Latte/Mocha colors and a Mauve accent. Local data settings show actual saved content and read failures.

### Android timetable widget

The home-screen widget is a read-only, offline projection of the selected timetable account and term, following application appearance. It uses the effective whole-term timetable, calendar, period times, and local adjustments; personal events and credentials are not included.

It adapts from course summaries to scrollable narrow/wide lists as size and font scale allow, focuses the current or next course, and opens the corresponding agenda date when tapped. Launcher grid allocation is launcher-dependent. Timetable/account/calendar/appearance changes synchronize the snapshot; removal waits for snapshot cleanup and reports failures.

System periodic updates and inexact course-boundary alarms can be delayed by power management. The widget is not a precise reminder service and is not available on Windows.

## Planned or awaiting acceptance

| Item | Status |
| --- | --- |
| Update checking and About-dialog GitHub action | Disabled UI placeholders; no implementation |
| ICS export and school examination-schedule retrieval | Not implemented; manually entered examination events already work |
| System course reminders, Live Updates/status-bar enhancements, and couple timetables | Not implemented; no cloud-sharing guarantee or acceptance claim |
| Real-school login, timetable, grades, and enrollment results | Need comparison against actual school records |
| Android multi-account persistence, process recovery, background behavior, widget launchers, and restart behavior | Need production-device acceptance |
| Windows minimize/sleep behavior during selection | Needs acceptance beyond source inspection |
| GitHub CI quality checks and tag-triggered Android/Windows release builds | Configured in `.github/workflows/`; requires GitHub Actions acceptance |
| Android release signing and application upgrades | Signing secrets and production-device acceptance still required |

These entries retain the product direction without presenting it as working functionality or a delivery commitment. See [development](development.md) for recording evidence.

## Out of scope

Scheduled auto-enrollment, a separate task page, activation, account quotas, signature penalties, cloud enrollment delegation, automatic course withdrawal, and cross-device synchronization are outside the current scope. Do not introduce them during unrelated maintenance.
