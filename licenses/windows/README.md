# Windows desktop components

The Windows host source is covered by the application's GPL-3.0 license.
It uses the Microsoft WebView2 SDK under the included BSD-style license.
The self-contained .NET runtime and Windows Forms runtime retain their Microsoft
MIT license and third-party notices in `licenses/windows-host/` in binary bundles.
The build collects these notices directly from the pinned NuGet runtime packages.

The official, unmodified Microsoft Evergreen WebView2 runtime installer is a
separate Microsoft component. Setup installs it only when missing, under its own
Microsoft terms. It is shared with other applications, receives Microsoft updates,
and is retained when RDataCraft is uninstalled. It is not relicensed as GPL.
Its reviewed download URL and SHA-256 are recorded in
`config/windows-components.json`. Windows builds also require a valid Microsoft
Authenticode signature before packaging it.

- [Microsoft deployment and redistribution instructions](https://learn.microsoft.com/en-us/microsoft-edge/webview2/concepts/distribution)
- [Microsoft runtime download and terms](https://developer.microsoft.com/en-us/microsoft-edge/webview2/)
- [.NET runtime source and notices](https://github.com/dotnet/runtime)
- [Windows Forms source and notices](https://github.com/dotnet/winforms)

The existing R/native-library redistribution audit and signing release gates
still apply to final public installers. This component inventory does not certify
that those gates have been completed.
