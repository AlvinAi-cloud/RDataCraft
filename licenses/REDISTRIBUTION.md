# v0.32 release preparation

The GitHub workflow now collects the pinned native source superset and immutable
Rtools45 MXE r6768 recipes used for the v0.31 source review, together with vendored
Rust dependencies and the current R/package source inventories from all three
platform builds. It includes dependency notices in the apps before packaging and
testing, then attaches the matching source bundle to the draft release.
A prepared workflow is not evidence of a completed v0.32 build or source download.
Consult the exact run’s combined validation and source records before publishing.
Mac builds remain ad-hoc signed/not notarized; Windows setup remains unsigned.
The historical inventory/build-provenance limitations below still apply.

# Redistribution status · v0.3

Application source is GPL-3.0. R is offered under GPL version 2 or 3; individual
packages and native components retain their own licenses. ggprism is not used or
included. Preserve copyright, license and disclaimer notices, including the
original MIT UI attribution. This inventory is not a legal opinion.

## Source repository

The generated GitHub folder contains application source, original teaching data,
synthetic test fixtures, build scripts and notices. It excludes the local runtimes,
private studies, source downloads, installers and diagnostic logs. Run
`scripts/preflight.py` on the exact upload folder before committing it.

Dependency lock files record the audited runtime, including all recommended R
packages. They do not lock a future CRAN mirror. Development installation may
resolve newer dependencies; regenerate inventories and rerun tests after changes.

## Verified in the 24 October 2026 review

- Both official R 4.6.1 Mac installers match the checksums published by CRAN:
  Intel `8d3c9e7a71dcba7602aaaf948b574e2e9d29844e`; Apple Silicon
  `fc9f4ada15589e8e037b9bf05563d21e97181635`.
- Fresh `pkgutil --check-signature` checks report trusted Apple developer
  signatures, trusted timestamps and notarization for both installers. The old
  invalid-signature observation is resolved by these fresh checks. The bootstrap
  now stops if Apple cannot validate a newly downloaded installer.
- The 46 R framework Mach-O binaries in each local Mac runtime match the official
  extracted framework byte for byte. Relocation modifies the R shell launcher and
  framework symlinks, rather than those binaries.
- 89 exact R/package source releases for the selected three platform inventories
  were downloaded and checked. Existing pinned SHA-256 hashes were preserved;
  package DESCRIPTION files were inspected without running package source code.
  Their records are in `source-manifest.json`. Source files live in
  `downloads/sources/` in the development workspace and packaged bundles.
- Per-package DESCRIPTION and available license/COPYING/NOTICE files are collected
  for every bundled non-base package, including R's recommended packages. Packaging
  regenerates notices from the actual selected runtime.
- Mac native binary inventories record paths, hashes, CPU architectures and linked
  libraries in `native-macos-x86_64.json` and `native-macos-arm64.json`.
- Main Mac graphics use Quartz and SVG. Stock R Tcl/Tk and X11 modules retain
  optional external dependencies; those interfaces are not app prerequisites and
  are not automatically supplied by Advanced R package installation.
- v0.3 adds pinned OpenMP source/build material and license notices for the two
  versions identified in the actual Mac runtimes. The remaining compiler/static
  dependency questions are detailed in [NATIVE_SOURCE_REVIEW.md](NATIVE_SOURCE_REVIEW.md).

See the accompanying validation report for executed application tests. A binary
inventory and a successful test suite do not establish complete source coverage.

## Still required for a public bundled-binary release

1. Establish exact corresponding-source/build coverage for any bundled native
   components not fully covered by R/package source archives. The native inventories
   include compiler runtime libraries and packages with statically linked
   dependencies. Check upstream build recipes, patches and license-specific source
   requirements; a list of source URLs alone does not finish this work.
2. Make the required corresponding source and build/relocation instructions
   available with the binary release. `fetch_sources.py --lock PATH` can include
   additional target inventories; verify its resulting manifest and archives.
3. Execute the final Apple Silicon and Windows builds on their target platforms,
   including clean installations without system R, data entry, import, save/reopen,
   analysis, exports and package approval/cancellation. Cross-building and payload
   inspection do not establish native execution.
4. Complete developer distribution signing/notarization where desired. Current Mac
   apps have local ad-hoc signatures; Windows setup is unsigned. Developer signing
   credentials are not present in this workspace.
5. Continue reference numerical, accessibility and scientific-design validation.
   Unsupported repeated-measures/mixed-effects designs must use a reviewed suitable
   custom analysis rather than an ordinary independent-observation preset.

The source repository can be reviewed independently of the bundled binary release.
Current installers remain development/test artifacts while the items above remain.
No script publishes a repository or release.
Signing tools and GitHub Desktop steps are described in [RELEASE.md](../RELEASE.md).

References: [CRAN Mac releases](https://cran.r-project.org/bin/macosx/),
[R FAQ licensing](https://cran.r-project.org/doc/FAQ/R-FAQ.html),
[GNU GPL v3](https://www.gnu.org/licenses/gpl-3.0.html),
[R Mac build tools](https://mac.r-project.org/tools/).
