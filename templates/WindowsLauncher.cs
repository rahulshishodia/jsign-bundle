using System;
using System.Diagnostics;
using System.IO;

internal static class WindowsLauncher
{
    [STAThread]
    private static int Main(string[] args)
    {
        string root = AppContext.BaseDirectory.TrimEnd(Path.DirectorySeparatorChar);
        string integration = Path.Combine(root, "AllInOne");
        string config = Environment.GetEnvironmentVariable("JSIGNPDF_CONFIG_DIR");
        if (String.IsNullOrWhiteSpace(config))
            config = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "JSignPdf-AllInOne");
        Directory.CreateDirectory(config);

        string driver = Path.Combine(integration, "eps2003csp11.dll").Replace('\\', '/');
        File.WriteAllText(Path.Combine(config, "pkcs11.cfg"),
            "# Managed by JSignPDF All-in-One.\r\nname=HYP2003\r\nlibrary=\"" + driver + "\"\r\n");

        string original = File.ReadAllText(Path.Combine(integration, "original-executable")).Trim();
        var start = new ProcessStartInfo(Path.Combine(root, original));
        start.UseShellExecute = false;
        start.EnvironmentVariables["JSIGNPDF_CONFIG_DIR"] = config;
        start.Arguments = String.Join(" ", Array.ConvertAll(args,
            arg => "\"" + arg.Replace("\\", "\\\\").Replace("\"", "\\\"") + "\""));
        Process app = Process.Start(start);
        if (app == null) return 1;

        var updater = new ProcessStartInfo("powershell.exe");
        updater.UseShellExecute = false;
        updater.CreateNoWindow = true;
        updater.Arguments = "-NoProfile -ExecutionPolicy Bypass -File \"" +
            Path.Combine(integration, "update-windows.ps1") + "\" -AppDir \"" + root + "\" -AppPid " + app.Id;
        Process.Start(updater);

        app.WaitForExit();
        return app.ExitCode;
    }
}
