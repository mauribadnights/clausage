using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Text;
using System.Runtime.InteropServices;
using System.Windows.Forms;

namespace Clausage.Tray;

public static class IconRenderer
{
    public static readonly Color ColorGreen = Color.FromArgb(46, 204, 89);
    public static readonly Color ColorOrange = Color.FromArgb(255, 166, 0);
    public static readonly Color ColorRed = Color.FromArgb(242, 77, 64);
    public static readonly Color ColorGray = Color.FromArgb(128, 128, 128);

    private const int SM_CXSMICON = 49;

    [DllImport("user32.dll")]
    private static extern int GetSystemMetricsForDpi(int nIndex, uint dpi);

    [DllImport("user32.dll")]
    private static extern uint GetDpiForSystem();

    [DllImport("user32.dll", SetLastError = true)]
    private static extern IntPtr FindWindow(string lpClassName, string? lpWindowName);

    [DllImport("user32.dll")]
    private static extern uint GetDpiForWindow(IntPtr hwnd);

    /// Live tray icon size for the current DPI. Queries the actual taskbar DPI
    /// each time so it stays correct across restarts, monitor changes, and DPI changes.
    public static int SystemIconSize
    {
        get
        {
            try
            {
                // Prefer the taskbar's DPI — that's the surface our icon lands on
                IntPtr taskbar = FindWindow("Shell_TrayWnd", null);
                uint dpi = taskbar != IntPtr.Zero ? GetDpiForWindow(taskbar) : GetDpiForSystem();
                if (dpi == 0) dpi = 96;
                int size = GetSystemMetricsForDpi(SM_CXSMICON, dpi);
                return size > 0 ? size : (int)Math.Round(16.0 * dpi / 96.0);
            }
            catch
            {
                return 16;
            }
        }
    }

    public static Color UsageColor(double? pct)
    {
        if (pct == null) return ColorGray;
        if (pct < 50) return ColorGreen;
        if (pct < 80) return ColorOrange;
        return ColorRed;
    }

    public static Icon RenderNumberIcon(int? value, Color color, int size = 0)
    {
        if (size <= 0) size = SystemIconSize;

        using var bmp = new Bitmap(size, size);
        using var g = Graphics.FromImage(bmp);

        g.Clear(Color.Transparent);

        if (value == null)
        {
            g.SmoothingMode = SmoothingMode.AntiAlias;
            int r = Math.Max(2, size / 6);
            int cx = size / 2, cy = size / 2;
            using var brush = new SolidBrush(ColorGray);
            g.FillEllipse(brush, cx - r, cy - r, r * 2, r * 2);
        }
        else
        {
            g.SmoothingMode = SmoothingMode.AntiAlias;
            g.TextRenderingHint = TextRenderingHint.ClearTypeGridFit;

            string text = value >= 100 ? "!" : value.ToString()!;
            float fontSize = Math.Max(10f, size * 0.75f);

            using var font = CreateFont(fontSize);
            using var brush = new SolidBrush(color);

            var textSize = g.MeasureString(text, font, size, StringFormat.GenericTypographic);
            float x = (size - textSize.Width) / 2f;
            float y = (size - textSize.Height) / 2f;

            g.DrawString(text, font, brush, x, y, StringFormat.GenericTypographic);
        }

        return Icon.FromHandle(bmp.GetHicon());
    }

    private static Font CreateFont(float size)
    {
        foreach (var name in new[] { "Segoe UI Variable", "Segoe UI" })
        {
            try
            {
                var font = new Font(name, size, FontStyle.Bold, GraphicsUnit.Pixel);
                if (font.Name.StartsWith(name.Split(' ')[0], StringComparison.OrdinalIgnoreCase))
                    return font;
                font.Dispose();
            }
            catch { }
        }
        return new Font(FontFamily.GenericSansSerif, size, FontStyle.Bold, GraphicsUnit.Pixel);
    }
}
