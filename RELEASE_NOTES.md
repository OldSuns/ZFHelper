# Highlights

- Improved course adjustments and course details: rescheduling and makeup lessons support an explicit target end period, switching from whole-day to per-course selection clears preselected courses, and secondary course information (code, class, credits, notes) is folded behind an expansion tile while teacher, campus, place, hours, weeks, time and period clock stay visible.
- Reworked the calendar and term pickers: term import and update actions moved into the term picker sheet, and the stock date picker was replaced by a bounded Monday picker with month quick selection, a half-year range, and text that scales with window width.
- Fixed session restoration on Zhengfang systems that answer stale AJAX requests with the non-standard HTTP status 901: the transport now accepts it and the login gateway maps it to session expiration, so a restored session falls back to password re-login instead of failing with a protocol error.
- Course colors are now stable and consistent: each course keeps the same color across the week grid, agenda, and course details, with distinct courses drawing from an expanded twelve-color palette before any reuse.

## Installation

- Android: download the APK and install it on an Android 13+ device.
- Windows: download the ZIP, extract the complete directory, and run `zfhelper.exe`.
