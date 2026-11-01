app<-source('app.R')$value
checks<-0L
check<-function(x,label){if(!isTRUE(x))stop('FAIL: ',label,call.=FALSE);checks<<-checks+1L;cat('PASS:',label,'\n')}
role<-function(p,r)which(vapply(p$layers,function(l)identical(l$pc_role,r),logical(1)))
tab<-pc_check_table(data.frame(Control=c(2,4,7,9,11),Treatment=c(6,8,11,13,15)))
n<-pc_normalize(tab);s<-pc_defaults();s$method<-'descriptive';s$show_p<-FALSE
for(graph in c('points','paired','bar','box','violin','mean','median','violinbox')){
 s$graph<-graph
 shown<-pc_plot(n,s);hidden<-pc_plot(n,modifyList(s,list(show_points=FALSE)))
 check(length(role(shown,'observations'))==1L && !length(role(hidden,'observations')),paste(graph,'honors the observation checkbox'))
 b<-ggplot2::ggplot_build(shown);raw<-role(shown,'observations')
 check(nrow(b$data[[raw]])==nrow(n$data) && all(b$data[[raw]]$alpha==.55),paste(graph,'draws lighter original observations'))
 if(graph %in% c('points','paired','mean','median')) {
  pts<-which(vapply(hidden$layers,function(l)inherits(l$geom,'GeomPoint'),logical(1)))
  check(length(pts)==1L && nrow(ggplot2::ggplot_build(hidden)$data[[pts]])==length(n$groups),paste(graph,'keeps summary markers when observations are hidden'))
 }
 if(graph=='paired')check(!any(vapply(hidden$layers,function(l)inherits(l$geom,'GeomLine'),logical(1))),'hidden paired observations also hide their individual connectors')
 if(graph %in% c('points','paired','mean','median','bar')) {
  bars<-which(vapply(shown$layers,function(l)inherits(l$geom,'GeomErrorbar'),logical(1)))
  check(length(bars)==1L && raw<bars,paste(graph,'draws summary intervals above observations'))
 }
}
s$graph<-'mean';s$series_styles<-'{"Control":{"color":"#123456","point_shape":17,"point_size":2}}'
p<-pc_plot(n,s);b<-ggplot2::ggplot_build(p);raw<-role(p,'observations');summary<-role(p,'summary')
check(all(b$data[[raw]]$colour[b$data[[raw]]$group==1]=='#123456') && all(b$data[[raw]]$alpha==.55),'custom series colors retain lighter observation opacity')
check(raw<summary && all(is.na(b$data[[summary]]$alpha)) && all(b$data[[summary]]$size>s$point_size),'summary markers remain full-strength, larger and above raw points with custom styles')
check(length(pc_palettes)==9L && length(pc_palette_choices())==9L,'nine presets are available through a shared palette inventory')
for(id in names(pc_palettes)){
 ss<-pc_defaults();ss$palette<-id;ss$method<-'descriptive';ss$show_p<-FALSE
 restored<-pc_decode_project(pc_project(tab,ss))$settings
 check(all(grepl('^#[0-9A-Fa-f]{6}$',pc_palettes[[id]])) && restored$palette==id,paste(id,'has valid colors and saves/reopens'))
 check(identical(unname(ggplot2::ggplot_build(pc_plot(n,ss))$plot$scales$get_scales('colour')$palette(2)),unname(pc_palettes[[id]][1:2])),paste(id,'renders using its selected series colors'))
}
x<-rep(1:6,each=3);xy<-pc_check_table(data.frame(X=x,A=2+2*x+rep(c(-.2,0,.2),6),B=3+x+rep(c(-.1,0,.1),6)))
nx<-pc_normalize(xy,'xy');xs<-pc_defaults();xs$layout<-'xy';xs$graph<-'scatter';xs$method<-'linear';xs$group1<-'A';xs$group2<-'B';xs$fit_scope<-'all';xs$xy_connections<-'none'
a<-pc_analyze(nx,'linear','A','B',xs);before<-a
for(graph in c('scatter','line','xymean','xyband','step','area')){
 xs$graph<-graph
 visible<-pc_plot(nx,xs,a);raw_hidden<-pc_plot(nx,modifyList(xs,list(show_points=FALSE)),a);fit_hidden<-pc_plot(nx,modifyList(xs,list(xy_show_fit=FALSE)),a)
 is_fit<-function(l)is.data.frame(l$data) && 'fit' %in% names(l$data)
 check(length(role(visible,'observations'))==1L && !length(role(raw_hidden,'observations')),paste(graph,'can hide raw observations without removing its fit'))
 check(any(vapply(raw_hidden$layers,is_fit,logical(1))) && !any(vapply(fit_hidden$layers,is_fit,logical(1))),paste(graph,'hides fitted curve and confidence band independently'))
}
check(identical(a,before),'display changes do not alter fit estimates or source diagnostics')
comparison<-pc_analyze(n,'welch','Control','Treatment',pc_defaults())
check(pc_comparison_p_available(comparison),'a real group comparison enables comparison-P formatting')
single<-pc_analyze(nx,'linear','A','B',modifyList(xs,list(fit_scope='selected')))
check(is.finite(single$p) && !pc_comparison_p_available(single),'a regression slope P value does not expose a between-group annotation control')
check(!pc_comparison_p_available(pc_analyze(n,'descriptive')) && !pc_comparison_p_available(NULL),'descriptive results and unavailable analyses hide comparison-P controls')
check(!pc_comparison_p_available(list(comparisons=data.frame(p=c(NA_real_,Inf)))),'missing and nonfinite comparison P values do not expose unusable controls')
check(pc_comparison_p_available(list(comparisons=data.frame(p=c(NA_real_,0,.05)))),'finite P values, including numerical zero, retain annotation controls')
check(!pc_comparison_p_available(list(comparisons=data.frame(p=c(-.1,1.1)))),'invalid P-value ranges do not enable annotation controls')
svg<-pc_graph_svg(pc_plot(n,modifyList(s,list(palette='ocean'))),s,list(sheet='D1',view='V1',token='preview',table=tab))
check(grepl('palette_choices',svg,fixed=TRUE) && grepl('High contrast',svg,fixed=TRUE) && grepl('ocean',svg,fixed=TRUE),'direct-format graph metadata carries every palette choice and actual colors')
shiny::testServer(app,{
 raw(tab);document_open(TRUE);session$setInputs(layout='column',method='descriptive',graph='points',show_points=FALSE);session$flushReact()
 check(!length(role(pc_plot(normalized(),settings(),analysis_state()$value),'observations')),'live server respects the unchecked observation control')
 session$setInputs(show_points=TRUE,palette='vivid');session$flushReact()
 check(length(role(pc_plot(normalized(),settings(),analysis_state()$value),'observations'))==1L && settings()$palette=='vivid','live server restores observations and selected palette')
 session$setInputs(method='welch',group1='Control',group2='Treatment',show_p=FALSE);session$flushReact()
 check(identical(output$has_graph_comparison_p,'true') && !settings()$show_p,'valid comparisons expose the control without changing the saved checkbox preference')
 session$setInputs(method='descriptive');session$flushReact()
 check(identical(output$has_graph_comparison_p,'false') && !settings()$show_p,'switching to a method without comparisons hides controls and preserves preferences')
 raw(xy);do.call(session$setInputs,modifyList(xs,list(graph='scatter',fit_scope='selected')));session$flushReact()
 check(identical(output$has_graph_comparison_p,'false'),'curve fitting keeps the comparison-P control hidden in the live server')
})
dir.create('artifacts/graph-display-041',recursive=TRUE,showWarnings=FALSE)
for(fmt in c('svg','pdf','png')){
 file<-paste0('artifacts/graph-display-041/observations-and-summary.',fmt)
 ggplot2::ggsave(file,p,device=switch(fmt,svg=svglite::svglite,pdf=pc_pdf_device,png=pc_png_device),width=76.2,height=76.2,units='mm',dpi=150)
 check(file.info(file)$size>1000,paste('lighter observations and strong summaries export as',fmt))
}
cat(checks,'graph-display checks passed.\n')
