using System;
using System.Drawing;

namespace PipEdgeKeeper
{
    internal static class EdgeKeeperTests
    {
        private static int failures;

        private static int Main()
        {
            TestTitleMatching();
            TestFlushCaptureAndRestoration();
            TestAsymmetricDrift();
            TestMissingAnchorAcquisition();
            TestWorkAreaAndMonitorBounds();
            TestResizeAndNegativeCoordinates();
            TestCenterWindow();

            if (failures > 0)
            {
                Console.Error.WriteLine(
                    failures + " PiP Edge Keeper test(s) failed.");
                return 1;
            }

            Console.WriteLine("All PiP Edge Keeper tests passed.");
            return 0;
        }

        private static void TestTitleMatching()
        {
            AssertEqual(
                true,
                EdgeKeeperEngine.IsPictureInPictureTitle(
                    "Picture in picture"),
                "Space-separated PiP title");
            AssertEqual(
                true,
                EdgeKeeperEngine.IsPictureInPictureTitle(
                    "Picture-in-Picture"),
                "Hyphenated PiP title");
            AssertEqual(
                false,
                EdgeKeeperEngine.IsPictureInPictureTitle(
                    "Picture-in-Picture API - Google Chrome"),
                "Ordinary browser title");
        }

        private static void TestFlushCaptureAndRestoration()
        {
            AppSettings settings = FlushSettings();
            WindowSnapshot initial =
                NewWindow(550, 700, 450, 300);
            initial.ProcessId = 1234;

            EdgeState state =
                EdgeKeeperEngine.CaptureState(initial, settings);
            AssertEqual(true, state.Right, "Right anchor capture");
            AssertEqual(true, state.Bottom, "Bottom anchor capture");
            AssertEqual(0, state.RightGap, "Right gap normalization");
            AssertEqual(0, state.BottomGap, "Bottom gap normalization");
            AssertEqual((uint)1234, state.ProcessId, "Process identity");

            WindowSnapshot drifted =
                NewWindow(538, 688, 450, 300);
            Point restored = EdgeKeeperEngine.GetDesiredOrigin(
                state,
                drifted,
                settings);
            AssertEqual(550, restored.X, "Right-edge restoration");
            AssertEqual(700, restored.Y, "Bottom-edge restoration");
        }

        private static void TestAsymmetricDrift()
        {
            AppSettings captureSettings = new AppSettings();
            captureSettings.SnapDistance = 20;
            captureSettings.FlushEdges = false;

            WindowSnapshot initial =
                NewWindow(550, 700, 450, 300);
            EdgeState state = EdgeKeeperEngine.CaptureState(
                initial,
                captureSettings);
            WindowSnapshot drifted =
                NewWindow(538, 667, 450, 300);
            EdgeState recaptured = EdgeKeeperEngine.CaptureState(
                drifted,
                captureSettings);

            AssertEqual(
                true,
                recaptured.Right,
                "12-pixel right drift remains in range");
            AssertEqual(
                false,
                recaptured.Bottom,
                "33-pixel bottom drift is out of range");

            Point restored = EdgeKeeperEngine.GetDesiredOrigin(
                state,
                drifted,
                captureSettings);
            AssertEqual(550, restored.X, "Asymmetric right restoration");
            AssertEqual(700, restored.Y, "Asymmetric bottom restoration");
        }

        private static void TestMissingAnchorAcquisition()
        {
            AppSettings settings = FlushSettings();
            WindowSnapshot rightOnly =
                NewWindow(551, 620, 450, 300);
            EdgeState state =
                EdgeKeeperEngine.CaptureState(rightOnly, settings);
            AssertEqual(true, state.Right, "Initial right anchor");
            AssertEqual(false, state.Bottom, "No initial bottom anchor");

            WindowSnapshot nearBottom =
                NewWindow(551, 669, 450, 300);
            bool changed = EdgeKeeperEngine.AddMissingAnchors(
                state,
                nearBottom,
                settings);
            AssertEqual(true, changed, "Bottom anchor added");
            AssertEqual(true, state.Bottom, "Bottom anchor state");
            AssertEqual(0, state.BottomGap, "Bottom gap normalization");
        }

