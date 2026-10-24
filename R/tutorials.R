# Original teaching data and decision guidance; no vendor examples redistributed.
pc_tutorials <- function() list(
  independent=list(title="Two independent groups",layout="column",method="welch",graph="points",
    question="Does mean response differ between two independent groups?",
    why="Welch's t test compares two independent means without requiring equal variances. Select the two groups deliberately; a third column is not included in that comparison.",
    steps="Inspect individual observations in Graph. In Analysis, select Control and Treatment A, then review the mean difference, 95% interval and P value.",
    caution="Each observation must be an independent experimental unit. Use the paired example for repeated measurements on the same subjects; use ANOVA for a question involving all three groups."),
  paired=list(title="Before and after / matched subjects",layout="column",method="paired",graph="paired",
    question="Did a response change within the same subjects?",
    why="A paired t test compares within-subject differences. Each row represents the same subject in both columns.",
    steps="Inspect connected pairs in Graph. In Analysis, review the complete-pair count and the interval for the mean paired difference.",
    caution="Do not sort either column independently. Incomplete pairs are excluded. Independent pairs and approximately normal within-pair differences are assumed."),
  anova=list(title="Three or more independent groups",layout="column",method="anova",graph="points",
    question="Is there evidence of a mean difference across all groups?",
    why="Ordinary one-way ANOVA tests the overall group effect; the follow-up Tukey comparisons address which groups differ.",
    steps="Inspect all observations in Graph. In Analysis, review the omnibus F test, then the adjusted comparisons and confidence intervals.",
    caution="This example assumes independent observations, common population variance and approximately normal residuals. Repeated measurements require a matched analysis."),
  time=list(title="Time series with shaded SD / SEM",layout="xy",method="linear",graph="xyband",
    question="How does response vary over X, and how variable are its replicates?",
    why="XY tables retain separate replicate subcolumns. A mean line with SD or SEM shading summarizes variability at each X; regression uses the selected fitting policy.",
    steps="Open Graph → Figure settings → error bars to switch SD, SEM or 95% CI. Double-click an axis to edit ranges and physical axis lengths. Review the fit and residuals in Analysis.",
    caution="SD describes dispersion; SEM describes precision of the mean. A line fit assumes independent errors. This example is not a repeated-measures time-series model."),
  dose=list(title="Dose response / four-parameter curve",layout="xy",method="fourpl",graph="scatter",
    question="What concentration gives a half-maximal response?",
    why="A four-parameter logistic curve estimates bottom, top, midpoint concentration and slope from a concentration-response series.",
    steps="Inspect the fitted curve on the logarithmic X axis. In Analysis, review fit status, parameters and diagnostic notes; use a Residuals graph to inspect departures from the model.",
    caution="Concentrations must be positive. Sparse dose coverage, missing plateaus or an unsuitable model can make estimates unreliable."),
  grouped=list(title="Two independent experimental factors",layout="grouped",method="twoway",graph="interaction",
    question="Do treatment, time and their interaction affect the response?",
    why="Ordinary two-way ANOVA separates two factor effects and their interaction. Factor labels occupy the first two columns, followed by replicate measurements.",
    steps="Inspect the interaction plot in Graph and the effects table in Analysis. A changing treatment effect across time can indicate an interaction.",
    caution="This workflow assumes independent observations. Repeated measurements on the same subjects across time are not supported by ordinary two-way ANOVA."),
  counts=list(title="Categorical counts / Fisher's exact test",layout="contingency",method="fisher",graph="proportions",
    question="Is the proportion responding associated with treatment?",
    why="Fisher's exact test compares the two populations in this 2 × 2 count table, using observed counts rather than percentages.",
    steps="Enter category labels in the first column and integer counts in each population column. Compare the proportion graph with the test in Analysis.",
    caution="Counts must represent independent observations in mutually exclusive categories. Enter an observed zero as 0; leave no count cells blank."),
  survival=list(title="Time to event / censoring",layout="survival",method="logrank",graph="km",
    question="Do event-time distributions differ between groups?",
    why="Kaplan–Meier curves account for right censoring. The log-rank test compares survival distributions.",
    steps="Each row is one subject: Time, Status (1 event, 0 censored), Group. Inspect censor marks, confidence bands and the number-at-risk table in Analysis.",
    caution="Censoring should be independent of event risk. A censored observation is not an event. Late curve segments can be imprecise when few subjects remain."),
  pca=list(title="Principal component analysis (PCA)",layout="multiple",method="pca",graph="pcascores",
    question="Which combinations of measurements explain variation among samples?",
    why="PCA summarizes multiple numeric variables with orthogonal components. This example centers and SD-scales measurements and keeps sample labels and group labels as metadata.",
    steps="Add this example to open Analysis with 12 synthetic cell profiles and five selected measurements. Sample, Group and the numeric SampleID are metadata, not PCA variables. Three linked views show scores, loadings and explained variance.",
    workflow=c("Inspect Data table: each row is one synthetic sample; CellArea, Intensity, Texture, Roundness and Signal are measurements on different scales. Do not transpose the table or include SampleID.",
      "In Analysis → PCA settings, confirm the five measurements, Sample as the label column, Group as the color column, and unit-SD scaling enabled. All 12 rows are complete; no imputation is performed.",
      "Read Explained variance first. PC1 accounts for the largest share of total centered/scaled variation; PC2 accounts for the largest remaining orthogonal share. The cumulative column shows how much the chosen components retain.",
      "Open the Scores linked graph: one point represents one sample. Nearby points have similar coordinates in the displayed components. Check axis percentages before assuming two components summarize the whole dataset. Enable sample labels to identify individual points.",
      "Open Loadings: arrow coordinates are eigenvector coefficients for each variable. Variables with similar directions contribute similarly to these components; opposite directions indicate opposite contributions. These coefficients are not variable–component correlations.",
      "Open Explained variance: bars show the individual component percentages and the line shows their cumulative sum. Select other component pairs in PCA settings if more structure needs inspection. Each linked view retains its own settings.",
      "Export Variance, Scores, Loadings and Preprocessing CSVs from Analysis. Export editable SVG/PDF from Graph, or add the three views to Figure layout. Save the study to retain the selected columns and preprocessing."),
    exercises=c("Scaling exercise: in the Scores view, switch unit-SD scaling off and compare explained variance and loadings. Large-variance measurements can dominate an unscaled PCA. Restore scaling before comparing with the other linked views.",
      "Missing-data exercise: clear one measurement in Data table. The default policy stops the analysis. Explicitly choose Exclude incomplete rows to use 11 samples; review the excluded-row note. Undo the cell edit and restore the default policy.",
      "Metadata exercise: rename group labels or change their colors. Scores and explained variance should stay the same because groups do not enter the calculation. Editing a selected measurement should recompute them."),
    caution="This dataset is invented for teaching, not biological evidence. PCA is exploratory and sensitive to scaling, outliers, batch effects and variable choice. Group separation is not a significance test or a validated classifier; do not report a PCA P value. Component signs are arbitrary, so mirrored plots from other software can represent the same solution.",
    reference="https://stat.ethz.ch/R-manual/R-devel/library/stats/html/prcomp.html"),
  figures=list(title="Graph editing & multi-panel figures",layout="column",method="anova",graph="points",
    question="How can the same observations be presented in several linked panels?",
    why="Linked views share observations while retaining separate graph and analysis settings. This example adds points, box and violin views to one figure layout.",
    steps="Open Graph and double-click labels or axes, or use the format toolbar. Choose Figure layout, drag a panel to move it, and drag its lower-right corner to resize. Export the layout as SVG, PDF or PNG.",
    caution="Use consistent scales for comparable panels. Formatting and axis ranges do not change the observations used by the analysis.")
)
pc_tutorial <- function(id) {
  guide<-pc_tutorials()[[id]];if(is.null(guide)) stop("Choose a built-in example.")
  e<-pc_example(guide$layout);tab<-e$table;s<-pc_defaults()
  if(id=="paired") tab<-data.frame(Before=c(8,10,9,12,7,11,13,9),After=c(10,11,12,14,8,14,14,12))
  if(id=="time") {tab<-pc_xy_replicates(tab,3);for(i in 2:ncol(tab)) tab[[i]]<-as.numeric(e$table[[2+(i-2)%/%3]])+c(-.8,0,.8)[(i-2)%%3+1]}
  if(id=="dose") tab<-pc_read_text(paste(readLines("examples/dose-response.csv"),collapse="\n"))
  s$layout<-guide$layout;s$method<-guide$method;s$graph<-guide$graph
  s$title<-guide$title;s$x_label<-e$x_label;s$y_label<-e$y_label;s$show_p<-guide$layout=="column"
  if(id=="dose") {s$log_x<-TRUE;s$x_label<-"Concentration";s$y_label<-"Response"}
  if(id=="time") s$error<-"sd"
  if(id=="pca") {
    tab<-pc_pca_teaching_data();s$pca_label_column<-"Sample";s$pca_group_column<-"Group"
    s$pca_variables<-as.character(jsonlite::toJSON(c("CellArea","Intensity","Texture","Roundness","Signal")))
    s$pca_scale<-TRUE;s$pca_missing<-"error";s$show_p<-FALSE
  }
  n<-pc_normalize(tab,s$layout);s$group1<-n$groups[1];s$group2<-n$groups[min(2,length(n$groups))]
  linked<-if(id=="pca") pc_pca_views(s) else list(V1=pc_view(s,"Primary view"))
  if(id=="figures") for(i in 2:3) {v<-s;v$graph<-c("box","violinbox")[i-1];linked[[paste0("V",i)]]<-pc_view(v,c("Box plot","Violin + box")[i-1])}
  list(table=pc_check_table(tab),settings=linked[[1]]$settings,views=linked,name=paste("Example ·",guide$title),guide=guide)
}
pc_tutorial_guide <- function(g) div(class="tutorial-guide",
  h3(g$title),p(strong(g$question)),p(g$why),p(strong("Try this: "),g$steps),
  if(length(g$workflow)) tagList(h4("Step-by-step analysis"),tags$ol(lapply(g$workflow,tags$li))),
  if(length(g$exercises)) tagList(h4("Try changing the analysis"),tags$ul(lapply(g$exercises,tags$li))),
  p(class="inline-note",g$caution),if(length(g$reference)) p(tags$a(href=g$reference,target="_blank",rel="noopener","R PCA method reference")))

pc_pca_teaching_data <- function() data.frame(
  Sample=sprintf("Cell-%02d",1:12),Group=rep(c("Control","Stimulated","Recovery"),each=4),SampleID=101:112,
  CellArea=c(980,1040,950,1080,1450,1520,1390,1580,1190,1260,1140,1310),
  Intensity=c(45,52,47,55,90,96,88,101,68,73,63,76),
  Texture=c(.31,.36,.28,.39,.64,.69,.59,.73,.52,.46,.57,.49),
  Roundness=c(.91,.88,.94,.86,.69,.65,.74,.62,.78,.83,.75,.81),
  Signal=c(8,7,9,6,16,14,18,15,13,16,11,17),check.names=FALSE)
