# Cross-platform XML reader. No DTD/entity expansion, XInclude or stylesheet execution.
pc_prism_xml <- function(path) {
  if(!requireNamespace('xml2',quietly=TRUE)) stop('PZFX import requires xml2. Run the dependency installer.')
  size<-file.info(path)$size;if(is.na(size) || size>30e6) stop('Choose a PZFX file under 30 MB.')
  bytes<-readBin(path,'raw',n=30e6+1L)
  # Reject entity declarations in UTF-8 and UTF-16 before libxml sees the document.
  scan<-rawToChar(bytes[bytes!=as.raw(0)])
  if(grepl('<!DOCTYPE|<!ENTITY',scan,ignore.case=TRUE,useBytes=TRUE)) stop('PZFX files with DTDs or entity declarations are not supported.')
  doc<-xml2::read_xml(bytes,options='NONET')
  roots<-xml2::xml_find_all(doc,"//*[local-name()='GraphPadPrismFile']")
  if(length(roots)!=1) stop('Invalid PZFX XML: expected one GraphPadPrismFile element.')
  nodes<-xml2::xml_find_all(roots[[1]],"./*[local-name()='Table']")
  if(length(nodes)>100) stop('Import supports at most 100 source tables.')
  children<-function(node,tag) xml2::xml_find_all(node,paste0("./*[local-name()='",tag,"']"))
  text<-function(node,tag) {v<-children(node,tag);if(length(v)) xml2::xml_text(v[[1]]) else ''}
  attr<-function(node,name,default='') {v<-xml2::xml_attr(node,name);if(is.na(v)) default else v}
  subcols<-function(node) lapply(children(node,'Subcolumn'),function(sub) vapply(children(sub,'d'),function(cell) {
    if(tolower(attr(cell,'Excluded')) %in% c('1','true','yes')) NA_character_ else trimws(xml2::xml_text(cell))
  },character(1)))
  lapply(nodes,function(node) {
    x<-children(node,'XColumn');rows<-children(node,'RowTitlesColumn')
    list(id=attr(node,'ID'),name=text(node,'Title'),type=attr(node,'TableType'),format=attr(node,'YFormat','replicates'),xFormat=attr(node,'XFormat','none'),
      xTitle=if(length(x)) text(x[[1]],'Title') else 'X',x=if(length(x)) subcols(x[[1]])[[1]] else NULL,
      rows=if(length(rows)) subcols(rows[[1]])[[1]] else NULL,
      ys=lapply(children(node,'YColumn'),function(y) list(name=text(y,'Title'),subcolumns=subcols(y))))
  })
}
