# Video PiP moves away from right/bottom screen edges after media updates

**Type:** Bug

**Suggested component:** Chromium > Blink > Media > PictureInPicture

**OS:** Windows 11 Pro 10.0.26200 (build 26200)

**Display:** 2560x1440 primary display; 2560x1392 work area; 100% scaling
**Observed browsers:** Vivaldi 8.1.4087.55 and Chrome

## Description

When a video Picture-in-Picture window is placed flush against the right or
bottom screen edge, it does not reliably remain attached to that edge when the
active video changes or its video surface is refreshed. The reported behavior
is apparent on ordinary video transitions generally; it is not tied to any
particular natural size, aspect ratio, or change between them. Those properties
only affect how large or visually obvious the resulting displacement may be.

The PiP window remains in roughly the same part of the screen, but its right or
bottom edge moves inward. Repeated media changes and bounds recalculations can
leave it noticeably separated from the corner where the user placed it.

The top-left corner does not exhibit the same behavior. This asymmetry makes the
window appear to be laid out and resized relative to its top-left origin rather
than preserving the user-selected right/bottom edge placement.

## Steps to reproduce

1. Open a video in video Picture-in-Picture mode.
2. Move the PiP window so it is flush against the bottom-right edge of the
   display work area.
3. Let autoplay switch to any other video, or navigate to another video without
   closing PiP. No particular size or aspect-ratio combination is required.
4. Repeat across several videos.

Control case: repeat from the top-left corner. That corner remains substantially
more stable than the right or bottom edges.

## Instrumented measurements

On Windows 11 (build 26200), 2560x1392 work area, 100% scaling, using a local
test page whose video streams come from `canvas.captureStream()` (so the natural
size is exact; the local repro page is `pip-drift-test.html` and can be served
over localhost), bounds were
measured via `GetWindowRect` under per-monitor-v2 DPI awareness. These
instrumented measurements were collected in an Electron-embedded Chromium host;
they corroborate, but do not replace, the user-observed reproduction in Chrome
and Vivaldi 8.1.4087.55:

- Initial PiP placement of a 494x278 window was `(2035, 1083)` — exactly the
  `default_origin` produced by the 2% buffer formula (buffer = 31). The window
  therefore never opens flush with the screen edges; the flush placements below
  were set manually before each transition. This initial inset is expected
  default-placement behavior and is not itself the defect — the defect is that
  later recalculations force a user-placed window back to this initial inset.
- With the window flush bottom-right at `(2066, 1114)`, one controlled stream
  transition moved it to exactly `(2035, 1083)` while the window size remained
  unchanged. This is one measured example of the general transition bug, not a
  size-specific trigger or limitation.
- In the top-left control, the window origin remained `(0, 0)` when a transition
  changed its size. This confirms the right/bottom-only asymmetry.
- An aspect-ratio change (16:9 to 1:1) from flush bottom-right left the right
  edge 210 px and the bottom edge 33 px away from the work-area boundary; 33 px
  is exactly the recomputed buffer for the resulting 284x284 window bounds.

## Actual result

The PiP bounds are recalculated and the window is pulled inward from the right
and/or bottom edge during ordinary video transitions, regardless of the videos'
dimensions or aspect ratios. When the window size also changes, retaining or
clamping from the top-left origin further changes its right/bottom gap.

## Expected result

An automatically resized PiP window that was attached to an edge should preserve
its distance from that edge:

- right edge attached: preserve the right gap;
- bottom edge attached: preserve the bottom gap;
- corner attached: preserve both gaps;
- away from all edges: keep the existing origin and do not move unnecessarily.

A small edge threshold would preserve intentional edge placement without moving
centrally positioned PiP windows.

## Code-level observations

There appear to be two directly related top-left/inward anchoring problems and
one multi-monitor correctness problem in the current implementation.

### Trigger path: surface updates always recalculate the bounds

