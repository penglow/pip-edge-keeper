@echo off
start "" powershell.exe -NoLogo -NoProfile -Sta -WindowStyle Hidden -ExecutionPolicy Bypass -File "%~dp0PipEdgeKeeper.ps1" -TrayIcon -SnapDistance 64 -FlushEdges -UseMonitorBounds
