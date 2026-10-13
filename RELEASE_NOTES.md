# Highlights

- Added an in-app browser entry for the school portal in Settings: it opens the portal home in an embedded WebView reusing the selected account's saved session cookies, with back/forward/reload controls and an editable address bar restricted to http(s). Portal cookies are isolated per account, and unsupported platforms show a notice instead of the view.
- Course colors are now stable and consistent: each course keeps the same color across the week grid, agenda, and course details, with distinct courses drawing from an expanded twelve-color palette before any reuse.
- Course details align expanded secondary fields with the other fields, and the calendar school selector includes campuses found in timetable entries while keeping the generic times as the default.
- Redesigned the period time generator: the weekday dropdown became wrapping chips and the form is grouped into basic info, schedule, and weeks cards; each period session can keep regular breaks, one fixed special break, or recurring breaks; the generator previews as parameters change, allows editing preview breaks, and warns when an automatic regeneration discards manual preview edits.
- Added Android Live Updates: Dynamic Island-style live course reminders with a dedicated settings page organized into reminders, display style and preview, system permissions, and current status sections. The capsule shows the course name and location, with a style setting to switch layouts; changing it republishes active reminders immediately.

## Installation

- Android: download the APK and install it on an Android 13+ device.
- Windows: download the ZIP, extract the complete directory, and run `zfhelper.exe`.
