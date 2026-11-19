# Highlights

- Fixed white course cards and countdown badges in the home-screen widget by replacing white drawable backgrounds and runtime tinting with fixed Catppuccin Mocha resources.
- Removed legacy appearance selection, appearance storage, and dual-palette widget code. The app and widget retain their dark colors regardless of the system theme or saved appearance preferences.
- Preserved offline courses from older widget snapshots while ignoring their obsolete theme metadata. Timetable synchronization no longer depends on reading appearance settings.

## Installation

- Android 13+: install the signed APK over the previous signed LXY edition, or use its in-app update checker. Version 0.2.5 uses Android build number 16 and preserves the existing application identity and local data locations; do not uninstall the existing app first.
- LXY checks only LXY releases. This channel distributes signed APKs only and does not take GitHub's Latest designation.
