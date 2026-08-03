using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Text;

namespace PipEdgeKeeper
{
    internal static class NativeMethods
    {
        private const uint MonitorDefaultToNearest = 2;
        private const uint NoSize = 0x0001;
        private const uint NoZOrder = 0x0004;
        private const uint NoActivate = 0x0010;
        private const uint AsyncWindowPosition = 0x4000;

        private delegate bool EnumWindowsCallback(
            IntPtr window,
            IntPtr parameter);

        [StructLayout(LayoutKind.Sequential)]
        private struct GuiThreadInfo
        {
            public int Size;
            public uint Flags;
            public IntPtr ActiveWindow;
            public IntPtr FocusWindow;
            public IntPtr CaptureWindow;
            public IntPtr MenuOwnerWindow;
            public IntPtr MoveSizeWindow;
            public IntPtr CaretWindow;
            public NativeRect CaretRect;
        }

        [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Auto)]
        private struct MonitorInfo
        {
            public int Size;
            public NativeRect Monitor;
            public NativeRect WorkArea;
            public uint Flags;
        }

        [DllImport("user32.dll")]
        private static extern bool EnumWindows(
            EnumWindowsCallback callback,
            IntPtr parameter);

        [DllImport("user32.dll")]
        private static extern bool IsWindowVisible(IntPtr window);

        [DllImport("user32.dll", CharSet = CharSet.Unicode)]
        private static extern int GetWindowTextLength(IntPtr window);

        [DllImport("user32.dll", CharSet = CharSet.Unicode)]
        private static extern int GetWindowText(
            IntPtr window,
            StringBuilder text,
            int maximumCount);

        [DllImport("user32.dll")]
        private static extern uint GetWindowThreadProcessId(
            IntPtr window,
            out uint processId);

        [DllImport("user32.dll")]
        private static extern bool GetWindowRect(
            IntPtr window,
            out NativeRect bounds);

        [DllImport("user32.dll")]
        private static extern IntPtr MonitorFromWindow(
            IntPtr window,
            uint flags);

        [DllImport("user32.dll", CharSet = CharSet.Auto)]
        private static extern bool GetMonitorInfo(
            IntPtr monitor,
            ref MonitorInfo info);

        [DllImport("user32.dll")]
        private static extern bool GetGUIThreadInfo(
            uint threadId,
            ref GuiThreadInfo info);

        [DllImport("user32.dll")]
        private static extern bool SetWindowPos(
            IntPtr window,
            IntPtr insertAfter,
            int x,
            int y,
            int width,
            int height,
            uint flags);

        public static IList<WindowSnapshot> GetTopLevelWindows()
        {
            List<WindowSnapshot> windows = new List<WindowSnapshot>();

            EnumWindows(
                delegate(IntPtr window, IntPtr parameter)
                {
                    if (!IsWindowVisible(window))
                    {
                        return true;
                    }

                    int titleLength = GetWindowTextLength(window);
                    if (titleLength == 0)
                    {
                        return true;
                    }

                    StringBuilder title =
                        new StringBuilder(titleLength + 1);
                    GetWindowText(window, title, title.Capacity);

                    uint processId;
                    GetWindowThreadProcessId(window, out processId);

                    NativeRect bounds;
                    if (!GetWindowRect(window, out bounds))
                    {
                        return true;
                    }

                    IntPtr monitor = MonitorFromWindow(
                        window,
                        MonitorDefaultToNearest);
                    MonitorInfo monitorInfo = new MonitorInfo();
                    monitorInfo.Size =
                        Marshal.SizeOf(typeof(MonitorInfo));
                    if (!GetMonitorInfo(monitor, ref monitorInfo))
                    {
                        return true;
                    }

                    windows.Add(
                        new WindowSnapshot
                        {
                            Handle = window,
                            Title = title.ToString(),
                            ProcessId = processId,
                            Bounds = bounds,
                            WorkArea = monitorInfo.WorkArea,
                            MonitorBounds = monitorInfo.Monitor
                        });

                    return true;
                },
                IntPtr.Zero);

            return windows;
        }

        public static IntPtr GetMoveSizeWindow()
        {
            GuiThreadInfo info = new GuiThreadInfo();
            info.Size = Marshal.SizeOf(typeof(GuiThreadInfo));
            return GetGUIThreadInfo(0, ref info)
                ? info.MoveSizeWindow
                : IntPtr.Zero;
        }

        public static bool MoveWindow(IntPtr window, int x, int y)
        {
            uint flags =
                NoSize | NoZOrder | NoActivate | AsyncWindowPosition;
            return SetWindowPos(
                window,
                IntPtr.Zero,
                x,
                y,
                0,
                0,
                flags);
        }
    }
}
