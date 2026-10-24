args<-commandArgs(trailingOnly=TRUE);destination<-if(length(args)) args[1] else '.'
lib<-normalizePath(file.path(Sys.getenv('RDATACRAFT_RUNTIME','runtime'),'library'),winslash='/',mustWork=TRUE)
p<-installed.packages(lib.loc=.libPaths());p<-p[!duplicated(p[,'Package']),,drop=FALSE]
p<-p[normalizePath(p[,'LibPath'],winslash='/',mustWork=FALSE)==lib | (!is.na(p[,'Priority']) & p[,'Priority']=='recommended'),,drop=FALSE]
manifest<-data.frame(package=p[,'Package'],version=p[,'Version'],license=p[,'License'],row.names=NULL);manifest<-manifest[order(manifest$package),]
write.csv(manifest,file.path(destination,'dependencies.csv'),row.names=FALSE)
jsonlite::write_json(list(r_version=as.character(getRversion()),platform=R.version$platform,packages=manifest),file.path(destination,'dependencies.lock.json'),auto_unbox=TRUE,pretty=TRUE)
