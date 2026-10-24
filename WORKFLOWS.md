# RDataCraft workflow and validation scope

RDataCraft is an independent scientific plotting and statistics application using
original application code and open-source R components. Its application code is
GPL-3.0. Third-party notices remain in `licenses/`.

## Study workflow

1. Create or open a study. New Study opens an independent window on Mac and a
   separate browser session on Windows. Each study has its own data and save state.
2. Add a named worksheet with a table structure matching the experimental design.
   Paste directly into a selected cell; click study, table or column names to edit.
3. Choose an analysis compatible with the table. Review experimental units,
   matching, exclusions, assumptions and multiple-comparison correction.
4. Inspect the linked graph and diagnostics. Add linked views to compare supported
   analyses or graph types using the same working observations.
5. Save the study, export a figure or create a multi-panel layout and analysis report.

## Tables and analyses

- **Column:** independent groups, paired observations, one-sample comparisons,
  ANOVA and supported nonparametric tests. Rows must reflect experimental units;
  paired tests require correctly aligned subjects.
- **XY:** numeric X values and one or more Y series, optional replicate columns,
  correlation, linear/polynomial regression and supported dose-response models.
- **Grouped:** explicit factor labels and replicate observations for two-factor
  designs. Repeated-measures designs are not treated as independent observations.
- **Contingency:** nonnegative counts for categorical comparisons.
- **Survival:** time, event status and group for survival curves and supported tests.
- **Multiple variables:** numeric measurements and optional sample/group metadata
  for distributions and PCA. PCA variables must be selected explicitly where IDs
  could be mistaken for measurements. See Help → Examples & Analysis Guide.

## Figure defaults in v0.25

New figures use 3 × 3 inches and 7-point text. The preview starts at 200%; switch
to 100% actual size or Fit to window as needed. Preview zoom does not change export
size. Existing saved studies retain their explicit dimensions and text settings.
Interface typography is 10% larger than v0.21 and is independent of figure text.
Click titles to edit and axes or data to format. SVG/PDF exports retain vector text;
the Mac clipboard supplies PDF and SVG. External design-app paste requires a check
in the destination application.

## Advanced R analysis

Analysis → Advanced R analysis supports reviewed scripts for methods beyond the
presets. The AI can draft a script through `r_analysis`, but never executes it.
Open the draft, review it, then explicitly Run. The worker receives `data` with
numeric conversion and `data_raw` with cell text. Return `result` with named tables,
a ggplot or base-plot drawing function and explanatory text. Missing CRAN packages resolve into a separate approval list with versions and required dependencies. Approved binaries install into a user-specific R/CPU library without changing the app libraries. Stop can cancel installation and roll back incomplete staged changes; the analysis still requires a separate Run click. Source builds and non-CRAN repositories are not installed. Package checks, Stop and a maximum five-minute analysis limit are provided. Results retain code, exact input,
console, R/package versions and SVG/PDF in schema 11. Loading a study never runs its
scripts. Saved results are snapshots; import a result table to graph it normally.
Custom scripts run with account permissions; a separate process is not a security
sandbox. See the inline guide and `examples/Advanced R analysis guide.html`.

P-value graph labels can use four-significant-digit numeric values (P < 10⁻⁶ below
one millionth) or ns/*/**/***/**** at the usual 0.05/0.01/0.001/0.0001 thresholds.

## Prism file interoperability

The importer reads supported `.prism` and `.pzfx` source tables using stable IDs.
Multiple input sheets stay separate; importing sheets does not infer a cross-sheet
calculation. Empty trailing replicate slots can be compacted, and wide replicate
inputs can use long rows without averaging observations. Supported analysis
metadata can create an editable R analysis, with conversion limits in the report.

Saved mean/SEM and numeric result tables are labelled snapshots. They do not
recompute upstream baseline or estimation transformations. Unresolved exclusions
remain labelled unreviewed and block automatic inferential conversion. Binary
graph appearance and unsupported analyses are not reproduced. Optional original
Prism attachments preserve the source file separately from editable working tables.
Save the import history and review its warnings before interpreting results.

## Validation and releases

`scripts/test.py` runs numerical, table, analysis, graph, project persistence,
import, assistant and JavaScript checks. Desktop integration tests exercise the
application's own disposable windows and files, including multiple study windows,
save/cancel handling, figure editing, PCA, export and read-only app execution.
Synthetic test fixtures and examples are supplied; private workbooks are excluded.

`scripts/build_desktop.py` creates matching Intel or Apple Silicon apps. The Windows
portable builder audits matching Windows R/packages; `scripts/package_installers.py`
creates disk images or per-user Windows setup. Cross-building and inspecting
installer payloads do not establish execution on another platform. Consult each
release's validation report. Current installers are development builds; complete
`licenses/REDISTRIBUTION.md` before public binary distribution.

`scripts/prepare_github.py` prepares source for a GitHub repository without uploading
or publishing anything. Large installers belong in release assets. The source
upload excludes runtimes, generated builds, caches and private studies.
