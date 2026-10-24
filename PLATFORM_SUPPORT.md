# RDataCraft platform builds

The scientific code, editable graph and figure-layout UI, project files and Prism converters are shared R/JavaScript code. Compiled R libraries must be rebuilt for each operating system and CPU. Do not copy the Mac runtime to Windows, or an Intel package library into an ARM runtime.

## Apple Silicon and Intel Macs

The native AppKit host supports both architectures. Build matching R runtimes without replacing another architecture's library:

```
python3 scripts/bootstrap.py --arch arm64 --runtime-root runtime-arm64
python3 scripts/build_desktop.py --arch arm64 --runtime-root runtime-arm64 --output "dist/RDataCraft 0.3 Apple Silicon.app"

python3 scripts/bootstrap.py --arch x86_64 --runtime-root runtime-intel
python3 scripts/build_desktop.py --arch x86_64 --runtime-root runtime-intel --output "dist/RDataCraft 0.3 Intel.app"
```

Apple Silicon uses ARM R and ARM packages (no Rosetta requirement) and requires macOS 14 or newer with the current R runtime. Intel builds use Intel R/packages and require macOS 13 or newer with the current host toolchain. Build checks reject mismatches; `--allow-rosetta` is an explicit development fallback. Earlier v0.1 was an ARM host with Intel R under Rosetta.

## Windows x64

Windows uses the same local app UI in the default browser, with file-upload controls and browser downloads in place of macOS native dialogs. Unzip a Windows portable bundle into a user-owned folder and launch **Launch RDataCraft.cmd**. Keep its console open; closing it stops the local engine. The workspace binds only to `127.0.0.1`, chooses an available port, and opens no study automatically. Browser tabs warn before closing unsaved work. Save projects through the app's Save button and reopen the downloaded `.rdatacraft` file to continue later.

A Windows portable bundle contains Windows R and compiled Windows packages. If using a source folder instead, install official x64 R, run `Rscript --vanilla scripts/install.R` from this folder, then launch the CMD file. PowerShell execution follows the user's normal execution policy; the launcher does not bypass or weaken it. If local policy blocks PS1 files, run `Rscript --vanilla scripts/portable.R` from an R-enabled terminal.

Double-click **Validate RDataCraft.cmd** to run the R regression suites with the bundled Windows engine, without installing Python or Node. It uses synthetic fixtures and writes logs plus `artifacts/validation-native-0.3.json`; it does not open or change user studies. This utility requires a Windows run to provide Windows execution evidence. The Python runner adds the JavaScript checks when Node is available.

Build the portable bundle on Windows after installing matching dependencies:

```
python scripts/test.py
python scripts/package_portable.py
```

The assistant's offline tools run on all three targets. The connected model uses the existing signed-in Codex CLI when its executable is installed. Prompts go through input files and an argument-array process API; shell execution is disabled for model requests. Model plans still pass the same local validators and require Apply to new table copy. Native macOS vector clipboard support is specific to the Mac host; Windows provides SVG/PDF/PNG exports.

## Verification and delivery

`.github/workflows/platform-builds.yml` defines separate Apple Silicon, Intel and Windows build/test jobs. Each job installs native packages, runs the complete numerical/workflow suite and packages its own artifact. It is a build recipe until it has actually run; a workflow file alone does not certify Windows or Intel hardware. Check the accompanying examination report for the platforms actually exercised in this session. Public distribution would additionally require Apple notarization and Windows code signing, which are not performed without the developer's signing credentials.

The current Windows deliverable is a local-browser portable build target, not a native Windows window host or a cross-compiled Mac binary. Windows ARM is not included in the verified target set.
