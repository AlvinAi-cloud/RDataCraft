# Layout geometry is stored in millimetres from the upper left of the exported page.
pc_layout_design_defaults <- function() list(arrangement="grid",gap=4,margin=4,label_size=14,scale_text=TRUE,positions="{}",labels="{}")
pc_layout_map <- function(text, kind="positions") {
  if(!is.character(text) || length(text)!=1L || is.na(text) || nchar(text)>15000 || !grepl("^\\s*\\{",text)) stop("Invalid panel settings.",call.=FALSE)
  value <- tryCatch(jsonlite::fromJSON(text,simplifyVector=FALSE),error=function(e) NULL)
  if(!is.list(value) || length(value)>8 || (length(value) && (is.null(names(value)) || anyDuplicated(names(value)) || any(!grepl("^D[0-9]+:V[0-9]+$",names(value)))))) stop("Invalid panel settings.",call.=FALSE)
  for(v in value) {
    if(kind=="labels") {if(!is.character(v) || length(v)!=1L || is.na(v) || nchar(v)>20 || grepl("[[:cntrl:]]",v)) stop("Panel labels support up to 20 characters.",call.=FALSE)}
    else {
      if(!is.list(v) || !setequal(names(v),c("x","y","w","h")) || anyDuplicated(names(v)) || any(!vapply(v,function(z) is.numeric(z) && length(z)==1L && is.finite(z),logical(1))) || v$x<0 || v$y<0 || v$w<15 || v$h<15 || v$x+v$w>400.001 || v$y+v$h>400.001) stop("Each panel needs finite page coordinates and a width and height of at least 15 mm.",call.=FALSE)
    }
  }
  value
}
pc_layout_rects <- function(s) {
  keys <- s$selected; count <- length(keys); if(!count) return(list())
  cols <- min(s$columns,count);rows <- ceiling(count/cols);m <- s$margin;g <- s$gap
  top <- m + if(nzchar(s$title)) 9 else 0
  w <- (s$width-2*m-(cols-1)*g)/cols;h <- (s$height-top-m-(rows-1)*g)/rows
  rects <- setNames(lapply(seq_len(count),function(i) list(x=m+((i-1)%%cols)*(w+g),y=top+((i-1)%/%cols)*(h+g),w=w,h=h)),keys)
  if(s$arrangement=="hero" && count>1) {
    lowercols <- min(3,count-1);lowerrows <- ceiling((count-1)/lowercols);available <- s$height-top-m
    hero_h <- (available-g)*.5;lw <- (s$width-2*m-(lowercols-1)*g)/lowercols;lh <- (available-hero_h-g-(lowerrows-1)*g)/lowerrows
    rects[[1]] <- list(x=m,y=top,w=s$width-2*m,h=hero_h)
    for(i in 2:count) rects[[i]] <- list(x=m+((i-2)%%lowercols)*(lw+g),y=top+hero_h+g+((i-2)%/%lowercols)*(lh+g),w=lw,h=lh)
  }
  if(s$arrangement=="manual") {overrides <- pc_layout_map(s$positions);for(k in intersect(keys,names(overrides))) rects[[k]] <- overrides[[k]]}
  for(r in rects) if(r$w<15 || r$h<15 || r$x<0 || r$y<0 || r$x+r$w>s$width+.001 || r$y+r$h>s$height+.001) stop("Panels do not fit this page. Increase the page size, reduce margins/gaps, or reset the arrangement.",call.=FALSE)
  rects
}
pc_compose_layout <- function(plots,s) {
  s <- pc_layout_settings(s); rects <- pc_layout_rects(s);labels <- pc_layout_map(s$labels,"labels")
  if(!length(plots) || length(plots)!=length(rects)) stop("Select linked graph views for the layout.",call.=FALSE)
  children <- list()
  if(nzchar(s$title)) children <- list(grid::textGrob(s$title,x=grid::unit(s$margin,"mm"),y=grid::unit(1,"npc")-grid::unit(s$margin,"mm"),just=c("left","top"),gp=grid::gpar(fontsize=14,fontface="bold")))
  for(i in seq_along(plots)) {
    r <- rects[[i]]; p <- plots[[i]] + ggplot2::theme(panel.widths=NULL,panel.heights=NULL)
    if(s$scale_text) {
      font <- p$theme$axis.text$size;if(is.null(font) || !is.numeric(font) || length(font)!=1L) font <- 13
      font <- max(7,font / sqrt(s$columns))
      p <- p+ggplot2::theme(axis.text=ggplot2::element_text(size=font),axis.title=ggplot2::element_text(size=font,face="bold"),legend.text=ggplot2::element_text(size=font),plot.title=ggplot2::element_text(size=font+1,face="bold"),plot.subtitle=ggplot2::element_text(size=font),plot.caption=ggplot2::element_text(size=font*.85))
    }
    # Wrap long headings/captions for the available physical panel width.
    for(key in c("title","subtitle","caption")) {
      text <- p$labels[[key]]
      if(is.character(text) && length(text)==1L && nzchar(text)) {
        size <- p$theme[[paste0("plot.",key)]]$size
        if(is.null(size) || !is.numeric(size) || length(size)!=1L) size <- if(key=="title") 13 else 10
        count <- max(12,floor((r$w-9)/(size*.19)))
        wrapped <- paste(vapply(strsplit(text,"\n",fixed=TRUE)[[1]],function(line) paste(strwrap(line,width=count),collapse="\n"),character(1)),collapse="\n")
        p <- p+do.call(ggplot2::labs,setNames(list(wrapped),key))
      }
    }
    label <- labels[[names(rects)[i]]];if(is.null(label)) label <- LETTERS[i]
    p <- p+ggplot2::labs(tag=label)+ggplot2::theme(plot.tag=ggplot2::element_text(size=s$label_size,face="bold"),plot.margin=ggplot2::margin(8,8,8,8))
    grob <- ggplot2::ggplotGrob(p);grob$name <- paste0("layout-panel-",i)
    grob$vp <- grid::viewport(x=grid::unit(r$x,"mm"),y=grid::unit(1,"npc")-grid::unit(r$y,"mm"),width=grid::unit(r$w,"mm"),height=grid::unit(r$h,"mm"),just=c("left","top"),clip="on")
    children[[length(children)+1]] <- grob
  }
  grid::gTree(children=do.call(grid::gList,children))
}
pc_layout_svg <- function(plots,s,context=NULL) {
  svg <- pc_graph_svg(pc_compose_layout(plots,s),s)
  if(!is.null(context)) {
    context$settings <- s;context$rects <- pc_layout_rects(s)
    metadata <- paste0("<metadata id='rdatacraft-layout'>",htmltools::htmlEscape(jsonlite::toJSON(context,auto_unbox=TRUE,null="null",digits=10)),"</metadata>")
    svg <- sub("</svg>",paste0(metadata,"</svg>"),svg,fixed=TRUE)
  }
  svg
}
pc_layout_apply_edit <- function(s,e) {
  if(!is.list(e) || !is.character(e$action) || length(e$action)!=1L) stop("Choose a layout action.",call.=FALSE)
  rects <- pc_layout_rects(s)
  if(e$action=="template") {
    if(!is.character(e$value) || length(e$value)!=1L || !e$value %in% c("grid","hero")) stop("Choose a layout template.",call.=FALSE)
    s$arrangement <- e$value;s$positions <- "{}"
  } else {
    if(!is.character(e$key) || length(e$key)!=1L || !e$key %in% s$selected) stop("Select a current panel.",call.=FALSE)
    if(e$action=="move") {
      rects[[e$key]] <- e$rect;s$arrangement <- "manual";s$positions <- jsonlite::toJSON(rects,auto_unbox=TRUE,digits=10)
    } else if(e$action=="label") {
      labels <- pc_layout_map(s$labels,"labels");labels[[e$key]] <- e$value;s$labels <- jsonlite::toJSON(labels,auto_unbox=TRUE)
    } else if(e$action %in% c("earlier","later")) {
      i <- match(e$key,s$selected);j <- i+if(e$action=="earlier") -1L else 1L
      if(j<1 || j>length(s$selected)) return(s)
      s$selected[c(i,j)] <- s$selected[c(j,i)]
    } else stop("Choose a supported layout action.",call.=FALSE)
  }
  s <- pc_layout_settings(s);pc_layout_rects(s);s
}
