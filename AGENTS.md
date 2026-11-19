# ZFHelper Working Agreement

Read [requirements](docs/requirements.md) for product scope, [architecture](docs/architecture.md) for ownership boundaries, and [development](docs/development.md) for validation commands. Public contributions follow [CONTRIBUTING.md](CONTRIBUTING.md).

## Scope and workflow

- Communicate in Chinese by default; English is also acceptable. Maintain documentation and commit messages in English, except the translated root README.
- LXY targets Android 13+ (API 33) and distributes APKs only. Preserve shared Windows source when synchronizing upstream, but do not add Windows or AAB builds to LXY workflows. Adapt layout to window width rather than assuming a device category.
- Inspect the affected implementation and its callers before editing. Reuse existing code and dependencies; choose the smallest correct change and leave unrelated files alone.
- Shared development stays on `dev`; approved shared changes can reach both `main` and `LXY` through separate pull requests. Select commits when only part of `dev` is needed. LXY-specific changes target `LXY` and must not be merged wholesale into the ordinary edition. Stable `vX.Y.Z` tags belong to `main`, pre-release `vX.Y.Z-stage.N` tags to `dev`, and `lxy-vX.Y.Z` tags to `LXY`; release workflows guard commit ancestry.
- Before merging a pull request, get two separate explicit confirmations from the user: one to proceed with the merge plan, then a second immediately before merging after checks and reviews are complete. Prefer GitHub's **Squash and merge** method unless the user or repository constraints require otherwise.
- Ordinary stable releases use `vX.Y.Z` and `X.Y.Z+build`; `dev` pre-releases use `vX.Y.Z-beta.N` (also `rc.N`/`dev.N`) and `X.Y.Z-stage.N+build`. LXY uses `lxy-vX.Y.Z` and `X.Y.Z+build`, with its own increasing X.Y.Z sequence. Build numbers must exceed every published build across all three channels, because they share one Android application ID. Check all published tags before each release; a branch-local version alone is insufficient.
- Prepare ordinary stable version commits on `dev` before merging to `main`. Prepare LXY version bumps and RELEASE_NOTES.md on `LXY`; do not copy ordinary release metadata over LXY metadata during synchronization.
- Preserve user changes, staged content, and existing formatting. Do not commit, push, publish, or perform destructive operations without authorization.
- Before every commit, run formatting and the relevant validation checks; do not commit while those checks fail.
- Before a version patch or pushing a release tag, update [RELEASE_NOTES.md](RELEASE_NOTES.md) with only the latest release notes and include that update in the version commit; do not append a `Previous release` section.
- Never place real school URLs, personal information, credentials, cookies, or other identifying data in source code, tests, fixtures, documentation, or committed logs; use clearly fictional domains and synthetic values instead.
- Separate implemented behavior, planned work, and acceptance evidence. Update the relevant document when an interface or user-visible behavior changes.

## Product boundaries

### LXY edition invariants

- The display name is `流星雨课表`; the installed application ID remains `dev.zfhelper.app`. Keep the existing release signing certificate, database paths, secure-storage options/keys, and native storage identifiers so a signed LXY APK can replace the ordinary edition while retaining data. Never solve an upgrade by uninstalling or clearing data.
- Keep `lib/app/app_identity.dart` fixed to `ReleaseChannel.lxy`. LXY checks only published, non-draft, non-prerelease `lxy-vX.Y.Z` releases, resolves its current release notes within that channel, and accepts APK assets from the matching tag. A missing or failed LXY lookup must not fall back to ordinary releases.
- Ordinary clients continue using their stable channel. Every LXY Release must explicitly use `--latest=false`; do not mark it Latest. Separate update-check timestamps and notification state by channel while retaining shared business data and credentials.
- Pull requests and branch pushes run quality checks only. APK packaging/publication runs only for LXY release tags after quality checks pass. Require all existing Android signing secrets; never publish an unsigned LXY fallback. Attach the signed APK and SHA-256 checksum only.
- Synchronizing `dev` must preserve LXY identity, version, release notes, update channel, workflow rules, and this working agreement. Review shared data-schema changes for upgrade compatibility before adopting them. Returning to the ordinary edition also requires a compatible schema, matching signature, and higher build number; an older APK is not a supported rollback.
- This is an edition intended for one recipient, not an access-control system. Release visibility follows repository visibility. Do not embed personal or school-identifying data for the recipient.

### Shared product boundaries

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
