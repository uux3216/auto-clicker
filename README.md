# Activity Monitor — Shizuku diagnostic build

Package: `com.activity.monitor`  
Target: Android 12+ (minSdk 31, targetSdk 32)  
Build: Kotlin + Jetpack Compose + GitHub Actions  
Shizuku API: 13.1.5

## Important limitation

This build uses a Shizuku UserService (instead of the private/deprecated `Shizuku.newProcess()` API) and is a **best-effort diagnostic prototype**, not a guaranteed live sensor-use detector. Android does not provide ordinary third-party apps with a universal API to identify every other app using Camera or Microphone. Shizuku provides user-authorized shell access, but `dumpsys appops`, `dumpsys media.camera`, and `dumpsys audio` output varies by Android build and OEM. Vivo firmware may omit or redact package attribution.

The app runs only three allowlisted, read-only diagnostic commands through its UserService. It deliberately labels any inferred package as **Possible active client** and does not claim certainty. A permission being granted is not proof that the sensor is currently active. It may return "Not identified" even while Android's green privacy indicator is visible.

## Shizuku setup on Vivo / Android 12

1. Install Shizuku from its official distribution channel.
2. Enable Developer options and Wireless debugging.
3. Start Shizuku using Wireless debugging / pairing instructions in the Shizuku app.
4. Open Activity Monitor and confirm Shizuku says "Running".
5. Tap "Grant Shizuku" and approve the request in Shizuku Manager.
6. Tap "Test now". Optionally enable Auto diagnostic polling.
7. Test in a controlled way: first with Camera closed, then open the stock Camera app, then repeat with a microphone recording app.
8. Compare the diagnostics and share the diagnostic excerpts if package attribution is missing.

Keep Shizuku running while testing. On some Vivo devices, battery/background restrictions may stop Shizuku; whitelist it from battery optimization if necessary.

## What the app shows

- Camera, Microphone, Location, Gallery and Files tabs.
- App icon, app label, package name, and declared permission grant status.
- Show system app checkbox.
- Shizuku service and permission status.
- Manual and optional 4-second diagnostic polling.
- Camera/audio diagnostic excerpts for troubleshooting.

## GitHub Actions

Copy the repository contents to your existing repository and push to `main` or `master`. The workflow builds `app-debug.apk` and uploads it as an artifact.

## Security

The app only runs read-only diagnostic shell commands. It does not record audio/video, capture files, change other apps' permissions, or silently access sensors.
