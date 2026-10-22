# Auto Clicker v2 — Flutter + GitHub Actions

## GitHub build
Push the repository to `main` and open Actions. Download the `auto-clicker-release-apk` artifact from a successful run.

## Features in this starter
- Single Click, Multiple Click, Hold.
- Draggable numbered target points over other apps.
- Floating `STOP` control intended to remain above other apps.
- Multiple mode: use `+` in the floating panel to add points.
- Hold: Hold Time and Hold Break Time; Infinity repeats until Stop.
- Accessibility Service is opt-in through Android Settings.

## Important limitations / safety
- This is an initial implementation and must be tested on the target Android device before use.
- Android may complete/cancel an in-flight gesture asynchronously. The floating STOP control stops future repeats immediately and requests best-effort cancellation; no third-party app can promise a universal instantaneous release on every Android version.
- Overlay permission and Accessibility Service must be enabled by the user.
- Point coordinates are screen pixels and may need repositioning after orientation or resolution changes.
