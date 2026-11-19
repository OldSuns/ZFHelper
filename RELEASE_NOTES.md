# Highlights

- Pin compatible Android JNI dependencies to address the application-data directory initialization failure observed in the previous test release.
- CI and release builds now restore dependencies from the source recorded in the lockfiles and enforce their locked versions. Release builds reuse those restored dependencies to prevent dependency drift.

## Installation

- Android: download the APK and install it on an Android 13+ device.
- Windows: download the ZIP, extract the complete directory, and run `zfhelper.exe`.