`VideoPictureInPictureWindowControllerImpl::EmbedSurface()` unconditionally
calls `window_->UpdateNaturalSize(natural_size)` (line 150) before setting the
new surface:

https://chromium.googlesource.com/chromium/src/+/db5418d8949a4f526a732fcf2aa8158759cf1ee3/content/browser/picture_in_picture/video_picture_in_picture_window_controller_impl.cc#128

The surrounding comment explicitly notes that a surface ID can be updated for
the same video as well as for a different video. There is no equality check for
the natural size before `UpdateNaturalSize()` is called. Therefore this placement
path runs for a new video with identical dimensions/aspect ratio, and may even
run for a surface refresh of the same video.

The user reports the behavior in Chrome and Vivaldi. A controlled
identical-natural-size transition was reproduced and measured in the
Electron-embedded Chromium host described above (a same-dimension stream swap
on one video element). A same-video surface refresh remains a code-path
deduction.

`VideoOverlayWindowViews::UpdateNaturalSize()` has no equality guard (only a
`DCHECK` that the size is non-empty) and calls
`SetBounds(CalculateAndUpdateWindowBounds())` after updating the natural size:

https://chromium.googlesource.com/chromium/src/+/db5418d8949a4f526a732fcf2aa8158759cf1ee3/chrome/browser/ui/views/overlay/video_overlay_window_views.cc#1823

Note that adding an equality guard on the natural size alone would not fix the
flush-placement case: `CalculateAndUpdateWindowBounds()` clamps unconditionally
whenever it runs, so the clamp itself must stop targeting the initial-placement
inset.

### 1. Already-shown windows are clamped to a default inset position

`CalculateAndUpdateWindowBounds()` calculates a `buffer` intended as 2% of the
average remaining work-area dimensions (see the multi-monitor problem below for
what it actually computes), then creates a `default_origin` inset from the
right and bottom edges. For every already-shown PiP window it executes:

```cpp
origin.SetToMin(default_origin);
```

Relevant code (`CalculateAndUpdateWindowBounds()` starts at line 460; the buffer
calculation is lines 512-517; the clamp is line 524):

https://chromium.googlesource.com/chromium/src/+/db5418d8949a4f526a732fcf2aa8158759cf1ee3/chrome/browser/ui/views/overlay/video_overlay_window_views.cc#524

Because `SetToMin()` clamps the x and y coordinates independently, a user-placed
window that is flush with the right or bottom work-area edge is forced back to
the calculated 2% default inset whenever these bounds are recalculated. A
top-left window is unaffected because its origin is already smaller than the
default origin. This directly explains why top-left placement remains stable
while right/bottom placement does not, even when the video's aspect ratio is
unchanged.

The comment above the clamp reads "Make sure window is displayed entirely in
the work area", but `SetToMin(default_origin)` does not do that: it clamps to
the default placement inset rather than the work-area boundary, and there is no
corresponding `SetToMax(work_area.origin())`, so a window pushed past the left
or top edge is never corrected.

The visibility constraint for an existing user-positioned window should clamp
against the actual work-area boundary rather than the initial-placement margin.
For example, the maximum visible origin is
`(work_area.right() - window_size.width(), work_area.bottom() -
window_size.height())`; it should be paired with a lower clamp at
`work_area.origin()`. That fixes the same-size inward movement without applying
the default 2% buffer to an existing window.

When the window size changes, Chromium must additionally preserve the user's
edge intent. If the old bounds are within a small attachment threshold of an
edge, preserve that signed edge gap and use the adjusted origin that
`gfx::SizeRectToAspectRatio()` already computes for the corresponding anchored
axis. If the old bounds are away from every edge, retain the existing origin.
A persistent anchor state could be used instead of a threshold. Reusing the
quadrant-adjusted origin for every window without checking attachment would
shift centrally positioned windows, contrary to the expected behavior above.
The default 2% buffer remains appropriate for initial placement only.

