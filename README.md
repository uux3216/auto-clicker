# Activity Monitor (Android 12 starter)

A Kotlin Android starter project that builds a debug APK through GitHub Actions.

## What this version does

- Requests Android Usage Access and polls usage events to estimate the current foreground app.
- Lists installed apps that declare selected permissions (Camera, Microphone, Location, and shared media/storage permissions).
- Shows whether Android reports each listed runtime permission as granted.

## Important Android limitation

This app **does not** provide true live monitoring of other apps' camera, microphone, location, or individual file reads/writes.

Android 12 does not expose a general public third-party API that lets an ordinary app observe every other app's live permission-use events. Usage Access identifies foreground-app activity; it is not proof that an app is using a particular sensor or file.

The permission inventory is also not an access log. A permission being granted does not mean the app is currently using it.

## Build with GitHub Actions

1. Create or open your existing GitHub repository.
2. Copy the contents of this project into the repository root.
3. Commit and push to `main` (or `master`).
4. Open the repository's **Actions** tab.
5. Open **Build Activity Monitor APK** and download the `Activity-Monitor-debug-apk` artifact after the workflow succeeds.

You can also run the workflow manually with **Run workflow**.

## Test on Android 12

1. Install `app-debug.apk`.
2. Open Activity Monitor.
3. Tap **Grant Usage Access**.
4. Enable Usage Access for Activity Monitor in Android Settings.
5. Return to the app. The foreground-app field refreshes approximately every two seconds.

## Project configuration

- Package: `com.activity.monitor`
- Min SDK: 31 (Android 12)
- Compile SDK: 35
- Target SDK: 32
- Kotlin: 2.0.21
- Android Gradle Plugin: 8.7.3
- Gradle: 8.9
- JDK: 17

## Next development step

If true live sensor-use events are a hard requirement, investigate a separately authorized privileged/system-level solution for the target device. Do not treat Accessibility Service or Usage Access as a substitute for system permission-use telemetry.
