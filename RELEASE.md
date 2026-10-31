# RDataCraft v0.4 release preparation

Open-source scientific plotting and statistics powered by R, with editable tables,
curve fitting, PCA and optional AI-assisted analysis.

## Keep the single main branch

The existing repository is https://github.com/AlvinAi-cloud/RDataCraft.
Use its existing GitHub Desktop checkout on **main**. The prepared source-only
folder is `dist/RDataCraft-0.4-GitHub`; it contains no installers or private studies.
Copy its source changes into the existing checkout, review them in GitHub Desktop,
commit **Prepare RDataCraft v0.4**, then **Push origin**. No new branch is needed.

## GitHub creates the three installers

A push to main runs **Actions → Native platform validation**. It collects the
pinned source material and notices, builds Intel Mac, Apple Silicon and Windows
installers on matching runners, runs the source tests, and exercises the installed
applications. The Mac tests run from the read-only disk image; Windows tests cover
setup, the embedded desktop window, bundled R, uninstall and study preservation.
The required Mac installed-app checks cover core study, multiwindow and graph workflows. Recent extended paste/layout and pilot-planning UI checks are excluded from GitHub runs, including the Windows pilot-planning UI sequence. Their numerical/server tests remain. Source tests include numerical power, pilot estimates, transformations and atomic table replacement.

After every required job passes, the workflow assembles a draft v0.4 release
with exactly three installer downloads, checksums, the combined validation report
and corresponding source/build material. It verifies GitHub’s uploaded asset
names, sizes and SHA-256 digests and the tested tag, then publishes the release.
A failed build or asset mismatch leaves it unpublished. The publication step is
authorized for this release; a published version is never overwritten. The release tag records the tested commit
and does not create another development branch.

Do not build the Windows installer on this Mac. Release installers should come
from the tested GitHub workflow. Local Mac app builds remain useful for UI review;
local DMGs and Windows setup generation are optional and skipped for this release.

After publishing, share these three links:

- [Intel Mac](https://github.com/AlvinAi-cloud/RDataCraft/releases/download/v0.4/RDataCraft-0.4-macos-x86_64.dmg)
- [Apple Silicon Mac](https://github.com/AlvinAi-cloud/RDataCraft/releases/download/v0.4/RDataCraft-0.4-macos-arm64.dmg)
- [Windows x64](https://github.com/AlvinAi-cloud/RDataCraft/releases/download/v0.4/RDataCraft-0.4-windows-x64-setup.exe)

These URLs become available when the draft is published; their presence here is
not evidence that the builds have run or passed.

## Signing and compatibility

GitHub runners do not supply signing credentials. Mac builds currently use ad-hoc
signatures and are not notarized; Windows setup is unsigned. Trusted signing needs
an Apple Developer ID/notarization setup and a Windows signing certificate/service.
The prepared signing tools remain available, but this workflow does not claim
trusted signing. Re-test final installers after any later signing changes.

Studies using the new XY connection/curve controls use project schema 12 and need
v0.32 or later. Older studies continue to open with their original automatic
connection behavior. The included release source material preserves the R/package,
native-toolchain and Rust sources/notices; bit-for-bit reproduction of upstream
CRAN binaries is not claimed. See [redistribution notes](licenses/REDISTRIBUTION.md).

Automated tests use synthetic/local AI services. Live provider account eligibility
and vector paste into Illustrator/Affinity Designer still require acceptance testing.
