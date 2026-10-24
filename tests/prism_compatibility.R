app<-source('app.R')$value
checks<-0L
check<-function(value,label) {if(!isTRUE(value)) stop('FAIL: ',label);checks<<-checks+1L;cat('PASS:',label,'\n')}
reject<-function(expr) inherits(tryCatch(force(expr),error=identity),'error')
x<-pc_prism_import('tests/fixtures/multi-input-workbook.prism')
check(length(x$tables)==7 && !length(x$skipped),'all five input sheets, saved result and supported analysis are retained')
get<-function(id) x$tables[[which(vapply(x$tables,function(t) identical(t$source_id,id),logical(1)))[1]]]
wide<-get('WIDE');summary<-get('SUMMARY');saved<-get('SAVED');excluded<-get('EXCLUSIONS');grouped<-get('GROUPED')
check(ncol(wide$table)==3 && identical(names(wide$table),c('X','Signal [rep 1]','Signal [rep 2]')),'wide Prism tables trim only empty trailing slots and retain rich-text labels')
check(identical(as.numeric(wide$table[[2]]),c(1,101)) && pc_xy_structure(wide$table)$n==2,'replicate observations and grouping survive compaction')
check(!isTRUE(wide$snapshot),'excluded styling for unused future columns does not mark observed data as excluded')
check(summary$layout=='multiple' && isTRUE(summary$snapshot) && all(c('Response Mean','Response SEM') %in% names(summary$table)),'summary means and SEM are explicit snapshots rather than raw replicates')
check(isTRUE(saved$snapshot) && grepl('do not rerun',saved$conversion),'saved derived values disclose that upstream operations are not live')
check(isTRUE(excluded$unresolved_exclusions) && identical(as.numeric(excluded$table[[2]]),c(4,9)),'unresolved exclusions retain all numeric values in an unreviewed source table')
check(grouped$layout=='grouped' && nrow(grouped$table)==100 && ncol(grouped$table)==3,'wide grouped tables retain every replicate in long rows')
check(sum(!is.na(grouped$table[[3]]))==100 && length(unique(grouped$table$Group))==2,'long grouped conversion does not pool or discard observations')
check(any(grepl('MULTI-INPUT SHEETS:.*2 of 2',x$report)),'multiple linked input sheets are reported as separate preserved tables')
check(any(grepl('UNLINKED ANALYSIS:',x$report)) && !any(grepl('Multiple input sheets or a missing input',x$report)),'missing links are distinguished from multi-input workflows')
analysis<-x$tables[[which(vapply(x$tables,function(t) identical(t$settings$method,'student'),logical(1)))]]
s<-analysis$settings;a<-pc_analyze(pc_normalize(analysis$table,'column'),'student',s$group1,s$group2,s)
reference<-t.test(c(3,6,8,10),c(1,3,4,6),var.equal=TRUE)
check(s$group1=='Treatment' && s$group2=='Control' && abs(a$p-reference$p.value)<1e-12,'legacy-schema unpaired Student test preserves direction and recomputes from observations')
check(abs(a$comparisons$estimate-3.25)<1e-12 && abs(a$comparisons$ci_low-reference$conf.int[1])<1e-12,'unpaired estimates and intervals use the saved comparison direction')
bad<-list(analysisClass='T_TESTS_AND_NONPARAMETRIC',isAllDataAnalyzed=TRUE,title='Unknown')
parameters<-list('$id'='unknown/schema.json',content=list(experimentalDesign='UNPAIRED_T_TEST'))
check(reject(pc_prism_analysis(get('STUDENT'),bad,parameters)),'unknown parameter schemas do not acquire an inferred analysis class')
check(reject(pc_prism_analysis(excluded,bad,list(analysisClass=bad$analysisClass,content=list()))),'unreviewed source exclusions block automatic inferential conversion')
full<-pc_prism_import('tests/fixtures/fully-populated-replicates.prism');wide<-full$tables[[1]]
check(ncol(wide$table)==2 && nrow(wide$table)==100 && isTRUE(wide$replicates_in_rows),'fully populated wide XY inputs retain replicates as repeated-X rows')
check(sum(!is.na(wide$table[[2]]))==100 && identical(as.numeric(wide$table[[2]]),as.numeric(c(1:50,101:150))),'wide XY conversion preserves every value in source row/subcolumn order')
for(t in x$tables) {
 s<-if(is.null(t$settings)) pc_prism_settings(t) else t$settings
 p<-pc_project(t$table,s,list(D1=pc_sheet(t$table,s,t$name,t$views)))
 check(identical(pc_decode_project(p)$table,t$table),paste(t$name,'survives project save/reopen'))
}
shiny::testServer(app,{
 do.call(session$setInputs,pc_defaults());session$flushReact()
 session$setInputs(desktop_import_prism=list(path=normalizePath('tests/fixtures/multi-input-workbook.prism'),nonce=1));session$flushReact()
 check(!document_open(),'multi-input preview leaves the current study unchanged')
 session$setInputs(prism_all=TRUE,confirm_prism_import=1);session$flushReact()
 pending<-restoring_settings();if(!is.null(pending)) do.call(session$setInputs,pending);session$flushReact()
 check(length(workbook())==7,'confirmed multi-input import adds a separate table for every source and saved working representation')
 check(length(import_reports())==1 && grepl('MULTI-INPUT',import_reports()[[1]]),'multi-input provenance is retained in the saved import report')
})
cat(checks,'Prism compatibility checks passed.\n')
