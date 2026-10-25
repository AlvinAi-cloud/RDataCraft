# v0.31

- Added Accounts and Models with direct ChatGPT browser sign-in, saved-account switching, renewal and sign-out. Plan inference depends on OpenAI eligibility and consent.
- Added OpenAI, Claude, Gemini and compatible/local API connections, model discovery, remembered connections, a data-free connection test, and disconnect/forget controls. No Codex installation is required.
- Kept AI operation previews, table sharing controls and reviewed Advanced R execution.
- Rebuilt every Mac icon representation with the same visible footprint as the current companion app, independent of display scaling.
- Updated app, project, packaging and About version information to v0.31.

# Changelog

## v0.3 — release candidate (2026-10-24)

- Consolidated the reviewed v0.25 updates under v0.3 to distinguish this release
  from earlier development copies. App labels, saved-study metadata, reports,
  guides and all installer names use the new version; the Mac build number is 1.
- Preserved compatibility with existing studies and retained the earlier build
  history below. Release validation and signing status accompany the installers.

## v0.25 build 21 — final review and Help improvements (2026-10-24)

- Added searchable offline Help for data entry, analysis selection, PCA, regression,
  figure sizing, vector export, Prism import, AI privacy, saving and package recovery.
  Native Help and the toolbar now open the same guide; Windows setup includes it.
- Hardened saved SVG validation against external CSS resources, encoded references
  and attribute-changing animation, while retaining local clip references.
- Added recovery of recorded package transactions after their owner has ended,
  protected live installers in other windows, and rejected dependency conflicts.
- Prevented draft saves during an R operation from exhausting saved-result slots;
  bounded console diagnostics before reading them into memory.
- Included every recommended R package in inventories/notices; verified 89 exact
  R/package source archives across the selected platform runtimes.
- Rechecked official Mac R installer signatures/notarization and framework binaries;
  new runtime bootstraps stop on an invalid Apple installer signature.
- Replaced obsolete setup instructions; added source privacy/link preflight checks
  and release-tool tests, explicit JavaScript test requirements and PR validation.
- Kept v0.25; built separate reviewed app copies to preserve open earlier windows.
  Apple Silicon/Windows native execution and full native-library source coverage
  remain documented public-binary release requirements.


## v0.25 update — 2026-10-24

- Add explicit approval for missing CRAN binaries and required dependencies, a personal R/version/CPU library, staged installation and rollback, logs, stale-approval protection and cancellation.
- Detect literal package requirements in AI/manual scripts; keep analysis execution separate from package approval. Update Advanced R help and examples.

## v0.25 — 2026-10-23

- Add Advanced R scripts, explicit AI draft review, separate R workers, package checks, cancellation/time limits, retained input/code/results and schema 11 persistence. Include help and original teaching examples.
- Show numeric P values down to 10⁻⁶ or significance stars across supported graph annotations.

- Use platform-neutral About text with RDataCraft branding.
- Default new figures to 3 × 3 inches, 7-point text and a 200% preview; preserve export dimensions independently of zoom.
- Increase interface typography by 10%, independently of figure text.
- Add a source-only GitHub upload folder and installer validation for Mac Intel, Apple Silicon and Windows x64.

## v0.21 — 2026-10-23

- Merge the separate PCA Help menu item into Examples & Analysis Guide.
- Add independent Mac study windows, per-window R engines, focus-based menu routing, multi-project opening, and save/cancel review across all windows when quitting. Browser New Study uses a separate session.
- Preserve multiple Prism input sheets as separate tables; compact unused trailing replicate slots and retain populated wide inputs as long rows. Read rich-text titles.
- Import mean/SEM and saved numeric results as labelled snapshots. Preserve unresolved-exclusion sources as unreviewed snapshots and block automatic inferential conversion.
- Recognize verified legacy unpaired Student-test schemas and retain comparison direction. Separate genuinely missing input links from multi-input analysis reports.
- Fix inspection of multiple-variable/result tables containing an empty numeric column.

## v0.2 — 2026-10-23

- Expand PCA into an original 12-sample/five-measurement teaching study, with explicit selection excluding numeric sample IDs.
- Add a seven-step analysis guide, three exercises, a direct Help shortcut and a PCA-settings guide button. Include a standalone study, CSV and HTML guide.
- Update interface, project/report metadata, launchers, validation tools and package versions to 0.2 without changing the project schema.
- Add Mac disk-image packaging and a per-user Windows setup/uninstall executable. Cross-build the ARM host with matching ARM R/packages and static architecture/version audits; cross-building does not verify target execution.
- Verify the Intel build on physical Intel hardware and retain platform evidence in the release report.

