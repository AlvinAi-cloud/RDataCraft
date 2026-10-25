# v0.32 collection update

The release workflow preserves the native archive SHA-256 pins and immutable
Rtools45 MXE revision from the reviewed v0.31 release preparation. Platform jobs
also collect their exact R/package source archives and OpenMP source subset.
Rust sources are vendored from the committed Cargo.lock. Notices are installed
before the final packages are tested. The resulting source bundle is assembled
only after the three platform jobs pass for the same commit and workflow run.
This does not establish bit-identical reproduction of upstream native binaries;
the historical provenance questions documented below remain explicit.

# Native component source review · v0.3

This review supplements the 89 exact R/package archives in `source-manifest.json`.
It is incomplete. Do not treat an upstream version match, source URL or collected
archive as proof of the exact build inputs for every shipped binary.

## Newly traced components

| Component | Runtime evidence | Collected source/build material |
| --- | --- | --- |
| LLVM OpenMP, Intel Mac | `libomp.dylib` embeds `openmp-14.0.6.src` paths | Official R Mac mirror's 14.0.6 source, license and upstream build script |
| LLVM OpenMP, Apple Silicon | `libomp.dylib` embeds `openmp-19.1.5.src` paths | Official R Mac mirror's 19.1.5 source, matching CMake modules, license and upstream build script |

`native-source-manifest.json` pins SHA-256 hashes for these five downloaded files.
`python3 scripts/fetch_native_sources.py` restores this subset without executing
downloaded build scripts. Packaging includes the files when collected. The build
script and CMake patch are upstream reference material; their exact use for each
R release's binary has not been demonstrated by a reproducible rebuild.

The [official OpenMP page](https://mac.r-project.org/openmp/) states that CRAN R
ships its runtime, and provides source and build scripts. Both runtime versions
above were identified from the actual files, rather than the newest download.

## Coverage that still needs resolution

- **Mac compiler runtimes:** bundled libgfortran, libquadmath and libgcc runtime
  libraries come with the official R frameworks. R's Mac tools specify the patched
  Darwin GCC 14.2 toolchain. Exact release/commit, patches and build configuration
  must be matched to the shipped libraries. Plain GNU GCC 14.2 is insufficient
  evidence for the Darwin fork. See the [R Mac compiler release](https://github.com/R-macos/gcc-14-branch/releases).
- **R core's external libraries:** version information on the Intel runtime reports
  liblzma 5.8.3, libdeflate 1.25, zstd 1.5.7, PCRE2 10.47 and readline 5.2.
  Distinguish included static code from Apple-provided dynamic system libraries
  using the recorded link dependencies. R's optional Cairo/Tcl/Tk/X11 modules need
  their own coverage even though the app's ordinary graphs use Quartz/SVG.
- **R packages' native dependencies:** some package sources contain libuv, libsass,
  ICU, cmark, libxls and other vendor code. Other packages statically link external
  libraries. Inspect the exact package source and corresponding CRAN build recipe,
  including version-specific patches, notices and any applicable relinking needs.
  The current [R Mac recipes](https://github.com/R-macos/recipes) alone do not prove
  which historical revision produced an installed package binary.
- **Windows:** the bundled R Makeconf identifies GCC 14.3.0 and Rtools45. The
  [official Rtools45 guide](https://cran.r-project.org/bin/windows/Rtools/rtools45/rtools.html)
  covers R 4.5 and later, including R 4.6; R's version number is not the toolchain
  version. Match its MXE recipes/patches and native library sources to the actual
  R/package builds. Include Tcl/Tk and shipped extensions, compiler support code,
  compression, text/font, XML and graphics libraries where present.
- **Installer:** NSIS 3.13 is locally built from its official source, with its
  COPYING notice included. Preserve its source/build inputs alongside the final
  public binary release; the NSIS-generated script is in the local build artifacts.

The Mac inventories list 120 Mach-O files each. The Windows inventory verifies
102 x64 PE files. These are architecture/file inventories, not complete component
bill-of-materials certifications. `licenses/REDISTRIBUTION.md` remains the release
decision record. Source repository upload can proceed while this binary audit is
completed; current bundled installers remain release candidates.
