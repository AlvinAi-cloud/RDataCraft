# One local browser workspace, no public listening socket or shared-network server.
root<-normalizePath(getwd(),winslash='/')
.libPaths(c(file.path(Sys.getenv('RDATACRAFT_RUNTIME',file.path(root,'runtime')),'library'),.libPaths()))
required<-c('shiny','bslib','ggplot2','DT','readxl','jsonlite','svglite','survival','xml2','processx')
missing<-required[!vapply(required,requireNamespace,logical(1),quietly=TRUE)]
if(length(missing)) stop('Missing local dependencies: ',paste(missing,collapse=', '),'. Run scripts/install.R with this R installation before launching.')
Sys.setenv(RDATACRAFT_PORTABLE='1')
# Pick a free loopback port, so an older workspace never receives this session's requests.
if(!any(grepl('^--port=',commandArgs(trailingOnly=TRUE)))) {
  args<-c(commandArgs(trailingOnly=TRUE),paste0('--port=',httpuv::randomPort()))
  port<-as.integer(sub('^--port=','',args[grepl('^--port=',args)][1]))
  options(device=function(...) grDevices::pdf(file=NULL,...),shiny.sanitize.errors=TRUE)
  cat('RDataCraft portable: keep this console open; close it to stop the local workspace.\n')
  shiny::runApp(root,host='127.0.0.1',port=port,launch.browser=TRUE,display.mode='normal')
} else source('scripts/run.R')
