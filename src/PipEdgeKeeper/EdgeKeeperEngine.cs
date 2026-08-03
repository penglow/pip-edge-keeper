using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.Text.RegularExpressions;

namespace PipEdgeKeeper
{
    internal sealed class EdgeKeeperEngine
    {
        private static readonly Regex PictureInPictureTitle =
            new Regex(
                @"^\s*picture[\s-]*in[\s-]*picture\s*$",
                RegexOptions.IgnoreCase | RegexOptions.CultureInvariant);

        private readonly AppSettings settings;
        private readonly Dictionary<IntPtr, EdgeState> trackedWindows;
        private readonly HashSet<string> browserProcessNames;

        public EdgeKeeperEngine(AppSettings settings)
        {
            this.settings = settings;
            trackedWindows = new Dictionary<IntPtr, EdgeState>();
            browserProcessNames = new HashSet<string>(
                new[]
                {
                    "chrome",
                    "vivaldi",
                    "msedge",
                    "brave",
                    "chromium",
                    "opera",
                    "opera_gx"
                },
                StringComparer.OrdinalIgnoreCase);
        }

        public void Reset()
        {
            trackedWindows.Clear();
        }

        public void Poll()
        {
            IntPtr moveSizeWindow = NativeMethods.GetMoveSizeWindow();
            HashSet<IntPtr> seenHandles = new HashSet<IntPtr>();

            foreach (WindowSnapshot window in
                     NativeMethods.GetTopLevelWindows())
            {
                if (!IsPictureInPictureTitle(window.Title) ||
                    !IsSupportedBrowser(window.ProcessId))
                {
                    continue;
                }

                seenHandles.Add(window.Handle);

                EdgeState state;
                if (trackedWindows.TryGetValue(window.Handle, out state) &&
                    (state.ProcessId != window.ProcessId ||
                     !String.Equals(
                         state.Title,
                         window.Title,
                         StringComparison.Ordinal)))
                {
                    trackedWindows.Remove(window.Handle);
                    state = null;
                }

                if (state == null)
                {
                    state = CaptureState(window, settings);
                    state.Interacting = moveSizeWindow == window.Handle;
                    trackedWindows[window.Handle] = state;
                    continue;
                }

                if (moveSizeWindow != IntPtr.Zero &&
                    moveSizeWindow == window.Handle)
                {
                    state.Interacting = true;
                    continue;
                }

                if (state.Interacting)
                {
                    trackedWindows[window.Handle] =
                        CaptureState(window, settings);
                    continue;
                }

                AddMissingAnchors(state, window, settings);
                Point desired = GetDesiredOrigin(state, window, settings);
                if (desired.X != window.Bounds.Left ||
                    desired.Y != window.Bounds.Top)
                {
                    NativeMethods.MoveWindow(
                        window.Handle,
                        desired.X,
                        desired.Y);
                }
            }

            List<IntPtr> closedHandles = new List<IntPtr>();
            foreach (IntPtr handle in trackedWindows.Keys)
            {
                if (!seenHandles.Contains(handle))
                {
                    closedHandles.Add(handle);
                }
            }

            foreach (IntPtr handle in closedHandles)
            {
                trackedWindows.Remove(handle);
            }
        }

        internal static bool IsPictureInPictureTitle(string title)
        {
            return title != null && PictureInPictureTitle.IsMatch(title);
        }

        internal static EdgeState CaptureState(
            WindowSnapshot window,
            AppSettings settings)
        {
            NativeRect area = GetPlacementArea(window, settings);
            int leftGap = window.Bounds.Left - area.Left;
            int rightGap = area.Right - window.Bounds.Right;
            int topGap = window.Bounds.Top - area.Top;
            int bottomGap = area.Bottom - window.Bounds.Bottom;

            bool left = Math.Abs(leftGap) <= settings.SnapDistance;
            bool right = Math.Abs(rightGap) <= settings.SnapDistance;
            bool top = Math.Abs(topGap) <= settings.SnapDistance;
            bool bottom = Math.Abs(bottomGap) <= settings.SnapDistance;

            return new EdgeState
            {
                Left = left,
                Right = right,
                Top = top,
                Bottom = bottom,
                LeftGap = settings.FlushEdges && left ? 0 : leftGap,
                RightGap = settings.FlushEdges && right ? 0 : rightGap,
                TopGap = settings.FlushEdges && top ? 0 : topGap,
                BottomGap = settings.FlushEdges && bottom ? 0 : bottomGap,
                Title = window.Title,
                ProcessId = window.ProcessId
            };
        }

        internal static bool AddMissingAnchors(
            EdgeState state,
            WindowSnapshot window,
            AppSettings settings)
        {
            EdgeState candidate = CaptureState(window, settings);
            bool changed = false;

            if (!state.Left && candidate.Left)
            {
                state.Left = true;
                state.LeftGap = candidate.LeftGap;
                changed = true;
            }
            if (!state.Right && candidate.Right)
            {
                state.Right = true;
                state.RightGap = candidate.RightGap;
                changed = true;
            }
            if (!state.Top && candidate.Top)
            {
                state.Top = true;
                state.TopGap = candidate.TopGap;
                changed = true;
            }
            if (!state.Bottom && candidate.Bottom)
            {
                state.Bottom = true;
                state.BottomGap = candidate.BottomGap;
                changed = true;
            }

            return changed;
        }

        internal static Point GetDesiredOrigin(
            EdgeState state,
            WindowSnapshot window,
            AppSettings settings)
        {
            NativeRect area = GetPlacementArea(window, settings);
            int x = window.Bounds.Left;
            int y = window.Bounds.Top;

            if (state.Right)
            {
                x = area.Right - state.RightGap - window.Bounds.Width;
            }
            else if (state.Left)
            {
                x = area.Left + state.LeftGap;
            }

            if (state.Bottom)
            {
                y = area.Bottom - state.BottomGap - window.Bounds.Height;
            }
            else if (state.Top)
            {
                y = area.Top + state.TopGap;
            }

            return new Point(x, y);
        }

        private static NativeRect GetPlacementArea(
            WindowSnapshot window,
            AppSettings settings)
        {
            return settings.UseMonitorBounds
                ? window.MonitorBounds
                : window.WorkArea;
        }

        private bool IsSupportedBrowser(uint processId)
        {
            try
            {
                using (Process process =
                       Process.GetProcessById((int)processId))
                {
                    return browserProcessNames.Contains(
                        process.ProcessName);
                }
            }
            catch
            {
                return false;
            }
        }
    }
}