## v0.1.1 — editable Prism workflows and platform builds

- Convert supported modern paired-test and PCA metadata into editable, rerunnable working tables. Translate supported direct-source JSON XY graphs and recreate unambiguous binary source-linked graphs as clearly labeled linked views.
- Add an explicit reconstruction preview for other supported analysis/graph families; preflight all selected plans before mutation. Persist conversion/skip reports in schema 10, retaining schemas 1–9.
- Replace the Mac-only PZFX decoder dependency with a bounded cross-platform xml2 reader. Preserve namespaces, missing cells and X titles while blocking entities/network resolution.
- Add native Apple Silicon R/packages and separately compiled ARM/Intel hosts with mismatch guards and per-runtime manifests. Add Windows x64 portable launch/package targets with Windows R/package binaries and a three-target CI recipe.
- Add a cancellable portable Codex transport using data files and argument arrays; retain local validation and preview/apply behavior. Add browser unsaved-tab protection and an always-accessible Help button.
- Add regression coverage for converted/rerun workflows, atomic import rejection, graph persistence, portable assistant delivery/cancellation and all six table types exported as SVG/PDF/PNG.
- Keep selected analysis groups and custom series styling through column renames, Undo/Redo and project saving across linked views. Fix the navigator delete button's pointer target.
- Fix Windows Rscript invocation in launchers, validation and CI; prefer the bundled x64 engine, preserve launch failure codes, and add one-click native R validation. Reject mixed-platform or wrong-architecture portable runtimes before packaging.

## v0.1 — Help examples, empty startup and Prism preservation

- Reset the release label to v0.1 as requested, retaining the 0.9.0 feature set and compatibility with project schemas 1–8.
- Rename Results navigation to Analysis. Add Help → Examples & Analysis Guide with ten original examples, design guidance, walkthroughs and interpretation limits. Adding an example preserves existing data tables.
- Launch with no file open. Show a welcome screen and disable document-only commands until a study is created, imported or opened.
- Reduce most interface typography by approximately 12% after increasing the first compact revision by 10%, independently of graph/export typography.
- Preserve complete .prism/.pzfx originals as optional SHA-256-verified attachments inside schema 9 projects, recoverable from Project & sources. Editable source-table import remains available. Saved Prism analyses and graphs are retained in the original file; automatic editable conversion is not implemented.

## 0.9.0 — PCA workflow and focused toolbar

- Rename Inspector to Figure settings, place it between Graph and Figure layout, and move AI Assistant to the far right. Figure settings opens the active graph before showing its panel.
- Add a Multiple variables table with SVD-based PCA, explicit variable/metadata selection, unit-SD scaling, component choices and complete-row exclusion policy. Reject constant variables, malformed numeric cells and insufficient data.
- Create linked scores, eigenvector loading and scree views. Export scores, loadings, explained variance and preprocessing to CSV, JSON and HTML; use PCA views in figure layouts and assistant operations.
- Preserve PCA settings and graphs in schema 8 and track selected column references through direct header rename and table Undo. Keep earlier projects compatible.


## 0.8.0 — compact Craft interface and internal assistant

- Compare the live PlasmidCraft 0.34 UI and reduce chrome to 15 px body text, 14 px controls, 13 px labels and 20 px toolbar icons. Keep figure typography unchanged.
- Add a docked internal assistant with context sharing, prompt templates, conversation, cancellable model requests, operation previews and rendered graphs/layouts.
- Connect through the installed Codex CLI using its existing sign-in and structured output; no credentials are imported from PlasmidCraft. Model output is data only and all changes pass R validators before application to a new table copy.
- Support graph edits, R analyses, column renaming, transforms, and generated figure arrangements. Reject stale or unsupported proposals. Keep existing layout Undo support.
- Include offline local data checks, descriptive summaries, clean-figure presets and SD/SEM comparison layouts. Exclude assistant history from project saves.


## 0.7.1 — 2026-10-22

- Remove expansion beyond entered axis limits and anchor the automatic Y baseline at its lowest tick.
- Add independent physical X/Y axis lengths in millimetres, with canvas-fit validation and consistent standalone vector/raster exports. Figure layout panels retain their own sizing.
- Add per-time-point mean trajectories with shaded SD, SEM or t-based 95% mean intervals, preserving gaps where replication is insufficient.
- Add schema 7 persistence and regression checks for limits, physical SVG geometry, interval calculations and missing replicates.

## 0.7.0 — 2026-10-22

- Added a graph gallery with previews from the current observations and ten new
  graph choices (30 total across the five source table types).
- Added median/IQR summaries, violin/box and density distributions, grouped
  distributions and mean heatmaps, XY step/area and stacked count graphs.
