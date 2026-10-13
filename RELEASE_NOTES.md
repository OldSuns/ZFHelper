# Highlights

- Improved course adjustments and course details: rescheduling and makeup lessons support an explicit target end period, switching from whole-day to per-course selection clears preselected courses, and secondary course information (code, class, credits, notes) is folded behind an expansion tile while teacher, campus, place, hours, weeks, time and period clock stay visible.
- Course colors are now stable and consistent: each course keeps the same color across the week grid, agenda, and course details, with distinct courses drawing from an expanded twelve-color palette before any reuse.
- Added an in-app browser entry for the school portal in Settings: it opens the portal home in an embedded WebView reusing the selected account's saved session cookies, with back/forward/reload controls and an editable address bar restricted to http(s). Portal cookies are isolated per account, and unsupported platforms show a notice instead of the view.
- Reworked the calendar and term pickers: term import and update actions moved into the term picker sheet, and the stock date picker was replaced by a bounded Monday picker with month quick selection, a half-year range, and text that scales with window width.
- Fixed session restoration on Zhengfang systems that answer stale AJAX requests with the non-standard HTTP status 901: the transport now accepts it and the login gateway maps it to session expiration, so a restored session falls back to password re-login instead of failing with a protocol error.
- Redesigned the period time generator: the weekday dropdown became wrapping chips and the form is grouped into basic info, schedule, and weeks cards; each period session can keep regular breaks, one fixed special break, or recurring breaks; the generator previews as parameters change, allows editing preview breaks, and warns when an automatic regeneration discards manual preview edits.

## Installation

- Android: download the APK and install it on an Android 13+ device.
- Windows: download the ZIP, extract the complete directory, and run `zfhelper.exe`.
