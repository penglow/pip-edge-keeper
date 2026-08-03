# Development

PiP Edge Keeper is a dependency-free C# Windows Forms application targeting the
.NET Framework included with Windows 10 and Windows 11. It uses Win32 APIs to
observe Chromium Picture-in-Picture windows and keep recognized screen-edge
placements stable.

## Repository layout

- `src/PipEdgeKeeper/` contains the tray application, settings UI, placement
  engine, and Win32 interop.
- `tests/` contains geometry and placement regression tests.
- `docs/chromium-bug-report.md` documents the Chromium behavior that motivated
  the app.
- `repro/pip-drift-test.html` is a deterministic reproduction page.
- `build.ps1` compiles the Windows GUI executable.

## Build

Run from a Windows PowerShell prompt at the repository root:

```powershell
.\build.ps1
```

The executable is written to `dist\PipEdgeKeeper.exe`. The build script locates
the .NET Framework C# compiler already included with Windows; no package restore
or separate SDK is required.

## Test

```powershell
.\tests\run-tests.ps1
```

The test runner compiles and runs the placement tests, then returns a non-zero
exit code if any test fails. GitHub Actions runs the tests and build for every
push and pull request.

## Local configuration

The app writes user settings to:

```text
%LOCALAPPDATA%\PipEdgeKeeper\settings.ini
```

Delete that file while the app is closed to restore default settings.

## Releases

Push a version tag such as `v1.0.1` from a tested commit on `main`. The release
workflow tests and builds the app, creates `PipEdgeKeeper-windows.zip`, and
publishes it on GitHub Releases with generated notes.
