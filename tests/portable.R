app<-source('app.R')$value
checks<-0L
check<-function(v,label) {if(!isTRUE(v)) stop('FAIL: ',label);checks<<-checks+1L;cat('PASS:',label,'\n')}
# Exercise the real async process transport with a local fixture, without sending data to a provider.
fake<-tempfile(fileext='.R')
writeLines(c(
 "args<-commandArgs(trailingOnly=TRUE)",
 "if('login' %in% args) {cat('Logged in using a fixture account\\n');quit(status=0)}",
 "out<-args[match('--output-last-message',args)+1]",
 "request<-paste(readLines(file('stdin'),warn=FALSE),collapse='\\n')",
 "cat('PRIVATE_DIAGNOSTIC_DO_NOT_DISPLAY\\n',file=stderr())",
 "if(grepl('DELAY_FIXTURE',request,fixed=TRUE)) Sys.sleep(8)",
 "writeLines('{\"answer\":\"Local transport fixture response\",\"operations\":[]}',out)"
),fake)
deliveries<-list();driver<-pc_portable_ai(function(x) deliveries[[length(deliveries)+1L]]<<-x,
 command=if(.Platform$OS.type=='windows') list(binary=file.path(R.home('bin'),'Rscript.exe'),args=c('--vanilla',fake)) else list(binary=file.path(R.home('bin'),'exec/R'),args=c('--vanilla','--slave',paste0('--file=',fake),'--args')),timeout=4)
check(grepl('Connected',driver$status()),'portable transport checks an existing local CLI sign-in without copying credentials')
request<-list(id='fixture',instructions='Return a data-only plan.',prompt='A prompt with quotes and shell-looking text: $(touch NEVER_RUN) & `anything`',context=list(values_shared=FALSE),history=list(),schema=pc_ai_schema())
driver$start(request)
end<-Sys.time()+6
while(!length(deliveries) && Sys.time()<end) later::run_now(.1)
check(length(deliveries)==1 && isTRUE(deliveries[[1]]$ok),'portable model transport completes asynchronously through a real child process')
check(grepl('Local transport fixture response',deliveries[[1]]$response) && !grepl('PRIVATE_DIAGNOSTIC',jsonlite::toJSON(deliveries)),'request data and diagnostics are not substituted for the structured model response')
check(!file.exists('NEVER_RUN'),'shell-looking prompt text is passed as data and is never evaluated')
deliveries<-list();driver<-pc_portable_ai(function(x) deliveries[[length(deliveries)+1L]]<<-x,
 command=if(.Platform$OS.type=='windows') list(binary=file.path(R.home('bin'),'Rscript.exe'),args=c('--vanilla',fake)) else list(binary=file.path(R.home('bin'),'exec/R'),args=c('--vanilla','--slave',paste0('--file=',fake),'--args')),timeout=.3)
request$id<-'slow';request$prompt<-'DELAY_FIXTURE';driver$start(request)
end<-Sys.time()+5
while(!length(deliveries) && Sys.time()<end) later::run_now(.1)
check(length(deliveries)==1 && !deliveries[[1]]$ok && grepl('timed out',deliveries[[1]]$message),'portable model timeout terminates the child without applying any operation')
driver$cancel(announce=FALSE)
check(file.exists('scripts/portable.R') && if(.Platform$OS.type=='windows') all(file.exists(c('Launch RDataCraft.cmd','Launch RDataCraft.ps1','Validate RDataCraft.cmd'))) else file.exists('desktop/RDataCraft.swift') || file.exists('Launch RDataCraft portable.command'),'current-platform launch entry points are included in the distribution')
# Use the real Rscript parser: R's --file/--args form is not Rscript's file form.
probe_dir<-file.path(tempdir(),'Rscript path with spaces Δ');dir.create(probe_dir,showWarnings=FALSE)
probe<-file.path(probe_dir,'argument check.R');writeLines('cat(paste(commandArgs(TRUE),collapse="|"),"\\n",sep="")',probe)
rscript<-file.path(R.home('bin'),if(.Platform$OS.type=='windows') 'Rscript.exe' else 'Rscript')
probe_args<-c('--port=8765','two words','Δvalue')
execution<-processx::run(rscript,c('--vanilla',probe,probe_args),env=c(RHOME=R.home()),timeout=10000,error_on_status=FALSE)
check(execution$status==0L && identical(trimws(execution$stdout),paste(probe_args,collapse='|')),'real Rscript runs a Unicode/spaced file path and preserves script arguments without --file or --args')
for(kind in unname(pc_layouts())) {
 e<-pc_example(kind);s<-pc_defaults();s$layout<-kind;s$method<-e$method;s$graph<-unname(pc_graphs(kind))[1];s$title<-e$title;s$x_label<-e$x_label;s$y_label<-e$y_label
 if(kind=='multiple') {s$graph<-'pcascores';s$pca_label_column<-'Sample';s$pca_group_column<-'Group'}
 n<-pc_normalize(e$table,kind);s$group1<-n$groups[1];s$group2<-n$groups[min(2,length(n$groups))];a<-pc_analyze(n,s$method,s$group1,s$group2,s)
 for(fmt in c('svg','pdf','png')) {
  f<-tempfile(fileext=paste0('.',fmt));device<-switch(fmt,svg=svglite::svglite,pdf=pc_pdf_device,png=pc_png_device)
  ggplot2::ggsave(f,pc_plot(n,s,a),device=device,width=5,height=4,dpi=96)
  check(file.info(f)$size>100,paste(kind,fmt,'renders using the current platform device'))
 }
}
cat(checks,'portable transport and device checks passed on',R.version$platform,'\n')