- Added series selection from legend/data marks, axis tick intervals, X tick
  rotation, reference lines and per-view formatting Undo/Redo.
- Added physical figure-layout editing: templates, drag/resize, snapping, exact
  dimensions, panel labels/order, spacing and SVG/PDF/PNG exports.
- Made source column and shared XY series headers directly editable and undoable.
- Added a navigator × per data table with a named deletion confirmation and
  dependent-view/layout cleanup. The final table becomes a blank replacement.
- Updated studio chrome, table presentation, keyboard focus and layout inspector.
- Added schema 6 and native/R regression coverage for the new workflows.
- Fixed interactive graph controls disappearing when Shiny redraws an image with
  the same SVG source; verified repeated title, legend and axis edits visually.

## 0.6.0 — 2026-10-22

- Inspect the installed Prism 11.0.1 application interactively: table/result/graph families, Format Graph and analysis dataset selection.
- Recover missing dependencies, then reconcile the complete 0.5.0 release/source and original test suites recovered from OneDrive. Preserve updated local code, verify the remaining files, and move the requested cloud project folder to Trash. Rebuild an arm64 host around the existing Intel R engine.
- Replace XQuartz-dependent PDF/PNG devices with macOS Quartz, retaining Unicode text and physical export dimensions.
- Add validated per-series color, symbol, size, line width and pattern settings; persist independent overrides per linked view.
- Add undoable row-range insertion/deletion and complete Column/XY series rename, move and deletion, with stale-source protection.
- Fit all XY series independently using existing linear/nonlinear models, retaining series identity in curves, residuals, parameters, reports and fit status; report partial failures.
- Add schema 5 to prevent older apps silently discarding the new fit/appearance settings.
- Restore native vector PDF/SVG copy, clipboard paste and data Undo/Redo; support wrapped base64 and preserve missing-cell positions in the source importer.
- Compact analysis controls and initially fit graph previews to the available window.
- Add original demonstration projects, reproducible test setup, runtime/build preflight, and expanded numerical/native integration tests.

## 0.5.0 — 2026-10-21

- Click graph titles and axis titles to edit them in place. Click axes/ticks or data symbols to open contextual formatting. The interactive surface uses the same SVG geometry as export.
- Add Format and Graph toolbars for labels, axes, data, typography, canvas size, vector copy, formatting reuse, linked views, deletion and curve fitting.
- Persist title/axis text sizes and colors, axis widths, symbol shapes and curve widths per linked view.
- Delete linked views from the navigator or toolbar, preserve at least one view per table, restore surviving settings, and remove deleted graphs from layouts.
- Copy vector PDF and SVG to the native macOS clipboard through Copy vector, Edit → Copy Graph as Vector, or Command+C on the Graph page outside a text field.
- Add ten fitting models: through-origin line, quadratic/cubic polynomials, logarithmic, power, exponential, one-phase decay/association, Michaelis–Menten and Gaussian peak. Add equal/1-Y-squared/replicate-SD weighting, individual/mean replicate fitting, parameters with intervals, residuals, fit statistics and residual CSV export.
- Import supported raw tables from XML PZFX and modern PRISM archives with preview and explicit unsupported-table reporting. Do not reinterpret summary/error-value tables as observations or import saved Prism analysis results as R results.
- Keep authoritative restored graph settings until every setting has been acknowledged by the interface.

## 0.4.3 — 2026-10-21

- Paste spreadsheet blocks directly into a selected data cell with Command+V or native Edit → Paste; support an explicit first-row header option, table expansion, pagination, validation, and whole-block undo/redo.
- Move the old whole-table text replacement into an Advanced disclosure.
- Click a data table name in the navigator or above the grid to rename it in place; Enter/blur commits, Escape cancels, and names persist in projects.
- Choose side-by-side Y replicate subcolumns when creating or configuring XY tables. Preserve values when expanding, prevent removal of populated columns, group replicate headers, and add complete Y series blocks.
- Combine Y replicates into their series for means, SD/SEM/CI, fitting and exports; retain grouping in explicit CSV/TSV headers and saved projects.
- Start new figures at 6 × 4.5 inches, expose inch dimensions, render previews with the export SVG device at the requested size, and offer 100% or Fit to window without changing export dimensions.

## 0.4.2 — 2026-10-21

- Review the public Prism 11 user guide and implement original workflow improvements.
- Replace the tall dropdown-first sidebar with searchable data-table families and direct links to results and graphs; keep larger Craft typography and compact workspace navigation.
- Preview and explain each supported data structure before creating a data table and linked graph.
- Duplicate a data table with all linked analysis/graph views into an independent experiment.
- Copy graph appearance to selected views while preserving each analysis, graph type, labels, error-bar definition, and axes.
- Add bounded per-table undo/redo for committed data edits, imports, pasted replacements, rows, and columns, with native Edit-menu integration.
- Support a separate desktop build destination to preserve an earlier open app.

