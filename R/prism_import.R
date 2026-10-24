# Original observations plus explicit, validated conversion of supported Prism JSON.
source("R/prism_xml.R",local=TRUE)
source("R/prism_convert.R",local=TRUE)
pc_prism_text <- function(value,fallback="") {
  if(is.list(value) && is.character(value$string)) value<-value$string
  if(!is.character(value) || length(value)!=1 || is.na(value) || !nzchar(trimws(value))) return(fallback)
  trimws(gsub('[[:cntrl:]]',' ',value))
}
pc_prism_exclusions <- function(meta) {
  if(!is.list(meta)) return(FALSE)
  for(key in names(meta)) {
    value<-meta[[key]]
    if(key %in% c("title","name")) next
    if(grepl("exclud",tolower(key)) && length(value)>0 && !identical(value,FALSE) && !identical(value,0L) && !identical(value,0)) return(TRUE)
    if(key %in% c("attributes","commonAttributes","flags","status") && is.character(unlist(value)) && any(grepl("EXCLUD",toupper(unlist(value))))) return(TRUE)
    if(is.list(value) && (pc_prism_exclusions(value) || any(vapply(value,pc_prism_exclusions,logical(1))))) return(TRUE)
  }
  FALSE
}
pc_prism_table <- function(name,layout,x=NULL,ys,rows=NULL) {
  if(!is.character(name) || length(name)!=1 || is.na(name)) stop("The source table needs a valid title.",call.=FALSE)
  name<-trimws(gsub("[[:cntrl:]]"," ",name));if(!nzchar(name)) name<-"Imported table"
  labels <- vapply(seq_along(ys),function(i) if(is.null(ys[[i]]$name) || !nzchar(trimws(ys[[i]]$name))) paste("Series",i) else trimws(ys[[i]]$name),character(1))
  labels<-gsub("[[:cntrl:]]"," ",labels)
  labels <- make.unique(labels,sep=" ")
  counts <- vapply(ys,function(y) length(y$subcolumns),integer(1))
  if(!length(counts) || any(counts<1) || length(unique(counts))!=1) stop("Y series need the same positive replicate count.",call.=FALSE)
  nr <- max(c(length(x),length(rows),unlist(lapply(ys,function(y) lengths(y$subcolumns)))))
  if(nr<1 || nr>10000) stop("The source table is empty or exceeds 10,000 rows.",call.=FALSE)
  pad <- function(v) {
    # JSON null represents one missing source cell, and must not shift later rows.
    if (is.list(v)) v <- vapply(v,function(cell) {
      if (is.null(cell) || !length(cell)) return(NA_character_)
      if (length(cell)!=1L || is.list(cell)) stop("Invalid source cell.",call.=FALSE)
      as.character(cell)
    },character(1)) else v <- as.character(v)
    length(v)<-nr;v[is.na(v)|v==""]<-NA_character_;v
  }
  if(layout=="grouped") {
    parts <- lapply(seq_along(ys),function(i) {
      out<-data.frame(Condition=if(length(rows)) pad(rows) else paste("Row",seq_len(nr)),Group=labels[i],stringsAsFactors=FALSE)
      for(j in seq_len(counts[i])) out[[paste0("Replicate",j)]]<-pad(ys[[i]]$subcolumns[[j]])
      out
    }); tab<-do.call(rbind,parts)
  } else {
    tab<-data.frame(row.names=seq_len(nr))
    if(layout=="xy") tab[["X"]]<-pad(x)
    if(layout=="contingency") tab[["Category"]]<-if(length(rows)) pad(rows) else paste("Category",seq_len(nr))
    for(i in seq_along(ys)) for(j in seq_len(counts[i])) {
      if(layout!="xy" && counts[i]>1) stop("This source table needs a supported replicate representation.",call.=FALSE)
      label<-if(layout=="xy" && counts[i]>1) paste0(labels[i]," [rep ",j,"]") else labels[i]
      if(label %in% names(tab)) label<-paste0(label," Y")
      tab[[label]]<-pad(ys[[i]]$subcolumns[[j]])
    }
  }
  tab<-pc_check_table(tab);pc_normalize(tab,layout,allow_empty=TRUE)
  list(name=substr(trimws(name),1,100),layout=layout,table=tab)
}
pc_prism_import <- function(path,name=basename(path)) {
  if(!file.exists(path) || file.info(path)$size>30e6) stop("Choose a Prism file under 30 MB.",call.=FALSE)
  ext<-tolower(tools::file_ext(name)); tables<-list(); skipped<-character();conversion_report<-character()
  add <- function(label,expr) tryCatch({tables[[length(tables)+1L]]<<-force(expr)},error=function(e) skipped<<-c(skipped,paste0(label,": ",conditionMessage(e))))
  if(ext=="pzf") stop("Binary .pzf files are not supported. In Prism, Save As .pzfx or .prism, then import that file.",call.=FALSE)
  if(ext=="pzfx") {
    items<-pc_prism_xml(path)
    for(item in items) add(item$name,{
      if(!item$format %in% c("replicates","single","")) stop("Summary/error-value tables are not imported as raw observations.")
      layout<-switch(tolower(item$type),xy="xy",oneway="column",column="column",twoway="grouped",grouped="grouped",contingency="contingency",multivariable="multiple",NULL)
      if(is.null(layout)) stop(paste("Unsupported table type",item$type))
      if(layout=="xy" && !item$xFormat %in% c("numbers","")) stop("Numeric X values are required.")
      out<-pc_prism_table(item$name,layout,item$x,item$ys,item$rows)
      if(layout=='xy' && nzchar(trimws(item$xTitle))) names(out$table)<-make.unique(c(trimws(item$xTitle),names(out$table)[-1]))
      out$source_id<-item$id;out
    })
  } else if(ext=="prism") {
    index<-tryCatch(utils::unzip(path,list=TRUE),error=function(e) stop("This .prism file is not a readable ZIP archive.",call.=FALSE))
    if(nrow(index)>20000 || anyDuplicated(index$Name) || sum(index$Length)>100e6 || any(index$Length>30e6) ||
       any(grepl("(^/|(^|/)\\.\\.(/|$)|\\\\|^[A-Za-z]:)",index$Name))) stop("The archive contains unsafe paths or exceeds import limits.",call.=FALSE)
    # Stream bounded entries directly; no archive paths or symlinks are extracted.
    read_entry<-function(entry) {
      i<-match(entry,index$Name);if(is.na(i)) stop(paste("Missing archive entry",entry))
      con<-unz(path,entry,open="rb");on.exit(close(con))
      bytes<-readBin(con,"raw",n=index$Length[i]+1L)
      if(length(bytes)!=index$Length[i]) stop("Archive entry length mismatch.")
      rawToChar(bytes)
    }
    read_json<-function(entry) jsonlite::fromJSON(read_entry(entry),simplifyVector=FALSE)
    document<-read_json("document.json");ids<-unlist(document$sheets$data)
    if(length(ids)>100 || !length(ids) || anyDuplicated(ids)) stop("The archive needs 1–100 uniquely identified data tables.",call.=FALSE)
    valid_id<-function(id) {if(!is.character(id) || length(id)!=1L || !grepl("^[A-Za-z0-9_-]+$",id)) stop("Invalid table identifier.");id}
    read_sheet<-function(id,snapshot=FALSE) {
      sheet<-read_json(paste0("data/sheets/",valid_id(id),"/sheet.json")); t<-sheet$table
      summary<-identical(t$dataFormat,"y_se")
      if(!t$dataFormat %in% c("y_replicates","y_single","y_se")) stop(paste(sheet$title,"uses unsupported summary/error or text values."))
      layout<-switch(t$format,xy="xy",column="column",oneway="column",grouped="grouped",contingency="contingency",multivariable="multiple",NULL)
      if(snapshot && identical(t$format,'view')) layout<-switch(t[['@class']],XYDataTable='xy',ColumnDataTable='column',GroupedDataTable='grouped',DataTable='multiple',NULL)
      if(is.null(layout)) stop(paste("Unsupported source layout",t$format))
      if(layout=="xy" && (!is.null(t$xDataSetFormat) && t$xDataSetFormat!="y_single")) stop("X-error/summary tables are not yet supported.")
      exclusion_sheet<-sheet
      exclusion_sheet$table$columnFormats<-NULL # Formatting of unused/future cells is not a source exclusion.
      unresolved_exclusions<-pc_prism_exclusions(exclusion_sheet)
      nrep<-if(summary) 2L else if(is.null(t$replicatesCount)) 1L else t$replicatesCount
      if(!is.numeric(nrep) || nrep<1 || nrep>512 || nrep!=floor(nrep)) stop("Invalid replicate count.")
      datasets<-unlist(t$dataSets); if(!length(datasets) || length(datasets)>50) stop("The table exceeds 50 data series.")
      rawtext<-read_entry(paste0("data/tables/",valid_id(t$uid),"/data.csv"))
      rawtext<-sub("^\ufeff","",sub("\r?\n$","",rawtext))
      storage<-read_json(paste0("data/tables/",valid_id(t$uid),"/content.json"))
      if(storage$numberOfRows>10000 || storage$numberOfColumns>512) stop("The source table exceeds preview limits.")
      raw<-utils::read.table(text=rawtext,header=FALSE,sep=",",colClasses="character",quote='"',comment.char="",blank.lines.skip=FALSE,fill=FALSE,na.strings="",check.names=FALSE)
      lead<-as.integer(!is.null(t$xDataSet))+as.integer(!is.null(t$rowTitlesDataSet))
      if(ncol(raw)!=length(datasets)*nrep+lead || nrow(raw)!=storage$numberOfRows) stop("The CSV shape does not match its metadata.")
      for(labelid in unlist(t[c('xDataSet','rowTitlesDataSet')])) {
        entry<-paste0('data/sets/',valid_id(labelid),'.json')
        if(entry %in% index$Name && pc_prism_exclusions(read_json(entry))) unresolved_exclusions<-TRUE
      }
      ys<-lapply(seq_along(datasets),function(i) {
        meta<-read_json(paste0("data/sets/",valid_id(datasets[i]),".json"))
        if(pc_prism_exclusions(meta)) unresolved_exclusions<<-TRUE
        list(name=pc_prism_text(meta$title,paste("Series",i)),current_type=meta$currentType,subcolumns=lapply(seq_len(nrep),function(j) raw[[lead+(i-1)*nrep+j]]))
      })
      if(summary || snapshot) {
        tab<-data.frame(row.names=seq_len(nrow(raw)))
        if(!is.null(t$rowTitlesDataSet)) tab[['Row label']]<-raw[[1]]
        if(!is.null(t$xDataSet)) tab[['X']]<-raw[[lead]]
        for(i in seq_along(ys)) for(j in seq_len(nrep)) {
          label<-paste(ys[[i]]$name,if(summary) c('Mean','SEM')[j] else if(nrep>1) paste('rep',j) else '')
          label<-trimws(label);while(label %in% names(tab)) label<-paste0(label,' copy')
          tab[[label]]<-ys[[i]]$subcolumns[[j]]
        }
        out<-list(name=substr(paste(if(snapshot) 'Saved result ·' else 'Summary ·',sheet$title),1,100),layout='multiple',table=pc_check_table(tab),snapshot=TRUE)
        out$conversion<-paste(if(summary) 'Saved means and SEM values, not individual observations.' else 'Saved numeric result values.',
          if(snapshot) 'Archived result snapshot: edits do not rerun the upstream Prism calculation; cached results may be stale.' else 'Summary snapshot: no sample sizes or raw observations are inferred.',
          'The default is descriptive inspection only; this is not a reconstructed inferential analysis or original Prism graph.')
      } else {
        original_nrep<-nrep
        populated<-vapply(seq_len(nrep),function(j) any(vapply(ys,function(y) any(!is.na(y$subcolumns[[j]]) & nzchar(trimws(y$subcolumns[[j]]))),logical(1))),logical(1))
        nrep<-if(any(populated)) max(which(populated)) else 1L
        ys<-lapply(ys,function(y) {y$subcolumns<-y$subcolumns[seq_len(nrep)];y})
        x<-if(!is.null(t$xDataSet)) raw[[lead]] else NULL
        rows<-if(!is.null(t$rowTitlesDataSet)) raw[[1]] else NULL
        collapsed<-FALSE
        if((layout=='xy' && 1+length(ys)*nrep>50) || (layout=='grouped' && 2+nrep>50)) {
          if(nrow(raw)*nrep>10000) stop('Retaining these replicate observations would exceed 10,000 rows.')
          ys<-lapply(ys,function(y) {y$subcolumns<-list(as.vector(t(do.call(cbind,y$subcolumns))));y})
          if(layout=='xy') x<-rep(x,each=nrep)
          if(layout=='grouped') rows<-rep(if(length(rows)) rows else paste('Row',seq_len(nrow(raw))),each=nrep)
          collapsed<-TRUE
        }
        out<-pc_prism_table(sheet$title,layout,x,ys,rows)
        if(original_nrep>nrep || collapsed) out$conversion<-paste('Source observations retained.',
          if(original_nrep>nrep) paste(original_nrep-nrep,'entirely empty trailing replicate slots removed per series.'),
          if(collapsed) paste('Replicates retained as successive rows within each original row (replicate order 1–',nrep,'); no values averaged or discarded.'))
        if(collapsed && layout=='xy') out$replicates_in_rows<-TRUE
      }
      if(!is.null(t$xDataSet) && out$layout=='xy') {
        entry<-paste0('data/sets/',valid_id(t$xDataSet),'.json')
        if(entry %in% index$Name) {label<-pc_prism_text(read_json(entry)$title);if(nzchar(label)) names(out$table)<-make.unique(c(label,names(out$table)[-1]))}
      }
      if(layout=="multiple" && !isTRUE(out$snapshot)) out$measurement_names<-names(out$table)[vapply(ys,function(y) identical(y$current_type,"continuous"),logical(1))]
      if(unresolved_exclusions) {
        out$snapshot<-TRUE;out$unresolved_exclusions<-TRUE
        out$name<-substr(paste('Unreviewed ·',out$name),1,100)
        out$conversion<-paste(out$conversion,'Unreviewed source snapshot: Prism contains exclusion attributes whose cell-level meaning is not translated. All stored numeric values are retained, including possibly excluded values. Review exclusions in Prism and edit this table before selecting an inferential analysis. Automatic analysis conversion is disabled for this source.')
      }
      out$source_id<-id;out$dataset_ids<-datasets;out$label_ids<-unlist(t[c("xDataSet","rowTitlesDataSet")]);out
    }
    for(id in ids) add(id,read_sheet(id))
    analysis_ids<-unlist(document$sheets$analyses)
    if(length(analysis_ids)>200 || anyDuplicated(analysis_ids)) stop('Too many or duplicate analysis identifiers.')
    # Preserve archived numeric output tables independently of whether an analysis
    # can be reconstructed. Stable sheet IDs avoid title-based associations.
    known_ids<-vapply(tables,function(t) t$source_id,character(1))
    for(aid in analysis_ids) {
      a<-read_json(paste0('analyses/',valid_id(aid),'/sheet.json'))
      for(view in a$resultSheets) {
        entry<-paste0('analyses/',aid,'/result_sheets/',valid_id(view$uid),'.json')
        if(!entry %in% index$Name) next
        result<-read_json(entry);id<-result$dataSheet
        if(is.null(id) || id %in% known_ids) next
        entry<-paste0('data/sheets/',valid_id(id),'/sheet.json')
        if(!entry %in% index$Name) next
        sheet<-read_json(entry)
        if(!sheet$table$dataFormat %in% c('y_single','y_replicates','y_se')) next
        csv<-paste0('data/tables/',valid_id(sheet$table$uid),'/data.csv')
        if(!csv %in% index$Name) next
        tryCatch({
          saved<-read_sheet(id,TRUE)
          tables[[length(tables)+1L]]<-saved;known_ids<-c(known_ids,id)
          conversion_report<-c(conversion_report,paste('SAVED RESULT TABLE:',saved$name,'—',saved$conversion))
        },error=function(e) conversion_report<<-c(conversion_report,paste('RESULT TABLE NOT IMPORTED:',sheet$title,'—',conditionMessage(e))))
      }
    }
    sources<-tables
    # Each conversion names the source sheet explicitly; no title-based association.
    conversion_ids<-function(kind) {
      x<-unlist(document$sheets[[kind]])
      if(length(x)>200 || anyDuplicated(x)) stop('Too many or duplicate analysis/graph identifiers.')
      vapply(x,valid_id,character(1))
    }
    for(aid in conversion_ids('analyses')) {
      label<-aid
      tryCatch({
        a<-read_json(paste0('analyses/',aid,'/sheet.json'));label<-a$title
        if(!length(a$inputSheets)) {
          conversion_report<-c(conversion_report,paste('UNLINKED ANALYSIS:',label,'— Prism stores no input links. Any available numeric result was preserved as a labelled snapshot; the calculation cannot be rerun from an identified source.'))
          next
        }
        if(length(a$inputSheets)>1) {
          input_ids<-vapply(a$inputSheets,function(x) x$uid,character(1))
          available<-vapply(sources,function(t) t$source_id,character(1))
          conversion_report<-c(conversion_report,paste('MULTI-INPUT SHEETS:',label,'—',sum(input_ids %in% available),'of',length(input_ids),'input sheets retained as separate tables. Saved numeric outputs are separate snapshots; this cross-sheet calculation is not silently pooled or substituted.'))
          next
        }
        srcid<-a$inputSheets[[1]]$uid;matched<-which(vapply(sources,function(t) identical(t$source_id,srcid),logical(1)))
        if(length(matched)!=1) stop('The source table is unavailable; inspect the skipped-table report.')
        if(identical(a$analysisClass,'REMOVE_BASELINE')) {
          conversion_report<-c(conversion_report,paste('BASELINE WORKFLOW:',label,'— source observations are retained. Any saved numeric result is a separate snapshot; edits do not recompute the baseline operation.'))
          next
        }
        entry<-paste0('analyses/',aid,'/parameters.json')
        if(!entry %in% index$Name) stop('Binary analysis parameters are unavailable; choose an analysis manually in the preview.')
        converted<-pc_prism_analysis(sources[[matched]],a,read_json(entry))
        tables[[length(tables)+1L]]<-converted
        conversion_report<-c(conversion_report,paste('CONVERTED ANALYSIS:',label,'—',converted$conversion))
      },error=function(e) conversion_report<<-c(conversion_report,paste('NOT CONVERTED:',label,'—',conditionMessage(e))))
    }
    for(gid in conversion_ids('graphs')) {
      label<-gid
      tryCatch({
        g<-read_json(paste0('graphs/',gid,'/sheet.json'));label<-g$title
        if(is.null(g$graph) && is.character(unlist(g$inputDataSets))) {
          graphids<-unlist(g$inputDataSets)
          rawmatch<-which(vapply(sources,function(t) !isTRUE(t$snapshot) && t$layout!='multiple' && length(graphids)>0 && all(t$dataset_ids %in% graphids) && all(graphids %in% c(t$dataset_ids,t$label_ids)),logical(1)))
          if(length(rawmatch)==1) {
            i<-rawmatch[1];t<-tables[[i]];s<-pc_prism_settings(t);s$title<-substr(g$title,1,300)
            if(is.null(t$views)) {base<-pc_prism_settings(t);t$settings<-base;t$views<-list(V1=pc_view(base,'Source observations'))}
            if(length(t$views)>=12) stop('The source already has twelve linked views; recreate additional graphs manually.')
            vid<-paste0('V',length(t$views)+1L);t$views[[vid]]<-pc_view(s,substr(paste('Recreated ·',g$title),1,100));tables[[i]]<-t
            conversion_report<-c(conversion_report,paste('RECREATED SOURCE GRAPH:',label,'— editable',s$graph,'view linked to its source observations. Binary formatting and saved analysis are not reproduced; choose the analysis and refine graph formatting in RDataCraft.'))
            next
          }
        }
        srcid<-g$graph$dataSheet;matched<-which(vapply(sources,function(t) identical(t$source_id,srcid),logical(1)))
        if(length(matched)!=1) stop('Graph uses binary formatting, derived data or an unavailable source. Choose an editable replacement graph in the preview.')
        converted<-pc_prism_graph(sources[[matched]],g)
        tables[[length(tables)+1L]]<-converted
        conversion_report<-c(conversion_report,paste('CONVERTED GRAPH:',label,'—',converted$conversion))
      },error=function(e) conversion_report<<-c(conversion_report,paste('NOT CONVERTED GRAPH:',label,'—',conditionMessage(e))))
    }
  } else stop("Choose a .pzfx or .prism file.",call.=FALSE)
  if(!length(tables)) stop(paste(c("No supported source tables were found.",skipped),collapse="\n"),call.=FALSE)
  titles<-make.unique(vapply(tables,function(t) substr(t$name,1,94),character(1)),sep=' · ')
  for(i in seq_along(tables)) tables[[i]]$name<-titles[i]
  list(tables=tables,skipped=skipped,source=name,report=conversion_report,
    note="Each supported input sheet is imported as a separate editable data table. Supported analysis conversions recompute from observations. Summary and archived numeric result tables are clearly labelled snapshots, not inferred raw observations or live upstream calculations. Multi-input sources remain separate; review conversion and skipped-table reports. PZFX exposes source tables only.")
}