        private static void TestWorkAreaAndMonitorBounds()
        {
            WindowSnapshot window = NewWindow(
                550,
                652,
                450,
                300,
                0,
                0,
                1000,
                952,
                0,
                0,
                1000,
                1000);

            AppSettings workAreaSettings = FlushSettings();
            workAreaSettings.UseMonitorBounds = false;
            EdgeState workAreaState = EdgeKeeperEngine.CaptureState(
                window,
                workAreaSettings);
            Point workAreaOrigin = EdgeKeeperEngine.GetDesiredOrigin(
                workAreaState,
                window,
                workAreaSettings);
            AssertEqual(652, workAreaOrigin.Y, "Taskbar-top placement");

            AppSettings monitorSettings = FlushSettings();
            EdgeState monitorState = EdgeKeeperEngine.CaptureState(
                window,
                monitorSettings);
            Point monitorOrigin = EdgeKeeperEngine.GetDesiredOrigin(
                monitorState,
                window,
                monitorSettings);
            AssertEqual(700, monitorOrigin.Y, "Physical-bottom placement");
        }

        private static void TestResizeAndNegativeCoordinates()
        {
            AppSettings settings = FlushSettings();
            EdgeState state = EdgeKeeperEngine.CaptureState(
                NewWindow(550, 700, 450, 300),
                settings);

            Point resized = EdgeKeeperEngine.GetDesiredOrigin(
                state,
                NewWindow(388, 688, 600, 300),
                settings);
            AssertEqual(400, resized.X, "Resized right-edge restoration");
            AssertEqual(700, resized.Y, "Resized bottom restoration");

            WindowSnapshot leftInitial = NewWindow(
                -450,
                700,
                450,
                300,
                -1000,
                0,
                1000,
                1000,
                -1000,
                0,
                1000,
                1000);
            EdgeState leftState = EdgeKeeperEngine.CaptureState(
                leftInitial,
                settings);
            WindowSnapshot leftDrifted = NewWindow(
                -462,
                688,
                450,
                300,
                -1000,
                0,
                1000,
                1000,
                -1000,
                0,
                1000,
                1000);
            Point leftRestored = EdgeKeeperEngine.GetDesiredOrigin(
                leftState,
                leftDrifted,
                settings);
            AssertEqual(-450, leftRestored.X, "Negative-origin restoration");
            AssertEqual(700, leftRestored.Y, "Negative-origin bottom");
        }

        private static void TestCenterWindow()
        {
            AppSettings settings = new AppSettings();
            settings.SnapDistance = 20;
            settings.FlushEdges = false;

            WindowSnapshot center =
                NewWindow(250, 250, 450, 300);
            EdgeState state =
                EdgeKeeperEngine.CaptureState(center, settings);
            Point desired = EdgeKeeperEngine.GetDesiredOrigin(
                state,
                center,
                settings);
            AssertEqual(250, desired.X, "Center x");
            AssertEqual(250, desired.Y, "Center y");
        }

        private static AppSettings FlushSettings()
        {
            AppSettings settings = new AppSettings();
            settings.SnapDistance = 64;
            settings.FlushEdges = true;
            settings.UseMonitorBounds = true;
            return settings;
        }

        private static WindowSnapshot NewWindow(
            int left,
            int top,
            int width,
            int height,
            int workLeft = 0,
            int workTop = 0,
            int workWidth = 1000,
            int workHeight = 1000,
            int monitorLeft = 0,
            int monitorTop = 0,
            int monitorWidth = 1000,
            int monitorHeight = 1000)
        {
            return new WindowSnapshot
            {
                Handle = new IntPtr(123),
                Title = "Picture in picture",
                Bounds = Rect(left, top, width, height),
                WorkArea =
                    Rect(workLeft, workTop, workWidth, workHeight),
                MonitorBounds =
                    Rect(
                        monitorLeft,
                        monitorTop,
                        monitorWidth,
                        monitorHeight)
            };
        }

        private static NativeRect Rect(
            int left,
            int top,
            int width,
            int height)
        {
            return new NativeRect
            {
                Left = left,
                Top = top,
                Right = left + width,
                Bottom = top + height
            };
        }

        private static void AssertEqual<T>(
            T expected,
            T actual,
            string message)
        {
            if (!Object.Equals(expected, actual))
            {
                failures += 1;
                Console.Error.WriteLine(
                    message + ": expected '" + expected +
                    "', got '" + actual + "'.");
            }
        }
    }
}
