# Reviewed custom analyses execute only in a separate local R process.
source("R/r_packages.R",local=TRUE)
pc_r_text <- function(x,max=30000L) {
  if(!is.character(x) || length(x)!=1L || is.na(x) || nchar(x,type='bytes')>max) stop('Invalid or oversized Advanced R text.',call.=FALSE)
  x
}
pc_r_packages <- function(text='') {
  text<-pc_r_text(text,1000L);p<-trimws(unlist(strsplit(text,'[,[:space:]]+')));p<-unique(p[nzchar(p)])
  if(length(p)>30 || any(!grepl('^[A-Za-z][A-Za-z0-9.]*$',p))) stop('Enter package names separated by commas.',call.=FALSE)
  p
}
pc_r_script <- function(code) {
  code<-pc_r_text(code)
  if(!nzchar(trimws(code))) stop('Write or load an R script first.',call.=FALSE)
  tryCatch(parse(text=code,keep.source=FALSE),error=function(e) stop(paste('R syntax:',conditionMessage(e)),call.=FALSE))
  if(pc_pkg_script_info(code)$installs) stop('Use Check / install packages for a separate approval. Remove installation commands from the analysis script.',call.=FALSE)
  code
}
pc_r_svg <- function(svg) {
  svg<-pc_r_text(svg,2e6L);if(!nzchar(svg)) return(svg)
  if(grepl('<!DOCTYPE|<!ENTITY',svg,ignore.case=TRUE)) stop('Unsupported SVG declaration.')
  # Exported figures need only local fragment references. Reject CSS escapes
  # and imports instead of attempting to execute or interpret arbitrary CSS.
  check_styles<-function(text) {
    urls<-regmatches(text,gregexpr('url\\([^)]*\\)',text,perl=TRUE,ignore.case=TRUE))[[1]]
    if(grepl('\\\\|@import|<\\?xml-stylesheet',text,ignore.case=TRUE) ||
       any(!grepl("^url\\(\\s*(['\"]?)#[^[:space:]'\"()<>]+\\1\\s*\\)$",urls,perl=TRUE,ignore.case=TRUE))) stop('Unsupported external or escaped SVG styles.')
  }
  check_styles(svg)
  doc<-xml2::read_xml(svg,options='NONET');nodes<-xml2::xml_find_all(doc,'//*')
  if(xml2::xml_name(xml2::xml_root(doc))!='svg' || any(tolower(xml2::xml_name(nodes)) %in% c('script','foreignobject','iframe','object','embed','animate','animatetransform','animatemotion','set','discard'))) stop('Unsupported active SVG content.')
  for(node in nodes) {
    a<-xml2::xml_attrs(node)
    if(any(grepl('^on|^base$',names(a),ignore.case=TRUE)) || any(grepl('href$',names(a),ignore.case=TRUE) & !startsWith(a,'#'))) stop('Unsupported SVG links or events.')
    for(value in a) check_styles(value)
    if(tolower(xml2::xml_name(node))=='style') check_styles(xml2::xml_text(node))
  }
  svg
}
pc_r_records <- function(records=NULL) {
  if(is.null(records)) return(list())
  if(!is.list(records) || length(records)>20L) stop('A study supports up to 20 saved Advanced R analyses.')
  for(r in records) {
    if(!is.list(r) || !setequal(names(r),c('id','title','code','packages','source_name','source_tsv','created','result'))) stop('Invalid Advanced R record.')
    for(k in c('id','title','source_name','created')) pc_r_text(r[[k]],150L)
    pc_r_text(r$code);pc_r_packages(r$packages);pc_r_text(r$source_tsv,2e6L)
    pc_read_text(r$source_tsv,'\t')
    z<-r$result
    if(!is.null(z)) {
      if(!is.list(z) || !setequal(names(z),c('status','console','text','tables','svg','pdf','r_version','packages','seconds'))) stop('Invalid Advanced R result.')
      if(!z$status %in% c('success','error','cancelled','timeout')) stop('Invalid Advanced R status.')
      for(k in c('console','text')) pc_r_text(z[[k]],30000L)
      pc_r_text(z$r_version,150L);pc_r_svg(z$svg);pc_r_text(z$pdf,3e6L)
      if(nzchar(z$pdf) && !startsWith(rawToChar(head(jsonlite::base64_dec(z$pdf),4)),'%PDF')) stop('Invalid Advanced R PDF.')
      if(!is.numeric(z$seconds) || length(z$seconds)!=1 || !is.finite(z$seconds) || z$seconds<0) stop('Invalid R duration.')
      if(!is.list(z$packages) || length(z$packages)>200 || any(!vapply(z$packages,function(p) is.list(p) && setequal(names(p),c('name','version')) && is.character(p$name) && length(p$name)==1L && grepl('^[A-Za-z][A-Za-z0-9.]*$',p$name) && is.character(p$version) && length(p$version)==1L && nchar(p$version)<100,logical(1)))) stop('Invalid R package record.')
      if(!is.list(z$tables) || length(z$tables)>10L) stop('Return up to ten result tables.')
      for(t in z$tables) {if(!is.list(t) || !setequal(names(t),c('name','data_tsv'))) stop('Invalid R result table.');pc_r_text(t$name,100);pc_r_text(t$data_tsv,2e6L);pc_read_text(t$data_tsv,'\t')}
    }
  }
  if(anyDuplicated(vapply(records,function(r) r$id,character(1)))) stop('Duplicate Advanced R record IDs.')
  if(nchar(jsonlite::toJSON(records,auto_unbox=TRUE,null='null'),type='bytes')>18e6) stop('Saved R analyses exceed 18 MB. Export/remove an older record before adding another.')
  unname(records)
}
pc_r_record <- function(title,code,packages,tab,name) {
  r<-list(id=paste0(format(Sys.time(),'%Y%m%d%H%M%OS6'),'-',sample.int(1e8,1)),title=pc_r_text(title,100),code=pc_r_script(code),packages=pc_r_text(packages,1000),source_name=pc_r_text(name,100),source_tsv=pc_table_text(tab),created=format(Sys.time(),tz='UTC',usetz=TRUE),result=NULL)
  if(!nzchar(trimws(title))) stop('Give this analysis a title.')
  pc_r_records(list(r))[[1]]
}
pc_r_failure <- function(status,message,seconds=0) list(status=status,console=substr(message,1,30000),text='',tables=list(),svg='',pdf='',r_version=R.version.string,packages=list(),seconds=seconds)
pc_r_log <- function(path,max=30000L) {
  if(!file.exists(path)) return('')
  con<-file(path,'rb');on.exit(close(con))
  bytes<-readBin(con,'raw',n=max)
  iconv(rawToChar(bytes[bytes!=as.raw(0)]),from='UTF-8',to='UTF-8',sub='')
}
pc_r_engine <- function() {
  if(.Platform$OS.type=='windows') {
    paths<-c(file.path(R.home('bin'),'Rscript.exe'),file.path(R.home(),'bin','x64','Rscript.exe'))
    path<-paths[file.exists(paths)][1];if(is.na(path)) stop('The bundled Rscript engine is missing.')
    return(path)
  }
  file.path(R.home('bin'),'exec','R')
}
pc_r_runner <- function(root=getwd(),timeout=120) {
  root<-normalizePath(root,winslash='/',mustWork=TRUE);worker<-NULL;folder<-NULL;started<-NULL;record<-NULL;limit<-timeout
  cleanup<-function() {if(!is.null(worker) && worker$is_alive()) {try(worker$kill_tree(),silent=TRUE);if(worker$is_alive()) try(worker$kill(),silent=TRUE);try(worker$wait(timeout=2000),silent=TRUE)};worker<<-NULL;if(!is.null(folder)) unlink(folder,recursive=TRUE);folder<<-NULL}
  finish<-function(status=NULL,message=NULL) {
    seconds<-as.numeric(difftime(Sys.time(),started,units='secs'))
    if(is.null(status)) {
      output<-file.path(folder,'result.json')
      result<-tryCatch({if(!file.exists(output) || file.info(output)$size>7e6) stop(paste('R did not return a bounded result.',pc_r_log(file.path(folder,'process.log'))));jsonlite::read_json(output,simplifyVector=FALSE)},error=function(e) pc_r_failure('error',conditionMessage(e),seconds))
    } else result<-pc_r_failure(status,message,seconds)
    result$seconds<-seconds;record$result<<-result
    value<-tryCatch(pc_r_records(list(record))[[1]],error=function(e) {record$result<-pc_r_failure('error',paste('Invalid R output:',conditionMessage(e)),seconds);record})
    cleanup();value
  }
  start<-function(value,seconds=timeout) {
    if(!is.null(worker)) stop('An R analysis is already running.')
    record<<-pc_r_records(list(value))[[1]];pc_r_script(record$code)
    packages<-pc_pkg_requirements(record$code,record$packages);missing<-pc_pkg_missing(packages)
    if(length(missing)) stop(paste('Packages unavailable in this R runtime:',paste(missing,collapse=', '),'. Use Check / install packages to review and approve installation.'))
    if(!is.numeric(seconds) || length(seconds)!=1L || !is.finite(seconds) || seconds<1 || seconds>300) stop('Choose a time limit from 1 to 300 seconds.')
    limit<<-seconds;folder<<-tempfile('RDataCraft-Advanced-R-');dir.create(folder,mode='0700');started<<-Sys.time()
    saveRDS(list(code=record$code,packages=packages,table=pc_read_text(record$source_tsv,'\t'),root=root),file.path(folder,'input.rds'))
    args<-c('--vanilla','--slave',paste0('--file=',file.path(root,'scripts/advanced_r_worker.R')),'--args',folder)
    if(.Platform$OS.type=='windows') args<-c('--vanilla',file.path(root,'scripts/advanced_r_worker.R'),folder)
    tryCatch(worker<<-processx::process$new(pc_r_engine(),args,wd=folder,stdout=file.path(folder,'process.log'),stderr='2>&1',cleanup_tree=TRUE,env=c('current',R_LIBS_USER=paste(pc_pkg_libraries(),collapse=.Platform$path.sep))),error=function(e) {cleanup();stop(e)})
    invisible(TRUE)
  }
  poll<-function() {
    if(is.null(worker)) return(NULL)
    if(worker$is_alive()) {
      log<-file.path(folder,'console.txt');process_log<-file.path(folder,'process.log')
      if(any(file.info(c(log,process_log))$size>1e6,na.rm=TRUE)) return(finish('error','R produced too much console output.'))
      if(as.numeric(difftime(Sys.time(),started,units='secs'))>limit) return(finish('timeout','R exceeded the selected time limit.'))
      return(NULL)
    }
    finish()
  }
  cancel<-function() {if(is.null(worker)) NULL else finish('cancelled','Stopped by the user. No source observations were changed.')}
  list(start=start,poll=poll,cancel=cancel,busy=function() !is.null(worker),cleanup=cleanup)
}
pc_r_templates <- function() list(
 summary=list(title='Custom summaries and intervals',packages='',code='# data is an independent copy of the selected input table.\n# Convert or reshape explicitly when the study design requires it.\nnumeric_columns <- data[vapply(data, is.numeric, logical(1))]\nif (!length(numeric_columns)) stop("Choose a table with numeric measurements.")\nsummary_table <- do.call(rbind, lapply(names(numeric_columns), function(name) {\n  x <- stats::na.omit(numeric_columns[[name]])\n  data.frame(Variable=name, N=length(x), Mean=mean(x), SD=stats::sd(x))\n}))\nresult <- list(tables=list(Summary=summary_table),\n  plot=ggplot2::ggplot(summary_table, ggplot2::aes(x=Variable, y=Mean)) +\n    ggplot2::geom_point() + ggplot2::labs(title="Custom R summary"),\n  text="Descriptive results; no inferential test was selected.")'),
 wilcoxon=list(title='Custom rank comparison',packages='',code='numeric_columns <- data[vapply(data, is.numeric, logical(1))]\nif (ncol(numeric_columns) < 2) stop("Choose at least two numeric columns.")\nx <- stats::na.omit(numeric_columns[[1]])\ny <- stats::na.omit(numeric_columns[[2]])\nfit <- stats::wilcox.test(x, y, exact=FALSE, conf.int=TRUE)\nresult <- list(tables=list(Test=data.frame(Statistic=unname(fit$statistic), P=fit$p.value,\n  CI_low=fit$conf.int[1], CI_high=fit$conf.int[2])), text=paste(fit$method, "Assumes independent experimental units."))'),
 glm=list(title='Generalized linear model',packages='',code='# This template extends beyond the app presets.\n# Rename your input columns to Response, Treatment and Batch, or edit the formula.\nrequired <- c("Response", "Treatment", "Batch")\nif (!all(required %in% names(data))) stop("This example needs Response, Treatment and Batch columns. Edit the formula for your data.")\nfit <- stats::glm(Response ~ Treatment + Batch, data=data, family=stats::poisson())\nresult <- list(tables=list(Coefficients=as.data.frame(cbind(Term=rownames(summary(fit)$coefficients), summary(fit)$coefficients))),\n text="Poisson GLM: verify count outcomes, independence and dispersion. This template does not establish model suitability.")'))
