# Chromium PiP Edge Keeper

[![Tests](https://github.com/penglow/pip-edge-keeper/actions/workflows/test.yml/badge.svg)](https://github.com/penglow/pip-edge-keeper/actions/workflows/test.yml)

Windows helper that keeps Chromium Picture-in-Picture windows attached to the
screen edge when autoplay or media updates move them inward.

## Run

1. Double-click `Start-PipEdgeKeeper.cmd`.
2. Place the PiP window within 64 pixels of an edge or corner.
3. Leave the helper running. Press Ctrl+C in its window to stop it.

The launcher snaps to the physical monitor edge, so a bottom-anchored PiP can
overlap the taskbar. To stop at the top of the taskbar instead, run
`PipEdgeKeeper.ps1` directly without `-UseMonitorBounds`.

Chrome, Vivaldi, Edge, Brave, Chromium, Opera, and Opera GX are supported by
default. The helper only repositions matching PiP windows; it does not resize
them, modify browser files, install anything, or require administrator access.

## Reproduce the Chromium bug

```powershell
python -m http.server 8000
```

Open <http://localhost:8000/repro/pip-drift-test.html>, enter PiP, place it flush
with an edge, and use the stream-swap buttons.

## Test

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File .\tests\PipEdgeKeeper.Tests.ps1
```

The Chromium bug report and technical analysis are in
[`docs/chromium-bug-report.md`](docs/chromium-bug-report.md).
