# Separate R process: receives a copied table, executes only a reviewed script,
# returns bounded data-only JSON. This is process separation, not an OS sandbox.
args<-commandArgs(trailingOnly=TRUE);folder<-normalizePath(args[[1]],winslash='/',mustWork=TRUE)
job<-readRDS(file.path(folder,'input.rds'))
setwd(job$root)
source('R/data.R',local=TRUE)
source(file.path(job$root,'R/style.R'),local=TRUE)
source(file.path(job$root,'R/devices.R'),local=TRUE)
setwd(folder)
.libPaths(c(strsplit(Sys.getenv('R_LIBS_USER'),.Platform$path.sep,fixed=TRUE)[[1]],.Library))
options(device=function(...) grDevices::pdf(file=NULL,...))
ggplot2::theme_set(pc_theme(7))
console<-file(file.path(folder,'console.txt'),open='wt');sink(console);sink(console,type='message')
result<-tryCatch({
 for(p in job$packages) if(!requireNamespace(p,quietly=TRUE)) stop(paste('Missing package:',p))
 env<-new.env(parent=globalenv());env$data_raw<-job$table
 env$data<-as.data.frame(lapply(job$table,function(x) utils::type.convert(x,as.is=TRUE)),check.names=FALSE)
 env$result<-list();eval(parse(text=job$code,keep.source=FALSE),envir=env)
 z<-env$result
 if(!is.list(z) || any(!names(z) %in% c('tables','plot','text'))) stop('Assign result <- list(tables=list(...), plot=..., text="...").')
 tables<-if(is.null(z$tables)) list() else z$tables
 if(!is.list(tables) || length(tables)>10) stop('Return up to ten named data-frame tables.')
 if(length(tables) && (is.null(names(tables)) || any(!nzchar(names(tables))) || anyDuplicated(names(tables)))) stop('Name every result table uniquely.')
 tables<-lapply(seq_along(tables),function(i) {
  tab<-as.data.frame(tables[[i]],check.names=FALSE)
  if(!nrow(tab) || !ncol(tab) || any(vapply(tab,is.list,logical(1)))) stop('Return nonempty data frames with atomic columns.')
  tab<-pc_check_table(tab)
  list(name=substr(names(z$tables)[i],1,100),data_tsv=pc_table_text(tab))
 })
 svg<-'';pdf<-''
 if(!is.null(z$plot)) {
  if(!inherits(z$plot,'ggplot') && !is.function(z$plot)) stop('plot must be a ggplot or a function that draws a base R plot.')
  draw<-function() {if(is.function(z$plot)) z$plot() else print(z$plot)}
  svglite::svglite(file.path(folder,'figure.svg'),width=3,height=3,pointsize=7)
  tryCatch(draw(),finally=grDevices::dev.off())
  pc_pdf_device(file.path(folder,'figure.pdf'),width=3,height=3,pointsize=7)
  tryCatch(draw(),finally=grDevices::dev.off())
  if(file.info(file.path(folder,'figure.svg'))$size>2e6 || file.info(file.path(folder,'figure.pdf'))$size>2e6) stop('Figure output exceeds 2 MB.')
  svg<-paste(readLines(file.path(folder,'figure.svg'),warn=FALSE),collapse='\n')
  pdf<-jsonlite::base64_enc(readBin(file.path(folder,'figure.pdf'),'raw',n=2e6))
 }
 text<-if(is.null(z$text)) '' else paste(as.character(z$text),collapse='\n')
 if(nchar(text,type='bytes')>30000) stop('Result text exceeds 30 KB.')
 list(status='success',text=text,tables=unname(tables),svg=svg,pdf=pdf)
},error=function(e) list(status='error',text=conditionMessage(e),tables=list(),svg='',pdf=''))
sink(type='message');sink();close(console)
console_path<-file.path(folder,'console.txt')
console_connection<-file(console_path,'rb')
console_bytes<-readBin(console_connection,'raw',n=30000L);close(console_connection)
result$console<-iconv(rawToChar(console_bytes[console_bytes!=as.raw(0)]),from='UTF-8',to='UTF-8',sub='')
result$r_version<-R.version.string
result$packages<-unname(lapply(sort(loadedNamespaces()),function(p) list(name=p,version=as.character(utils::packageVersion(p)))))
result$seconds<-0
out<-jsonlite::toJSON(result,auto_unbox=TRUE,null='null',na='null',digits=15)
if(nchar(out,type='bytes')>7e6) {
 result$status<-'error';result$text<-'Combined R output exceeds 7 MB.';result$tables<-list();result$svg<-'';result$pdf<-''
}
jsonlite::write_json(result,file.path(folder,'result.json'),auto_unbox=TRUE,null='null',na='null',digits=15)
