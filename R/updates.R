# Explicit, read-only update checks. Installers are downloaded only on user action.
pc_update_version <- function(x) {
 if(!is.character(x) || length(x)!=1L || is.na(x) || !grepl('^v?[0-9]+\\.[0-9]+(?:\\.[0-9]+)?$',x,perl=TRUE)) stop('Unsupported release version.')
 p<-strsplit(sub('^v','',x),'\\.')[[1]]
 # Early RDataCraft releases use decimal numbering: 0.41, 0.42, then 0.5.
 c(as.numeric(p[1]),if(p[1]=='0') as.numeric(paste0('0.',p[2])) else as.numeric(p[2]),if(length(p)>2) as.numeric(p[3]) else 0)
}
pc_update_newer <- function(candidate,current) {a<-pc_update_version(candidate);b<-pc_update_version(current);i<-which(a!=b);length(i)>0 && a[i[1]]>b[i[1]]}
pc_update_platform <- function(system=Sys.info()[['sysname']],machine=Sys.info()[['machine']]) {
 if(system=='Darwin') return(if(machine %in% c('arm64','aarch64')) 'macos-arm64' else 'macos-x86_64')
 if(system=='Windows') return('windows-x64')
 if(system=='Linux' && machine %in% c('x86_64','amd64')) return('ubuntu-amd64')
 ''
}
pc_update_release <- function(value,current,platform=pc_update_platform()) {
 base<-'https://github.com/AlvinAi-cloud/RDataCraft/releases'
 if(!is.list(value) || isTRUE(value$draft) || isTRUE(value$prerelease)) stop('No public stable release was returned.')
 pc_update_version(value$tag_name)
 expected<-c('macos-x86_64'='RDataCraft-macos-x86_64.dmg','macos-arm64'='RDataCraft-macos-arm64.dmg','windows-x64'='RDataCraft-windows-x64-setup.exe','ubuntu-amd64'='RDataCraft-ubuntu-amd64.deb')
 asset<-NULL
 if(platform %in% names(expected)) for(x in value$assets) {
  url<-paste0(base,'/download/',value$tag_name,'/',expected[[platform]])
  if(identical(x$name,expected[[platform]]) && identical(x$browser_download_url,url) && identical(x$state,'uploaded') && is.numeric(x$size) && length(x$size)==1 && is.finite(x$size) && x$size>0) asset<-list(name=x$name,url=url,size=x$size)
 }
 list(current=current,latest=sub('^v','',value$tag_name),newer=pc_update_newer(value$tag_name,current),url=paste0(base,'/tag/',value$tag_name),asset=asset)
}
pc_update_fetch <- function(destination) {
 options(timeout=10)
 utils::download.file('https://api.github.com/repos/AlvinAi-cloud/RDataCraft/releases/latest',destination,method='libcurl',quiet=TRUE,mode='wb',headers=c('User-Agent'='RDataCraft update check','Accept'='application/vnd.github+json'))
 if(!file.exists(destination) || file.info(destination)$size>1e6) stop('The update response was unavailable or too large.')
 jsonlite::read_json(destination,simplifyVector=FALSE)
}
pc_updates_server <- function(input,output,session) {
 worker<-NULL;folder<-NULL;started<-NULL;generation<-0L
 current<-jsonlite::read_json('config/release.json')$version
 result<-shiny::reactiveVal(NULL);message<-shiny::reactiveVal('')
 cleanup<-function() {if(!is.null(worker) && worker$is_alive()) try(worker$kill_tree(),silent=TRUE);worker<<-NULL;if(!is.null(folder)) unlink(folder,recursive=TRUE);folder<<-NULL}
 poll<-function(token) {
  if(token!=generation || is.null(worker)) return()
  if(worker$is_alive() && as.numeric(difftime(Sys.time(),started,units='secs'))<20) {later::later(function() shiny::withReactiveDomain(session,shiny::isolate(poll(token))),.2);return()}
  tryCatch({
   path<-file.path(folder,'response.json')
   if(worker$is_alive() || worker$get_exit_status()!=0 || !file.exists(path) || file.info(path)$size>1e6) stop('Could not check for updates. Check your connection and try again, or open the releases page.')
   result(pc_update_release(jsonlite::read_json(path,simplifyVector=FALSE),current));message('')
  },error=function(e) message(conditionMessage(e)))
  cleanup()
 }
 shiny::observeEvent(input$check_updates,{
  generation<<-generation+1L;cleanup();result(NULL);message('Checking the latest public GitHub release…')
  shiny::showModal(shiny::modalDialog(title='Check for Updates',shiny::uiOutput('update_result'),easyClose=TRUE,fade=FALSE,footer=shiny::modalButton('Close')))
  tryCatch({
   folder<<-tempfile('RDataCraft-update-');dir.create(folder,mode='0700');started<<-Sys.time()
   env<-c('current',RDATACRAFT_UPDATE_FOLDER=folder)
   if(.Platform$OS.type=='windows') {exe<-file.path(R.home('bin'),'Rscript.exe');args<-c('--vanilla',normalizePath('scripts/check_updates.R',winslash='/'))}
   else {exe<-file.path(R.home('bin'),'exec','R');args<-c('--vanilla','--slave',paste0('--file=',normalizePath('scripts/check_updates.R')))}
   worker<<-processx::process$new(exe,args,wd=getwd(),env=env,stdout='|',stderr='|',cleanup_tree=TRUE)
   token<-generation;later::later(function() shiny::withReactiveDomain(session,shiny::isolate(poll(token))),.2)
  },error=function(e) {cleanup();message('Could not start the update check. Open the releases page to check manually.')})
 })
 output$update_result<-shiny::renderUI({
  r<-result();shiny::tagList(shiny::p(paste('Installed version:',current)),
   if(is.null(r)) shiny::p(role='status',message()) else shiny::tagList(shiny::p(paste('Latest public release:',r$latest)),
    shiny::p(if(r$newer) 'A newer version is available.' else if(all(pc_update_version(current)==pc_update_version(r$latest))) 'You are up to date.' else 'This copy is newer than the latest public release.'),
    if(r$newer && !is.null(r$asset)) shiny::tagList(shiny::tags$a(class='btn btn-primary',href=r$asset$url,target='_blank',rel='noopener noreferrer',paste('Download',r$asset$name)),shiny::p('Download the installer, close RDataCraft, then install the update. Your saved studies remain separate.')) else if(r$newer) shiny::p('Choose a compatible installer on the release page.')),
   shiny::p(shiny::tags$a(href=if(is.null(r)) 'https://github.com/AlvinAi-cloud/RDataCraft/releases/latest' else r$url,target='_blank',rel='noopener noreferrer','View release notes & downloads')),
   shiny::p(class='inline-note','Checks run only when requested. This sends no study data, AI credentials or local file paths. Nothing is installed automatically.'))
 })
 session$onSessionEnded(cleanup)
 invisible(list(result=result,message=message))
}
