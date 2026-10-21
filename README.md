# Auto Clicker — Flutter + GitHub Actions starter

## Build APK on GitHub
1. Create a new GitHub repository.
2. Upload the contents of this ZIP to the repository root (not the ZIP itself).
3. Commit to `main` (or `master`) or open **Actions → Build Auto Clicker APK → Run workflow**.
4. Open the completed workflow run and download the `auto-clicker-release-apk` artifact.

## Important current limitations
- This is a starter scaffold, not a production-ready auto clicker.
- Multiple points currently use screen X/Y coordinate entry. A draggable on-screen point picker and floating control overlay are not implemented yet.
- Gesture coordinates depend on the device resolution and screen orientation.
- Android Accessibility Service must be explicitly enabled by the user in Settings.
- Stop requests prevent further repeats, but Android does not expose a universal public API to force-release every in-flight gesture. Verify behavior on the target Android version.
- Review and test the generated Android project before distributing the APK. Use the accessibility capability only with the device owner's consent and in accordance with each app's rules.
