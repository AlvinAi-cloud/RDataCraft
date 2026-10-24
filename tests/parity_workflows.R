app <- source("app.R")$value
checks <- 0L
check <- function(ok,label) {if (!isTRUE(ok)) stop("FAIL: ",label,call.=FALSE);checks <<- checks+1L;cat("PASS:",label,"\n")}
errors <- function(expr) inherits(tryCatch(force(expr),error=identity),"error")
tab <- pc_xy_replicates(data.frame(X=1:8,A=c(2.1,4,5.8,8.1,10.2,11.9,14.1,16),B=c(5,8.2,10.9,14,17.1,19.9,23.2,26)),2)
tab[[3]] <- as.character(as.numeric(tab[[2]])+.5);tab[[5]] <- as.character(as.numeric(tab[[4]])-.3)
n <- pc_normalize(tab,"xy");s <- pc_defaults();s$layout <- "xy";s$graph <- "scatter";s$method <- "linear";s$group1 <- "A";s$group2 <- "B";s$fit_scope <- "all"
r <- pc_analyze(n,"linear","A",options=s)
check(nrow(r$parameters)==4 && all(r$fit_status$status=="Fitted") && is.na(r$p),"independent linear fits expose both series without a pooled P value")
for(g in n$groups) {
  reference <- lm(value~x,data=n$data[n$data$group==g,])
  check(max(abs(r$parameters$estimate[r$parameters$series==g]-coef(reference)))<1e-12,paste("multi-series coefficients match independent lm for",g))
  check(max(abs(r$diagnostics$residual[r$diagnostics$series==g]-residuals(reference)))<1e-12,paste("residuals retain the fitted series for",g))
}
check(all(table(r$curve$series)==240) && nrow(ggplot2::ggplot_build(pc_plot(n,s,r))$data[[length(pc_plot(n,s,r)$layers)]])==480,"both fitted curves render with separate group identities")
s$graph <- "residual";check(length(unique(ggplot2::ggplot_build(pc_plot(n,s,r))$data[[2]]$colour))==2,"multi-series residual plot keeps both series colors")
partial <- n;partial$data <- partial$data[!(partial$data$group=="B" & partial$data$x>1),]
failed <- pc_analyze(partial,"linear","A",options=s)
check(identical(failed$fit_status$status,c("Fitted","Not fitted")) && nzchar(failed$fit_status$detail[2]),"a failed series is identified alongside successful fits")
check(errors(pc_analyze(pc_normalize(data.frame(X=1:2,A=1:2,B=3:4),"xy"),"linear","A",options=s)),"failure of every series rejects the analysis")
for (mode in c("individual","mean")) for (weight in c("none","inv_y2","replicate_sd")) {
  options <- s;options$fit_replicates <- mode;options$fit_weight <- weight
  combined <- pc_analyze(n,"linear","A",options=options);options$fit_scope <- "selected"
  check(all(vapply(n$groups,function(g) {
    separate <- pc_analyze(n,"linear",g,options=options)
    max(abs(combined$parameters$estimate[combined$parameters$series==g]-separate$parameters$estimate))<1e-12
  },logical(1))),paste("all-series fits preserve",mode,"replicates with",weight,"weighting"))
}
s$graph <- "scatter";s$series_styles <- '{"A":{"color":"#C03050","point_shape":17,"point_size":4,"line_width":1.4,"line_type":"dashed"}}'
edited <- pc_graph_edit(tab,s,list(series_styles=s$series_styles));p <- pc_plot(n,edited,r);built <- ggplot2::ggplot_build(p)
check(all(c("#C03050",pc_palettes$craft[2]) %in% built$data[[1]]$colour),"one custom series color preserves the other series default")
check(all(built$data[[1]]$shape[built$data[[1]]$colour=="#C03050"]==17),"per-series symbols reach point geometry")
last <- built$data[[length(built$data)]]
check(all(last$linetype[last$colour=="#C03050"]=="dashed") && all(last$linewidth[last$colour=="#C03050"]==1.4),"per-series patterns and widths reach fitted curves")
grob <- ggplot2::ggplotGrob(p);legend <- grob$grobs[[which(grob$layout$name=="guide-box-top")]]
check(sum(legend$layout$name=="guides")==1,"color, symbols and line styles share one series legend")
check(errors(pc_series_styles('{"A":{"point_shape":1.5}}')) && errors(pc_series_styles('{"A":{"color":"red<script>"}}')) && errors(pc_series_styles('[]')),"malformed series styles reject atomically")
project <- pc_project(tab,s,study_name="Independent fits");decoded <- pc_decode_project(project)
check(project$schema_version==5L && identical(decoded$settings$series_styles,s$series_styles) && decoded$settings$fit_scope=="all","new settings round-trip in a schema that older apps reject")
target <- pc_defaults();copied <- pc_graph_style(s,target)
check(copied$series_styles==s$series_styles && copied$fit_scope==target$fit_scope && copied$method==target$method,"format reuse copies series overrides while preserving the target analysis")
old <- pc_project(pc_example("column")$table,pc_defaults());old$settings$series_styles <- NULL;old$settings$fit_scope <- NULL
check(pc_decode_project(old)$settings$fit_scope=="selected","older projects acquire safe single-series defaults")
inserted <- pc_edit_rows(tab,"xy","insert",3,2)
check(nrow(inserted)==10 && all(is.na(inserted[3:4,])) && identical(inserted[5:10,1],tab[3:8,1]),"row insertion shifts every replicate together and keeps new cells missing")
check(identical(pc_table_text(pc_edit_rows(inserted,"xy","delete",3,2)),pc_table_text(tab)),"deleting inserted rows restores the source exactly")
check(nrow(pc_edit_rows(tab,"xy","insert",9,1))==9,"rows can be appended at the end")
check(errors(pc_edit_rows(tab,"xy","delete",1,8)) && errors(pc_edit_rows(tab,"xy","insert",1.5,1)),"invalid row ranges cannot change the table")
renamed <- pc_edit_series(tab,"xy","rename","A","Control")
check(identical(names(renamed)[2:3],c("Control [rep 1]","Control [rep 2]")) && identical(renamed[[2]],tab[[2]]),"renaming a series preserves both replicate columns")
moved <- pc_edit_series(tab,"xy","right","A")
check(identical(names(moved),names(tab)[c(1,4,5,2,3)]) && identical(moved[[1]],tab[[1]]),"moving an XY series moves its entire replicate block and preserves X")
removed <- pc_edit_series(tab,"xy","delete","A")
check(ncol(removed)==3 && identical(pc_xy_structure(removed)$groups,"B"),"deleting an XY series removes its whole block")
check(errors(pc_edit_series(removed,"xy","delete","B")) && errors(pc_edit_series(tab,"xy","rename","A","B")),"the last series and duplicate names are protected")
counts <- pc_edit_rows(pc_example("contingency")$table,"contingency","insert",1,2)
check(all(counts[1:2,-1]=="0") && !anyDuplicated(counts[[1]]),"new contingency rows have unique labels and explicit zero counts")
file <- "artifacts/tests/parity-unicode.pdf";ggplot2::ggsave(file,p+ggplot2::labs(title="α ± μ"),device=pc_pdf_device,width=6,height=4)
check(rawToChar(readBin(file,"raw",n=4))=="%PDF","Unicode vector PDF exports without XQuartz")
shiny::testServer(app, {
  # Explicit fixture: production startup is intentionally empty.
  raw(pc_example("column")$table);sheet_name("Treatment groups");project_name("Example study");document_open(TRUE)
  do.call(session$setInputs,pc_defaults());session$flushReact()
  before <- pc_table_text(raw());session$setInputs(manage_table=1);session$flushReact()
  session$setInputs(table_edit_tab="rows",row_edit_action="insert",row_edit_first=2,row_edit_count=2,confirm_table_edit=1);session$flushReact()
  check(nrow(raw())==10 && all(is.na(raw()[2:3,])),"server commits a structural change as one data edit")
  session$setInputs(undo_data=1);session$flushReact();check(pc_table_text(raw())==before,"Undo restores the complete table structure")
  session$setInputs(redo_data=1);session$flushReact();check(nrow(raw())==10,"Redo reapplies the whole structural edit")
  session$setInputs(manage_table=2);session$flushReact();session$setInputs(add_row=1);session$flushReact()
  session$setInputs(row_edit_count=1,confirm_table_edit=2);session$flushReact();check(nrow(raw())==11,"stale structural dialogs cannot edit a changed source")
})
cat(checks,"new Prism workflow checks passed.\n")
