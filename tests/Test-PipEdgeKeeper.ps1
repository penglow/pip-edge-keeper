$ErrorActionPreference = 'Stop'
$scriptPath = Join-Path $PSScriptRoot '..\Keep-PipAtEdge.ps1'

. $scriptPath -Once 6>$null

function Assert-Equal($Expected, $Actual, [string]$Message) {
    if ($Expected -ne $Actual) {
        throw "$Message Expected '$Expected', got '$Actual'."
    }
}

function New-TestWindow(
    [int]$Left,
    [int]$Top,
    [int]$Width,
    [int]$Height,
    [long]$Handle = 123,
    [int]$WorkLeft = 0,
    [int]$WorkTop = 0,
    [int]$WorkWidth = 1000,
    [int]$WorkHeight = 1000,
    [int]$MonitorLeft = 0,
    [int]$MonitorTop = 0,
    [int]$MonitorWidth = 1000,
    [int]$MonitorHeight = 1000
) {
    $window = [PipEdge.WindowInfo]::new()
    $window.Handle = [IntPtr]$Handle
    $window.Title = 'Picture in picture'

    $bounds = [PipEdge.Rect]::new()
    $bounds.Left = $Left
    $bounds.Top = $Top
    $bounds.Right = $Left + $Width
    $bounds.Bottom = $Top + $Height
    $window.Bounds = $bounds

    $workArea = [PipEdge.Rect]::new()
    $workArea.Left = $WorkLeft
    $workArea.Top = $WorkTop
    $workArea.Right = $WorkLeft + $WorkWidth
    $workArea.Bottom = $WorkTop + $WorkHeight
    $window.WorkArea = $workArea

    $monitorBounds = [PipEdge.Rect]::new()
    $monitorBounds.Left = $MonitorLeft
    $monitorBounds.Top = $MonitorTop
    $monitorBounds.Right = $MonitorLeft + $MonitorWidth
    $monitorBounds.Bottom = $MonitorTop + $MonitorHeight
    $window.MonitorBounds = $monitorBounds
    return $window
}

# Exact title matching must recognize PiP titles but not ordinary browser tabs
# whose page title happens to mention Picture-in-Picture.
Assert-Equal $true ('Picture in picture' -match $TitlePattern) 'Space-separated PiP title.'
Assert-Equal $true ('Picture-in-Picture' -match $TitlePattern) 'Hyphenated PiP title.'
Assert-Equal $false ('Picture-in-Picture API - Google Chrome' -match $TitlePattern) 'Ordinary browser title false positive.'

# A flush bottom-right window should capture both zero gaps.
$initial = New-TestWindow -Left 550 -Top 700 -Width 450 -Height 300
$initial.ProcessId = 1234
$state = Get-EdgeState $initial
Assert-Equal $true $state.Right 'Right anchor detection.'
Assert-Equal $true $state.Bottom 'Bottom anchor detection.'
Assert-Equal 0 $state.RightGap 'Right gap capture.'
Assert-Equal 0 $state.BottomGap 'Bottom gap capture.'
Assert-Equal 1234 $state.ProcessId 'Process identity capture.'

# Reproduce Chromium's 12-pixel inward move and ensure we restore the origin.
$drifted = New-TestWindow -Left 538 -Top 688 -Width 450 -Height 300
$restored = Get-DesiredOrigin $state $drifted
Assert-Equal 550 $restored.X 'Same-size right-edge restoration.'
Assert-Equal 700 $restored.Y 'Same-size bottom-edge restoration.'

# Chromium can move the two axes by different amounts. The restoration distance
# is intentionally not limited by SnapDistance once the edge state is captured.
$asymmetricDrift = New-TestWindow -Left 538 -Top 667 -Width 450 -Height 300
$recapturedAsymmetric = Get-EdgeState $asymmetricDrift
Assert-Equal $true $recapturedAsymmetric.Right '12-pixel drift remains inside right snap threshold.'
Assert-Equal $false $recapturedAsymmetric.Bottom '33-pixel drift exceeds bottom snap threshold.'
$asymmetricRestored = Get-DesiredOrigin $state $asymmetricDrift
Assert-Equal 550 $asymmetricRestored.X '12-pixel right drift restoration.'
Assert-Equal 700 $asymmetricRestored.Y '33-pixel bottom drift restoration.'

