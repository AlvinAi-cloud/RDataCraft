# Optional packages are resolved read-only, approved, then staged in a user library.
pc_pkg_repo <- function() 'https://cloud.r-project.org'
pc_pkg_library <- function() {
  override<-Sys.getenv('RDATACRAFT_USER_LIBRARY','')
  if(nzchar(override)) return(normalizePath(override,winslash='/',mustWork=FALSE))
  base<-if(.Platform$OS.type=='windows') file.path(Sys.getenv('LOCALAPPDATA',path.expand('~')),'RDataCraft') else if(Sys.info()[['sysname']]=='Darwin') file.path(path.expand('~/Library/Application Support'),'RDataCraft') else tools::R_user_dir('RDataCraft','data')
  minor<-strsplit(R.version$minor,'.',fixed=TRUE)[[1]][1]
  file.path(base,'R',paste(R.version$major,minor,sep='.'),gsub('[^A-Za-z0-9_.-]','_',R.version$platform),'library')
}
pc_pkg_libraries <- function() unique(c(pc_pkg_library(),.libPaths()))
pc_pkg_installed <- function(libs=pc_pkg_libraries()) {
  libs<-libs[dir.exists(libs)]
  db<-utils::installed.packages(lib.loc=libs,noCache=TRUE)
  db[!duplicated(db[,'Package']),,drop=FALSE]
}
pc_pkg_missing <- function(packages,libs=pc_pkg_libraries()) setdiff(packages,rownames(pc_pkg_installed(libs)))
pc_pkg_script_info <- function(code) {
  tree<-parse(text=code,keep.source=FALSE);packages<-character();install<-FALSE
  call_name<-function(x) {if(is.symbol(x)) as.character(x) else if(is.call(x) && as.character(x[[1]])[1] %in% c('::',':::')) paste(as.character(x[[2]]),as.character(x[[3]]),sep='::') else ''}
  walk<-function(x) {
    if(missing(x)) return()
    if(is.expression(x) || is.pairlist(x)) {invisible(lapply(as.list(x),walk));return()}
    if(!is.call(x)) return()
    fn<-call_name(x[[1]]);parts<-strsplit(fn,'::',fixed=TRUE)[[1]];short<-tail(parts,1)
    if(length(parts)==2) packages<<-c(packages,parts[1])
    if(fn %in% c('::',':::') && length(x)>=3) packages<<-c(packages,as.character(x[[2]]))
    if(short %in% c('install.packages','download.packages','install_github','install_gitlab','install_url','pkg_install','pkg_build','install_local') || (length(parts)==2 && parts[1] %in% c('BiocManager','remotes','devtools','renv','pak') && short %in% c('install','restore','hydrate'))) install<<-TRUE
    if(short %in% c('library','require','requireNamespace','loadNamespace') && length(x)>1) {
      args<-as.list(x)[-1];arg<-if('package' %in% names(args)) args[['package']] else args[[1]]
      literal<-is.character(arg) && length(arg)==1
      character_only<-isTRUE(args[['character.only']])
      if(literal || (is.symbol(arg) && !character_only)) packages<<-c(packages,as.character(arg))
    }
    invisible(lapply(as.list(x),walk))
  }
  walk(tree);list(packages=pc_r_packages(paste(unique(packages),collapse=',')),installs=install)
}
pc_pkg_requirements <- function(code,packages='') unique(c(pc_r_packages(packages),pc_pkg_script_info(code)$packages))
pc_pkg_type <- function() {
  type<-.Platform$pkgType
  if(!grepl('binary',type,fixed=TRUE)) stop('Approved in-app installation currently requires compatible CRAN binaries on Mac or Windows. Source builds are not started automatically.')
  type
}
pc_pkg_dependencies <- function(text) {
  if(is.null(text) || is.na(text) || !nzchar(text)) return(list())
  lapply(strsplit(text,',',fixed=TRUE)[[1]],function(item) {
    match<-regmatches(trimws(item),regexec('^([A-Za-z][A-Za-z0-9.]*)\\s*(?:\\(\\s*(>=|<=|==|>|<|=)\\s*([^()[:space:]]+)\\s*\\))?$',trimws(item),perl=TRUE))[[1]]
    if(!length(match)) stop(paste('Unsupported package dependency:',item))
    list(name=match[2],op=match[3],version=match[4])
  })
}
pc_pkg_satisfies <- function(version,requirement) {
  if(!nzchar(requirement$op)) return(TRUE)
  n<-utils::compareVersion(version,requirement$version)
  switch(requirement$op,'>='=n>=0,'<='=n<=0,'=='=n==0,'='=n==0,'>'=n>0,'<'=n<0,FALSE)
}
pc_pkg_plan <- function(requested,db,installed=pc_pkg_installed(),library=pc_pkg_library(),repo=pc_pkg_repo(),type=pc_pkg_type()) {
  requested<-pc_r_packages(paste(requested,collapse=','));selected<-list();edges<-list();walking<-character()
  field<-function(name,key) {if(!key %in% colnames(db) || is.na(db[name,key])) '' else db[name,key]}
  need<-function(req,parent='Requested analysis') {
    name<-req$name
    if(name=='R') {if(!pc_pkg_satisfies(as.character(getRversion()),req)) stop('A required dependency needs a different R version.');return()}
    if(!is.null(selected[[name]])) {if(!pc_pkg_satisfies(selected[[name]]$version,req)) stop(paste('Conflicting required versions for',name));return()}
    old<-if(name %in% rownames(installed)) installed[name,'Version'] else ''
    if(nzchar(old) && pc_pkg_satisfies(old,req)) return()
    if(!name %in% rownames(db)) stop(paste('No compatible CRAN binary is available for',name,'with this R version and computer. No packages were installed.'))
    version<-field(name,'Version')
    if(!grepl('^[0-9][0-9A-Za-z.+-]*$',version) || !pc_pkg_satisfies(version,req)) stop(paste('Available version cannot satisfy dependency:',name,req$op,req$version))
    if(!is.null(selected[[name]])) return()
    suffix<-if(type=='win.binary') '.zip' else '.tgz'
    url<-paste0(utils::contrib.url(repo,type=type),'/',name,'_',version,suffix)
    selected[[name]]<<-list(name=name,version=version,previous=old,required_by=parent,url=url,md5=field(name,'MD5sum'),license=substr(field(name,'License'),1,400))
    if(length(selected)>200L) stop('This request requires over 200 packages. Choose a smaller package set.')
    deps<-unlist(lapply(c('Depends','Imports','LinkingTo'),function(k) pc_pkg_dependencies(field(name,k))),recursive=FALSE)
    edges[[name]]<<-vapply(deps,function(d) d$name,character(1))
    for(dep in deps) need(dep,name)
  }
  for(name in requested) need(list(name=name,op='',version=''))
  ordered<-character();visiting<-character()
  visit<-function(name) {
    if(name %in% ordered || !name %in% names(selected)) return()
    if(name %in% visiting) stop('Circular package dependencies could not be resolved.')
    visiting<<-c(visiting,name);for(dep in edges[[name]]) visit(dep)
    visiting<<-setdiff(visiting,name);ordered<<-c(ordered,name)
  }
  for(name in names(selected)) visit(name)
  list(requested=as.list(requested),packages=unname(selected[ordered]),repository=repo,type=type,library=library,r_version=as.character(getRversion()),platform=R.version$platform,created=as.numeric(Sys.time()))
}
pc_pkg_validate_plan <- function(plan) {
  if(!is.list(plan) || !identical(plan$repository,pc_pkg_repo()) || !identical(plan$type,pc_pkg_type()) || !identical(plan$library,pc_pkg_library()) || !identical(plan$platform,R.version$platform) || !identical(plan$r_version,as.character(getRversion()))) stop('Package approval does not match this R installation. Check packages again.')
  if(!is.numeric(plan$created) || length(plan$created)!=1L || !is.finite(plan$created) || abs(as.numeric(difftime(Sys.time(),as.POSIXct(plan$created,origin='1970-01-01'),units='secs')))>15*60) stop('This package list has expired. Check packages again before approving.')
  if(!is.list(plan$packages) || length(plan$packages)>200) stop('Invalid package list.')
  for(p in plan$packages) {
    pc_r_packages(p$name);if(length(p$name)!=1 || !grepl('^[0-9][0-9A-Za-z.+-]*$',p$version)) stop('Invalid package version.')
    expected<-paste0(utils::contrib.url(plan$repository,type=plan$type),'/',p$name,'_',p$version,if(plan$type=='win.binary') '.zip' else '.tgz')
    if(!identical(p$url,expected) || !is.character(p$md5) || length(p$md5)!=1 || (!identical(p$md5,'') && !grepl('^[0-9a-fA-F]{32}$',p$md5))) stop('Invalid package archive or checksum.')
  }
  if(anyDuplicated(vapply(plan$packages,function(p) p$name,character(1)))) stop('Duplicate package approval entries.')
  invisible(plan)
}
pc_pkg_transaction <- function(plan,id) {
  if(!grepl('^[0-9A-Za-z-]+$',id)) stop('Invalid installation identifier.')
  list(stage=file.path(dirname(plan$library),paste0('.rdatacraft-install-',id)),lock=file.path(plan$library,'.rdatacraft-install-lock'))
}
pc_pkg_recover_stale <- function(library) {
  lock<-file.path(library,'.rdatacraft-install-lock');metadata<-file.path(lock,'transaction.json')
  if(!dir.exists(lock)) return(invisible(NULL))
  # Recover only when the owner is demonstrably gone. Creation time identifies
  # the original process even if the operating system has since reused its PID.
  if(!file.exists(metadata) || file.info(metadata)$size>1e6) stop('A package installation lock needs manual review. Close other RDataCraft windows and see Help → Package installation recovery.')
  x<-jsonlite::read_json(metadata,simplifyVector=FALSE)
  if(!is.list(x) || !is.character(x$id) || length(x$id)!=1 || !grepl('^[0-9A-Za-z-]+$',x$id) || !identical(x$library,library) || !is.numeric(x$pid) || length(x$pid)!=1 || !is.finite(x$pid) || x$pid<1 || !is.numeric(x$started) || length(x$started)!=1 || !is.finite(x$started) || !is.list(x$packages) || length(x$packages)>200 || any(!vapply(x$packages,function(p) is.list(p) && is.character(p$name) && length(p$name)==1 && grepl('^[A-Za-z][A-Za-z0-9.]*$',p$name),logical(1)))) stop('Invalid package recovery record. See Help → Package installation recovery.')
  alive<-tryCatch({h<-ps::ps_handle(x$pid);ps::ps_is_running(h) && abs(as.numeric(ps::ps_create_time(h))-x$started)<.01},error=function(e) {if(ps::ps_pid_exists(x$pid)) stop('Could not check the package installer. Close other RDataCraft windows and try again.');FALSE})
  if(alive) stop('Another RDataCraft package installation is running. Wait for it to finish or stop it in its window.')
  pc_pkg_recover(list(library=library,packages=x$packages),x$id)
  if(dir.exists(lock)) stop('Could not recover the previous installation. See Help → Package installation recovery.')
  invisible(TRUE)
}
pc_pkg_recover <- function(plan,id) {
  p<-pc_pkg_transaction(plan,id);owner<-file.path(p$lock,'owner')
  if(!file.exists(owner) || !identical(readLines(owner,warn=FALSE),id)) return(invisible(NULL))
  # All recovery callers (worker, parent and other windows) use the same atomic
  # claim. An interrupted recovery claim is retained for explicit review.
  claim<-file.path(p$lock,'recovering')
  if(!dir.create(claim,showWarnings=FALSE)) stop('Another window is recovering this installation, or recovery was interrupted. See Help → Package installation recovery.')
  token<-paste(Sys.getpid(),sample.int(1e8,1),sep='-');claim_owner<-file.path(claim,'owner')
  writeLines(token,claim_owner)
  on.exit(if(file.exists(claim_owner) && identical(readLines(claim_owner,warn=FALSE),token)) unlink(claim,recursive=TRUE),add=TRUE)
  if(!file.exists(owner) || !identical(readLines(owner,warn=FALSE),id)) return(invisible(NULL))
  marker<-file.path(p$stage,'committed.json')
  receipt<-if(file.exists(marker)) tryCatch(jsonlite::read_json(marker,simplifyVector=FALSE),error=function(e) NULL) else NULL
  if(is.null(receipt) && file.exists(file.path(p$stage,'promoting'))) for(pkg in rev(plan$packages)) {
    name<-pkg$name;target<-file.path(plan$library,name);backup<-file.path(p$stage,'backup',name);staged<-file.path(p$stage,'library',name)
    restored<-file.path(p$stage,'restoring',name)
    if(dir.exists(backup)) {
      dir.create(dirname(restored),showWarnings=FALSE)
      if(!file.create(restored)) stop('Could not record package recovery. Installation files were retained.')
      if(dir.exists(target)) unlink(target,recursive=TRUE)
      if(!file.rename(backup,target)) stop(paste('Could not restore package',name,'. Installation files retained at',p$stage))
    } else if(file.exists(restored)) {
      if(!dir.exists(target)) stop(paste('A restored package is missing:',name,'. Installation files retained at',p$stage))
    } else if(!dir.exists(staged) && dir.exists(target)) unlink(target,recursive=TRUE)
  }
  unlink(p$stage,recursive=TRUE);unlink(p$lock,recursive=TRUE);invisible(receipt)
}
pc_pkg_install <- function(plan,id,fetch=function(url,dest) utils::download.file(url,dest,mode='wb',quiet=TRUE),verify=NULL) {
  pc_pkg_validate_plan(plan)
  if(is.null(plan$approved_at) || !is.numeric(plan$approved_at) || length(plan$approved_at)!=1 || !is.finite(plan$approved_at)) stop('Installation requires a separately approved package list.')
  if(!length(plan$packages)) return(list(status='success',message='All required packages are already installed.',packages=list()))
  dir.create(plan$library,recursive=TRUE,showWarnings=FALSE,mode='0700')
  p<-pc_pkg_transaction(plan,id)
  if(dir.exists(p$stage)) stop('Installation staging folder already exists. Check packages again.')
  pc_pkg_recover_stale(plan$library)
  if(!dir.create(p$lock,showWarnings=FALSE)) stop('Another RDataCraft package installation is running, or its lock needs recovery. Wait for it to finish.')
  committed<-FALSE;on.exit(if(!committed) {if(!file.exists(file.path(p$lock,'owner'))) unlink(p$lock,recursive=TRUE) else pc_pkg_recover(plan,id)},add=TRUE)
  writeLines(id,file.path(p$lock,'owner'))
  jsonlite::write_json(list(id=id,library=plan$library,packages=lapply(plan$packages,function(p) list(name=p$name)),pid=Sys.getpid(),started=as.numeric(ps::ps_create_time(ps::ps_handle()))),file.path(p$lock,'transaction.json'),auto_unbox=TRUE)
  if(!dir.create(p$stage,showWarnings=FALSE,mode='0700')) stop('Could not create the installation staging folder.')
  stage<-file.path(p$stage,'library');dir.create(stage);dir.create(file.path(p$stage,'downloads'));dir.create(file.path(p$stage,'backup'))
  options(timeout=180,install.packages.compile.from.source='never')
  for(pkg in plan$packages) {
    cat('Downloading approved package',pkg$name,pkg$version,'\n')
    archive<-file.path(p$stage,'downloads',basename(pkg$url));fetch(pkg$url,archive)
    if(!file.exists(archive) || (!identical(pkg$md5,'') && !identical(tolower(unname(tools::md5sum(archive))),tolower(pkg$md5)))) stop(paste('Download checksum changed or failed for',pkg$name,'. Check packages and approve a fresh list.'))
    utils::install.packages(archive,lib=stage,repos=NULL,type=plan$type,dependencies=FALSE,quiet=TRUE,lock=TRUE)
    description<-file.path(stage,pkg$name,'DESCRIPTION')
    if(!file.exists(description)) stop(paste('Installation failed for',pkg$name))
    actual<-read.dcf(description)
    if(actual[1,'Package']!=pkg$name || actual[1,'Version']!=pkg$version) stop('Installed package does not match the approved version.')
  }
  cat('Verifying approved packages in a separate R process…\n')
  if(is.null(verify)) {
    job<-file.path(p$stage,'verify.rds');saveRDS(list(names=vapply(plan$packages,function(x)x$name,character(1)),libs=unique(c(stage,plan$library,.libPaths()))),job)
    script<-file.path(p$stage,'verify.R')
    writeLines(c('x<-readRDS(commandArgs(trailingOnly=TRUE)[1]);.libPaths(x$libs)',"for(p in x$names) if(!requireNamespace(p,quietly=TRUE)) stop(paste('Package cannot load:',p))"),script)
    args<-if(.Platform$OS.type=='windows') c('--vanilla',script,job) else c('--vanilla','--slave',paste0('--file=',script),'--args',job)
    check<-processx::run(pc_r_engine(),args,error_on_status=FALSE,timeout=120000)
    if(check$status!=0) stop(paste('Package load verification failed:',substr(paste(check$stdout,check$stderr),1,1000)))
  } else verify(stage)
  file.create(file.path(p$stage,'promoting'))
  for(pkg in plan$packages) {
    target<-file.path(plan$library,pkg$name)
    if(dir.exists(target) && !file.rename(target,file.path(p$stage,'backup',pkg$name))) stop(paste('Package is in use and cannot be updated:',pkg$name))
    if(!file.rename(file.path(stage,pkg$name),target)) stop(paste('Could not activate package:',pkg$name))
  }
  receipt<-list(status='success',message='Approved packages installed. Review the script, then click Run reviewed script.',packages=plan$packages,repository=plan$repository,library=plan$library,r_version=plan$r_version,platform=plan$platform,approved_at=plan$approved_at,installed_at=format(Sys.time(),tz='UTC',usetz=TRUE))
  jsonlite::write_json(receipt,file.path(p$stage,'committed.json'),auto_unbox=TRUE,null='null')
  try(cat(jsonlite::toJSON(receipt,auto_unbox=TRUE,null='null'),'\n',file=file.path(dirname(plan$library),'installations.jsonl'),append=TRUE),silent=TRUE)
  committed<-TRUE
  receipt
}
# Metadata and approved installation jobs never evaluate the analysis script.
pc_pkg_job <- function(root=getwd()) {
  root<-normalizePath(root,winslash='/',mustWork=TRUE);worker<-NULL;folder<-NULL;job<-NULL;started<-NULL;limit<-NULL
  cleanup<-function() {
    if(!is.null(worker) && worker$is_alive()) {try(worker$kill_tree(),silent=TRUE);if(worker$is_alive()) try(worker$kill(),silent=TRUE);try(worker$wait(timeout=2000),silent=TRUE)}
    worker<<-NULL
    receipt<-if(!is.null(job) && identical(job$action,'install')) tryCatch(pc_pkg_recover(job$plan,job$id),error=function(e) list(status='error',message=conditionMessage(e))) else NULL
    if(!is.null(folder)) unlink(folder,recursive=TRUE);folder<<-NULL;job<<-NULL;invisible(receipt)
  }
  log<-function() tryCatch({path<-if(is.null(folder)) '' else file.path(folder,'process.log');if(!file.exists(path)) '' else {con<-file(path,'rb');on.exit(close(con));size<-file.info(path)$size;seek(con,max(0,size-30000));bytes<-readBin(con,'raw',n=30000);iconv(rawToChar(bytes[bytes!=as.raw(0)]),from='UTF-8',to='UTF-8',sub='byte')}},error=function(e) '')
  start<-function(action,packages=NULL,plan=NULL) {
    if(!is.null(worker)) stop('A package job is already running.')
    if(!action %in% c('plan','install')) stop('Invalid package job.')
    if(action=='install') pc_pkg_validate_plan(plan)
    id<-paste0(as.integer(Sys.time()),'-',sample.int(1e8,1))
    job<<-list(action=action,packages=packages,plan=plan,id=id,root=root,library=pc_pkg_library(),libs=pc_pkg_libraries())
    folder<<-tempfile('RDataCraft-Packages-');dir.create(folder,mode='0700');saveRDS(job,file.path(folder,'job.rds'))
    args<-if(.Platform$OS.type=='windows') c('--vanilla',file.path(root,'scripts/r_packages_worker.R'),folder) else c('--vanilla','--slave',paste0('--file=',file.path(root,'scripts/r_packages_worker.R')),'--args',folder)
    started<<-Sys.time();limit<<-if(action=='plan') 90 else 900
    tryCatch(worker<<-processx::process$new(pc_r_engine(),args,wd=folder,stdout=file.path(folder,'process.log'),stderr='2>&1',cleanup_tree=TRUE,env=c('current',RDATACRAFT_USER_LIBRARY=pc_pkg_library())),error=function(e) {cleanup();stop(e)})
    invisible(TRUE)
  }
  stop_job<-function(message='Package operation stopped. Any incomplete staged installation was rolled back.') {text<-log();receipt<-cleanup();if(!is.null(receipt)) receipt else list(status='cancelled',message=message,log=text)}
  poll<-function() {
    if(is.null(worker)) return(NULL)
    if(worker$is_alive()) {if(as.numeric(difftime(Sys.time(),started,units='secs'))>limit) return(stop_job('Package operation timed out. Incomplete staged changes were rolled back.'));return(NULL)}
    result<-tryCatch({p<-file.path(folder,'result.json');if(!file.exists(p) || file.info(p)$size>2e6) stop('Package job did not return a valid result.');jsonlite::read_json(p,simplifyVector=FALSE)},error=function(e) list(status='error',message=conditionMessage(e)))
    result$log<-log();receipt<-cleanup();if(!is.null(receipt)) {receipt$log<-result$log;receipt} else result
  }
  list(start=start,poll=poll,cancel=stop_job,cleanup=cleanup,busy=function() !is.null(worker),log=log)
}
