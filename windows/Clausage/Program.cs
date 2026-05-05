using Clausage.Tray;

namespace Clausage;

static class Program
{
    [STAThread]
    static void Main()
    {
        // Single instance check
        using var mutex = new Mutex(true, "ClausageWindowsSingleInstance", out bool isNew);
        if (!isNew)
        {
            MessageBox.Show("Clausage is already running.", "Clausage",
                MessageBoxButtons.OK, MessageBoxIcon.Information);
            return;
        }

        Application.EnableVisualStyles();
        Application.SetCompatibleTextRenderingDefault(false);
        Application.SetHighDpiMode(HighDpiMode.PerMonitorV2);
        Application.Run(new ClausageApp());
    }
}