# A control click is not a manual move/size loop. Preserve the old zero-gap
# anchors instead of recapturing Right=true/Bottom=false from the 12/33 drift.
Assert-Equal $false (Test-NativeMoveSizeInteraction $asymmetricDrift ([IntPtr]::Zero)) 'Control click is not a native drag.'
if (Test-NativeMoveSizeInteraction $asymmetricDrift ([IntPtr]::Zero)) {
    Update-EdgeState $state $asymmetricDrift
}
$afterControlClick = Get-DesiredOrigin $state $asymmetricDrift
Assert-Equal 550 $afterControlClick.X 'Control click preserves right anchor.'
Assert-Equal 700 $afterControlClick.Y 'Control click preserves bottom anchor.'

# A confirmed native drag is allowed to replace or clear the captured anchors.
Assert-Equal $true (Test-NativeMoveSizeInteraction $initial $initial.Handle) 'Native drag detection.'
Assert-Equal $false (Test-NativeMoveSizeInteraction $initial ([IntPtr]456)) 'Other-window drag rejection.'
$draggedToCenter = New-TestWindow -Left 250 -Top 250 -Width 450 -Height 300
$manualState = Get-EdgeState $initial
if (Test-NativeMoveSizeInteraction $draggedToCenter $draggedToCenter.Handle) {
    Update-EdgeState $manualState $draggedToCenter
}
Assert-Equal $false $manualState.Right 'Native drag to center clears right anchor.'
Assert-Equal $false $manualState.Bottom 'Native drag to center clears bottom anchor.'

# First discovery at Chromium's default 31/33 px inset must not invent edge
# intent. A later confirmed manual placement flush to the corner captures both.
$defaultInset = New-TestWindow -Left 519 -Top 667 -Width 450 -Height 300
$defaultState = Get-EdgeState $defaultInset
Assert-Equal $false $defaultState.Right '31-pixel initial inset is not auto-anchored.'
Assert-Equal $false $defaultState.Bottom '33-pixel initial inset is not auto-anchored.'
Update-EdgeState $defaultState $initial
Assert-Equal $true $defaultState.Right 'Manual flush placement captures right anchor.'
Assert-Equal $true $defaultState.Bottom 'Manual flush placement captures bottom anchor.'
Assert-Equal 0 $defaultState.RightGap 'Manual flush placement captures zero right gap.'
Assert-Equal 0 $defaultState.BottomGap 'Manual flush placement captures zero bottom gap.'

# The CMD launch mode uses a wider acquisition zone and normalizes recognized
# edges to zero. Chromium's 31/33 px default inset should therefore be pulled
# flush instead of being preserved as the desired gap.
$savedSnapDistance = $SnapDistance
$savedFlushEdges = $FlushEdges
try {
    $SnapDistance = 48
    $FlushEdges = $true
    $launchInset = New-TestWindow -Left 519 -Top 667 -Width 450 -Height 300
    $launchState = Get-EdgeState $launchInset
    Assert-Equal $true $launchState.Right 'Launcher acquires 31-pixel right inset.'
    Assert-Equal $true $launchState.Bottom 'Launcher acquires 33-pixel bottom inset.'
    Assert-Equal 0 $launchState.RightGap 'Launcher normalizes right gap to zero.'
    Assert-Equal 0 $launchState.BottomGap 'Launcher normalizes bottom gap to zero.'
    $launchOrigin = Get-DesiredOrigin $launchState $launchInset
    Assert-Equal 550 $launchOrigin.X 'Launcher snaps right edge flush.'
    Assert-Equal 700 $launchOrigin.Y 'Launcher snaps bottom edge flush.'

    # A missing axis can also be acquired later without recapturing or dropping
    # an existing anchor. This covers custom Vivaldi PiP drag behavior.
    $rightOnlyWindow = New-TestWindow -Left 551 -Top 640 -Width 450 -Height 300
    $rightOnlyState = Get-EdgeState $rightOnlyWindow
    Assert-Equal $true $rightOnlyState.Right 'Right-only setup captures right edge.'
    Assert-Equal $false $rightOnlyState.Bottom 'Right-only setup starts without bottom edge.'
    $movedNearBottom = New-TestWindow -Left 551 -Top 669 -Width 450 -Height 300
    Assert-Equal $true (Add-MissingEdgeAnchors $rightOnlyState $movedNearBottom) 'Missing bottom edge is acquired while running.'
    Assert-Equal $true $rightOnlyState.Bottom 'Bottom anchor added without dropping right.'
    Assert-Equal 0 $rightOnlyState.BottomGap 'New bottom anchor is normalized flush.'
    $twoAxisOrigin = Get-DesiredOrigin $rightOnlyState $movedNearBottom
    Assert-Equal 550 $twoAxisOrigin.X 'Existing right anchor remains flush.'
    Assert-Equal 700 $twoAxisOrigin.Y 'New bottom anchor snaps flush.'
} finally {
    $SnapDistance = $savedSnapDistance
    $FlushEdges = $savedFlushEdges
}

