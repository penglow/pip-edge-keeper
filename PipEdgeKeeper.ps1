[CmdletBinding()]
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

    [Alias('BrowserProcess')]
    [string[]]$BrowserProcesses = @(
        'chrome', 'vivaldi', 'msedge', 'brave', 'chromium', 'opera', 'opera_gx'
    ),

    # Run without a console and expose an Exit command in the notification area.
    [switch]$TrayIcon,

    [Parameter(DontShow)]
    [switch]$Once
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

function Enable-DpiAwareness {
    # Windows may reject a process-wide change after PowerShell initializes, so
    # try per-monitor-v2 at the thread level before using the legacy fallback.
    try {
        if ([PipEdge.NativeMethods]::SetProcessDpiAwarenessContext([IntPtr](-4))) {
            return $true
        }
    } catch { }

    try {
        $previousContext =
            [PipEdge.NativeMethods]::SetThreadDpiAwarenessContext([IntPtr](-4))
        if ($previousContext -ne [IntPtr]::Zero) {
            return $true
        }
    } catch { }

    try {
        return [PipEdge.NativeMethods]::SetProcessDPIAware()
    } catch {
        return $false
    }
}

function New-SingleInstanceMutex {
    $createdNew = $false
    $mutex = [System.Threading.Mutex]::new(
        $true,
        'Local\PipEdgeKeeper',
        [ref]$createdNew
    )

    if (-not $createdNew) {
        $mutex.Dispose()
        return $null
    }

    return $mutex
}

function New-TrayResources {
    Add-Type -AssemblyName System.Drawing
    Add-Type -AssemblyName System.Windows.Forms

    $menu = [System.Windows.Forms.ContextMenuStrip]::new()
    $exitItem = [System.Windows.Forms.ToolStripMenuItem]::new('Exit')
    [void]$menu.Items.Add($exitItem)

    $notificationIcon = [System.Windows.Forms.NotifyIcon]::new()
    $notificationIcon.ContextMenuStrip = $menu
    $notificationIcon.Icon = [System.Drawing.SystemIcons]::Application
    $notificationIcon.Text = 'Chromium PiP Edge Keeper'

    $exitItem.add_Click({
        $script:stopRequested = $true
    })

    $notificationIcon.Visible = $true
    $notificationIcon.ShowBalloonTip(
        2000,
        'PiP Edge Keeper',
        'Running in the background. Right-click the tray icon to exit.',
        [System.Windows.Forms.ToolTipIcon]::Info
    )

    return @{
        Icon = $notificationIcon
        Menu = $menu
    }
}

function Remove-TrayResources([hashtable]$Resources) {
    if ($null -eq $Resources) {
        return
    }

    $Resources.Icon.Visible = $false
    $Resources.Icon.Dispose()
    $Resources.Menu.Dispose()
}

if (-not (Enable-DpiAwareness)) {
    Write-Warning 'Windows did not accept a DPI-awareness request. Edge placement may be less accurate across monitors with different scaling.'
}

$browserProcessNames = [System.Collections.Generic.HashSet[string]]::new(
    [string[]]$BrowserProcesses,
    [System.StringComparer]::OrdinalIgnoreCase
)
$trackedWindows = @{}
$setWindowPositionFlags = [PipEdge.NativeMethods]::NoSize -bor
                          [PipEdge.NativeMethods]::NoZOrder -bor
                          [PipEdge.NativeMethods]::NoActivate -bor
                          [PipEdge.NativeMethods]::AsyncWindowPos

function Get-PlacementArea([PipEdge.WindowInfo]$Window) {
    if ($UseMonitorBounds) {
        return $Window.MonitorBounds
    }
    return $Window.WorkArea
}

function Get-EdgeState([PipEdge.WindowInfo]$Window) {
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
        Interacting = $false
        Title = $Window.Title
        ProcessId = $Window.ProcessId
    }
}

function Update-EdgeState(
    [hashtable]$State,
    [PipEdge.WindowInfo]$Window
) {
    $newState = Get-EdgeState $Window
    foreach ($key in $newState.Keys) {
        $State[$key] = $newState[$key]
    }
}

