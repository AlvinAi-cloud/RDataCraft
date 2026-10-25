# Run the shipped R suites with this exact engine. No Python, model or user study.
root<-normalizePath(getwd(),winslash='/')
lib<-file.path(Sys.getenv('RDATACRAFT_RUNTIME',file.path(root,'runtime')),'library')
.libPaths(c(lib,.Library),include.site=FALSE)
if(!all(vapply(c('jsonlite','processx'),requireNamespace,logical(1),quietly=TRUE))) stop('Restore the bundled dependencies before validation.')
Sys.setenv(R_LIBS_USER=lib)
dir.create('artifacts',showWarnings=FALSE)
suites<-jsonlite::fromJSON('config/validation-suites.json')
if(!all(file.exists(file.path('tests',paste0(c('setup',suites),'.R'))))) stop('The validation suite is incomplete. Restore the full bundle.')
if(!file.exists('tests/fixtures/editable-workflows.prism')) stop('Synthetic fixtures are missing. Restore the full bundle or run tests/make_prism_fixtures.py.')
runner<-if(.Platform$OS.type=='windows') file.path(R.home('bin'),'Rscript.exe') else file.path(R.home('bin'),'exec/R')
args<-function(script) if(.Platform$OS.type=='windows') c('--vanilla',script) else c('--vanilla','--slave',paste0('--file=',script),'--args')
run<-function(name) {
  log<-file.path('artifacts',paste0('native-',name,'.log'))
  result<-tryCatch(processx::run(runner,args(file.path('tests',paste0(name,'.R'))),wd=root,stdout=log,stderr='2>&1',timeout=180000,error_on_status=FALSE),error=function(e) list(status=1L,error=conditionMessage(e)))
  lines<-if(file.exists(log)) readLines(log,warn=FALSE,encoding='UTF-8') else character()
  value<-list(test=name,exit_code=result$status,checks=sum(grepl('^PASS:',lines)),log=log)
  if(!is.null(result$error)) value$error<-result$error
  cat(name,if(result$status==0L) 'PASS' else 'FAIL',paste0('(',value$checks,' checks)'), '\n')
  if(result$status!=0L) cat(paste(tail(lines,15),collapse='\n'),'\n')
  value
}
setup<-run('setup')
if(setup$exit_code!=0L) stop('Validation setup failed; see artifacts/native-setup.log.')
results<-lapply(suites,run)
passed<-all(vapply(results,function(x) identical(as.integer(x$exit_code),0L),logical(1)))
version<-jsonlite::fromJSON('config/release.json')$version
report_file<-file.path('artifacts',paste0('validation-native-',version,'.json'))
report<-list(version=version,status=if(passed) 'passed' else 'failed',engine=R.version$platform,r_version=as.character(getRversion()),operating_system=Sys.info()[['sysname']],tests=results)
jsonlite::write_json(report,report_file,pretty=TRUE,auto_unbox=TRUE,null='null')
cat('Report:',report_file,'\n')
quit(save='no',status=if(passed) 0L else 1L)
