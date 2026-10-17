# Glissando

A native macOS menu bar app for OpenBox-style window movement and resizing. Requires macOS 13 or later.

- **Option + left drag:** move the window under the pointer, starting anywhere inside it.
- **Option + right drag:** resize from the nearest corner.
- **Esc while dragging:** restore the original position and size.
- Normal clicks keep working. Releasing Option first does not leak the mouse release into the application underneath.

Change the modifier to Control or Command, or pause the utility, from its menu bar icon. Option avoids the Control-click screenshot shortcut in Walkie Talkie.

## Build and run

Requires Xcode Command Line Tools with Swift 5.9 or later. No external dependencies.

```sh
cd /Users/nicolas/dev/glissando
swift test
./build.sh
open dist/Glissando.app
```

Use **Open Accessibility Settings…** in the guide or menu, then enable **Glissando** under **System Settings → Privacy & Security → Accessibility**. If needed, click **+** and choose the built app at `/Users/nicolas/dev/glissando/dist/Glissando.app`. The app automatically starts its listener after permission is granted. No Screen Recording or microphone permission is needed.

Use **Open Test Window** from the menu to try both gestures and see the window's live size. The app stays in the menu bar when you close its guide or test window. Use **Quit Glissando** to exit.

## Signing

The build script uses an available Apple Development or Developer ID Application identity. Override it with `SIGNING_IDENTITY='identity name or hash' ./build.sh`. A stable identity helps preserve macOS Accessibility authorization across rebuilds. Without an identity, the script falls back to ad hoc signing and prints a warning. This local development build is not a notarized distribution package.

The original internal bundle identifier `ch.nicolas.WindowDrag` is retained so existing Accessibility grants and preferences survive the rename. All visible names and build products use Glissando.

Quit Glissando before rebuilding. The script refuses to replace a running bundle. Nothing is installed in `/Applications` automatically.

## Behavior and limits

- Targets the visible window under the pointer, including background windows; does not switch focus or invoke clicks on its controls.
- Supports monitors to the left of or above the main monitor using global screen coordinates.
- Fixed-size windows, fullscreen windows, and apps that do not expose movable/resizable Accessibility windows may refuse the operation. Some apps enforce their own minimum sizes or keep windows inside screen bounds.
- Uses the nearest corner for right-drag resizing. Window size is bounded, and application-specific minimum sizes are respected where reported by Accessibility.
- Cross-process Accessibility requests run on a worker queue. Mouse movement is coalesced so a slow app does not build a backlog of input events.
- Input callbacks use a recent window snapshot collected on a separate worker. If the snapshot is unavailable or stale, the click passes through normally.
- If macOS disables the input listener, it stays stopped until you toggle Enable Glissando off and on. It never automatically re-enables a timed-out tap.
- Accessibility work for Glissando's own windows runs on the main thread; other applications remain on the worker queue.
- Preferences are stored locally in the app's defaults. Lifecycle and error diagnostics use the macOS unified log (subsystem `ch.nicolas.WindowDrag`); mouse coordinates and keystrokes are not logged. There is no network code, capture, or recording.

Built on Apple's [Accessibility window APIs](https://developer.apple.com/documentation/applicationservices/1462077-axuielementcopyelementatposition) and [Quartz event taps](https://developer.apple.com/documentation/coregraphics/cgevent/tapcreate(tap:place:options:eventsofinterest:callback:userinfo:)).
