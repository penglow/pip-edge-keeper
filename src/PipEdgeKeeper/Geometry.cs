using System;
using System.Drawing;

namespace PipEdgeKeeper
{
    internal struct NativeRect
    {
        public int Left;
        public int Top;
        public int Right;
        public int Bottom;

        public int Width
        {
            get { return Right - Left; }
        }

        public int Height
        {
            get { return Bottom - Top; }
        }
    }

    internal sealed class WindowSnapshot
    {
        public IntPtr Handle;
        public string Title;
        public uint ProcessId;
        public NativeRect Bounds;
        public NativeRect WorkArea;
        public NativeRect MonitorBounds;
    }

    internal sealed class EdgeState
    {
        public bool Left;
        public bool Right;
        public bool Top;
        public bool Bottom;
        public int LeftGap;
        public int RightGap;
        public int TopGap;
        public int BottomGap;
        public bool Interacting;
        public string Title;
        public uint ProcessId;
    }
}
