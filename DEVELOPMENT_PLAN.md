# ShareX-style capture app for macOS — development plan

Status: implementation started 8 October 2026. The first source build covers capture, recording, screenshot annotation, history, and hotkeys; macOS compilation and runtime validation are pending. See ROADMAP.md for current follow-up work. The estimates and architecture below preserve the original planning baseline.

## 1. Product goal and assumptions

Build a native Mac utility that stays in the menu bar and makes this workflow fast:

**Hotkey → select screen content → capture → annotate → copy or save.**

For recording: **Hotkey → select source → countdown → record → stop → preview and save.**

Use the supplied ShareX screenshots as visual references for thumbnail history, filenames, and context-menu actions. Their menu contents are reference material, not additional feature requirements.

Confirmed test environment: the user has macOS 26 or newer. Proposed first-release deployment target: macOS 26+, with earlier macOS support deferred unless requested. The Mac model and processor are not yet specified; identify these during the foundation milestone and only claim hardware compatibility after testing.

Confirmed first-release boundary: annotation tools apply to screenshots only. Videos support capture, playback, and saving. Video annotation is a possible later extension, excluded from the first-release estimate.

## 2. First-release features

| Area | Included behavior |
| --- | --- |
| Screenshots | Capture a display, window, or rectangular region; repeat last region; Escape cancels; optional cursor and capture delay. |
| Recordings | Record a display, window, or region on one display; countdown, elapsed time, stop button and global stop shortcut; MP4/H.264 output; 30 fps default and optional 60 fps subject to validation. |
| Audio | Independent system-audio and microphone switches; clear microphone permission flow; silent recording works without microphone access. |
| Screenshot editor | Text, crop, translucent highlighting, arrows, lines, and freehand drawing; color, thickness, opacity, and text-size controls where relevant. |
| Editing essentials | Select, move, resize, and delete annotations; undo/redo; zoom and pan; preserve the original and reopen editable annotations. |
| Export | Copy the rendered image to the clipboard; save PNG or JPEG; select output folder; collision-safe timestamp filenames. Recordings save as files. |
| History | Local thumbnail grid with screenshots/videos filter, date and filename, preview, edit, copy, reveal in Finder, and explicit Move to Trash. |
| Hotkeys | Assign, clear, and reset shortcuts for region/window/display capture, repeat region, start/stop recording, and open history. Persist across launches. |
| Settings | Capture behavior, output folder, after-capture action, recording/audio settings, hotkeys, and optional launch at login. |

Defer uploads, cloud accounts, OCR, scrolling capture, GIF export, automation chains, advanced effects, recording pause/resume, and HDR workflows. Cross-display stitched regions are also deferred: users can capture any connected display, but each region belongs to one display in version 1.

### Future idea: AI-assisted issue attachments

Explore an optional LLM + MCP integration that can take a completed screenshot or recording, prepare a concise issue description from user-provided context, and attach the selected media to a Jira issue or another work-tracking service. This must remain opt-in: the user selects the destination and approves the final content and upload. Do not build or connect this integration during the first release.

## 3. Interface direction

- Menu bar: capture screenshot, record video, repeat region, recent captures, settings, and quit. Recording shows a conspicuous active state and stop control.
- History window: compact sidebar for All Captures, Screenshots, Videos, and Settings; thumbnail grid; clear New Capture and Record actions. Follow native light/dark appearance.
- Selection overlay: dimmed background, region dimensions, visible selection handles, and Escape to cancel. Hide capture controls from the resulting image or recording.
- Editor: large canvas with a compact tool strip and contextual styling controls; Copy and Save always easy to reach.
- After capture: configurable Open Editor, Copy, Save, or Copy and Save. Saving a capture must not depend on the user finishing an edit.

## 4. Technical design

Use Swift and SwiftUI for the application, history, and settings, with AppKit for selection overlays, window behavior, and the annotation canvas. Use Core Graphics for consistent rendering of annotations and exports.

