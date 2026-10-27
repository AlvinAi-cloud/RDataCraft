// SPDX-License-Identifier: GPL-3.0-only
using System.Diagnostics;
using System.Net;
using System.Net.Sockets;
using System.Runtime.InteropServices;
using System.Text;
using System.Text.Json;
using Microsoft.Web.WebView2.Core;
using Microsoft.Web.WebView2.WinForms;

namespace RDataCraft;

internal static class Program
{
    internal static string Backend = AppContext.BaseDirectory;
    internal static string? TestFolder;
    internal static readonly List<StudyWindow> Windows = [];
    internal static ApplicationContext Context = null!;
    internal static int Result;

    [STAThread]
    private static int Main(string[] args)
    {
        // This probe does not create a window, run R, or install anything.
        if (args.Contains("--check-runtime"))
        {
            try { return string.IsNullOrEmpty(CoreWebView2Environment.GetAvailableBrowserVersionString()) ? 1 : 0; }
            catch { return 1; }
        }
        ApplicationConfiguration.Initialize();
        try
        {
            foreach (string arg in args)
            {
                if (arg.StartsWith("--backend=")) Backend = Path.GetFullPath(arg[10..]);
                if (arg.StartsWith("--native-test=")) TestFolder = Path.GetFullPath(arg[14..]);
            }
            if (!File.Exists(Path.Combine(Backend, "app.R"))) throw new Exception("The application files are missing. Reinstall RDataCraft.");
            if (TestFolder != null)
            {
                if (Directory.Exists(TestFolder) && Directory.EnumerateFileSystemEntries(TestFolder).Any())
                    throw new Exception("Native tests require a new empty output folder.");
                Directory.CreateDirectory(TestFolder);
            }
            Context = new ApplicationContext();
            Open(args.FirstOrDefault(a => !a.StartsWith("--") && File.Exists(a)));
            Application.Run(Context);
        }
        catch (Exception error)
        {
            Result = 1;
            if (TestFolder != null) File.WriteAllText(Path.Combine(TestFolder, "startup-error.txt"), error.ToString());
            else MessageBox.Show(error.Message, "RDataCraft", MessageBoxButtons.OK, MessageBoxIcon.Error);
        }
        return Result;
    }

    internal static StudyWindow Open(string? path = null, bool newStudy = false)
    {
        if (path != null)
        {
            path = Path.GetFullPath(path);
            var existing = Windows.FirstOrDefault(w => string.Equals(w.ProjectPath, path, StringComparison.OrdinalIgnoreCase));
            if (existing != null) { existing.Activate(); return existing; }
        }
        var window = new StudyWindow(path, newStudy);
        Windows.Add(window);
        window.FormClosed += (_, _) => { Windows.Remove(window); if (Windows.Count == 0) Context.ExitThread(); };
        window.Show();
        return window;
    }
}

internal sealed class StudyWindow : Form
{
    internal readonly WebView2 Web = new() { Dock = DockStyle.Fill };
    private readonly Label loading = new() { Dock = DockStyle.Fill, TextAlign = ContentAlignment.MiddleCenter, Text = "Starting RDataCraft…", Font = new Font("Segoe UI", 13) };
    private readonly CancellationTokenSource closing = new();
    private readonly string session = Guid.NewGuid().ToString("N");
    private readonly string? initialPath;
    private readonly bool startsNewStudy;
    private readonly string logPath;
    private readonly string profile;
    private readonly object logLock = new();
    private readonly HashSet<CoreWebView2DownloadOperation> downloads = [];
    private OwnedProcess? engine;
    private Uri endpoint = null!;
    internal bool Ready, Dirty, HasDocument;
    internal string? ProjectPath;
    private string studyName = "Untitled Study";
    private bool forceSaveAs, allowClose, savingToClose;
    internal string? NextTestDestination;
    internal int EnginePid => engine?.Id ?? 0;

