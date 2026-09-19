using System;
using System.Diagnostics;
using System.IO;
using System.IO.Compression;
using System.Reflection;
using System.Security.Cryptography;
using System.Text;
using System.Windows.Forms;

internal static class Setup
{
    private const string PayloadHash = "__PAYLOAD_SHA256__";
    private static string Quote(string value)
    {
        var output = new StringBuilder("\"");
        int slashes = 0;
        foreach (char c in value)
        {
            if (c == '\\') { slashes++; continue; }
            if (c == '"') { output.Append('\\', slashes * 2 + 1); output.Append(c); slashes = 0; continue; }
            output.Append('\\', slashes); slashes = 0; output.Append(c);
        }
        output.Append('\\', slashes * 2); output.Append('"');
        return output.ToString();
    }

    private static void Extract(string directory)
    {
        string root = Path.GetFullPath(directory);
        if (Directory.Exists(root) || File.Exists(root)) throw new IOException("Extraction destination must not already exist.");
        using (Stream payload = Assembly.GetExecutingAssembly().GetManifestResourceStream("VideoAI.Package.zip"))
        using (var bytes = new MemoryStream())
        {
            payload.CopyTo(bytes);
            using (var sha = SHA256.Create())
            {
                string actual = BitConverter.ToString(sha.ComputeHash(bytes.ToArray())).Replace("-", "");
                if (actual != PayloadHash) throw new IOException("Embedded payload integrity check failed.");
            }
            bytes.Position = 0;
            using (var zip = new ZipArchive(bytes, ZipArchiveMode.Read))
            {
                string prefix = root.TrimEnd(Path.DirectorySeparatorChar) + Path.DirectorySeparatorChar;
                foreach (var entry in zip.Entries)
                {
                    string target = Path.GetFullPath(Path.Combine(root, entry.FullName));
                    if (!target.StartsWith(prefix, StringComparison.OrdinalIgnoreCase)) throw new IOException("Unsafe archive path.");
                    Directory.CreateDirectory(Path.GetDirectoryName(target));
                    using (Stream input = entry.Open())
                    using (Stream output = new FileStream(target, FileMode.CreateNew, FileAccess.Write))
                        input.CopyTo(output);
                }
            }
        }
    }

    [STAThread]
    private static int Main(string[] args)
    {
        string root = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Programs", "VideoAI");
        string extract = null;
        bool quiet = Array.IndexOf(args, "--quiet") >= 0, prepare = false, whatIf = false;
        string stage = null;
        string log = Path.Combine(Path.GetTempPath(), "VideoAI-Setup-" + Guid.NewGuid().ToString("N") + ".log");
        try
        {
            for (int i = 0; i < args.Length; i++)
            {
                switch (args[i])
                {
                    case "--quiet": quiet = true; break;
                    case "--prepare-runtime": prepare = true; break;
                    case "--what-if": whatIf = true; break;
                    case "--install-root":
                        if (++i >= args.Length) throw new ArgumentException("--install-root needs a path.");
                        root = args[i]; break;
                    case "--extract":
                        if (++i >= args.Length) throw new ArgumentException("--extract needs a new directory path.");
                        extract = args[i]; break;
                    default: throw new ArgumentException("Options: --quiet --what-if --prepare-runtime --install-root PATH --extract NEW_DIRECTORY");
                }
            }
            if (extract != null) { Extract(extract); return 0; }
            if (!quiet && MessageBox.Show(
                "Install VideoAI preview for this user?\n\nDestination: " + root +
                "\n\nRequires PowerShell 7, uv, FFmpeg, ffprobe, Deno, Chrome and NVIDIA/CUDA." +
                (prepare ? "\nRuntime package downloads are enabled." : "\nNo downloads: existing dependencies and cached runtime must be ready.") +
                "\nYour media and previous Tools installation will be preserved.",
                "VideoAI Setup", MessageBoxButtons.OKCancel, MessageBoxIcon.Information) != DialogResult.OK) return 0;
            string pwsh = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles), "PowerShell", "7", "pwsh.exe");
            if (!File.Exists(pwsh))
            {
                pwsh = null;
                foreach (string folder in (Environment.GetEnvironmentVariable("PATH") ?? "").Split(Path.PathSeparator))
                {
                    string candidate = Path.Combine(folder.Trim('"'), "pwsh.exe");
                    if (Path.IsPathRooted(candidate) && File.Exists(candidate)) { pwsh = candidate; break; }
                }
            }
            if (pwsh == null) throw new IOException("Install PowerShell 7 first: https://learn.microsoft.com/powershell/scripting/install/installing-powershell-on-windows");
            stage = Path.Combine(Path.GetTempPath(), "VideoAI-Setup-" + Guid.NewGuid().ToString("N"));
            Extract(stage);
            string command = "-NoLogo -NoProfile -File " + Quote(Path.Combine(stage, "Install-VideoAI.ps1")) + " -InstallRoot " + Quote(root);
            if (prepare) command += " -PrepareRuntime";
            if (whatIf) command += " -WhatIf";
            var start = new ProcessStartInfo(pwsh, command);
            start.UseShellExecute = false;
            start.CreateNoWindow = true;
            start.RedirectStandardOutput = true;
            start.RedirectStandardError = true;
            int code;
            using (var process = Process.Start(start))
            {
                var stdout = process.StandardOutput.ReadToEndAsync();
                var stderr = process.StandardError.ReadToEndAsync();
                process.WaitForExit();
                File.WriteAllText(log, stdout.Result + Environment.NewLine + stderr.Result);
                code = process.ExitCode;
            }
            if (!quiet) MessageBox.Show(
                code == 0 ? (whatIf ? "Validation completed; no installation changes made." : "VideoAI installed.\n\nLaunch with PowerShell 7:\n" + Path.Combine(root, "Start-VideoAI.ps1"))
                          : "Installation did not complete. Review:\n" + log,
                "VideoAI Setup", MessageBoxButtons.OK, code == 0 ? MessageBoxIcon.Information : MessageBoxIcon.Error);
            return code;
        }
        catch (Exception error)
        {
            File.WriteAllText(log, error.ToString());
            if (!quiet) MessageBox.Show(error.Message + "\n\nLog: " + log, "VideoAI Setup", MessageBoxButtons.OK, MessageBoxIcon.Error);
            return 1;
        }
        finally
        {
            if (stage != null && Directory.Exists(stage))
            {
                string prefix = Path.GetFullPath(Path.GetTempPath()).TrimEnd(Path.DirectorySeparatorChar) + Path.DirectorySeparatorChar;
                if (Path.GetFullPath(stage).StartsWith(prefix, StringComparison.OrdinalIgnoreCase) &&
                    Path.GetFileName(stage).StartsWith("VideoAI-Setup-", StringComparison.Ordinal))
                    Directory.Delete(stage, true);
            }
        }
    }
}
