using System;
using System.Drawing;
using System.Windows.Forms;

namespace PipEdgeKeeper
{
    internal sealed class TrayApplicationContext : ApplicationContext
    {
        private readonly AppSettings settings;
        private readonly EdgeKeeperEngine engine;
        private readonly NotifyIcon trayIcon;
        private readonly ContextMenuStrip menu;
        private readonly ToolStripMenuItem pauseItem;
        private readonly Timer timer;
        private bool paused;

        public TrayApplicationContext(bool openSettings)
        {
            settings = AppSettings.Load();
            engine = new EdgeKeeperEngine(settings);

            menu = new ContextMenuStrip();

            ToolStripMenuItem settingsItem =
                new ToolStripMenuItem("Settings...");
            settingsItem.Font = new Font(
                settingsItem.Font,
                FontStyle.Bold);
            settingsItem.Click += delegate { OpenSettings(); };

            pauseItem = new ToolStripMenuItem("Pause edge keeping");
            pauseItem.CheckOnClick = true;
            pauseItem.Click += delegate { TogglePaused(); };

            ToolStripMenuItem exitItem =
                new ToolStripMenuItem("Exit");
            exitItem.Click += delegate { ExitThread(); };

            menu.Items.Add(settingsItem);
            menu.Items.Add(pauseItem);
            menu.Items.Add(new ToolStripSeparator());
            menu.Items.Add(exitItem);

            trayIcon = new NotifyIcon();
            trayIcon.ContextMenuStrip = menu;
            trayIcon.Icon = SystemIcons.Application;
            trayIcon.Text = "PiP Edge Keeper - Running";
            trayIcon.Visible = true;
            trayIcon.DoubleClick += delegate { OpenSettings(); };

            timer = new Timer();
            timer.Interval = settings.PollMilliseconds;
            timer.Tick += delegate { Poll(); };
            timer.Start();

            trayIcon.ShowBalloonTip(
                2000,
                "PiP Edge Keeper",
                "Running in the notification area. Right-click for options.",
                ToolTipIcon.Info);

            if (openSettings)
            {
                OpenSettings();
            }
        }

        protected override void ExitThreadCore()
        {
            timer.Stop();
            timer.Dispose();
            settings.Save();
            trayIcon.Visible = false;
            trayIcon.Dispose();
            menu.Dispose();
            base.ExitThreadCore();
        }

        private void Poll()
        {
            if (paused)
            {
                return;
            }

            try
            {
                engine.Poll();
            }
            catch (Exception error)
            {
                paused = true;
                pauseItem.Checked = true;
                UpdateStatus();
                trayIcon.ShowBalloonTip(
                    4000,
                    "PiP Edge Keeper paused",
                    error.Message,
                    ToolTipIcon.Error);
            }
        }

        private void TogglePaused()
        {
            paused = pauseItem.Checked;
            engine.Reset();
            UpdateStatus();
        }

        private void UpdateStatus()
        {
            trayIcon.Text = paused
                ? "PiP Edge Keeper - Paused"
                : "PiP Edge Keeper - Running";
        }

        private void OpenSettings()
        {
            using (SettingsForm form = new SettingsForm(settings))
            {
                if (form.ShowDialog() == DialogResult.OK)
                {
                    engine.Reset();
                    timer.Interval = settings.PollMilliseconds;
                }
            }
        }
    }
}
