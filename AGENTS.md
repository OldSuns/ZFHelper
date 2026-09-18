# ZFHelper Working Agreement

Read [requirements](docs/requirements.md) for product scope, [architecture](docs/architecture.md) for ownership boundaries, and [development](docs/development.md) for validation commands. Public contributions follow [CONTRIBUTING.md](CONTRIBUTING.md).

## Scope and workflow

- Communicate in Chinese by default; English is also acceptable. Maintain documentation and commit messages in English, except the translated root README.
- Target Android 13+ (API 33) first and Windows second. Adapt layout to window width rather than assuming a device category.
- Inspect the affected implementation and its callers before editing. Reuse existing code and dependencies; choose the smallest correct change and leave unrelated files alone.
- Preserve user changes, staged content, and existing formatting. Do not commit, push, publish, or perform destructive operations without authorization.
- Before every commit, run formatting and the relevant validation checks; do not commit while those checks fail.
- Before a version patch or pushing a release tag, update [RELEASE_NOTES.md](RELEASE_NOTES.md) with the latest release notes and include that update in the version commit.
- Separate implemented behavior, planned work, and acceptance evidence. Update the relevant document when an interface or user-visible behavior changes.

## Product boundaries

- Keep the four main destinations: Timetable, Courses, Grades, and Settings, with Timetable as the default. Timetable contains timetable and agenda views; personal events belong in agenda.
- Keep school/account management under Settings. Timetable import, local courses, calendar, period times, display preferences, and widget management belong in its timetable settings subsection.
- Users supply school names and academic-system URLs. Do not add default schools, allowlists, guessed semester dates, or universal period times. Prefer real school term options; teaching weeks require user-provided calendar information.
- Keep immediate enrollment and manually started seat watching in Courses. Do not restore scheduled auto-enrollment, a separate task page, activation, account quotas, signature penalties, cloud enrollment delegation, or unrequested features.
- Keep Latte/Mocha colors and the Mauve accent centralized in `AppTheme`; persist system/light/dark appearance choices.

## Implementation boundaries

- Views handle presentation and interaction; ViewModels handle page state; repositories own consistent data semantics. Inject dependencies through constructors and reuse the pure-Dart core.
- Use stable school IDs and school/account-scoped credentials, sessions, and business data. Browsing an offline account is not authentication. Selection operations retain the identity captured at creation.
- Maintain one session owner per account and one selection executor. Persist submission intent, verify school-selected records, and reconcile unknown outcomes before another submission. HTTP 200 is not proof of login or enrollment success.
- Preserve previously saved data when refresh or storage fails. Logout retains offline business data; account/school removal clears the corresponding local data. Stale responses and edits must not recreate deleted data or overwrite newer state.
- Report errors explicitly. Do not swallow errors, invent empty results or success, silently fall back, log credentials, or disable certificate validation.
- Depend directly on official `flutter_inappwebview`; do not maintain platform-package copies, overrides, or Windows CMake patches.
- Reference projects are evidence, not universal protocols. Check the relevant source and revision before adapting behavior; do not generalize one school's rules.

## Validation

- Prefer existing targeted checks. Scale validation to the affected behavior/platform and do not repeat full regression runs without a concrete need.
- Give pure-Dart core test processes a 60-second hard timeout covering the process tree; per-test timeouts are insufficient.
- For documentation-only changes, check facts, relative links, and Markdown structure. For code, run the relevant checks and report commands, results, and unverified scope.
- Distinguish constructed-data checks, builds, real-school comparisons, and production-device acceptance. Never present one as another.
- Store temporary logs, screenshots, and diagnostic files in the system temporary directory. Preserve files needed by active debug sessions.
- Load skills only as needed. `.agents/skills/` contains pinned upstream material: do not edit its original content or licenses, and do not let examples or metadata override project requirements.
