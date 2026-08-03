using System;
using System.Drawing;
using System.Windows.Forms;

namespace PipEdgeKeeper
{
    internal sealed class SettingsForm : Form
    {
        private readonly AppSettings settings;
        private readonly NumericUpDown snapDistance;
        private readonly CheckBox flushEdges;
        private readonly CheckBox useMonitorBounds;

        public SettingsForm(AppSettings settings)
        {
            this.settings = settings;

            Text = "PiP Edge Keeper Settings";
            ClientSize = new Size(430, 245);
            FormBorderStyle = FormBorderStyle.FixedDialog;
            MaximizeBox = false;
            MinimizeBox = false;
            StartPosition = FormStartPosition.CenterScreen;
            AutoScaleMode = AutoScaleMode.Dpi;

            Label heading = new Label();
            heading.Text = "Picture-in-Picture edge behavior";
            heading.Font = new Font(
                Font,
                FontStyle.Bold);
            heading.AutoSize = true;
            heading.Location = new Point(18, 18);

            Label snapLabel = new Label();
            snapLabel.Text = "Recognize windows within:";
            snapLabel.AutoSize = true;
            snapLabel.Location = new Point(18, 59);

            snapDistance = new NumericUpDown();
            snapDistance.Minimum = 0;
            snapDistance.Maximum = 100;
            snapDistance.Value = settings.SnapDistance;
            snapDistance.Location = new Point(210, 56);
            snapDistance.Width = 70;

            Label pixelsLabel = new Label();
            pixelsLabel.Text = "pixels of an edge";
            pixelsLabel.AutoSize = true;
            pixelsLabel.Location = new Point(289, 59);

            flushEdges = new CheckBox();
            flushEdges.Text = "Snap recognized edges completely flush";
            flushEdges.Checked = settings.FlushEdges;
            flushEdges.AutoSize = true;
            flushEdges.Location = new Point(18, 94);

            useMonitorBounds = new CheckBox();
            useMonitorBounds.Text =
                "Use the physical screen edge (may overlap the taskbar)";
            useMonitorBounds.Checked = settings.UseMonitorBounds;
            useMonitorBounds.AutoSize = true;
            useMonitorBounds.Location = new Point(18, 124);

            Label note = new Label();
            note.Text =
                "Clear this option to keep bottom PiP windows above the taskbar.";
            note.ForeColor = SystemColors.GrayText;
            note.AutoSize = true;
            note.Location = new Point(36, 151);

            Button save = new Button();
            save.Text = "Save";
            save.DialogResult = DialogResult.OK;
            save.Location = new Point(248, 195);
            save.Size = new Size(75, 28);

            Button cancel = new Button();
            cancel.Text = "Cancel";
            cancel.DialogResult = DialogResult.Cancel;
            cancel.Location = new Point(333, 195);
            cancel.Size = new Size(75, 28);

            AcceptButton = save;
            CancelButton = cancel;

            Controls.Add(heading);
            Controls.Add(snapLabel);
            Controls.Add(snapDistance);
            Controls.Add(pixelsLabel);
            Controls.Add(flushEdges);
            Controls.Add(useMonitorBounds);
            Controls.Add(note);
            Controls.Add(save);
            Controls.Add(cancel);
        }

        protected override void OnFormClosing(FormClosingEventArgs e)
        {
            if (DialogResult == DialogResult.OK)
            {
                settings.SnapDistance = (int)snapDistance.Value;
                settings.FlushEdges = flushEdges.Checked;
                settings.UseMonitorBounds = useMonitorBounds.Checked;
                settings.Save();
            }

            base.OnFormClosing(e);
        }
    }
}
