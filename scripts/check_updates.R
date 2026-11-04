source('R/updates.R')
folder<-Sys.getenv('RDATACRAFT_UPDATE_FOLDER');stopifnot(nzchar(folder),dir.exists(folder))
value<-pc_update_fetch(file.path(folder,'download.json'))
jsonlite::write_json(value,file.path(folder,'response.json'),auto_unbox=TRUE,null='null')