Use ScreenCaptureKit for display/window capture and streaming, SCScreenshotManager for still images, and SCRecordingOutput for initial recording-to-file support. Apple documents screen, system-audio, microphone capture, and direct file recording in its [ScreenCaptureKit session](https://developer.apple.com/videos/play/wwdc2024/10088/). Avoid beta-only APIs in the first release.

Evaluate the [KeyboardShortcuts package](https://github.com/sindresorhus/KeyboardShortcuts) for configurable global shortcuts. Its documented design supports sandboxed Mac apps without extra permission dialogs. Pin the selected dependency version. Detect internal duplicates and known reserved combinations, report registration failures, and avoid promising detection of every shortcut used by another app.

Suggested module boundaries:

- AppCoordinator: menu actions, application lifecycle, and shared capture commands.
- CaptureService and SelectionController: source selection, permissions, screenshot capture, and screen-coordinate conversion.
- RecordingController: explicit idle/selecting/countdown/recording/stopping/failed states; audio configuration; finalization and error handling.
- EditorDocument and AnnotationRenderer: original image, crop rectangle, ordered annotation objects, undo history, and export.
- CaptureLibrary: metadata and thumbnails indexed with SwiftData; media and versioned annotation sidecars stored as files.
- HotkeyService and SettingsStore: route shortcuts to the same commands used by menus; persist preferences.

Store annotation coordinates relative to the original image, independent of canvas zoom. Keep crop nondestructive and apply it when rendering. Use the same rendering logic for preview and export to prevent mismatched placement or text.

Write files to a temporary location and publish them to history after successful finalization. Do not label a recording saved until the recording completion callback succeeds. On failure, retain recoverable material where available and explain the result; do not promise every interrupted MP4 is recoverable.

## 5. Implementation milestones

Estimates assume one experienced macOS developer working full time with a Mac available from the start. They are planning ranges, not delivery commitments.

| Phase | Work | Completion check | Estimate |
| --- | --- | --- | --- |
| 0. Validate foundation | Create app target; test permissions, screenshot API, region coordinates, global hotkey, and short screen/system-audio/mic recording. | On a real Mac, a hotkey saves a correctly scaled region and a recording plays with intended audio. | 3–5 days |
| 1. Screenshot workflow | Menu bar commands, selection overlay, display/window/region capture, last region, clipboard, save settings, and a minimal recent-captures list. | Capture works with another app focused, on either connected display; cancellation leaves no unwanted capture. | 5–7 days |
| 2. Screenshot editor | Annotation document, all six requested tools, selection and styling, undo/redo, crop, zoom, and export. | Reopen an edit; manipulate annotations; exported image matches the editor at native resolution. | 8–12 days |
| 3. Recording workflow | Source selection, countdown, audio switches, active indicator, stop command, preview, and MP4 finalization. | A 30-minute reference recording plays correctly with no obvious audio drift or unbounded memory growth. | 6–9 days |
| 4. History and preferences | Thumbnail grid, image/video filters, file actions, full shortcut settings, persistence, launch at login, and missing-file handling. | Captures and preferences survive restart; invalid shortcuts have useful feedback; removing history is distinct from deleting media. | 4–6 days |
| 5. Beta and release | Compatibility and interruption testing, performance fixes, accessibility, signing, notarization, and distributable package. | A clean Mac can install, grant permissions, capture, annotate, copy, record, stop, and reopen saved results. | 6–10 days |

Total: approximately 32–49 working days, or 7–10 weeks before contingency; reserve roughly 8–12 calendar weeks for a dependable first release.

Ship a screenshot-only internal build after phase 2 and a feature-complete internal build after phase 4. Release planning assumes a directly distributed signed and notarized app; an App Store launch is a separate distribution decision.

## 6. Validation and release gates

Automated tests should cover coordinate transforms at different display scales and origins, crop/annotation rendering, undo/redo, document persistence, duplicate shortcuts, and recording state transitions. Use a small set of representative render comparisons to catch export regressions.

Real-Mac testing must cover:

- Retina and non-Retina displays, mixed scaling, negative display origins, fullscreen apps, Spaces, and display disconnection.
- Permission denied, granted, and revoked; microphone disabled; permission recovery without unexplained blank output.
- Latin and Cyrillic text and keyboard layouts, long text, drawing near crop boundaries, and repeated editing/export.
- System audio only, microphone only, both, and neither; audio/video synchronization and device changes.
- Rapid repeated hotkeys, capture during recording, stopping twice, sleep/wake, quitting during recording, low disk space, and unwritable output folders.
- No capture overlay, app editor, or recording controls accidentally appearing in output where exclusions are intended.
- Stable resource use during long recordings and correctly released streams after stop or error.

Performance targets should be measured in phase 0 on named hardware and enforced later. Optimize for a responsive selection overlay and fast screenshot-to-editor flow before adding effects or animation.

The current workspace is on Windows. Source preparation and planning can happen here, but the macOS app must be built and exercised with Xcode on a Mac. A macOS CI runner can support builds and tests; interactive capture, permissions, displays, and global hotkeys still need a real logged-in Mac session.

## 7. Optional later video-editing extension

Add a distinct milestone after recording: trim start/end, fixed crop, and text/arrows/lines/highlights/freehand overlays with explicit start and end times. Reuse annotation data and drawing geometry, while adding a timeline, preview composition, and an AVFoundation export pipeline that preserves audio synchronization.

Estimate this extension at an additional 3–5 weeks for basic timed annotations and export, followed by validation. Animated annotations, tracking, live drawing during recording, and a multitrack video editor require separate scope. This extension is excluded from the confirmed first-release scope.

## 8. First development task

Validate one complete path on the target Mac: **global hotkey → select region → save native-resolution PNG → open preview**, plus one short MP4 with system audio and microphone. This resolves the highest-risk platform questions before investing in the full editor and history interface.

Additional platform reference: [Apple's macOS capture sample](https://developer.apple.com/documentation/screencapturekit/capturing-screen-content-in-macos).
