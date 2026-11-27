<!--
SPDX-FileCopyrightText: 2026 Grayson Adams

SPDX-License-Identifier: AGPL-3.0-or-later
-->

# Android release builds

`seam-build.ps1` builds Seam's Android release on the Windows side, signed with one of the two
keys in `op://Production/seam-signing`:

| Mode | Output | Key | 1Password fields |
|---|---|---|---|
| `bundle` | `build/app/outputs/bundle/release/app-release.aab`, for Play | upload key, alias `upload` | `UPLOAD_KEYSTORE_B64`, `UPLOAD_KEYSTORE_PASSWORD` |
| `phone` | `build/app/outputs/flutter-apk/app-release.apk`, arm64 only | app signing key, alias `seam` | `APP_SIGNING_KEYSTORE_B64`, `APP_SIGNING_KEYSTORE_PASSWORD` |

A `phone` APK carries the same signature as the APKs Play delivers, so it installs over the Play
build of `dev.threeonetwo.seam` (and the other way round) with the login and data kept. A bundle
signed with the app signing key would be refused by Play, and `android/app/build.gradle.kts` stops
a build that is given both keys or a bundle given the app signing key.

## The loop

The key reaches the script only as environment variables of a sandbroker call, which the script
decodes into a temporary folder and deletes when the build ends (the log says `keydir removed`).
From WSL, inside a `sandbroker-production` `run` call that maps `SEAM_KS_B64` and
`SEAM_KS_PASSWORD` to the fields of the mode:

    export SEAM_KS_B64 SEAM_KS_PASSWORD
    WSLENV=SEAM_KS_B64/w:SEAM_KS_PASSWORD/w setsid nohup powershell.exe -NoProfile \
      -ExecutionPolicy Bypass -File 'C:\src\<worktree>\tools\release\seam-build.ps1' \
      -Mode phone -VersionCode <n> > /dev/null 2>&1 &

The build runs detached and writes to `%TEMP%\seam-build.log` (`-Log` to change it), which ends
with `flutter rc=`, the keydir line and `DONE`. Install a phone APK with `adb install -r`.

## versionCode

One counter for every build that leaves the machine, bundle or phone APK, starting at 3582 (3581
is the first Play upload). The Seam session owns it: take the next number from it, never reuse
one, never go lower. Android refuses to install a lower versionCode over a higher one, and Play
refuses a bundle whose versionCode it has seen. `-VersionCode` overrides the build number in
`pubspec.yaml`.
