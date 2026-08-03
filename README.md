# PiP Edge Keeper

[![Build and test](https://github.com/penglow/pip-edge-keeper/actions/workflows/test.yml/badge.svg)](https://github.com/penglow/pip-edge-keeper/actions/workflows/test.yml)
[![Latest release](https://img.shields.io/github/v/release/penglow/pip-edge-keeper?label=download)](https://github.com/penglow/pip-edge-keeper/releases/latest)

A tiny Windows tray app that keeps Chrome, Edge, and other Chromium
Picture-in-Picture windows attached to the edge of your screen.

## Download and run

1. **[Download the latest Windows version](https://github.com/penglow/pip-edge-keeper/releases/latest/download/PipEdgeKeeper-windows.zip).**
2. Open the downloaded ZIP and extract it.
3. Run `PipEdgeKeeper.exe`.

There is no installer and no terminal window. The app stays in the notification
area beside the Windows clock. If its icon is hidden, click the **^** arrow.

## Using the app

- **Double-click the tray icon** to change settings.
- **Right-click the tray icon** to pause, open settings, or exit.
- Leave it running while you use Picture-in-Picture.

Starting the app a second time opens the existing instance instead of creating
a duplicate.

## Settings

- **Edge recognition distance** controls how close a PiP window must be to an
  edge before the app keeps it there.
- **Snap completely flush** removes any small gap at a recognized edge.
- **Bottom edge mode** chooses whether PiP windows stop above the taskbar or use
  the physical bottom of the screen.

Settings are saved automatically in
`%LOCALAPPDATA%\PipEdgeKeeper\settings.ini`.

## Windows warning

Windows may show an unknown-publisher or SmartScreen warning because the app is
not code-signed. The complete source code and build process are public in this
repository.

## For developers

Building, testing, project structure, and release instructions are in
[`DEVELOPMENT.md`](DEVELOPMENT.md).
