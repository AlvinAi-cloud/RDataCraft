# RDataCraft

RDataCraft is an open-source, R-powered workspace for scientific data analysis and
publication-quality figures. It combines editable tables, linked graphs,
statistical workflows, curve fitting, PCA, multi-panel layouts and reviewed custom
R scripts with optional AI assistance.

**v0.3 is a development preview.** The Mac editions use a native desktop window;
the Windows x64 edition opens its local interface in a browser. R and the required
packages are included in packaged builds. Scientific calculations run locally.
The optional connected AI Assistant uses your signed-in Codex CLI.

## Start a study

1. Choose **Create… → Data table**, then choose a table type. Paste directly into
   a selected grid cell; use the header option when copying column names.
2. Click the study title or table name to rename it. Choose **Analyze** and select
   a method appropriate for the study design.
3. Review estimates, intervals, assumptions and diagnostics. Format the linked
   graph, arrange panels if needed, and export SVG, PDF or PNG.
4. Save a **.rdatacraft** study to retain data, graph settings, layouts and saved
   results. Exporting a figure alone does not save the study.

**Help** opens searchable, offline instructions. **Examples & analysis guide**
adds original teaching tables, including a PCA walkthrough. Existing observations
are retained. See [WORKFLOWS.md](WORKFLOWS.md) for the workflow reference.

## Data and analysis

- **Column:** independent groups, paired data, descriptive statistics, t tests,
  ANOVA and supported nonparametric comparisons.
- **XY:** numeric X and Y series with optional replicate subcolumns; correlation,
  regression and supported nonlinear / concentration-response models.
- **Grouped:** two factor labels with replicate measurements and ordinary
  two-way ANOVA. Repeated-measures and mixed-effects designs require an
  appropriate custom analysis.
- **Contingency:** observed integer counts and supported categorical tests.
- **Survival:** time, event/censoring status and group; Kaplan–Meier and log-rank.
- **Multiple variables:** measurements plus sample/group metadata; distributions
  and PCA with explicit variable, scaling and missing-value choices.

Blank measurements are missing values; a measured zero must be entered as 0.
The preview supports up to 10,000 rows and 50 columns per table. Check experimental
units, pairing, exclusions and model assumptions before interpreting an analysis.

New figures default to **3 × 3 inches, 7-point text and 200% display**. Screen zoom
and Fit window do not change export dimensions. Existing saved figure settings
are retained. Titles and axis labels are editable in the graph; axis and series
formatting are available through direct interaction and the toolbar. The native
Mac app also supplies a PDF/SVG vector clipboard; Windows supports vector file
export. Test editing and fonts in your destination design application.

P labels offer numeric values with four significant digits, displaying
**P < 10⁻⁶** below one millionth, or <code>ns / * / ** / *** / ****</code> using the
0.05 / 0.01 / 0.001 / 0.0001 cutoffs. Display formatting does not alter statistics.

## Advanced R and the AI Assistant

**Analysis → Advanced R analysis** supports methods beyond the presets. Write a
script, load a template, or review an AI draft, then choose **Run reviewed script**.
The worker receives `data` (a copied table with numeric conversion) and `data_raw`
(original cell text). Return results using:

```r
result <- list(
  tables = list(Summary = data.frame(N = nrow(data))),
  text = "Describe the method, assumptions and limitations."
)
```

A `plot` entry may contain a ggplot or a function drawing a base R plot. Results
retain the exact input snapshot, code, console, R/package versions and vector
figures. Saved scripts never execute when a study is opened. Results are historical
snapshots; import a returned table to use normal graph and analysis tools.

Missing packages use a separate **Check / install packages… → Approve & install**
workflow. Review exact versions, required dependencies, repository and destination.
Compatible CRAN binaries install into a personal library separated by R version
and platform. Bundled app libraries stay unchanged. Source builds and non-CRAN
repositories are excluded. Stop cancels incomplete staging with rollback; recorded
interrupted transactions can recover after their owner has ended. Installation
does not run the script automatically.

Custom R and downloaded packages run with your account permissions. A separate
process handles ordinary errors and time limits; it is not an OS security sandbox.
Review code before running it. See the in-app Advanced R guide and
[the original teaching example](examples/Advanced%20R%20teaching%20example.rdatacraft).

The connected assistant sends your message, column names, graph settings and
recent conversation to the model service. Table values and computed results are
included only when **Share active table values and computed results** is checked.
Local assistant tools and the main analysis workflows work offline. Model changes
require review; Advanced R proposals remain drafts until explicitly run.

## Prism interoperability

Import supported **.prism** and **.pzfx** files with a preview and conversion
report. Source sheets become separate tables; supported multi-input operations
produce separate working tables for their inputs. Review imported exclusions,
analysis settings, group direction and diagnostics against the original.

Saved result / summary tables are labelled snapshots and do not recompute upstream
calculations. Binary graph formatting and unsupported analyses are not reproduced.
Legacy **.pzf** files must first be saved as .pzfx or .prism in Prism. The optional
original-file attachment preserves bytes for later recovery; it does not make all
original content editable. Import is not a complete migration of every Prism
feature. RDataCraft is an independent project and is not affiliated with GraphPad.

## Build and verify

Python 3 and Node.js are build/test tools; end users of packaged apps do not need
them. On a matching Intel or Apple Silicon Mac:

```sh
python3 scripts/bootstrap.py
python3 scripts/test.py --require-node
python3 scripts/build_desktop.py --zip
```

On Windows x64, install R 4.6.1 and make Rscript available, then:

```text
Rscript --vanilla scripts/install.R
python scripts/test.py --require-node
python scripts/package_portable.py
```

The dependency lock files describe the audited runtime versions. The development
installer resolves available CRAN dependencies; it is not an immutable restore
of an old package repository. Re-run validation and collect the resulting exact
sources when dependencies change. Architecture checks reject mismatched runtimes.
See [PLATFORM_SUPPORT.md](PLATFORM_SUPPORT.md) for build flags and platform limits.

The GitHub workflow uses pinned action commits and runs tests/builds on Intel Mac,
Apple Silicon and Windows. Validation reports upload automatically; binary artifact
uploads require an explicitly selected manual run after redistribution review.
It has to run in your repository before it provides evidence for those machines.
This review executes the Intel Mac build; cross-built Apple Silicon/Windows
artifacts require native execution tests. Development builds use ad-hoc Mac
signatures and have no Apple notarization or Windows code signing.
See [RELEASE.md](RELEASE.md) for GitHub Desktop publishing steps, the app description,
prepared signing tools and the remaining public-binary release requirements.

Prepare an upload without publishing:

```sh
python3 scripts/prepare_github.py
python3 scripts/preflight.py --source dist/RDataCraft-0.3-GitHub
```

Use the generated **source folder contents**, rather than the entire development
workspace. Runtime binaries, installers, private studies, caches and local logs
are excluded. Existing output folders are not overwritten. Source collection:

```sh
python3 scripts/fetch_sources.py
```

Repeat `--lock PATH` to include other target-platform inventories. Matching R and
package archives are validated against pinned hashes where recorded. Native
library source coverage is tracked separately. See
[licenses/REDISTRIBUTION.md](licenses/REDISTRIBUTION.md) before a public binary
release. No build or preparation script uploads or publishes a release.

## License

Application code is **GNU GPL version 3**. R and third-party components retain
their licenses and notices; see [LICENSE](LICENSE), [licenses](licenses) and the
dependency manifests. ggprism is not used or included in current builds. The UI
adaptation retains the original MIT attribution in
[licenses/PlasmidCraft-LICENSE](licenses/PlasmidCraft-LICENSE).