For example, in a 1000x1000 work area with an existing 450x300 PiP window, a
flush bottom-right origin is `(550, 700)`. The current buffer calculation yields
12 pixels, making `default_origin` `(538, 688)`. Calling
`UpdateNaturalSize({300, 200})` with the same 3:2 dimensions therefore moves the
window to `(538, 688)` even though no resize is necessary.

The buffer calculation has an additional multi-monitor problem. It calculates
the remaining width and height as:

```cpp
work_area.right() - window_size.width()
work_area.bottom() - window_size.height()
```

These are absolute screen-coordinate origins, not the remaining dimensions.
Only the buffer calculation should use `work_area.width() - window_size.width()`
and `work_area.height() - window_size.height()`; `work_area.right() - width` is
otherwise appropriate when calculating the final x origin. For a 1920x1080
secondary display at x=1920 with a 450x300 PiP window, the current formula makes
the forced inset 41 pixels instead of the size-based 22 pixels. On an equally
sized display immediately to the left of the primary display, it produces about
3 pixels. Thus the unwanted inset also varies according to monitor origin.

### 2. Aspect-ratio adjustment discards its adjusted origin

When size/aspect adjustment is necessary, Chromium also:

1. chooses an aspect-ratio resize edge based on the window quadrant;
2. constructs `window_rect` from the existing origin and candidate size;
3. calls `gfx::SizeRectToAspectRatio(...)`, which may adjust both size and origin;
4. copies only `window_rect.size()`;
5. later resets `origin` to `bounds.origin()` before applying the inward clamp
   described above.

Relevant code (the aspect-ratio block is lines 480-507; the size-only copy is
line 504 and the origin reset is line 510):

https://chromium.googlesource.com/chromium/src/+/db5418d8949a4f526a732fcf2aa8158759cf1ee3/chrome/browser/ui/views/overlay/video_overlay_window_views.cc#480

For a bottom-right window, the code selects `gfx::ResizeEdge::kTopLeft`, and
`gfx::SizeRectToAspectRatio()` (ui/gfx/geometry/resize_utils.cc) computes
exactly the bottom-right-anchored origin that intent implies (`left = right -
new_width; top = bottom - new_height`), but the resulting adjusted origin is
then discarded. This makes the edge-placement loss larger when the window
dimensions do change, but dimension or aspect-ratio changes are not required
for the first problem above.

### 3. Quadrant detection ignores a secondary display's screen origin

`GetCurrentWindowQuadrant()` obtains its work area from the opener browser's
top-level native window rather than from the visible PiP window. It then compares
the PiP window's absolute screen-coordinate center against
`work_area.width() / 2` and `work_area.height() / 2`:

https://chromium.googlesource.com/chromium/src/+/db5418d8949a4f526a732fcf2aa8158759cf1ee3/chrome/browser/ui/views/overlay/video_overlay_window_views.cc#153

If the PiP window has been moved to a different display from the browser window,
the work area can therefore belong to the wrong display. Even when both windows
are on the same display, the comparisons do not include `work_area.x()` or
`work_area.y()` (or simply use `work_area.CenterPoint()`). On a display whose
origin is not `(0, 0)`, the wrong quadrant, and therefore the wrong aspect-ratio
resize edge, can be selected. This is especially relevant on multi-monitor
layouts with a display positioned to the left, right, or above the primary
display.

The existing unit coverage (`UpdateNaturalSizeDoesNotMoveWindow`, line 462)
verifies that a window at `(100, 100)` in a `(0, 0)` 1000x1000 work area does
not move after an aspect-ratio change, but does not cover preserving the right
or bottom edge for windows in those screen quadrants:

https://chromium.googlesource.com/chromium/src/+/db5418d8949a4f526a732fcf2aa8158759cf1ee3/chrome/browser/ui/views/overlay/video_overlay_window_views_unittest.cc#462