## 0.4.1 — 2026-10-21

- Match PlasmidCraft 0.34 interface typography: 16 px body, 14.8 px controls, 13.5 px labels, with wider panels and readable tables.
- Click the study title to edit it; Enter or leaving the field commits, Escape cancels. Titles persist independently of file names and participate in native unsaved-change tracking.
- Replace the ambiguous New toolbar action with a Create… chooser that distinguishes adding data, linked views, layouts, and starting another study. Native File → New Study retains save/discard/cancel protection.
- Keep the R graphics scratch device in memory so preview measurement does not write into the signed app bundle.
- Keep GPL-3.0, bundled R processing, original graph styling, and compatibility with earlier project files.


## 0.4.0 — 2026-10-21

- Inspected local Prism 10.6.1 user-facing help/resources and shipped graph examples.
- Added up to twelve named analysis/graph views per source worksheet, with independent settings and shared source edits.
- Added saved figure layouts with up to eight panels, 1–3 columns, panel letters, and SVG/PDF/PNG export.
- Added manual numeric axis ranges, legend placement, and major grid controls; cropping preserves statistical inputs.
- Kept unsaved-state tracking active even while an axis entry is incomplete or invalid.
- Preserved authoritative worksheet settings while client controls are being restored; added rapid-switch and blank-template save regressions.
- Added schema 3 while preserving legacy project migration; native View menu includes Layout and layout PDF export.
- Expanded regression checks for linked data, independent views, layout persistence, axis validation, and native panel export.

## 0.3.1 — 2026-10-21

- Replaced ggprism theme and significance annotations with original ggplot2 helpers.
- Kept RDataCraft under GPL-3.0 and retained third-party licensing obligations.
- Removed ggprism from runtime requirements, dependency/source/license inventories, and new desktop bundles.
- Added bracket geometry, label-mode, empty-group, export, and dependency-removal checks.
- Rebuild generated app bundles from scratch to prevent retired components persisting.

## 0.3.0 — 2026-10-21

- Renamed the app to RDataCraft; added `.rdatacraft` workbooks while preserving PlotCraft project import.
- Added named worksheets, templates, per-worksheet settings, and source-preserving transformations.
- Expanded from two to five table types and from seven to twenty graph choices.
- Added Student/one-sample/signed-rank tests, Welch ANOVA, Kruskal–Wallis, Friedman, complete-case repeated-measures ANOVA, normality diagnostics, and corrected pairwise comparisons.
- Added balanced factorial two-way ANOVA, contingency inference, Kaplan–Meier/log-rank, risk counts, correlations, dose-response fits, AUC, and residual graphs.
- Added embedded-figure HTML reports, CSV result exports, significance-star annotations, and context-aware figure controls.
- Added numerical, invalid-design, workbook, report, graph-export, and expanded native integration checks.
- Indexed recommended survival/Matrix/lattice dependencies and collected their matching sources and notices.
- Canonicalized numeric table serialization to preserve clean save/reopen state.

## 0.2.0 — 2026-10-21

- Added a standalone macOS `.app` with a native window, menu bar, Dock icon,
  document dialogs, keyboard shortcuts, and automatic bundled-R lifecycle.
- Added native Save/Save As, Finder-openable JSON `.rdatacraft` projects, dirty
  tracking, and save-before-close/new/open handling.
- Matched PlasmidCraft's green palette, compact toolbar, light chrome, and inspector.
- Organized the navigator around linked data, results, and graphs; start at data.
- Added blank projects and row/column creation while retaining missing cells.
- Added native integration checks and captures from the app's own WebKit view.
- Repaired absolute fontconfig links for a self-contained, signable R bundle.

The interface uses embedded WebKit; calculations use the app-local R process.
This remains a development preview with broader scientific validation pending.

## 0.1.0 — 2026-10-21

- Created the RDataCraft local application and figure studio.
- Added column/XY tables, spreadsheet import/paste, and cell editing.
- Added descriptive statistics, two-group tests, ANOVA/Tukey, and linear regression.
- Added configurable figures, SVG/PDF/PNG exports, and JSON projects/results.
- Downloaded an app-local Intel macOS R runtime, package binaries, upstream
  ggprism source, and matching R/R-package source archives.
- Added numerical/export checks, reactive workflow tests, dependency/license
  manifests, and development-bundle scripts.

This is a development preview. Browser QA, clean-machine checks, additional
statistical validation, and the public redistribution audit remain open.
