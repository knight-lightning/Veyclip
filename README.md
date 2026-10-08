# ShareX Mac

A native macOS 26+ capture utility inspired by [ShareX](https://github.com/ShareX/ShareX). Development version 0.1.0, written in Swift with SwiftUI, AppKit, and ScreenCaptureKit.

## Current source implementation

- Menu bar capture controls and a local thumbnail history with screenshot/video filters and filename search.
- All-display, monitor, window, region, light region, and transparent-background region screenshots; repeat last region during the current session; cursor toggle and 0–10 second delay.
- Scrolling capture with overlap matching, a 20-frame/50-megapixel limit, cancellation, and recovery PNGs. Select only moving content, excluding sticky headers and scrollbars; Accessibility permission is required for automatic scrolling.
- Auto-capture of a selected region with a configurable interval and count, up to 100 screenshots; Stop preserves saved captures.
- Screenshot editor with rectangles, ellipses, lines, arrows, freehand, text, speech bubbles, numbered steps, embedded images, emoji stickers, cursor stamps, highlight, eraser, blur, pixelate, magnify, and crop.
- ShareX-style highlight: full-opacity darken blending caps each RGB channel at the highlight color. Pure yellow preserves red/green and caps blue; overlapping highlights do not accumulate opacity. Each drawing tool remembers its own color during the editor session.
- Select/move/delete annotations, resize areas and inserted images using the bottom-right handle, edit text/bubbles by double-clicking, style controls, undo/redo, zoom, and pan.
- Nondestructive crop and annotation sidecars; the original PNG is preserved. Edited clipboard output and PNG/JPEG export.
- Region, display, and window MP4/H.264 recording at 30 fps; a three-second countdown, recording indicator, stop controls, and optional system audio/microphone.
- Silent GIF recording from region/monitor/window: 10 fps, up to 960 pixels on the longest edge, stops after 60 seconds and converts the finalized movie to a looping GIF. The MP4 recovery source is retained in InProgress.
- Configurable global hotkeys with duplicate validation; a selectable captures folder and after-capture settings.
- Persistent local history, Reveal in Finder, separate Remove from History and confirmed Move to Trash actions.
- Xcode app project, Swift package for tests, and a macOS build workflow.

**Validation status:** authored on Windows. Swift syntax, property-list/XML structure, project references, and build-script syntax have been checked locally. No macOS compilation or runtime validation has run yet. Nineteen Swift tests are included but have not been executed. Capture, transparency, effects, scrolling, and GIF conversion require the real-Mac checks in docs/MAC_VALIDATION.md before release.

## Build and run on your Mac

Install Xcode 26 or newer and finish its first-launch setup. The selected Xcode must include Swift 6.2 or newer because the pinned hotkey dependency requires it. Copy this whole project folder to your Mac.

Open `ShareXMac.xcodeproj`, choose the **ShareXMac** scheme and **My Mac**, then build and run. Xcode resolves KeyboardShortcuts 3.1.0 automatically; first builds require internet access.

Alternatively, from the project folder in Terminal:

```sh
swift test
bash scripts/build-macos.sh debug
open "dist/ShareX Mac.app"
```

Use the Xcode project or the bundled app for interactive capture. `swift run` does not launch the configured app bundle with its privacy descriptions.

The script produces a locally signed development app. Developer ID signing, hardened runtime, notarization, App Store packaging, and release distribution remain later work. The current native Xcode target is intentionally a nonsandboxed development target; sandbox support has not been validated.

## First launch

1. Click **Capture → Region** and grant macOS Screen Recording access when requested. If macOS asks to quit and reopen the app, do so.
2. Drag a region on one display. Press Escape to cancel. The editor opens after saving the original.
3. Choose a tool and draw on the image. Select an annotation to move or delete it. Double-click text with Select active to edit it.
4. Use **Copy** or **Save As…** for the edited result. Edits save automatically so you can reopen them from history.
5. Record a short region, then stop using the menu bar or recording hotkey. The video enters history only after successful finalization. Double-click it to play in the default video app.

Microphone access is requested only if microphone recording is enabled. Changing permissions may require reopening the app. Recording controls and the app's windows are excluded from display/region capture through the content filter; confirm this behavior on your Mac.

Transparent region captures windows intersecting the display against a clear background; desktop wallpaper is omitted, and actual transparency depends on the macOS compositor. All-display capture uses the highest connected display scale and preserves the display arrangement; displays are captured sequentially rather than at exactly the same instant. Light region uses the same capture output with a minimally dimmed selection overlay.

**Auto-capture** uses the interval/count in Settings and starts after region selection. **Scrolling Capture** scrolls the target application; animated content, sticky elements, or repeated patterns can prevent a confident match. Recovery frames remain in InProgress even after a successful stitch. A result that reaches the frame limit is explicitly labelled as limited. Opening GIFs uses your default external viewer.

## Default hotkeys

| Action | Shortcut |
| --- | --- |
| Capture region | Command + Option + Shift + R |
| Capture display | Command + Option + Shift + D |
| Capture window | Command + Option + Shift + W |
| Start / stop region recording | Command + Option + Shift + V |
| Repeat last region | Unassigned; set in Settings |
| Stop capture / active recording | Command + Option + Escape |
| All displays, light/transparent region, GIF, scrolling, auto-capture | Unassigned; set in Settings |

Change or clear these in **Settings → Hotkeys**. Some other applications or macOS services may reserve a combination; choose a different one if necessary. During capture selection and recording finalization, repeated commands are ignored.

## Local files

Library metadata, thumbnails, edits, and incomplete recordings live in `~/Library/Application Support/ShareXMac/`. Original screenshots/videos default to its `Captures` folder. Choose another output folder in Settings; existing history entries continue pointing to their original files.

Incomplete recordings are retained in `InProgress`; they are not listed as successful captures. A recording interrupted by a crash may be unplayable. Removing an item from history leaves its media intact. Moving it to Trash removes the media via macOS Trash.

## Development boundaries

Optional syntax checks on Windows (Python 3.10+):

```powershell
python -m pip install --target .validation-tools -r requirements-validation.txt
$env:PYTHONPATH = "$PWD\.validation-tools"
python scripts/check-source.py
```

These checks do not replace a Swift compiler or the Mac runtime tests.

This iteration covers the requested screenshot-editor toolbar and capture-menu modes. It is not full ShareX feature parity. Region resize before capture, saved last-region settings across launches, precise freehand hit testing, 60 fps, launch at login, in-app video playback, picker thumbnails, and accessibility polish remain follow-up work. Screenshot editing is implemented; video editing is deferred.

Uploads, OCR, custom workflows, and additional advanced effects remain later work. The future LLM + MCP idea for preparing Jira issues and attaching selected media is tracked in the roadmap; it has not been connected.

See [ROADMAP.md](ROADMAP.md) and [docs/MAC_VALIDATION.md](docs/MAC_VALIDATION.md) for the next development steps. See [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) for dependency attribution.
