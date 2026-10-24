# Opaque, byte-for-byte source preservation. Never execute or interpret saved Prism output as R output.
pc_prism_archive <- function(path,name=basename(path)) {
  if(!file.exists(path) || file.info(path)$size>10e6) stop("Original-file preservation supports Prism files up to 10 MB. Import tables without an attachment for larger files.")
  bytes<-readBin(path,"raw",n=10e6+1L)
  list(name=basename(name),sha256=digest::digest(bytes,algo="sha256",serialize=FALSE),bytes=length(bytes),content=jsonlite::base64_enc(bytes))
}
pc_prism_archives <- function(sources=NULL) {
  if(is.null(sources) || !length(sources)) return(list())
  if(!is.list(sources) || length(sources)>10 || sum(vapply(sources,function(s) if(is.numeric(s$bytes) && length(s$bytes)==1) s$bytes else Inf,numeric(1)))>15e6) stop("Preserved Prism originals exceed the 15 MB total attachment limit.")
  lapply(sources,function(s) {
    if(!is.list(s) || !is.character(s$name) || length(s$name)!=1 || is.na(s$name) || nchar(s$name)>255 || grepl("[/\\\\[:cntrl:]]",s$name) || !tolower(tools::file_ext(s$name)) %in% c("prism","pzfx")) stop("Invalid Prism attachment name.")
    if(!is.character(s$content) || length(s$content)!=1 || is.na(s$content) || nchar(s$content)>14e6 || !is.numeric(s$bytes) || length(s$bytes)!=1 || s$bytes<1 || s$bytes>10e6) stop("Invalid preserved Prism file.")
    bytes<-tryCatch(jsonlite::base64_dec(s$content),error=function(e) stop("Invalid Prism attachment encoding."))
    if(length(bytes)!=s$bytes || !identical(digest::digest(bytes,algo="sha256",serialize=FALSE),s$sha256)) stop("The preserved Prism file failed its SHA-256 integrity check.")
    list(name=s$name,sha256=s$sha256,bytes=length(bytes),content=s$content)
  })
}
