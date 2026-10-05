## Highlights

- Added silent startup update checks against GitHub releases, throttled to once every 24 hours, with a non-blocking notice for each new version and a badge on the Data-and-application settings entry until a manual check confirms the app is current.
- Added in-app updates on Android: the release APK downloads with progress through the GitHub mirror with automatic fallback to the official URL, then hands off to the system installer, including the "install unknown apps" permission flow. Download and installer failures are explicit and retryable, and the release page remains a fallback. Windows keeps browser-based downloads.

## Installation

- Android: download the APK and install it on an Android 13+ device.
- Windows: download the ZIP, extract the complete directory, and run `zfhelper.exe`.
