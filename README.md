# Simple Hold Auto Clicker

A minimal Flutter + Android AccessibilityService app with only:
- Hold Time (seconds)
- Break Time (seconds)
- Floating overlay with icon-only Start and Stop controls

## Build
```bash
flutter pub get
flutter build apk --release
```

## Use
1. Install the APK.
2. Open the app and grant “Display over other apps” permission when prompted.
3. Enable Auto Clicker in Android Accessibility settings.
4. Set Hold Time and Break Time in seconds.
5. Enable Floating and drag the floating controls to a convenient position.
6. Tap Start to repeat the hold gesture; tap Stop to stop scheduling further gestures.

## Notes
- The default target is screen coordinate (540, 960). This is a fixed coordinate and may need adjustment for different screen sizes. This starter does not provide a separate target picker.
- Android may not guarantee cancellation of a gesture already dispatched when Stop is pressed.