    internal StudyWindow(string? path, bool newStudy)
    {
        initialPath = path;
        startsNewStudy = newStudy;
        Text = "RDataCraft";
        Size = new Size(1380, 940);
        MinimumSize = new Size(960, 680);
        StartPosition = FormStartPosition.CenterScreen;
        Icon = Icon.ExtractAssociatedIcon(Environment.ProcessPath!);
        AutoScaleMode = AutoScaleMode.Dpi;
        string local = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "RDataCraft");
        Directory.CreateDirectory(Path.Combine(local, "logs"));
        logPath = Path.Combine(local, "logs", session + ".log");
        profile = Path.Combine(local, "WebView2", session);
        Controls.Add(Web); Controls.Add(loading);
        MainMenuStrip = BuildMenu(); Controls.Add(MainMenuStrip);
        Shown += async (_, _) => await StartAsync();
        FormClosing += OnClosing;
        FormClosed += (_, _) =>
        {
            closing.Cancel();
            foreach (var download in downloads.ToArray()) { try { download.Cancel(); } catch { } }
            Web.Dispose(); engine?.Dispose();
            if (Program.TestFolder != null) { try { File.Copy(logPath, Path.Combine(Program.TestFolder, "engine-" + session + ".log")); } catch { } }
            closing.Dispose();
            // Chromium can briefly retain profile handles after disposal.
            _ = Task.Run(async () => { for (int i = 0; i < 10; i++) { try { Directory.Delete(profile, true); break; } catch { await Task.Delay(500); } } });
        };
    }

    private MenuStrip BuildMenu()
    {
        var bar = new MenuStrip();
        ToolStripMenuItem Menu(string title) { var m = new ToolStripMenuItem(title); bar.Items.Add(m); return m; }
        void Item(ToolStripMenuItem menu, string title, Keys keys, Action action)
        { var item = new ToolStripMenuItem(title, null, (_, _) => action()) { ShortcutKeys = keys }; menu.DropDownItems.Add(item); }
        var file = Menu("&File");
        Item(file, "&New study", Keys.Control | Keys.N, () => Program.Open(newStudy: true));
        Item(file, "&Open study…", Keys.Control | Keys.O, OpenDialog);
        Item(file, "&Import data or Prism project…", Keys.Control | Keys.I, ImportDialog);
        file.DropDownItems.Add(new ToolStripSeparator());
        Item(file, "&Save", Keys.Control | Keys.S, () => Save(false));
        Item(file, "Save &as…", Keys.Control | Keys.Shift | Keys.S, () => Save(true));
        Item(file, "Close window", Keys.Control | Keys.W, Close);
        var edit = Menu("&Edit");
        Item(edit, "Undo", Keys.Control | Keys.Z, () => Command("undo"));
        Item(edit, "Redo", Keys.Control | Keys.Y, () => Command("redo"));
        Item(edit, "Copy vector figure", Keys.Control | Keys.Shift | Keys.C, () => Command("copy-vector"));
        var view = Menu("&View");
        foreach (string name in new[] { "data", "analysis", "figure", "layout", "project", "inspector", "assistant" })
        { string command = name; Item(view, char.ToUpper(name[0]) + name[1..], Keys.None, () => Command(command)); }
        var ai = Menu("&AI");
        Item(ai, "AI Assistant", Keys.None, () => Command("assistant"));
        Item(ai, "Accounts and Models…", Keys.None, () => Command("ai-accounts"));
        var export = Menu("E&xport");
        foreach (string format in new[] { "svg", "pdf", "png" })
        { string command = "export-" + format; Item(export, "Figure as " + format.ToUpper() + "…", Keys.None, () => Command(command)); }
        var help = Menu("&Help");
        Item(help, "Examples & analysis guide", Keys.F1, () => Command("help"));
        Item(help, "Show engine log", Keys.None, () => Process.Start(new ProcessStartInfo("notepad.exe") { ArgumentList = { logPath }, UseShellExecute = false }));
        Item(help, "About RDataCraft", Keys.None, () => MessageBox.Show(this,
            "RDataCraft v0.34\nScientific data analysis and publication-ready figures, powered by R.\n\nGPL-3.0. Third-party notices are included in the application folder.", "About RDataCraft", MessageBoxButtons.OK, MessageBoxIcon.Information));
        return bar;
    }

    private void Log(string? text)
    {
        if (text == null) return;
        lock (logLock)
        {
            // Bound each window's engine log; it may contain imported data errors.
            if (File.Exists(logPath) && new FileInfo(logPath).Length > 4 * 1024 * 1024) return;
            try { File.AppendAllText(logPath, text + Environment.NewLine); } catch { }
        }
    }

    private async Task StartAsync()
    {
        CancellationToken token = closing.Token;
        try
        {
            string runtime = Path.Combine(Program.Backend, "runtime"), home = Path.Combine(runtime, "R");
            string rscript = Path.Combine(home, "bin", "x64", "Rscript.exe");
            if (!File.Exists(rscript)) rscript = Path.Combine(home, "bin", "Rscript.exe");
            if (!File.Exists(rscript)) throw new Exception("The bundled R engine is missing. Reinstall RDataCraft.");
            using (var listener = new TcpListener(IPAddress.Loopback, 0))
            { listener.Start(); endpoint = new Uri($"http://127.0.0.1:{((IPEndPoint)listener.LocalEndpoint).Port}/"); }
            var start = new ProcessStartInfo(rscript) { WorkingDirectory = Program.Backend, UseShellExecute = false, CreateNoWindow = true, RedirectStandardError = true, RedirectStandardOutput = true };
            foreach (string arg in new[] { "--vanilla", "scripts/run.R", $"--port={endpoint.Port}", "--no-browser" }) start.ArgumentList.Add(arg);
            start.Environment["R_HOME"] = home; start.Environment["RHOME"] = home;
            start.Environment["R_LIBS_USER"] = Path.Combine(runtime, "library");
            start.Environment["R_LIBS_SITE"] = ""; start.Environment["R_LIBS"] = "";
            start.Environment["RDATACRAFT_RUNTIME"] = runtime;
            start.Environment["RDATACRAFT_DESKTOP"] = "1";
            start.Environment["RDATACRAFT_NATIVE_HOST"] = "windows";
            start.Environment["RDATACRAFT_PORTABLE"] = "1"; // Use the shared R assistant transport.
            start.Environment["RDATACRAFT_PARENT_PID"] = Environment.ProcessId.ToString();
            start.Environment["R_USER_CACHE_DIR"] = Path.Combine(Path.GetDirectoryName(Path.GetDirectoryName(logPath))!, "cache");
            engine = OwnedProcess.Start(start, Log);
            using var client = new HttpClient(new HttpClientHandler { UseProxy = false }) { Timeout = TimeSpan.FromSeconds(2) };
            var deadline = DateTime.UtcNow.AddSeconds(100);
            while (true)
            {
                token.ThrowIfCancellationRequested();
                if (engine.HasExited) throw new Exception("The R engine stopped during startup. See Help → Show engine log.");
                try { using var response = await client.GetAsync(endpoint, token); if (response.IsSuccessStatusCode) break; }
                catch (HttpRequestException) { } catch (TaskCanceledException) when (!token.IsCancellationRequested) { }
                if (DateTime.UtcNow > deadline) throw new Exception("RDataCraft took too long to start. See Help → Show engine log.");
                await Task.Delay(250, token);
            }
            var options = new CoreWebView2EnvironmentOptions { AllowSingleSignOnUsingOSPrimaryAccount = false };
            var environment = await CoreWebView2Environment.CreateAsync(null, profile, options);
            await Web.EnsureCoreWebView2Async(environment);
            token.ThrowIfCancellationRequested();
            var core = Web.CoreWebView2;
            core.Settings.AreDevToolsEnabled = Program.TestFolder != null;
            core.Settings.AreDefaultContextMenusEnabled = true;
            core.Settings.AreBrowserAcceleratorKeysEnabled = false;
            core.Settings.IsStatusBarEnabled = false;
            core.Settings.IsPasswordAutosaveEnabled = false;
            core.Settings.IsGeneralAutofillEnabled = false;
            core.Settings.AreHostObjectsAllowed = false;
            core.PermissionRequested += (_, e) =>
            {
                bool allowed = PermissionAllowed(e.Uri, e.PermissionKind);
                Log("Permission " + e.PermissionKind + ": " + (allowed ? "allowed" : "denied"));
                e.State = allowed ? CoreWebView2PermissionState.Allow : CoreWebView2PermissionState.Deny;
                e.SavesInProfile = false; e.Handled = true;
            };
            core.NavigationStarting += (_, e) => { if (!Trusted(e.Uri)) { e.Cancel = true; if (e.IsUserInitiated) External(e.Uri); } };
            core.FrameNavigationStarting += (_, e) => { if (!Trusted(e.Uri) && !e.Uri.StartsWith("about:") && !e.Uri.StartsWith("blob:" + endpoint.GetLeftPart(UriPartial.Authority))) e.Cancel = true; };
            core.NewWindowRequested += (_, e) => { e.Handled = true; if (e.IsUserInitiated) External(e.Uri); };
            core.WebMessageReceived += OnMessage;
            core.DownloadStarting += OnDownload;
            core.ProcessFailed += (_, _) => { Log("The embedded web view stopped."); loading.Text = "The application view stopped. Close and reopen this window."; loading.Show(); };
            string origin = JsonSerializer.Serialize(endpoint.GetLeftPart(UriPartial.Authority));
            await core.AddScriptToExecuteOnDocumentCreatedAsync($"if(window===window.top&&location.origin==={origin}){{window.webkit={{messageHandlers:{{rdatacraft:{{postMessage:body=>window.chrome.webview.postMessage(body)}}}}}};}}");
            core.Navigate(endpoint.AbsoluteUri);
            if (Program.TestFolder != null && Program.Windows.Count == 1) _ = NativeTests.Run(this, Program.TestFolder);
        }
        catch (Exception) when (token.IsCancellationRequested || IsDisposed) { }
        catch (Exception error)
        {
            Log(error.ToString());
            loading.Text = error.Message + "\n\nSee Help → Show engine log. The WebView2 runtime is included by the Windows installer.";
            if (Program.TestFolder != null) NativeTests.Fail(error, Program.TestFolder);
        }
    }

    internal bool Trusted(string url) => Uri.TryCreate(url, UriKind.Absolute, out var uri) && uri.Scheme == "http" && uri.Host == "127.0.0.1" && uri.Port == endpoint.Port;
    internal bool PermissionAllowed(string url, CoreWebView2PermissionKind permission) =>
        Trusted(url) && permission == CoreWebView2PermissionKind.MultipleAutomaticDownloads;

    private void External(string url)
    {
        // Never forward local paths or custom executable protocols from web content.
        if (Program.TestFolder != null) return;
        if (Uri.TryCreate(url, UriKind.Absolute, out var uri) && uri.Scheme is "https" or "http")
            Process.Start(new ProcessStartInfo(uri.AbsoluteUri) { UseShellExecute = true });
    }

    internal async Task Send(object message)
    {
        if (Ready && !Web.IsDisposed) await Web.CoreWebView2.ExecuteScriptAsync($"window.RDataCraftDesktop.receive({JsonSerializer.Serialize(message)})");
    }
    internal async void Command(string name)
    {
        try { await Send(new { type = "command", name }); } catch (Exception error) { Log(error.Message); }
    }
    internal void Save(bool saveAs)
    {
        if (!Ready || !HasDocument) { savingToClose = false; return; }
        forceSaveAs = saveAs; Command("save");
    }

    private async void OnMessage(object? sender, CoreWebView2WebMessageReceivedEventArgs e)
    {
        if (!Trusted(e.Source)) return;
        try
        {
            if (e.WebMessageAsJson.Length > 100_000_000) return;
            using var document = JsonDocument.Parse(e.WebMessageAsJson);
            var data = document.RootElement;
            string type = data.GetProperty("type").GetString() ?? "";
            switch (type)
            {
                case "ready":
                    if (Ready) break;
                    Ready = true; loading.Hide(); Web.BringToFront(); MainMenuStrip!.BringToFront();
                    if (initialPath != null) await OpenFile(initialPath);
                    else if (startsNewStudy) await Send(new { type = "new" });
                    break;
                case "document":
                    HasDocument = data.TryGetProperty("open", out var open) && open.ValueKind == JsonValueKind.True;
                    Dirty = data.TryGetProperty("dirty", out var dirty) && dirty.ValueKind == JsonValueKind.True;
                    ProjectPath = data.TryGetProperty("path", out var path) && path.ValueKind == JsonValueKind.String && !string.IsNullOrWhiteSpace(path.GetString()) ? path.GetString() : null;
                    studyName = data.TryGetProperty("name", out var name) && name.ValueKind == JsonValueKind.String ? name.GetString()! : "Untitled Study";
                    Text = (Dirty ? "● " : "") + (HasDocument ? studyName + " — " : "") + "RDataCraft";
                    if (savingToClose && !Dirty) { allowClose = true; Close(); } break;
                case "command":
                    switch (data.GetProperty("name").GetString())
                    { case "new": Program.Open(newStudy: true); break; case "open": OpenDialog(); break; case "import": ImportDialog(); break; case "save-as": Save(true); break; }
                    break;
                case "ai-status":
                    await Web.CoreWebView2.ExecuteScriptAsync("Shiny.setInputValue('assistant_connection',{nonce:Date.now()},{priority:'event'})"); break;
                case "vector":
                    CopyVector(data); await Send(new { type = "vector-result", ok = true, message = "Vector PDF and SVG copied." }); break;
                case "error": Log(data.GetProperty("message").GetString()); break;
            }
        }
        catch (Exception error)
        {
            Log(error.Message);
            try { await Send(new { type = "vector-result", ok = false, message = "The clipboard could not be updated. Use SVG or PDF export." }); } catch { }
        }
    }

    private void CopyVector(JsonElement data)
    {
        string svg = data.GetProperty("svg").GetString() ?? "", encoded = data.GetProperty("pdf").GetString() ?? "";
        if (svg.Length > 40_000_000 || encoded.Length > 60_000_000 || !svg.Contains("<svg")) throw new Exception("Invalid vector graph.");
        byte[] pdf = Convert.FromBase64String(encoded);
        if (!pdf.AsSpan().StartsWith("%PDF"u8)) throw new Exception("Invalid PDF graph.");
        var clipboard = new DataObject();
        clipboard.SetData("image/svg+xml", false, new MemoryStream(Encoding.UTF8.GetBytes(svg)));
        clipboard.SetData("application/pdf", false, new MemoryStream(pdf));
        clipboard.SetData("PDF", false, new MemoryStream(pdf));
        Clipboard.SetDataObject(clipboard, true, 5, 100);
    }

    private void OpenDialog()
    {
        using var dialog = new OpenFileDialog { Title = "Open study", Filter = "RDataCraft studies|*.rdatacraft;*.plotcraft;*.json|Prism projects|*.prism;*.pzfx;*.pzf|All files|*.*" };
        if (dialog.ShowDialog(this) == DialogResult.OK) { if (HasDocument) Program.Open(dialog.FileName); else _ = OpenFile(dialog.FileName); }
    }
    private async void ImportDialog()
    {
        using var dialog = new OpenFileDialog { Title = "Import data or Prism project", Filter = "Data and Prism projects|*.csv;*.tsv;*.txt;*.xlsx;*.prism;*.pzfx;*.pzf|All files|*.*" };
        if (dialog.ShowDialog(this) == DialogResult.OK) await OpenFile(dialog.FileName);
    }
    internal Task OpenFile(string path)
    {
        string type = Path.GetExtension(path).ToLowerInvariant() switch
        { ".prism" or ".pzfx" or ".pzf" => "prism", ".csv" or ".tsv" or ".txt" or ".xlsx" => "import", _ => "open" };
        return Send(new { type, path = Path.GetFullPath(path) });
    }

    private void OnDownload(object? sender, CoreWebView2DownloadStartingEventArgs e)
    {
        var deferral = e.GetDeferral();
        try
        {
            if (!Trusted(e.DownloadOperation.Uri)) { Log("Download rejected: untrusted origin."); e.Cancel = true; return; }
            string filename = Path.GetFileName(e.ResultFilePath);
            Log("Download requested: " + filename);
            bool project = filename.EndsWith(".rdatacraft", StringComparison.OrdinalIgnoreCase);
            string? destination = NextTestDestination; NextTestDestination = null;
            if (destination == null && project && !forceSaveAs) destination = ProjectPath;
            forceSaveAs = false;
            if (destination == null)
            {
                using var dialog = new SaveFileDialog { Title = project ? "Save study" : "Export figure or results", FileName = filename, AddExtension = true, DefaultExt = Path.GetExtension(filename).TrimStart('.'), Filter = "Selected format|*" + Path.GetExtension(filename) + "|All files|*.*", OverwritePrompt = true };
                if (dialog.ShowDialog(this) == DialogResult.OK) destination = dialog.FileName;
            }
            if (destination == null) { e.Cancel = true; savingToClose = false; return; }
            destination = Path.GetFullPath(destination);
            // Download to a sibling temporary file; preserve the existing study on interruption.
            string temporary = Path.Combine(Path.GetDirectoryName(destination)!, ".rdatacraft-" + Guid.NewGuid().ToString("N") + ".tmp");
            e.ResultFilePath = temporary; e.Handled = true;
            var operation = e.DownloadOperation; downloads.Add(operation);
            operation.StateChanged += async (_, _) =>
            {
                if (operation.State == CoreWebView2DownloadState.InProgress) return;
                downloads.Remove(operation);
                try
                {
                    if (operation.State == CoreWebView2DownloadState.Completed)
                    {
                        File.Move(temporary, destination, true);
                        Log("Saved " + Path.GetFileName(destination));
                        if (project) await Send(new { type = "saved", path = destination });
                    }
                    else { savingToClose = false; Log("Download interrupted: " + operation.InterruptReason); if (Program.TestFolder == null) MessageBox.Show(this, "The file could not be saved. Your existing file has been kept.", "RDataCraft"); }
                }
                catch (Exception error) { savingToClose = false; Log(error.ToString()); if (Program.TestFolder == null) MessageBox.Show(this, error.Message, "Unable to save"); }
                finally { try { File.Delete(temporary); } catch { } }
            };
        }
        catch (Exception error) { e.Cancel = true; savingToClose = false; Log(error.ToString()); }
        finally { deferral.Complete(); }
    }

    internal bool ConfirmClose(DialogResult? testChoice = null)
    {
        if (!Dirty) return true;
        DialogResult choice = testChoice ?? MessageBox.Show(this, $"Save changes to {studyName} before closing?", "RDataCraft", MessageBoxButtons.YesNoCancel, MessageBoxIcon.Question);
        if (choice == DialogResult.Cancel) return false;
        if (choice == DialogResult.No) return true;
        savingToClose = true; Save(false); return false;
    }
    private void OnClosing(object? sender, FormClosingEventArgs e)
    { if (!allowClose) e.Cancel = !ConfirmClose(); }
    internal void CloseForTest() { allowClose = true; Close(); }
}

