// SPDX-License-Identifier: GPL-3.0-only
// Runs the installed WinForms/WebView2 host against its bundled R, with disposable studies.
using System.Diagnostics;
using System.Text;
using System.Text.Json;
using Microsoft.Web.WebView2.Core;

namespace RDataCraft;

internal static class NativeTests
{
    private static readonly List<string> Checks = [];
    private static bool finished;
    private static void Check(bool condition, string label)
    { if (!condition) throw new Exception(label); Checks.Add(label); }
    private static async Task Wait(Func<Task<bool>> predicate, string label, int seconds = 45)
    {
        var deadline = DateTime.UtcNow.AddSeconds(seconds);
        while (DateTime.UtcNow < deadline) { if (await predicate()) return; await Task.Delay(200); }
        throw new TimeoutException(label);
    }
    private static Task<string> JS(StudyWindow window, string script) => window.Web.CoreWebView2.ExecuteScriptAsync(script);
    private static Task Until(StudyWindow window, string expression, string label) => Wait(async () => await JS(window, "Boolean(" + expression + ")") == "true", label);
    private static Task FileReady(string path) => Wait(() => Task.FromResult(File.Exists(path) && new FileInfo(path).Length > 50), "File not saved: " + Path.GetFileName(path));

    internal static async Task Run(StudyWindow window, string folder)
    {
        IDataObject? originalClipboard = null;
        try
        {
            originalClipboard = Clipboard.GetDataObject();
            await Wait(() => Task.FromResult(window.Ready), "Native bridge did not connect", 120);
            Check(window.MainMenuStrip?.Items.Count >= 5, "Native menus are present");
            Check(!window.HasDocument, "Cold startup opens no study");
            Check(!window.Trusted("https://example.com/") && !window.Trusted("file:///C:/private") && !window.Trusted("http://127.0.0.1:1/"), "Remote pages and other local ports cannot use the host bridge");
            Check(window.PermissionAllowed(window.Web.Source.AbsoluteUri, CoreWebView2PermissionKind.MultipleAutomaticDownloads) &&
                !window.PermissionAllowed("https://example.com/", CoreWebView2PermissionKind.MultipleAutomaticDownloads) &&
                !window.PermissionAllowed(window.Web.Source.AbsoluteUri, CoreWebView2PermissionKind.Camera),
                "Successive exports are allowed only for the local app; unrelated permissions are denied");
            await Until(window, "document.body.dataset.runtime==='desktop'", "Desktop runtime bridge missing");
            Checks.Add("Embedded interface uses desktop mode");
            await window.OpenFile(Path.Combine(Program.Backend, "examples", "RDataCraft examples.rdatacraft"));
            await Until(window, "document.querySelector('#data_grid table')!==null && !document.documentElement.classList.contains('shiny-busy')", "Example data did not load");
            Checks.Add("Bundled R opens the example study");
            await Until(window, "getComputedStyle(document.documentElement).getPropertyValue('--accent').trim()==='#247763'", "App colors differ");
            await using (var file = File.Create(Path.Combine(folder, "data.png"))) await window.Web.CoreWebView2.CapturePreviewAsync(CoreWebView2CapturePreviewImageFormat.Png, file);
            window.Command("figure");
            await Until(window, "document.querySelector('#figure svg.graph-interactive')!==null && !document.documentElement.classList.contains('shiny-busy')", "Graph did not render");
            await JS(window, "document.getElementById('title').value='Windows desktop test';document.getElementById('title').dispatchEvent(new Event('change',{bubbles:true}));");
            await Wait(() => Task.FromResult(window.Dirty), "Native dirty state did not update");
            Check(!window.ConfirmClose(DialogResult.Cancel) && !window.IsDisposed, "Cancel closing preserves the edited study");
            string project = Path.Combine(folder, "Native study.rdatacraft");
            window.NextTestDestination = project; window.Save(true);
            await FileReady(project);
            await Wait(() => Task.FromResult(!window.Dirty && window.ProjectPath == project), "Native saved state did not update");
            using (var json = JsonDocument.Parse(File.ReadAllText(project))) Check(json.RootElement.GetProperty("format").GetString() == "rdatacraft", "Native Save writes a valid study");
            Check(window.Text.Contains("RDataCraft") && !window.Text.StartsWith("●"), "Saved native window title clears the edit marker");
            foreach (string format in new[] { "svg", "pdf", "png" })
            {
                string path = Path.Combine(folder, "figure." + format);
                window.NextTestDestination = path; window.Command("export-" + format);
                await FileReady(path);
                byte[] bytes = File.ReadAllBytes(path);
                Check(format == "svg" ? Encoding.UTF8.GetString(bytes).Contains("<svg") : format == "pdf" ? bytes.AsSpan().StartsWith("%PDF"u8) : bytes.AsSpan().StartsWith(new byte[] { 137, 80, 78, 71 }), "Native " + format.ToUpper() + " export");
            }
            window.Command("copy-vector");
            await Wait(() => Task.FromResult(Clipboard.ContainsData("image/svg+xml") && Clipboard.ContainsData("application/pdf")), "Vector clipboard missing");
            Checks.Add("Windows clipboard exposes SVG and PDF vector formats");
            await window.Send(new { type = "new" });
            await Until(window, "document.getElementById('title').value==='Untitled figure' && document.querySelector('#nav_data.active')!==null", "New blank study did not open");
            await window.OpenFile(project);
            await Until(window, "document.getElementById('title').value==='Windows desktop test'", "Saved study did not reopen");
            Checks.Add("Native Open restores the saved figure settings");
            await JS(window, "window.RDataCraftDesktop.receive({type:'command',name:'help'})");
            await Until(window, "document.getElementById('help_search')!==null", "Help did not open");
            Checks.Add("Offline examples and analysis help opens");
            await JS(window, "document.querySelector('.modal.show [data-bs-dismiss=modal],.modal.show [data-dismiss=modal]')?.click()");
            await Until(window, "document.querySelector('.modal.show')===null", "Help did not close");
            await JS(window, "Shiny.setInputValue('advanced_open',1,{priority:'event'})");
            await Until(window, "document.getElementById('nav_advanced').classList.contains('active') && document.getElementById('r_run')!==null", "Advanced R did not open");
            await JS(window, "document.getElementById('r_load_template').click()");
            await Until(window, "document.getElementById('r_code').value.includes('summary_table')", "Advanced R template did not load");
            await JS(window, "document.getElementById('r_run').click()");
            await Until(window, "document.getElementById('r_status').textContent.includes('R success') && document.querySelector('#r_results img.r-result-figure')?.complete===true", "Reviewed Advanced R script did not finish");
            Checks.Add("Advanced R worker returns results and a vector figure inside the native app");
            var second = Program.Open(newStudy: true); int secondPid = 0;
            await Wait(() => Task.FromResult(second.Ready && second.HasDocument), "Second native study did not start", 120);
            secondPid = second.EnginePid;
            Check(Program.Windows.Count == 2 && secondPid != window.EnginePid && second.HasDocument && !second.Dirty, "New study opens an independent blank document, native window and R engine");
            second.CloseForTest();
            await Wait(() => Task.FromResult(!ProcessExists(secondPid)), "Second window left its R engine running");
            Checks.Add("Closing a window stops its own bundled R engine");
            Check(window.Ready && ProcessExists(window.EnginePid), "Closing a second window preserves the first engine");
            var starting = Program.Open(newStudy: true);
            await Wait(() => Task.FromResult(starting.EnginePid > 0), "New engine did not start");
            int startingPid = starting.EnginePid;
            starting.CloseForTest();
            await Wait(() => Task.FromResult(!ProcessExists(startingPid)), "Closing during startup left an R engine running");
            Checks.Add("Closing a starting window cancels initialization and stops its R engine");
            await window.OpenFile(Path.Combine(Program.Backend, "examples", "Prism workflow improvements.rdatacraft"));
            await Until(window, "document.getElementById('fit_scope').value==='all' && document.getElementById('title').value==='Independent fits for each series'", "Regression example did not load");
            window.Command("figure");
            await Until(window, "document.querySelector('#figure svg.graph-interactive')?.textContent.includes('Independent fits for each series')===true", "Regression figure missing");
            Checks.Add("Linked multi-series regression renders in the embedded window");
            await using (var file = File.Create(Path.Combine(folder, "figure.png"))) await window.Web.CoreWebView2.CapturePreviewAsync(CoreWebView2CapturePreviewImageFormat.Png, file);
            File.WriteAllText(Path.Combine(folder, "validation-windows-desktop.json"), JsonSerializer.Serialize(new { version = "0.31", status = "passed", native_window = true, embedded_webview = true, bundled_R = true, external_browser_launched = false, engine_pid = window.EnginePid, checks = Checks }, new JsonSerializerOptions { WriteIndented = true }));
            finished = true; Program.Result = 0;
            window.CloseForTest();
        }
        catch (Exception error) { Fail(error, folder); }
        finally { try { if (originalClipboard != null) Clipboard.SetDataObject(originalClipboard, true); } catch { } }
    }
    private static bool ProcessExists(int pid) { try { using var p = Process.GetProcessById(pid); return !p.HasExited; } catch { return false; } }
    internal static void Fail(Exception error, string folder)
    {
        if (finished) return;
        finished = true; Program.Result = 1;
        Directory.CreateDirectory(folder);
        File.WriteAllText(Path.Combine(folder, "validation-windows-desktop.json"), JsonSerializer.Serialize(new { version = "0.31", status = "failed", error = error.ToString(), checks = Checks }, new JsonSerializerOptions { WriteIndented = true }));
        foreach (var window in Program.Windows.ToArray()) window.CloseForTest();
    }
}
