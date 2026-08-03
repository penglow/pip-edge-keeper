# Chromium PiP Edge Keeper

[![Build and test](https://github.com/penglow/pip-edge-keeper/actions/workflows/test.yml/badge.svg)](https://github.com/penglow/pip-edge-keeper/actions/workflows/test.yml)

A small Windows tray app that keeps Chromium Picture-in-Picture windows attached
to the screen edge when autoplay or media updates move them inward.

## Run

Download the `PipEdgeKeeper-windows` artifact from the
[latest successful build](https://github.com/penglow/pip-edge-keeper/actions/workflows/test.yml),
extract it, and run `PipEdgeKeeper.exe`.

The app has no terminal or taskbar window. It lives in the Windows notification
area:

- Double-click the icon to open settings.
- Right-click it to pause, open settings, or exit.
- Starting it twice does not create duplicate instances.

Windows may show a SmartScreen warning because the executable is not
code-signed.

## Settings

The settings window controls the edge recognition distance, whether recognized
edges snap completely flush, and whether bottom PiP windows use the physical
screen edge or stop above the taskbar.

Settings are stored in `%LOCALAPPDATA%\PipEdgeKeeper\settings.ini`.

## Build

Windows 10 or 11 includes the .NET Framework compiler used by this project:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\build.ps1
```

The executable is written to `dist\PipEdgeKeeper.exe`.

## Test

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\run-tests.ps1
```

The Chromium bug analysis and deterministic reproduction page remain in
[`docs/chromium-bug-report.md`](docs/chromium-bug-report.md) and
[`repro/pip-drift-test.html`](repro/pip-drift-test.html).