// A Windows job owns only this window's R process and its analysis workers.
// Closing the host also terminates its workers after a crash or forced exit.
internal sealed class OwnedProcess : IDisposable
{
    private readonly Process process;
    private readonly nint job;
    internal int Id => process.Id;
    internal bool HasExited => process.HasExited;
    private OwnedProcess(Process process, nint job) { this.process = process; this.job = job; }
    internal static OwnedProcess Start(ProcessStartInfo start, Action<string?> log)
    {
        nint job = CreateJobObjectW(0, null);
        if (job == 0) throw new System.ComponentModel.Win32Exception();
        var limits = new ExtendedLimits(); limits.Basic.LimitFlags = 0x2000; // JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE
        if (!SetInformationJobObject(job, 9, ref limits, (uint)Marshal.SizeOf<ExtendedLimits>())) { CloseHandle(job); throw new System.ComponentModel.Win32Exception(); }
        var process = new Process { StartInfo = start };
        try
        {
            process.OutputDataReceived += (_, e) => log(e.Data); process.ErrorDataReceived += (_, e) => log(e.Data);
            process.Start();
            if (!AssignProcessToJobObject(job, process.Handle)) throw new System.ComponentModel.Win32Exception();
            process.BeginOutputReadLine(); process.BeginErrorReadLine();
            return new OwnedProcess(process, job);
        }
        catch { try { if (!process.HasExited) process.Kill(true); } catch { } process.Dispose(); CloseHandle(job); throw; }
    }
    public void Dispose()
    { CloseHandle(job); try { if (!process.WaitForExit(3000)) process.Kill(true); } catch { } process.Dispose(); }
    [StructLayout(LayoutKind.Sequential)] private struct BasicLimits { public long PerProcessUserTimeLimit, PerJobUserTimeLimit; public uint LimitFlags; public nuint MinimumWorkingSetSize, MaximumWorkingSetSize; public uint ActiveProcessLimit; public nuint Affinity; public uint PriorityClass, SchedulingClass; }
    [StructLayout(LayoutKind.Sequential)] private struct IoCounters { public ulong ReadOperationCount, WriteOperationCount, OtherOperationCount, ReadTransferCount, WriteTransferCount, OtherTransferCount; }
    [StructLayout(LayoutKind.Sequential)] private struct ExtendedLimits { public BasicLimits Basic; public IoCounters Io; public nuint ProcessMemoryLimit, JobMemoryLimit, PeakProcessMemoryUsed, PeakJobMemoryUsed; }
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)] private static extern nint CreateJobObjectW(nint attributes, string? name);
    [DllImport("kernel32.dll", SetLastError = true)] [return: MarshalAs(UnmanagedType.Bool)] private static extern bool SetInformationJobObject(nint job, int infoClass, ref ExtendedLimits info, uint length);
    [DllImport("kernel32.dll", SetLastError = true)] [return: MarshalAs(UnmanagedType.Bool)] private static extern bool AssignProcessToJobObject(nint job, nint process);
    [DllImport("kernel32.dll")] [return: MarshalAs(UnmanagedType.Bool)] private static extern bool CloseHandle(nint handle);
}
