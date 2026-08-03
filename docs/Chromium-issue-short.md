# Chromium issue — short version

**Title:** Video PiP moves away from right/bottom screen edges after media update

**Component:** Blink > Media > PictureInPicture
**Environment:** Windows 11 build 26200; Vivaldi 8.1.4087.55 and Chrome; 2560x1440 at 100% scaling

**Steps to reproduce**
1. Enter video Picture-in-Picture.
2. Move the PiP window flush with the bottom-right work-area corner.
3. Switch to any other video or let autoplay advance. The videos' dimensions and aspect ratios are irrelevant to the bug.
4. Repeat, then compare with the same test at the top-left corner.

**Actual:** Normal video transitions pull the window inward from the right and bottom edges regardless of video dimensions or aspect ratio. Repeating the transition accumulates visible drift. A window at `(0,0)` remains at `(0,0)`.
**Expected:** Preserve the existing right/bottom edge gaps during automatic bounds updates. Windows away from an edge should retain their origin.

**Measured example:** In a 2560x1392 work area, one controlled transition moved a 494x278 PiP from flush bottom-right `(2066,1114)` to `(2035,1083)`, creating a 31 px inset. This is evidence of the general bug, not a size-specific condition. The measurement was made in an Electron-embedded Chromium host; the same symptom is user-observed in Chrome and Vivaldi.

**Likely code:** `CalculateAndUpdateWindowBounds()` clamps an existing origin with `origin.SetToMin(default_origin)`: https://chromium.googlesource.com/chromium/src/+/db5418d8949a4f526a732fcf2aa8158759cf1ee3/chrome/browser/ui/views/overlay/video_overlay_window_views.cc#524
**Related:** https://issues.chromium.org/issues/40887946 overlaps bottom-right placement and shared bounds logic. This report is specifically an already-visible video PiP moving after ordinary video transitions; please merge if the root cause is the same.
