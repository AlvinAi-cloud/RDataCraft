# Additional scientific graphs use the same observations and analysis as other views.
pc_optional_number <- function(value, label, positive = FALSE) {
  if (is.null(value) || identical(value,"")) return(NULL)
  if (!is.character(value) || length(value)!=1L || is.na(value)) stop(paste("Enter a finite",label,"or leave it blank."),call.=FALSE)
  v <- suppressWarnings(as.numeric(value))
  if (!is.finite(v) || (positive && v<=0)) stop(paste("Enter a",if(positive) "positive" else "finite",label,"or leave it blank."),call.=FALSE)
  v
}
pc_validate_graph_details <- function(s) {
  for(axis in c("x","y")) {
    step <- pc_optional_number(s[[paste0(axis,"_tick_step")]],paste(axis,"tick interval"),TRUE)
    ref <- pc_optional_number(s[[paste0("ref_",axis)]],paste(axis,"reference value"))
    if (!is.null(ref) && isTRUE(s[[paste0("log_",axis)]]) && ref<=0) stop("Reference values on logarithmic axes must be positive.",call.=FALSE)
    if (!is.null(step) && isTRUE(s[[paste0("log_",axis)]])) stop("Use automatic ticks on logarithmic axes; clear the tick interval.",call.=FALSE)
  }
  invisible(TRUE)
}
pc_format_details <- function(p,n,s) {
  pc_validate_graph_details(s)
  nx <- n$layout %in% c("xy","survival","multiple") || s$graph %in% c("histogram","ecdf","qq","density")
  ny <- !s$graph %in% c("heatmap","groupheat")
  for(axis in c("x","y")) {
    numeric_axis <- if(axis=="x") nx else ny
    step <- pc_optional_number(s[[paste0(axis,"_tick_step")]],paste(axis,"tick interval"),TRUE)
    ref <- pc_optional_number(s[[paste0("ref_",axis)]],paste(axis,"reference value"))
    if ((!is.null(step) || !is.null(ref)) && !numeric_axis) stop("Tick intervals and reference lines require a numeric axis.",call.=FALSE)
    if (!is.null(step)) {
      # Limit rendered ticks, including after a manual zoom, without altering observations.
      breaks <- local({interval <- step; function(limits) {
        first <- ceiling(limits[1]/interval); last <- floor(limits[2]/interval)
        if (!all(is.finite(c(first,last))) || last-first>200) stop("Tick interval produces over 200 ticks. Increase the interval.",call.=FALSE)
        if (last<first) numeric() else seq(first,last)*interval
      }})
      scale <- p$scales$get_scales(axis)
      if (!is.null(scale)) scale$breaks <- breaks else p <- p + (if(axis=="x") ggplot2::scale_x_continuous(breaks=breaks) else ggplot2::scale_y_continuous(breaks=breaks))
    }
    if (!is.null(ref)) p <- p + (if(axis=="x") ggplot2::geom_vline(xintercept=ref,linetype="dashed",color="#73828E",linewidth=.45) else ggplot2::geom_hline(yintercept=ref,linetype="dashed",color="#73828E",linewidth=.45))
  }
  if (!is.null(s$x_tick_angle) && s$x_tick_angle!=0) p <- p + ggplot2::theme(axis.text.x=ggplot2::element_text(angle=s$x_tick_angle,hjust=1,vjust=1))
  p
}
pc_plot_additional <- function(n,s,analysis=NULL) {
  d <- n$data; colors <- pc_series_colors(n,s); graph <- s$graph
  if (s$log_y && any(d$value<=0)) stop("A log Y axis requires positive observations.",call.=FALSE)
  if (s$log_x && n$layout=="xy" && any(d$x<=0)) stop("A log X axis requires positive X values.",call.=FALSE)
  if (n$layout=="column") {
    p <- ggplot2::ggplot(d,ggplot2::aes(x=group,y=value,color=group,fill=group))
    if (graph %in% c("mean","median")) {
      z <- do.call(rbind,lapply(n$groups,function(g) {
        v <- d$value[d$group==g]; k <- length(v); m <- if(graph=="median") median(v) else mean(v)
        margin <- switch(s$error,sem=sd(v)/sqrt(k),sd=sd(v),ci=if(k>1) qt(.975,k-1)*sd(v)/sqrt(k) else NA_real_,none=NA_real_)
        q <- if(graph=="median") quantile(v,c(.25,.75),names=FALSE) else m+c(-margin,margin)
        data.frame(group=g,value=m,low=q[1],high=q[2])
      })); z$group <- factor(z$group,levels=n$groups)
      if(s$log_y && any(z$low<=0,na.rm=TRUE)) stop("An interval crosses zero; use a linear Y axis.",call.=FALSE)
      p <- ggplot2::ggplot(z,ggplot2::aes(x=group,y=value,color=group,fill=group)) + ggplot2::geom_errorbar(ggplot2::aes(ymin=low,ymax=high),width=.16,na.rm=TRUE) + ggplot2::geom_point(size=s$point_size+1)
      if (s$show_points) p <- p + ggplot2::geom_point(data=d,position=ggplot2::position_jitter(width=.1,height=0,seed=42),size=s$point_size,alpha=.55)
      p <- p + ggplot2::labs(caption=if(graph=="median") "Median and interquartile range (25th–75th percentiles)" else NULL)
    } else if(graph=="violinbox") {
      if(any(table(d$group)<2)) stop("Violin plots need at least two observations per group.",call.=FALSE)
      p <- p + ggplot2::geom_violin(trim=TRUE,alpha=.18,width=.8) + ggplot2::geom_boxplot(width=.16,outlier.shape=NA,alpha=.5)
      if(s$show_points) p <- p + ggplot2::geom_point(position=ggplot2::position_jitter(width=.08,height=0,seed=42),size=s$point_size,alpha=.7)
    } else if(graph=="density") {
      if(any(table(d$group)<2)) stop("Density curves need at least two observations per group.",call.=FALSE)
      if(s$log_y || s$log_x) stop("Use linear axes for density distributions.",call.=FALSE)
      p <- ggplot2::ggplot(d,ggplot2::aes(x=value,color=group,fill=group)) + ggplot2::geom_density(alpha=.18,linewidth=.8)
      p <- p + ggplot2::labs(x=s$y_label,y="Probability density")
    }
    if(graph!="density") p <- p + ggplot2::scale_x_discrete(limits=n$groups,drop=FALSE)
  } else if(n$layout=="xy") {
    z <- stats::aggregate(value~x+group,data=d,FUN=mean);z <- z[order(z$group,z$x),]
    p <- ggplot2::ggplot(z,ggplot2::aes(x=x,y=value,color=group,fill=group,group=group))
    if(graph=="area") {
      if(s$log_y) stop("Area plots use a zero baseline; use a linear Y axis.",call.=FALSE)
      p <- p + ggplot2::geom_area(position="identity",alpha=.2) + ggplot2::geom_line(linewidth=.7)
    } else p <- p + ggplot2::geom_step(direction="hv",linewidth=.75)
    if(s$show_points) p <- p + ggplot2::geom_point(size=s$point_size)
    p <- p + ggplot2::labs(caption="Mean response at each X; source replicates remain unchanged")
  } else {
    if(graph=="groupheat") {
      z <- pc_grouped_summary(n)
      p <- ggplot2::ggplot(z,ggplot2::aes(x=condition,y=group,fill=mean)) + ggplot2::geom_tile(color="white",linewidth=.8) + ggplot2::geom_text(ggplot2::aes(label=format(signif(mean,3),trim=TRUE)),size=s$font_size/ggplot2::.pt) + ggplot2::scale_fill_gradient(low="#eff4f7",high="#40858b",name="Mean")
      if(s$log_y) stop("Heatmap axes contain categories; use a linear axis.",call.=FALSE)
    } else {
      p <- ggplot2::ggplot(d,ggplot2::aes(x=condition,y=value,color=group,fill=group))
      if(graph=="groupviolin") {
        if(any(table(d$condition,d$group)<2)) stop("Grouped violins need at least two observations per factor combination.",call.=FALSE)
        p <- p + ggplot2::geom_violin(position=ggplot2::position_dodge(.8),alpha=.2,trim=TRUE)
      } else p <- p + ggplot2::geom_boxplot(position=ggplot2::position_dodge(.8),width=.65,outlier.shape=if(s$show_points) NA else 19,alpha=.22)
      if(s$show_points) p <- p + ggplot2::geom_point(position=ggplot2::position_jitterdodge(jitter.width=.1,dodge.width=.8,seed=42),size=s$point_size,alpha=.8)
    }
  }
  if(n$layout=="column" && graph!="density" && isTRUE(s$show_p) && !s$log_y && !is.null(analysis) && nrow(analysis$comparisons)) {
    ann <- analysis$comparisons;span <- diff(range(d$value));if(!span) span <- max(abs(d$value),1)
    ceiling <- if(graph %in% c("mean","median")) max(d$value,z$high,na.rm=TRUE) else max(d$value)
    ann$y.position <- ceiling+span*.14*seq_len(nrow(ann))
    prefix <- if(analysis$method %in% c("anova","multiple","kruskal")) "adj. p" else "p"
    ann$label <- pc_p_label(ann$p,prefix,identical(s$annotation,'stars'))
    p <- p+pc_comparison_layers(ann,n$groups,span,text_size=s$font_size/ggplot2::.pt)
  }
  p <- p + pc_theme(s$font_size) + ggplot2::labs(title=s$title,color=NULL) + ggplot2::theme(legend.position=if(n$layout=="column" && graph!="density") "none" else "top",plot.title=ggplot2::element_text(face="bold"),plot.margin=ggplot2::margin(18,20,16,18))
  if(graph!="density") p <- p + ggplot2::labs(x=s$x_label,y=if(graph=="groupheat") NULL else s$y_label)
  if(graph!="groupheat") p <- p + ggplot2::scale_color_manual(values=colors,drop=FALSE) + ggplot2::scale_fill_manual(values=colors,drop=FALSE) + ggplot2::labs(fill=NULL)
  if(s$log_y) p <- p + ggplot2::scale_y_log10()
  if(s$log_x && n$layout=="xy") p <- p + ggplot2::scale_x_log10()
  p
}
