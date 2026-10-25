The v0.31 revision includes a bundled Rust AI connection service. Rebuild and test every platform after this source change; previous v0.3 installer results do not certify v0.31. Direct ChatGPT sign-in and provider transport have synthetic/local tests; live account eligibility and paid provider requests require user acceptance testing.

# RDataCraft v0.31 release preparation

## Suggested GitHub description

Open-source scientific plotting and statistics powered by R, with editable tables,
curve fitting, PCA and optional AI-assisted analysis.

## Suggested introduction

RDataCraft is an open-source, R-powered workspace for scientific data analysis
and publication-quality figures. It brings editable data tables, linked graphs,
statistical workflows, curve fitting, PCA and multi-panel layouts into one local
application. Advanced R analysis supports methods beyond the presets, with
reviewed scripts, optional AI assistance and approval before installing missing
packages. Studies retain data, settings, analysis code and saved results.

Mac and Windows x64 editions use dedicated desktop windows with native menus
and file dialogs. The Windows installer includes Microsoft WebView2. Packaged editions include R and required packages.
Connected AI requests use an external service when the user chooses to send them.

## GitHub Desktop

Use the source folder `dist/RDataCraft-0.31-GitHub`, rather than this entire working
directory. It excludes private studies, runtimes, installers and test artifacts.

1. In GitHub Desktop, select **File → Add Local Repository** and choose that folder.
   If Desktop says it is not a Git repository, use its **create a repository here**
   link. Keep the existing README, license and ignore files.
2. Review the changed files and commit the prepared source. Choose **Publish
   repository**, name it **RDataCraft**, and select the intended visibility.
3. Open the repository on GitHub. The **Actions → Native platform validation**
   workflow runs tests on Intel Mac, Apple Silicon and Windows. Review every job.
   It now exercises the Mac app from the read-only disk image and the Windows
   setup/uninstall path. Reports upload automatically. Binary artifact upload is
   a separate manual opt-in for development testing.
4. Create a **draft** release tagged **v0.31** after resolving the remaining checks.
   Attach installer files as release assets. Keep all final checksums and validation
   reports together. Complete the native-source review and attach the required
   corresponding source/build material before publishing bundled binaries.

No repository or release has been created by the local preparation tools. Desktop
does not supply Apple/Windows signing credentials or itself run target-platform
tests. [GitHub's Desktop instructions](https://docs.github.com/en/desktop/adding-and-cloning-repositories/adding-a-repository-from-your-local-computer-to-github-desktop).

## Signing setup

No distribution signing credentials are currently configured. Current installers
are release candidates: Mac signatures are ad-hoc and Windows setup is unsigned.
The following tools are prepared but their credential-dependent paths have not
been executed. A signing plan or a script is not a signed release.

For Mac, obtain an Apple Developer ID Application certificate/private key through
your Apple developer account and configure a `notarytool` Keychain profile locally.
Keep credentials in Keychain or protected CI secrets, never source files or chat.
Preview the work without changing the app:

```sh
python3 scripts/sign_macos.py --app "dist/RDataCraft 0.3 Intel.app"
```

After setup, use `--apply --output NEW-APP-PATH --identity FULL-IDENTITY-NAME
--notary-profile PROFILE-NAME`. The tool signs a separate copy, signs nested code
before containers, enables hardened runtime, submits to Apple, requires Accepted,
staples the ticket and runs Gatekeeper checks. Only R executable processes get
exceptions for loading user-approved R packages and the bundled library path.
Run the native workflow tests again on the signed copy, especially Advanced R and
new package loading. Package it with `package_installers.py --distribution`.
The disk image itself may additionally be Developer ID signed/notarized before
the final checksum. [Apple's notarization requirements](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution).

For Windows, obtain a trusted code-signing certificate/service with a private key
accessible through the Windows certificate provider. Install the Windows SDK's
SignTool. The current tool supports a certificate in the current user's My store,
including a compatible hardware/provider-backed certificate; a cloud service
that exposes a different API needs its provider integration first.

Run Windows packaging with `--distribution --sign-certificate PUBLIC-THUMBPRINT
--timestamp-url PROVIDER-HTTPS-ENDPOINT --signtool SIGNTOOL-PATH`. NSIS hooks sign
and verify both setup and its embedded uninstaller. Verification requires a valid
signature, an RFC 3161 timestamp and the selected signer. No passwords or private
keys are passed by the build script. Test installation/uninstallation again after
signing. [Microsoft SignTool documentation](https://learn.microsoft.com/en-us/windows/win32/seccrypto/signtool).

## Final binary release gates

- Passing reports for the exact final packages on all target systems, including
  clean machines without system R and a Windows embedded-window workflow check.
- Native corresponding-source/build coverage completed; see
  [the source review](licenses/NATIVE_SOURCE_REVIEW.md) and
  [redistribution status](licenses/REDISTRIBUTION.md).
- Trusted signing/notarization verified where planned, with signed-runtime tests.
- Regenerated SHA-256 hashes after all signing, stapling and packaging changes.
- Optional connected AI and vector paste checked in the intended external apps;
  clearly disclose any remaining limitations in the release notes.

The local report accompanying v0.31 distinguishes executed checks from pending
checks. Do not relabel earlier v0.25 installers as v0.31; rebuild them from this
source so internal version metadata and download names agree.