function Add-MissingEdgeAnchors(
    [hashtable]$State,
    [PipEdge.WindowInfo]$Window
) {
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

function Test-NativeMoveSizeInteraction(
    [PipEdge.WindowInfo]$Window,
    [IntPtr]$MoveSizeWindow
) {
    return $MoveSizeWindow -ne [IntPtr]::Zero -and
           $MoveSizeWindow -eq $Window.Handle
}

function Get-DesiredOrigin(
    [hashtable]$State,
    [PipEdge.WindowInfo]$Window
) {
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

function Get-AnchorSummary([hashtable]$State) {
    return 'L={0} R={1} T={2} B={3}' -f @(
        $State.Left,
        $State.Right,
        $State.Top,
        $State.Bottom
    )
}

$script:stopRequested = $false
$instanceMutex = $null
$trayResources = $null

if ($TrayIcon) {
    $instanceMutex = New-SingleInstanceMutex
    if ($null -eq $instanceMutex) {
        Write-Verbose 'PiP Edge Keeper is already running.'
        return
    }
    $trayResources = New-TrayResources
} else {
    Write-Host 'PiP edge keeper is running. Place a PiP window within' $SnapDistance 'px of an edge.'
    if ($UseMonitorBounds) {
        Write-Host 'Using physical monitor edges; a bottom PiP may overlap the taskbar.'
    } else {
        Write-Host 'Using monitor work-area edges; the taskbar is excluded.'
    }
    Write-Host 'Press Ctrl+C in this window to stop.'
}

try {
do {
    $moveSizeWindow = [PipEdge.NativeMethods]::GetMoveSizeWindow()
    $seenHandles = [System.Collections.Generic.HashSet[long]]::new()

    foreach ($window in [PipEdge.NativeMethods]::GetTopLevelWindows()) {
        if ($window.Title -notmatch $TitlePattern) {
            continue
        }

        try {
            $processName = (Get-Process -Id $window.ProcessId -ErrorAction Stop).ProcessName
        } catch {
            continue
        }

        if (-not $browserProcessNames.Contains($processName)) {
            continue
        }

        $handle = $window.Handle.ToInt64()
        [void]$seenHandles.Add($handle)

        if ($trackedWindows.ContainsKey($handle) -and
            ($trackedWindows[$handle].ProcessId -ne $window.ProcessId -or
             $trackedWindows[$handle].Title -ne $window.Title)) {
            # A native handle can be reused after its old window closes. Never
            # apply placement state captured for a different window identity.
            [void]$trackedWindows.Remove($handle)
        }

        if (-not $trackedWindows.ContainsKey($handle)) {
            $trackedWindows[$handle] = Get-EdgeState $window
            if ($moveSizeWindow -eq $window.Handle) {
                $trackedWindows[$handle].Interacting = $true
            }
            $summary = Get-AnchorSummary $trackedWindows[$handle]
            Write-Verbose "Tracking '$($window.Title)' ($processName); anchors: $summary"
            continue
        }

        $state = $trackedWindows[$handle]

        # Only adopt new placement after Windows confirms a native move/size
        # loop. A media-control click can coincide with Chromium changing the
        # window bounds; treating mouse-down + geometry change as a drag would
        # overwrite the user's anchors with Chromium's unwanted inset.
        $isUserInteraction = Test-NativeMoveSizeInteraction $window $moveSizeWindow

        if ($isUserInteraction) {
            $state.Interacting = $true
            continue
        }

        if ($state.Interacting) {
            Update-EdgeState $state $window
            Write-Verbose "Placement updated; anchors: $(Get-AnchorSummary $state)"
            continue
        }

        if (Add-MissingEdgeAnchors $state $window) {
            Write-Verbose "Edge acquired; anchors: $(Get-AnchorSummary $state)"
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
                $setWindowPositionFlags
            )
            if ($moved) {
                Write-Verbose "Restored edge position to ($desiredLeft, $desiredTop) after size/position change."
            }
        }
    }

    foreach ($handle in @($trackedWindows.Keys)) {
        if (-not $seenHandles.Contains($handle)) {
            [void]$trackedWindows.Remove($handle)
        }
    }

    if ($TrayIcon) {
        [System.Windows.Forms.Application]::DoEvents()
    }

    if (-not $Once -and -not $script:stopRequested) {
        Start-Sleep -Milliseconds $PollMilliseconds
    }
} while (-not $Once -and -not $script:stopRequested)
} finally {
    Remove-TrayResources $trayResources
    if ($null -ne $instanceMutex) {
        $instanceMutex.ReleaseMutex()
        $instanceMutex.Dispose()
    }
}
