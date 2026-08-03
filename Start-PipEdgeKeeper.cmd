@echo off
title Chromium PiP Edge Keeper
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Keep-PipAtEdge.ps1" -SnapDistance 64 -FlushEdges -UseMonitorBounds
if errorlevel 1 pause