The browser-level regression test from the 2018 fix referenced below,
`SurfaceIdChangeDoesNotMoveWindow`, was flaky (issue 40156123) and no longer
exists in `video_picture_in_picture_window_controller_browsertest.cc`, so this
behavior is currently untested at the browser level as well.

Suggested regression coverage:

1. In a 1000x1000 work area, show a 450x300 3:2 PiP window at
   `(550, 700)`, call `UpdateNaturalSize({300, 200})` again, and assert the
   bounds remain `(550, 700, 450, 300)`.
2. Repeat with a changed aspect ratio and assert that the right and bottom gaps
   remain zero while the size changes.
3. Add right-only, bottom-only, and all four corner cases, plus a window away
   from every edge that should retain its origin.
4. Repeat quadrant/edge tests in a work area with a nonzero and a negative
   origin to cover secondary-display layouts.

The existing test covers only a window near the top-left of a `(0, 0)` work
area, which is the one placement that naturally passes the current
`origin.SetToMin(default_origin)` behavior.

## Related issues and regression history

Issue 41395926 was fixed in 2018 by commit `40dc0c129cc3` / CL 1126559,
"Picture-in-Picture: do not reset window size and position when SurfaceId
changes." That fix added an early return for an already-visible PiP window and
established that adaptive-quality or surface-ID changes must not reset user
placement:

- https://issues.chromium.org/issues/41395926
- https://chromium-review.googlesource.com/1126559

CL 1196363, for issue 41407719, later removed that visible-window early return
so the PiP bounds could stay synchronized with a changing video size. The same
change introduced the current `origin.SetToMin(default_origin)` branch to keep
updated bounds inside the work area:

- https://chromium-review.googlesource.com/1196363
- https://issues.chromium.org/issues/41407719

Simply restoring the early return would undo CL 1196363's intended
size-synchronization and work-area visibility behavior. The bounds still need
to be recalculated; the recalculation must preserve edge attachment instead of
applying the initial 2% inset to an existing user-positioned window.

The historical implementation also explains the top-left asymmetry. CL 1137837
explicitly preserved the window's "origin, or the top left corner coordinates"
when bounds were updated. CL 1363279 later selected an opposite resize edge by
screen quadrant, but copied only the adjusted rectangle's size, not its origin:

- https://chromium-review.googlesource.com/1137837
- https://chromium-review.googlesource.com/c/chromium/src/+/1363279

The browser-level regression test used by the 2018 SurfaceId fix,
`SurfaceIdChangeDoesNotMoveWindow`, was later tracked as flaky in issue 40156123
and no longer exists, leaving this behavior uncovered at the browser level:

https://issues.chromium.org/issues/40156123

Issue 40887946 has genuine overlap. It was filed through a Document
Picture-in-Picture initial-creation reproduction, but its discussion includes
incorrect bottom-right origin/placement and its landed CL changed shared native
window aspect-ratio plumbing, including a mechanical update in
`VideoOverlayWindowViews`:

- https://issues.chromium.org/issues/40887946
- https://chromium-review.googlesource.com/c/chromium/src/+/4336172

However, that issue does not exercise an already-visible native video PiP window
during a media/surface replacement, and its `VideoOverlayWindowViews` change did
not modify `UpdateNaturalSize()` or `CalculateAndUpdateWindowBounds()`. This
report should therefore be treated as a related live video-PiP update case;
maintainers can merge it if they determine both symptoms belong under the same
tracking issue.

Issue 525047264 concerns Wayland manual-resize aspect-ratio behavior. Issues
40787553 and 40685453 (manual resize from the top-left corner throwing the
window rightward/off-screen on Windows) may share the discarded-origin/quadrant
mechanics but describe manual resizing rather than media transitions. No exact
active duplicate of this report was found.

## User impact

PiP windows are commonly placed in corners to avoid covering the center of
another application. Losing edge alignment wastes screen space and can cover
content the user deliberately left visible. Repeated autoplay transitions make
the placement failure repeatedly noticeable.