$launcherText = Get-Content -LiteralPath (Join-Path $PSScriptRoot '..\Start-PipEdgeKeeper.cmd') -Raw
Assert-Equal $true ($launcherText -match '-SnapDistance 64\s+-FlushEdges\s+-UseMonitorBounds') 'CMD enables physical-screen flush mode.'

# Work-area bottom is the taskbar top; monitor bottom is the physical screen
# edge. The CMD mode must deliberately use the latter.
$savedUseMonitorBounds = $UseMonitorBounds
try {
    $SnapDistance = 64
    $FlushEdges = $true
    $taskbarWindow = New-TestWindow -Left 550 -Top 652 -Width 450 -Height 300 -WorkHeight 952 -MonitorHeight 1000

    $UseMonitorBounds = $false
    $workAreaState = Get-EdgeState $taskbarWindow
    Assert-Equal $true $workAreaState.Bottom 'Work-area mode recognizes taskbar-top placement.'
    $workAreaOrigin = Get-DesiredOrigin $workAreaState $taskbarWindow
    Assert-Equal 652 $workAreaOrigin.Y 'Work-area mode stops above taskbar.'

    $UseMonitorBounds = $true
    $monitorState = Get-EdgeState $taskbarWindow
    Assert-Equal $true $monitorState.Bottom 'Monitor mode recognizes taskbar-height inset.'
    Assert-Equal 0 $monitorState.BottomGap 'Monitor mode normalizes physical bottom gap.'
    $monitorOrigin = Get-DesiredOrigin $monitorState $taskbarWindow
    Assert-Equal 700 $monitorOrigin.Y 'Monitor mode moves PiP to physical screen bottom.'
} finally {
    $UseMonitorBounds = $savedUseMonitorBounds
    $SnapDistance = $savedSnapDistance
    $FlushEdges = $savedFlushEdges
}

# Preserve the original edge gaps when Chromium also changes the window size.
$resizedAndDrifted = New-TestWindow -Left 388 -Top 688 -Width 600 -Height 300
$restoredAfterResize = Get-DesiredOrigin $state $resizedAndDrifted
Assert-Equal 400 $restoredAfterResize.X 'Resized right-edge restoration.'
Assert-Equal 700 $restoredAfterResize.Y 'Resized bottom-edge restoration.'

# Preserve negative GetWindowRect gaps caused by invisible Windows resize borders.
$bordered = New-TestWindow -Left 542 -Top 692 -Width 466 -Height 316
$borderState = Get-EdgeState $bordered
Assert-Equal $true $borderState.Right 'Invisible-border right anchor detection.'
Assert-Equal $true $borderState.Bottom 'Invisible-border bottom anchor detection.'
$borderDrifted = New-TestWindow -Left 530 -Top 680 -Width 466 -Height 316
$borderRestored = Get-DesiredOrigin $borderState $borderDrifted
Assert-Equal 542 $borderRestored.X 'Invisible-border right gap preservation.'
Assert-Equal 692 $borderRestored.Y 'Invisible-border bottom gap preservation.'

# Multi-monitor coordinates, including negative origins, should remain correct.
$leftMonitorInitial = New-TestWindow -Left -450 -Top 700 -Width 450 -Height 300 -WorkLeft -1000
$leftMonitorState = Get-EdgeState $leftMonitorInitial
$leftMonitorDrifted = New-TestWindow -Left -462 -Top 688 -Width 450 -Height 300 -WorkLeft -1000
$leftMonitorRestored = Get-DesiredOrigin $leftMonitorState $leftMonitorDrifted
Assert-Equal -450 $leftMonitorRestored.X 'Negative-origin right-edge restoration.'
Assert-Equal 700 $leftMonitorRestored.Y 'Negative-origin bottom-edge restoration.'

# A center window must not be moved.
$center = New-TestWindow -Left 250 -Top 250 -Width 450 -Height 300
$centerState = Get-EdgeState $center
$centerOrigin = Get-DesiredOrigin $centerState $center
Assert-Equal 250 $centerOrigin.X 'Center x preservation.'
Assert-Equal 250 $centerOrigin.Y 'Center y preservation.'

Write-Host 'All PiP edge keeper tests passed.'
