app<-source('app.R')$value
checks<-0L
check<-function(v,label) {if(!isTRUE(v)) stop('FAIL: ',label);checks<<-checks+1L;cat('PASS:',label,'\n')}
reject<-function(x) inherits(tryCatch(force(x),error=identity),'error')
legacy<-pc_prism_import('tests/fixtures/source-tables.prism')
check(length(legacy$tables[[1]]$views)==2 && grepl('Recreated',legacy$tables[[1]]$views$V2$name),'binary source-linked graph becomes an editable linked view with explicit reconstruction labeling')
check(any(grepl('RECREATED SOURCE GRAPH',legacy$report)),'default graph recreation is distinguished from original formatting conversion')
x<-pc_prism_import('tests/fixtures/editable-workflows.prism')
check(length(x$tables)==4,'raw source, paired analysis, PCA and JSON graph become four editable working tables')
check(length(x$report)==5 && any(grepl('NOT CONVERTED.*binary',x$report)),'unconverted binary metadata is reported explicitly')
raw<-x$tables[[1]];pair<-x$tables[[2]];pca<-x$tables[[3]];graph<-x$tables[[4]]
check(raw$layout=='multiple' && identical(raw$table$Subject,c('S1','S2','S2','S1','S3','S3','S4','S4','S5','S5')),'multivariable import retains labels and original row order')
check(identical(as.numeric(pair$table$Control),c(5,6,7,9,10)) && identical(as.numeric(pair$table$Drug),c(9,8,10,13,15)),'paired conversion matches subject IDs instead of aligning source row positions')
s<-pair$settings;a<-pc_analyze(pc_normalize(pair$table,'column'),s$method,s$group1,s$group2,s)
reference<-t.test(c(9,8,10,13,15),c(5,6,7,9,10),paired=TRUE)
check(abs(a$p-reference$p.value)<1e-12,'rerun paired P value matches independent base R reference')
check(abs(a$comparisons$estimate[1]-mean(c(4,2,3,4,5)))<1e-12,'Prism swap direction is retained for the mean paired effect')
changed<-pair$table;changed[1,'Drug']<-'20';b<-pc_analyze(pc_normalize(changed,'column'),s$method,s$group1,s$group2,s)
check(abs(b$p-a$p)>1e-5,'editing imported observations recomputes the analysis instead of displaying saved Prism results')
s<-pca$settings;a<-pc_analyze(pc_normalize(pca$table,'multiple'),'pca',options=s)
check(identical(a$pca$variables,c('Response','Time')) && s$pca_scale,'PCA keeps the source variable selection and unit-SD scaling')
check(s$pca_group_column=='Group' && !'Subject' %in% a$pca$variables,'PCA grouping metadata is excluded from measurements')
check(grepl('Parallel analysis',pca$conversion),'unsupported PCA retention rules are disclosed')
check(graph$settings$x_min=='0' && graph$settings$x_max=='5' && graph$settings$y_max=='20' && graph$settings$title=='Response by time','JSON graph title, variable selection and explicit axis limits are editable settings')
for(t in x$tables) {
 s<-if(is.null(t$settings)) pc_prism_settings(t) else t$settings;n<-pc_normalize(t$table,t$layout)
 check(length(ggplot2::ggplot_build(pc_plot(n,s,pc_analyze(n,s$method,s$group1,s$group2,s)))$data)>0,paste(t$name,'renders from original observations'))
 linked<-if(is.null(t$views)) list(V1=pc_view(s)) else t$views
 p<-pc_project(t$table,s,list(D1=pc_sheet(t$table,s,t$name,linked)),import_reports=list(paste(x$report,collapse='\n')))
 decoded<-pc_decode_project(p)
 check(p$schema_version==10 && identical(decoded$settings,s) && length(decoded$import_reports)==1,paste(t$name,'settings and import history reopen in schema 10'))
}
# Reject changes to analysis semantics rather than accepting an approximate match.
t<-raw
base<-list(analysisClass='T_TESTS_AND_NONPARAMETRIC',isAllDataAnalyzed=TRUE,title='test')
ref<-function(uid) list(col=list(uid=uid))
params<-list(analysisClass=base$analysisClass,content=list(experimentalDesign='PAIRED_T_TEST',variableDesign=list(responseList=list(ref('RESPONSE')),factorList=list(ref('GROUP')),subject=ref('SUBJECT')),options=list(pValueTailType='P_VALUE_TWO_TAILED',significanceLevel=.05)))
bad<-params;bad$content$options$pValueTailType<-'ONE_TAILED'
check(reject(pc_prism_analysis(t,base,bad)),'one-tailed analysis is not silently replaced by a two-sided test')
bad<-base;bad$isAllDataAnalyzed<-FALSE
check(reject(pc_prism_analysis(t,bad,params)),'analysis-specific subset selections are rejected explicitly')
bad<-t;bad$table<-rbind(t$table,t$table[1,])
check(reject(pc_prism_analysis(bad,base,params)),'duplicate subject/group records are not pooled or treated as independent pairs')
bad<-params;bad$content$variableDesign$subject<-ref('DERIVED_ID')
check(reject(pc_prism_analysis(t,base,bad)),'missing upstream variables cannot be matched by a similar title')
check(length(pc_pca_views(pca$settings))==3,'new variable distribution graph does not become a fourth PCA component view')
shiny::testServer(app,{
 do.call(session$setInputs,pc_defaults());session$flushReact()
 session$setInputs(desktop_import_prism=list(path=normalizePath('tests/fixtures/editable-workflows.prism'),nonce=1));session$flushReact()
 check(!document_open(),'conversion preview leaves an empty session unopened')
 session$setInputs(prism_table='1',prism_all=TRUE,prism_override=FALSE,prism_keep_original=TRUE,confirm_prism_import=1);session$flushReact()
 if(!is.null(restoring_settings())) do.call(session$setInputs,restoring_settings());session$flushReact()
 check(length(workbook())==4 && workbook()$D2$settings$method=='paired' && length(workbook()$D3$views)==3,'confirmed import installs actual rerunnable analyses and linked PCA views')
 check(length(import_reports())==1 && grepl('NOT CONVERTED',import_reports()[[1]]),'conversion warnings remain in project import history')
 pc_write_project(snapshot(),'artifacts/tests/editable-prism.rdatacraft');loaded<-pc_load_project('artifacts/tests/editable-prism.rdatacraft')
 check(length(loaded$import_reports)==1 && loaded$worksheets$D4$settings$x_max=='5','native save/reopen snapshot retains converted graph axes and report')
 count<-length(workbook());session$setInputs(desktop_import_prism=list(path=normalizePath('tests/fixtures/source-tables.pzfx'),nonce=2));session$flushReact()
 session$setInputs(prism_table='2',prism_all=TRUE,prism_override=TRUE,prism_method='paired',prism_graph='paired',prism_group1='A',prism_group2='A',prism_error='sem',prism_title='Invalid pair',prism_x_title='Group',prism_y_title='Response',confirm_prism_import=2);session$flushReact()
 check(length(workbook())==count && length(import_reports())==1,'invalid manual plan is rejected before adding any table or attachment')
 session$setInputs(prism_method='welch',prism_graph='box',prism_group2='B',prism_all=FALSE,confirm_prism_import=3);session$flushReact()
 if(!is.null(restoring_settings())) do.call(session$setInputs,restoring_settings());session$flushReact()
 check(length(workbook())==count+1 && settings()$method=='welch' && settings()$graph=='box','legacy PZFX can be reconstructed as an editable Welch analysis and box graph')
 check(grepl('User-selected reconstruction',tail(import_reports(),1)[[1]]),'manual reconstruction is distinguished from metadata conversion in the saved log')
})
# The portable decoder handles Unicode and the embedded namespace used by Prism samples.
f<-tempfile(fileext='.pzfx');writeLines('<root xmlns:p="http://graphpad.com/prism/Prism.htm"><p:GraphPadPrismFile><p:Table TableType="OneWay"><p:Title>Unicode α</p:Title><p:YColumn><p:Title>Y</p:Title><p:Subcolumn><p:d>1</p:d><p:d>2</p:d></p:Subcolumn></p:YColumn></p:Table></p:GraphPadPrismFile></root>',f,useBytes=TRUE)
check(pc_prism_import(f)$tables[[1]]$name=='Unicode α','cross-platform XML decoder handles embedded Prism namespaces and Unicode')
check(reject(pc_prism_import('tests/fixtures/unsafe-source.pzfx')),'cross-platform decoder blocks DTD and external entity documents')
cat(checks,'editable Prism checks passed.\n')
