# Read-only CRAN resolution or an installation plan already approved in the app.
folder<-normalizePath(commandArgs(trailingOnly=TRUE)[[1]],winslash='/',mustWork=TRUE)
job<-readRDS(file.path(folder,'job.rds'));setwd(job$root)
source('R/advanced_r.R',local=TRUE);setwd(folder)
options(timeout=60)
result<-tryCatch({
 if(job$action=='plan') {
  type<-pc_pkg_type();repo<-pc_pkg_repo()
  cat('Checking compatible CRAN package metadata. No packages are being installed.\n')
  db<-utils::available.packages(repos=repo,type=type,fields=c('License','MD5sum'))
  if(!nrow(db)) stop('Could not read CRAN package metadata. Check the network connection and try again.')
  list(status='planned',plan=pc_pkg_plan(job$packages,db,pc_pkg_installed(job$libs),job$library,repo,type))
 } else if(job$action=='install') pc_pkg_install(job$plan,job$id) else stop('Invalid package job.')
},error=function(e) list(status='error',message=conditionMessage(e)))
jsonlite::write_json(result,file.path(folder,'result.json'),auto_unbox=TRUE,null='null')
