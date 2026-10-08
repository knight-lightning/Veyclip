# Development roadmap

Started 8 October 2026. Target: macOS 26+. The source foundation is present; runtime readiness depends on the first real-Mac build and the acceptance checks below.

## Next milestone: validate on the Mac

- [ ] Build the Xcode project and run the Swift tests; fix any compiler/API issues.
- [ ] Verify permissions, display/window/region selection, and a global hotkey with another app focused.
- [ ] Verify correct Retina resolution and selection on a second display with a negative global origin.
- [ ] Confirm original image orientation, crop/annotation alignment, and clipboard/export output.
- [ ] Record 30 seconds with system audio, microphone, both, and neither; check playback and synchronization.
- [ ] Confirm recording finalization, external macOS Stop, failure reporting, and Stop and Quit.
- [ ] Validate all-display layout, transparent-region alpha, light overlay, delay and cancellation.
- [ ] Validate all editor tools, effect/crop alignment, image resize and version-one edit compatibility.
- [ ] Validate GIF encoding/playback/automatic stop, auto-capture cancellation, and scrolling with recovery frames.

## Source foundation implemented, awaiting acceptance

ShareX-style capture menu including all displays, monitor/window, region variants, last region, delay/cursor options, auto-capture, scrolling, and MP4/GIF recording; original PNG saving; local history; 18 editor tools including full-opacity darken highlighting, shapes, bubbles, numbered steps, images/stickers/cursor, eraser, blur/pixelate/magnify, and nondestructive crop; selection/move/delete/area resize; text editing; styling; undo/redo; copy/export; shortcut mapping; folder selection; Mac build project and scripts.

## Complete first-release polish

- Region selection resizing and persistent repeat-last-region.
- Endpoint handles for lines/arrows, proportional image resizing, and accurate hit testing for diagonal lines/freehand paths.
- Efficient incremental editor redraw for large screenshots; history thumbnails that reflect saved edits.
- 60 fps after performance validation and a floating recording control.
- Scrolling recovery browsing, fixed-header detection, improved ambiguous-pattern matching, and GIF size/quality controls.
- Launch-at-login preference, optional native video preview, and better window/display picker previews.
- Full keyboard accessibility, localized UI including Russian, and missing-file recovery.
- Long recordings, sleep/wake, display/audio-device changes, disk-full behavior, and repeated-hotkey tests.
- Developer ID signing, hardened runtime, notarization, and a release package.

## Ideas for later

- Optional LLM + MCP integration: prepare issue text from user-provided context and attach selected screenshots or recordings to Jira or a similar service. The exact download/upload workflow should be clarified when this work starts. Preserve user control over destination, content, and publication.
- Video trim/crop and timed annotations after screenshot editing is stable.
- OCR, upload destinations, and configurable after-capture workflows.

Only the local capture/editor workflow is being implemented now. No accounts, external services, or uploads are connected.
