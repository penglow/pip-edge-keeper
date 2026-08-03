using System;
using System.Threading;
using System.Windows.Forms;

namespace PipEdgeKeeper
{
    internal static class Program
    {
        [STAThread]
        private static void Main(string[] arguments)
        {
            bool createdNew;
            using (Mutex mutex = new Mutex(
                       true,
                       @"Local\PipEdgeKeeper",
                       out createdNew))
            {
                if (!createdNew)
                {
                    return;
                }

                Application.EnableVisualStyles();
                Application.SetCompatibleTextRenderingDefault(false);

                try
                {
                    bool openSettings =
                        Array.IndexOf(arguments, "--settings") >= 0;
                    Application.Run(
                        new TrayApplicationContext(openSettings));
                }
                catch (Exception error)
                {
                    MessageBox.Show(
                        error.ToString(),
                        "PiP Edge Keeper",
                        MessageBoxButtons.OK,
                        MessageBoxIcon.Error);
                }
            }
        }
    }
}
