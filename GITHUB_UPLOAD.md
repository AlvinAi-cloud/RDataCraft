# RDataCraft v0.3: GitHub upload

Upload the contents of this folder to your repository. This is the application
source, examples, tests, build scripts and third-party notices. It excludes local
R binaries, installers, caches, private studies, personal paths and chat handoffs.
The original MIT attribution in the third-party notices must remain intact.
See `RELEASE.md` for the app description, GitHub Desktop steps, signing setup and
remaining release gates.

## Installers

Create a draft GitHub release tagged `v0.3` and attach these files from the
original project's `dist/` folder as **release assets**, rather than source commits:

- `RDataCraft-0.3-macos-x86_64.dmg`
- `RDataCraft-0.3-macos-arm64.dmg`
- `RDataCraft-0.3-windows-x64-setup.exe`
- `RDataCraft-0.3-SHA256SUMS.txt`
- `RDataCraft-0.3-validation.json`

The installers are larger than GitHub's ordinary file-upload/commit limits.
They contain bundled R and packages. Current packages are development builds:
Mac apps are ad-hoc signed, not notarized, and Apple Silicon/Windows execution
requires checks on those platforms. Complete the corresponding-source and native
library audit in `licenses/REDISTRIBUTION.md` before publicly distributing binaries.
No repository or release has been created by this preparation script.

## Build and check

On Mac, use `python3 scripts/bootstrap.py` to prepare a matching local R runtime,
then `python3 scripts/test.py` and `python3 scripts/build_desktop.py --zip`.
On Windows, install R, run `Rscript --vanilla scripts/install.R`, then
`python scripts/test.py` and `python scripts/package_portable.py`.
Python and Node are build/test tools; the installed application uses bundled R.
See `PLATFORM_SUPPORT.md` for architecture flags, packaging and validation limits.
`source-manifest.json` records dependency source provenance; run
`scripts/fetch_sources.py` to collect missing matching archives for a release.
