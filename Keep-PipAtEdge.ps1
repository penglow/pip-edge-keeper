param(
    [ValidateRange(0, 100)]
    [int]$SnapDistance = 20,

    # Normalize any captured near-edge gap to zero. The launcher enables this
    # so Chromium's default 31-33 px inset is pulled flush on first discovery.
    [switch]$FlushEdges,

    # Use physical monitor edges instead of the Windows work area. This allows
    # a bottom-anchored PiP to overlap the taskbar and touch the screen bottom.
    [switch]$UseMonitorBounds,

    [ValidateRange(50, 5000)]
    [int]$PollMilliseconds = 150,

    # Anchored to the complete native title so an ordinary browser window whose
    # tab title merely mentions Picture-in-Picture is never repositioned.
    [string]$TitlePattern = '(?i)^\s*picture[\s-]*in[\s-]*picture\s*$',

    [string[]]$BrowserProcess = @(
        'chrome', 'vivaldi', 'msedge', 'brave', 'chromium', 'opera', 'opera_gx'
    ),

    [switch]$Once,
    [switch]$VerboseEvents
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not ('PipEdge.NativeMethods' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Text;

namespace PipEdge {
    [StructLayout(LayoutKind.Sequential)]
    public struct Rect {
        public int Left;
        public int Top;
        public int Right;
        public int Bottom;

        public int Width { get { return Right - Left; } }
        public int Height { get { return Bottom - Top; } }
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct Point {
        public int X;
        public int Y;
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct GuiThreadInfo {
        public int Size;
        public uint Flags;
        public IntPtr ActiveWindow;
        public IntPtr FocusWindow;
        public IntPtr CaptureWindow;
        public IntPtr MenuOwnerWindow;
        public IntPtr MoveSizeWindow;
        public IntPtr CaretWindow;
        public Rect CaretRect;
    }

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Auto)]
    public struct MonitorInfo {
        public int Size;
        public Rect Monitor;
        public Rect WorkArea;
        public uint Flags;
    }

    public sealed class WindowInfo {
        public IntPtr Handle;
        public string Title;
        public uint ProcessId;
        public Rect Bounds;
        public Rect WorkArea;
        public Rect MonitorBounds;
    }

    public static class NativeMethods {
        private const uint MonitorDefaultToNearest = 2;
        public const uint NoSize = 0x0001;
        public const uint NoZOrder = 0x0004;
        public const uint NoActivate = 0x0010;
        public const uint AsyncWindowPos = 0x4000;

        private delegate bool EnumWindowsProc(IntPtr window, IntPtr parameter);

        [DllImport("user32.dll")]
        private static extern bool EnumWindows(EnumWindowsProc callback, IntPtr parameter);

        [DllImport("user32.dll")]
        private static extern bool IsWindowVisible(IntPtr window);

        [DllImport("user32.dll", CharSet = CharSet.Unicode)]
        private static extern int GetWindowTextLength(IntPtr window);

        [DllImport("user32.dll", CharSet = CharSet.Unicode)]
        private static extern int GetWindowText(IntPtr window, StringBuilder text, int maximumCount);

        [DllImport("user32.dll")]
        private static extern uint GetWindowThreadProcessId(IntPtr window, out uint processId);

        [DllImport("user32.dll")]
        private static extern bool GetWindowRect(IntPtr window, out Rect bounds);

        [DllImport("user32.dll")]
        private static extern IntPtr MonitorFromWindow(IntPtr window, uint flags);

        [DllImport("user32.dll", CharSet = CharSet.Auto)]
        private static extern bool GetMonitorInfo(IntPtr monitor, ref MonitorInfo info);

        [DllImport("user32.dll")]
        public static extern bool SetWindowPos(
            IntPtr window,
            IntPtr insertAfter,
            int x,
            int y,
            int width,
            int height,
            uint flags);

        [DllImport("user32.dll")]
        private static extern bool GetGUIThreadInfo(uint threadId, ref GuiThreadInfo info);

        [DllImport("user32.dll")]
        public static extern bool SetProcessDPIAware();

        [DllImport("user32.dll")]
        public static extern bool SetProcessDpiAwarenessContext(IntPtr value);

        [DllImport("user32.dll")]
        public static extern IntPtr SetThreadDpiAwarenessContext(IntPtr value);

        public static IntPtr GetMoveSizeWindow() {
            var info = new GuiThreadInfo();
            info.Size = Marshal.SizeOf(typeof(GuiThreadInfo));
            return GetGUIThreadInfo(0, ref info) ? info.MoveSizeWindow : IntPtr.Zero;
        }

        public static WindowInfo[] GetTopLevelWindows() {
            var windows = new List<WindowInfo>();
            EnumWindows(delegate(IntPtr window, IntPtr parameter) {
                if (!IsWindowVisible(window)) {
                    return true;
                }

                int titleLength = GetWindowTextLength(window);
                if (titleLength == 0) {
                    return true;
                }

                var title = new StringBuilder(titleLength + 1);
                GetWindowText(window, title, title.Capacity);

                uint processId;
                GetWindowThreadProcessId(window, out processId);

                Rect bounds;
                if (!GetWindowRect(window, out bounds)) {
                    return true;
                }

                IntPtr monitor = MonitorFromWindow(window, MonitorDefaultToNearest);
                var monitorInfo = new MonitorInfo();
                monitorInfo.Size = Marshal.SizeOf(typeof(MonitorInfo));
                if (!GetMonitorInfo(monitor, ref monitorInfo)) {
                    return true;
                }

                windows.Add(new WindowInfo {
                    Handle = window,
                    Title = title.ToString(),
                    ProcessId = processId,
                    Bounds = bounds,
                    WorkArea = monitorInfo.WorkArea,
                    MonitorBounds = monitorInfo.Monitor
                });
                return true;
            }, IntPtr.Zero);
            return windows.ToArray();
        }
    }
}
'@
}

# Request PER_MONITOR_AWARE_V2. Windows can reject a process-wide change if the
# host initialized DPI awareness before loading this script, so fall back to a
# thread-level context for the thread performing all Win32 coordinate calls.
$dpiAwarenessSet = $false
try {
    $dpiAwarenessSet = [PipEdge.NativeMethods]::SetProcessDpiAwarenessContext(
        [IntPtr](-4)
    )
} catch { }

if (-not $dpiAwarenessSet) {
    try {
        $previousDpiContext =
            [PipEdge.NativeMethods]::SetThreadDpiAwarenessContext([IntPtr](-4))
        $dpiAwarenessSet = $previousDpiContext -ne [IntPtr]::Zero
    } catch { }
}

if (-not $dpiAwarenessSet) {
    try {
        $dpiAwarenessSet = [PipEdge.NativeMethods]::SetProcessDPIAware()
    } catch { }
}

if (-not $dpiAwarenessSet) {
    Write-Warning 'Windows did not accept a DPI-awareness request. Edge placement may be less accurate across monitors with different scaling.'
}

$browserNames = [System.Collections.Generic.HashSet[string]]::new(
    [string[]]$BrowserProcess,
    [System.StringComparer]::OrdinalIgnoreCase
)
$tracked = @{}
$moveFlags = [PipEdge.NativeMethods]::NoSize -bor
             [PipEdge.NativeMethods]::NoZOrder -bor
             [PipEdge.NativeMethods]::NoActivate -bor
             [PipEdge.NativeMethods]::AsyncWindowPos

function Write-Event([string]$Message) {
    if ($VerboseEvents) {
        Write-Host "[$(Get-Date -Format 'HH:mm:ss.fff')] $Message"
    }
}

function Get-PlacementArea($Window) {
    if ($UseMonitorBounds) {
        return $Window.MonitorBounds
    }
    return $Window.WorkArea
}

function Get-EdgeState($Window) {
    $bounds = $Window.Bounds
    $placementArea = Get-PlacementArea $Window
    $leftGap = $bounds.Left - $placementArea.Left
    $rightGap = $placementArea.Right - $bounds.Right
    $topGap = $bounds.Top - $placementArea.Top
    $bottomGap = $placementArea.Bottom - $bounds.Bottom

    $left = [Math]::Abs($leftGap) -le $SnapDistance
    $right = [Math]::Abs($rightGap) -le $SnapDistance
    $top = [Math]::Abs($topGap) -le $SnapDistance
    $bottom = [Math]::Abs($bottomGap) -le $SnapDistance

    $rememberedLeftGap = $leftGap
    $rememberedRightGap = $rightGap
    $rememberedTopGap = $topGap
    $rememberedBottomGap = $bottomGap
    if ($FlushEdges) {
        if ($left) { $rememberedLeftGap = 0 }
        if ($right) { $rememberedRightGap = 0 }
        if ($top) { $rememberedTopGap = 0 }
        if ($bottom) { $rememberedBottomGap = 0 }
    }

    return @{
        Left = $left
        Right = $right
        Top = $top
        Bottom = $bottom
        LeftGap = $rememberedLeftGap
        RightGap = $rememberedRightGap
        TopGap = $rememberedTopGap
        BottomGap = $rememberedBottomGap
        LastLeft = $bounds.Left
        LastTop = $bounds.Top
        LastWidth = $bounds.Width
        LastHeight = $bounds.Height
        Interacting = $false
        Title = $Window.Title
        ProcessId = $Window.ProcessId
    }
}

function Update-EdgeState($State, $Window) {
    $newState = Get-EdgeState $Window
    foreach ($key in $newState.Keys) {
        $State[$key] = $newState[$key]
    }
}

function Add-MissingEdgeAnchors($State, $Window) {
    $candidate = Get-EdgeState $Window
    $added = $false
    foreach ($edge in @('Left', 'Right', 'Top', 'Bottom')) {
        if (-not $State[$edge] -and $candidate[$edge]) {
            $gapKey = $edge + 'Gap'
            $State[$edge] = $true
            $State[$gapKey] = $candidate[$gapKey]
            $added = $true
        }
    }
    return $added
}

function Test-NativeMoveSizeInteraction($Window, [IntPtr]$MoveSizeWindow) {
    return $MoveSizeWindow -ne [IntPtr]::Zero -and
           $MoveSizeWindow -eq $Window.Handle
}

function Get-DesiredOrigin($State, $Window) {
    $origin = [PipEdge.Point]::new()
    $origin.X = $Window.Bounds.Left
    $origin.Y = $Window.Bounds.Top
    $placementArea = Get-PlacementArea $Window

    if ($State.Right) {
        $origin.X = $placementArea.Right - $State.RightGap - $Window.Bounds.Width
    } elseif ($State.Left) {
        $origin.X = $placementArea.Left + $State.LeftGap
    }

    if ($State.Bottom) {
        $origin.Y = $placementArea.Bottom - $State.BottomGap - $Window.Bounds.Height
    } elseif ($State.Top) {
        $origin.Y = $placementArea.Top + $State.TopGap
    }

    return $origin
}

Write-Host 'PiP edge keeper is running. Place a PiP window within' $SnapDistance 'px of an edge.'
if ($UseMonitorBounds) {
    Write-Host 'Using physical monitor edges; a bottom PiP may overlap the taskbar.'
} else {
    Write-Host 'Using monitor work-area edges; the taskbar is excluded.'
}
Write-Host 'Press Ctrl+C in this window to stop.'

do {
    $moveSizeWindow = [PipEdge.NativeMethods]::GetMoveSizeWindow()
    $seen = [System.Collections.Generic.HashSet[string]]::new()

    foreach ($window in [PipEdge.NativeMethods]::GetTopLevelWindows()) {
        if ($window.Title -notmatch $TitlePattern) {
            continue
        }

        try {
            $processName = (Get-Process -Id $window.ProcessId -ErrorAction Stop).ProcessName
        } catch {
            continue
        }

        if (-not $browserNames.Contains($processName)) {
            continue
        }

        $key = $window.Handle.ToInt64().ToString()
        [void]$seen.Add($key)

        if ($tracked.ContainsKey($key) -and
            ($tracked[$key].ProcessId -ne $window.ProcessId -or
             $tracked[$key].Title -ne $window.Title)) {
            # A native handle can be reused after its old window closes. Never
            # apply placement state captured for a different window identity.
            [void]$tracked.Remove($key)
        }

        if (-not $tracked.ContainsKey($key)) {
            $tracked[$key] = Get-EdgeState $window
            if ($moveSizeWindow -eq $window.Handle) {
                $tracked[$key].Interacting = $true
            }
            Write-Event "Tracking '$($window.Title)' ($processName); anchors: L=$($tracked[$key].Left) R=$($tracked[$key].Right) T=$($tracked[$key].Top) B=$($tracked[$key].Bottom)"
            continue
        }

        $state = $tracked[$key]

        # Only adopt new placement after Windows confirms a native move/size
        # loop. A media-control click can coincide with Chromium changing the
        # window bounds; treating mouse-down + geometry change as a drag would
        # overwrite the user's anchors with Chromium's unwanted inset.
        $isUserInteraction = Test-NativeMoveSizeInteraction $window $moveSizeWindow

        if ($isUserInteraction) {
            $state.Interacting = $true
            $state.LastLeft = $window.Bounds.Left
            $state.LastTop = $window.Bounds.Top
            $state.LastWidth = $window.Bounds.Width
            $state.LastHeight = $window.Bounds.Height
            continue
        }

        if ($state.Interacting) {
            Update-EdgeState $state $window
            Write-Event "Placement updated; anchors: L=$($state.Left) R=$($state.Right) T=$($state.Top) B=$($state.Bottom)"
            continue
        }

        if (Add-MissingEdgeAnchors $state $window) {
            Write-Event "Edge acquired; anchors: L=$($state.Left) R=$($state.Right) T=$($state.Top) B=$($state.Bottom)"
        }

        $desiredOrigin = Get-DesiredOrigin $state $window
        $desiredLeft = $desiredOrigin.X
        $desiredTop = $desiredOrigin.Y

        if ($desiredLeft -ne $window.Bounds.Left -or $desiredTop -ne $window.Bounds.Top) {
            $moved = [PipEdge.NativeMethods]::SetWindowPos(
                $window.Handle,
                [IntPtr]::Zero,
                $desiredLeft,
                $desiredTop,
                0,
                0,
                $moveFlags
            )
            if ($moved) {
                Write-Event "Restored edge position to ($desiredLeft, $desiredTop) after size/position change."
            }
        }

        $state.LastLeft = $desiredLeft
        $state.LastTop = $desiredTop
        $state.LastWidth = $window.Bounds.Width
        $state.LastHeight = $window.Bounds.Height
    }

    foreach ($key in @($tracked.Keys)) {
        if (-not $seen.Contains($key)) {
            [void]$tracked.Remove($key)
        }
    }

    if (-not $Once) {
        Start-Sleep -Milliseconds $PollMilliseconds
    }
} while (-not $Once)
