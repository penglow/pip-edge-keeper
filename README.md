# Chromium PiP Edge Keeper

Temporary Windows workaround for Chromium Picture-in-Picture windows that drift
away from the screen edge after a media update.

## Run

Double-click `Start-PipEdgeKeeper.cmd`.

The CMD launcher recognizes a Chromium Picture-in-Picture window within 64
pixels of a physical screen edge or corner and snaps each recognized edge
flush. This covers Chromium's observed 31-33 pixel inset plus the 48-pixel
taskbar on the tested display. If the window starts farther away, drag it inside
that zone once. The helper then restores the captured edges whenever an
automatic bounds recalculation moves them. It works whether or not the video's
dimensions or aspect ratio changed.

The CMD launcher deliberately uses the physical monitor bounds, not the Windows
work area. A bottom-anchored PiP will therefore overlap the taskbar and touch the
actual bottom of the display. Run the PowerShell script directly without
-UseMonitorBounds if you prefer it to stop at the top of the taskbar.

To preserve an exact nonzero gap instead of snapping flush, also omit
-FlushEdges. The direct script defaults to a 20 px acquisition distance.

## Supported browsers

Chrome, Vivaldi, Microsoft Edge, Brave, Chromium, Opera, and Opera GX are
recognized by default.

## Stop

Focus the helper's console window and press Ctrl+C, or close that console.

The helper does not resize PiP windows, change browser files, install anything,
or require administrator access. It only repositions matching PiP windows.
It recognizes Windows native move/size loops so you can detach the window from
an edge or move it between monitors. Screen work areas and negative monitor
coordinates are handled per window. Browser-specific custom or touch drag paths
that do not enter a native Windows move/size loop may be reverted; stop the
helper before using such a path, then restart it after placing the window. A
very fast native drag that starts and finishes entirely between two polling
intervals can also be missed; repeat it more slowly or stop the helper first.

The script requests per-monitor-v2 DPI awareness and falls back to thread-level
DPI awareness if the PowerShell host has already fixed its process-wide mode. It
prints a warning if Windows rejects every DPI-awareness request; mixed-scaling
monitor placement may then be a few pixels less accurate.

For safety, the default title pattern matches the complete native title
"Picture in picture" (spaces or hyphens, case-insensitive). This prevents an
ordinary browser window from being moved merely because its current tab title
mentions Picture-in-Picture.

This title/process check is intentionally conservative but is not a cryptographic
window identity. A Document PiP, PWA, or other browser window given that exact
native title could also match. Stop the helper if it ever recognizes the wrong
window, then supply a more specific -TitlePattern or remove that browser from
-BrowserProcess.

If your browser uses a localized PiP window title, run the script manually with
a matching regular expression, for example:

```powershell
powershell -ExecutionPolicy Bypass -File .\Keep-PipAtEdge.ps1 `
  -TitlePattern '(?i)^your localized PiP title here$'
```

The title shown for the PiP window in Alt+Tab is usually the value to match.

Known limitation: the helper recognizes a mouse-driven move or resize only when
Windows exposes it as a native move/size loop. It does not treat keyboard or
programmatic moves as manual interaction. While a window is anchored, moving it
with Win+Arrow, keyboard snapping, or a window-management tool (for example
FancyZones) will be reverted within one polling interval. Detach the window
with a normal native mouse drag first, or stop the helper. This was confirmed
in live testing: a programmatic move of an anchored PiP window was reverted
within 250 ms.

Clicking controls inside the PiP window itself is treated as an automatic bounds
change, not as a manual drag. This prevents an asymmetric browser inset (for
example a smaller right gap and larger bottom gap) from silently dropping only
the bottom anchor.

Start-PipEdgeKeeper.cmd runs the script with -ExecutionPolicy Bypass so this
local, unsigned helper can execute without changing any machine-wide execution
policy setting.

## Optional diagnostics

```powershell
powershell -ExecutionPolicy Bypass -File .\Keep-PipAtEdge.ps1 -VerboseEvents
```

## Deterministic Chromium bug reproduction

Serve this folder from localhost with any static web server, open
`pip-drift-test.html` in a Chromium browser, and follow the numbered controls.
For example, if Python is installed:

```powershell
python -m http.server 8000
```

Then open <http://localhost:8000/pip-drift-test.html>. Enter PiP, place the
window flush against an edge, and use the stream-swap buttons. Run this once
without the helper to observe the bug and once with it to verify restoration.

Note: the PiP window does not open flush with the screen edge. Chromium's
initial placement is deliberately inset by a small buffer (about 31 px on a
2560x1392 work area). Without the helper, drag it flush before swapping streams.
With the CMD launcher running, that inset is acquired and snapped to the
physical monitor edge automatically, overlapping the taskbar at the bottom. The
browser bug is that later media changes recreate the inset unless placement is
corrected.

## Repository contents

- `Keep-PipAtEdge.ps1`: the PowerShell helper.
- `Start-PipEdgeKeeper.cmd`: the default Windows launcher.
- `pip-drift-test.html`: a deterministic local reproduction page.
- `tests/Test-PipEdgeKeeper.ps1`: synthetic placement and regression tests.
- `docs/`: Chromium issue drafts and supporting technical analysis.

## Tests

From PowerShell on Windows:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File .\tests\Test-PipEdgeKeeper.ps1
```
