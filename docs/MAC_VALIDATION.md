# First Mac validation checklist

Run from a logged-in macOS 26+ desktop session. CI can build and run the tests, but cannot certify the interactive capture and permission workflow.

## Automated

```sh
swift test
bash scripts/build-macos.sh debug
```

Nineteen tests cover geometry, undo/persistence and legacy edits, independent tool colors, scrolling alignment/rejection, export/crop orientation, ShareX highlight channel capping and idempotence, filled shapes/eraser restoration, embedded-image orientation, and effect alignment after crop. Record actual pass/fail results here after a Mac run; they have not run on Windows.

## Capture

- [ ] Screen Recording permission denied gives useful feedback and no empty successful capture.
- [ ] Permission grant/reopen permits capture.
- [ ] Region screenshot dimensions equal selected points times display scale.
- [ ] Display capture works on each connected display.
- [ ] Window capture contains the chosen window.
- [ ] Secondary displays left/above the main display select the correct region.
- [ ] Escape cancels with no new capture. Cross-display regions are not supported.
- [ ] App windows and selection overlay do not appear in display/region output.
- [ ] Repeat region is invalidated with useful feedback after display disconnection/layout change.
- [ ] All-display capture preserves display arrangement and negative origins; verify mixed Retina/non-Retina displays and mirrored displays.
- [ ] Light region selection is minimally dimmed and captures the same pixels as regular region.
- [ ] Transparent region excludes wallpaper and preserves alpha in uncovered areas; copied/exported PNG preserves alpha.
- [ ] Screenshot delay works from menus and hotkeys, and Stop Capture cancels it without saving.
- [ ] Auto-capture uses configured count/interval, remains responsive, and Stop keeps already saved screenshots.
- [ ] Scrolling capture asks for Accessibility access only when used; denied access reports how to enable it.
- [ ] Scrolling capture stitches a static page exactly, stops at its end, rejects ambiguous/animated content, and preserves recovery PNGs on cancellation/failure.
- [ ] Verify scrolling on Safari/Chrome and another native app, at both display scales. Exclude fixed headers and scrollbars.

## Editor

- [ ] Each requested tool appears in copied and exported output.
- [ ] Yellow highlight leaves black text black, turns white background yellow, and repeated overlaps do not become darker.
- [ ] Tool switches retain independent colors; arrow default stays red when highlight uses yellow.
- [ ] Rectangle/ellipse fill, speech bubble text, automatic numbered steps, image/sticker/cursor insertion work.
- [ ] Area/image resize handles, eraser, blur, pixelate, and magnify match preview and exported result after crop/undo.
- [ ] Version-one edit sidecars reopen and upgrade when new annotations are saved.
- [ ] Latin/Cyrillic text is upright and matches preview.
- [ ] Crop retains annotation alignment, can be reset, and can be undone.
- [ ] Select/move/delete and double-click text editing work.
- [ ] Apply to Selected changes color, width, and text size; undo restores the prior style.
- [ ] Undo followed by a new edit drops the old redo branch.
- [ ] Zoom/pan changes the view, not annotation coordinates or export resolution.
- [ ] Edits survive closing/reopening the editor; original PNG bytes remain unchanged.
- [ ] Save As supports PNG and JPEG; original source filename cannot be overwritten through export.

## Recording

- [ ] Region/display/window recordings play with correct dimensions at 30 fps.
- [ ] Record with neither audio source, system audio only, microphone only, and both.
- [ ] Deny microphone permission: get useful feedback; disable microphone and record successfully.
- [ ] Stop button and global hotkey finalize a playable MP4.
- [ ] macOS system Stop finalizes and imports the recording.
- [ ] Repeated Stop does not save duplicate captures.
- [ ] Stop and Quit saves before the app exits.
- [ ] Errors do not report a partial file as saved; InProgress is available for inspection.
- [ ] A 30-minute recording has stable memory use and no obvious audio drift.
- [ ] Cancel during countdown leaves no successful recording; global Stop works for MP4 and GIF.
- [ ] GIFs loop in a compatible viewer with correct orientation, no audio, and longest edge ≤960 pixels.
- [ ] GIF recording stops automatically after 60 seconds, converts only after MP4 finalization, and retains a recovery movie if conversion fails.
- [ ] Test GIF conversion memory/time on a 60-second recording and low disk space; the output enters history only after successful finalization/import.

## History and settings

- [ ] History, audio/capture preferences, and configured hotkeys survive relaunch.
- [ ] Hotkeys trigger while another app is active; duplicate assignments are rejected.
- [ ] Folder changes apply to new captures while old history still opens existing media.
- [ ] Remove from History preserves the media. Move to Trash moves the media to Trash.
- [ ] Deleted/moved files produce useful errors.
- [ ] Test low disk space and an unwritable captures folder.
