# RDataCraft platform builds

The scientific code, editable graph and figure-layout UI, project files and Prism converters are shared R/JavaScript code. Compiled R libraries must be rebuilt for each operating system and CPU. Do not copy the Mac runtime to Windows, or an Intel package library into an ARM runtime.

## Apple Silicon and Intel Macs

The native AppKit host supports both architectures. Build matching R runtimes without replacing another architecture's library:

```
python3 scripts/bootstrap.py --arch arm64 --runtime-root runtime-arm64
python3 scripts/build_desktop.py --arch arm64 --runtime-root runtime-arm64 --output "dist/RDataCraft v0.33 Apple Silicon.app"

python3 scripts/bootstrap.py --arch x86_64 --runtime-root runtime-intel
python3 scripts/build_desktop.py --arch x86_64 --runtime-root runtime-intel --output "dist/RDataCraft v0.33.app"
```

Apple Silicon uses ARM R and ARM packages (no Rosetta requirement) and requires macOS 14 or newer with the current R runtime. Intel builds use Intel R/packages and require macOS 13 or newer with the current host toolchain. Build checks reject mismatches; `--allow-rosetta` is an explicit development fallback. Earlier v0.1 was an ARM host with Intel R under Rosetta.

## Windows x64

Install the Windows x64 setup and open **RDataCraft** from the Start menu, or unzip a portable bundle and open **RDataCraft.exe**. The app has a native WinForms window, menus and Open/Save dialogs. Microsoft WebView2 renders the shared interface inside that window; no external browser or console is opened. R and Windows packages are bundled, and .NET is self-contained. The installer supplies the official Evergreen WebView2 runtime when missing; that shared Microsoft component receives its own security updates.

Each New study opens another window with its own R engine. Closing an edited study offers Save, Don’t save or Cancel. Closing a window stops its R engine and analysis workers. Help → Show engine log displays startup errors. The internal engine binds only to `127.0.0.1`; the native bridge accepts messages only from that window’s endpoint.

For source development, install official x64 R and the .NET 10 SDK, then run `Rscript --vanilla scripts/install.R`. The CMD launcher uses the native executable when packaged. Without it, the source launcher retains the optional local browser workflow. PowerShell execution follows the user's normal execution policy; the launcher does not bypass it.

Double-click **Validate RDataCraft.cmd** to run the R regression suites with the bundled Windows engine, without installing Python or Node. It uses synthetic fixtures and writes logs plus `artifacts/validation-native-0.33.json`; it does not open or change user studies. This utility requires a Windows run to provide Windows execution evidence. The Python runner adds the JavaScript checks when Node is available.

Build the portable bundle on Windows after installing matching dependencies:

```
python scripts/test.py
python scripts/build_windows.py
python scripts/package_portable.py --native-host artifacts/windows-host
```

The assistant's offline tools run on all three targets. The connected assistant uses the bundled native AI service. Users can sign in with an eligible ChatGPT account or connect an OpenAI, Claude, Gemini or compatible/local API service through AI → Accounts and Models. No Codex installation is required. Credentials stay in the local app profile outside studies; model requests have no shell or computer-control tools. Model plans still pass the same local validators and require Apply to new table copy. Both desktop hosts expose PDF/SVG clipboard data. Direct paste depends on the receiving application; SVG/PDF/PNG file exports are also available.

## Verification and delivery

`.github/workflows/platform-builds.yml` defines separate Apple Silicon, Intel and Windows build/test jobs. Each job installs native packages, runs the complete numerical/workflow suite and packages its own artifact. It is a build recipe until it has actually run; a workflow file alone does not certify Windows or Intel hardware. Check the accompanying examination report for the platforms actually exercised in this session. Public distribution would additionally require Apple notarization and Windows code signing, which are not performed without the developer's signing credentials.

Windows packages contain an x64 GUI executable and bundled Windows R. The host can be cross-compiled, but its embedded-window tests must run on Windows. Windows ARM is not included in the verified target set.
