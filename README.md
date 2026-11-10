# Activity Monitor — Android 12 / Shizuku

- Package: `com.activity.monitor`
- Minimum Android: 12 (API 31)
- Compile SDK: 35
- Language/UI: Kotlin + Jetpack Compose
- Shizuku API: 13.1.5
- CI: GitHub Actions

## Features

- Permission categories: Camera, Microphone, Location, Gallery, Files.
- Counts apps requesting each permission category.
- Shows app icon, app label, package name, and whether each requested permission is granted.
- A shared **Show system app** checkbox filters system apps in every category.
- Shizuku connection and permission status.
- Manual diagnostic and optional ~4-second polling for Camera/Microphone.
- Diagnostic excerpts for troubleshooting.

## Important live-detection limitation

Android does not expose a universal public API that lets an ordinary app identify every other app currently using the camera or microphone. Shizuku gives the user-authorized shell identity, but diagnostic output differs between Android versions and OEM firmware.

This build intentionally avoids the earlier unsafe heuristic that matched a package name anywhere in a large `dumpsys` output plus a generic word such as "recording". It now reports a package only when it finds a package-scoped AppOps operation block with an explicit `running=true` or `active=true` flag. If Vivo's firmware formats AppOps differently, the result will be **Not identified** rather than a guessed app.

A granted permission is not proof of current sensor use. The diagnostic is best-effort, not a guarantee of real-time attribution. Compare results with Android's green privacy indicator.

## Shizuku setup

1. Install and start Shizuku using Wireless debugging on Android 12.
2. Open Activity Monitor and confirm Shizuku reports Running.
3. Tap **Grant Shizuku** and approve the permission.
4. Wait briefly for the UserService Binder connection.
5. Tap **Test now**, or enable automatic diagnostic polling.
6. Test with the stock Camera app and a microphone recording app separately.

If Shizuku restarts, reopen Activity Monitor or retry after Shizuku is running.

## Build with GitHub Actions

1. Extract this project.
2. Upload/replace the project files in your existing repository (keep the `.github/workflows/build.yml` path).
3. Push to `main` or `master`, or run the workflow manually from Actions.
4. Download the `Activity-Monitor-debug-apk` artifact after the workflow succeeds.

The workflow installs Android SDK 35, uses JDK 17 and Gradle 8.9, then runs `assembleDebug`.

## Security

The UserService allows only these read-only commands:
- `dumpsys appops`
- `dumpsys media.camera`
- `dumpsys audio`

It does not record audio/video, change permissions, or read other apps' private files.

## Build verification status

This ZIP contains source code and CI configuration. It has not been executed by GitHub Actions from this environment; the first CI run is still required to verify compilation on GitHub's runner.


## GitHub Actions SDK setup note

The workflow uses the Android SDK command-line tools already provisioned on
GitHub-hosted Ubuntu runners and installs only `platforms;android-35` and
`build-tools;35.0.0`. It deliberately does not request the obsolete SDK
package named `tools`, which causes `Failed to find package 'tools'` on
current SDK repositories.
