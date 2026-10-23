# Hold Clicker — Debug Build Source

This archive contains the project files for the draggable-target Hold Clicker plus diagnostic logs.

## Build
```bash
flutter pub get
flutter build apk --release
```
Debug logs are also emitted in release builds, but Android may filter them depending on log settings.

## Capture logs in Termux / ADB
With ADB available:
```bash
adb logcat -c
adb logcat -v time -s HoldClickerDebug:I HoldClickerDebug:D HoldClickerDebug:E '*:S'
```
Start the app, enable Accessibility, enable floating controls, drag the blue target point, tap Start, wait a few seconds, then tap Stop. Copy the logs that appear.

If using the phone without ADB, use an on-device Logcat viewer and filter for `HoldClickerDebug`.

## Log meanings
- `ACCESSIBILITY_CONNECTED`: service connected.
- `TARGET_DRAGGED` / `TARGET_X_UPDATED` / `TARGET_Y_UPDATED`: target coordinates update.
- `GESTURE_PREPARE`: coordinates, screen dimensions and hold duration.
- `DISPATCH_RESULT accepted=true`: Android accepted the gesture request; this alone does not prove a visible tap happened.
- `GESTURE_COMPLETED`: Android reported completion.
- `GESTURE_CANCELLED`, `DISPATCH_REJECTED`, `DISPATCH_EXCEPTION`: gesture failed/cancelled.
- `FLOATING_START_FAILED`: Accessibility service is not connected.

## Important
Android does not guarantee that a gesture already dispatched can be force-cancelled immediately. Overlay coordinates can also differ from accessibility display coordinates on some devices; compare `TARGET_DRAGGED` with `GESTURE_PREPARE` logs to diagnose coordinate offsets.

## Floating close button
The third floating control is an X/close icon. Tapping it logs `FLOATING_CLOSE_TAPPED`, stops future hold cycles, and destroys the overlay service so all floating controls disappear. Re-enable Floating from the app to show them again.

## On-screen diagnostics (no computer needed)
Open the app and scroll to **Live Diagnostics**. It polls the Android side every 0.7 seconds and shows current status, last event, Accessibility connection, overlay state, running state, target coordinates, dispatch result, and last error. Tap Refresh if needed.
If `Accessibility` says `NOT CONNECTED`, enable the service in Android Settings. If target X/Y stays -1, drag the blue target point. If dispatch result is false or Last error shows an exception, share a screenshot of this panel.
