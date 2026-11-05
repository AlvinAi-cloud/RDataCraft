source('app.R');checks<-0L
check<-function(x,label){if(!isTRUE(x))stop(label);checks<<-checks+1L;cat('PASS:',label,'\n')}
fails<-function(expr)inherits(tryCatch(force(expr),error=identity),'error')
x<-seq(.2,10,length.out=35);tab<-data.frame(X=as.character(x),A=as.character(1+2*x+sin(x)*.02),B=as.character(5+2*x+cos(x)*.02));n<-pc_normalize(tab,'xy');s<-pc_defaults();s$layout<-'xy';s$method<-'linear';s$graph<-'scatter';s$group1<-'A';s$fit_scope<-'all'
s$fit_constraints<-'{"linear":{"intercept":{"fixed":0},"groups":{"B":{"intercept":{"fixed":5}}}}}'
r<-pc_analyze(n,'linear',options=s)
check(all(r$parameters$estimate[r$parameters$parameter=='intercept']==c(0,5)),'different group constants retain all fitted curves')
check(length(unique(r$curve$group))==2,'both group curves remain on the same graph')
s$fit_constraints<-'{"linear":{"intercept":{"fixed":0},"groups":{"A":{"intercept":{}},"B":{"intercept":{"lower":4,"upper":6}}}}}'
r<-pc_analyze(n,'linear',options=s);check(abs(r$parameters$estimate[1]-1)<.02,'empty group override clears inherited fixed value')
check(r$parameters$estimate[3]>=4&&r$parameters$estimate[3]<=6,'group-specific bounds apply')
s$fit_mode<-'global';s$fit_constraints<-'{"linear":{"shared":["slope"]}}';r<-pc_analyze(n,'linear',options=s)
ref<-lm(value~group+x,data=n$data)
check(max(abs(r$parameters$estimate[r$parameters$parameter=='slope']-coef(ref)['x']))<1e-6,'joint shared slope agrees with an independent linear-model reference')
check(diff(r$parameters$estimate[r$parameters$parameter=='slope'])==0,'shared coefficients are one identical joint estimate')
check(r$metrics$value[r$metrics$measure=='Residual degrees of freedom']=='67','global degrees of freedom count shared coefficients once')
check(all(is.finite(r$parameters$se)),'joint covariance supplies local and shared standard errors')
check(all(r$fit_status$status=='Fitted')&&nrow(r$curve)==480,'global fit produces both editable plotted curves')
s$fit_constraints<-'{"linear":{"shared":["slope"],"groups":{"A":{"slope":{"fixed":2}},"B":{"slope":{"fixed":3}}}}}'
check(fails(pc_analyze(n,'linear',options=s)),'conflicting shared fixed values reject')
s$fit_constraints<-'{"linear":{"shared":["slope"],"groups":{"A":{"slope":{"lower":1,"upper":2}},"B":{"slope":{"lower":3,"upper":4}}}}}'
check(fails(pc_analyze(n,'linear',options=s)),'disjoint shared bounds reject')
s$fit_constraints<-'{"linear":{"shared":["slope"],"groups":{"A":{"slope":{"lower":1,"upper":3}},"B":{"slope":{"lower":1.5,"upper":2.5}}}}}'
check(all(pc_analyze(n,'linear',options=s)$parameters$estimate[c(2,4)]>1.5),'compatible shared bounds are intersected')
p<-pc_decode_project(pc_project(tab,s));check(p$settings$fit_mode=='global'&&p$settings$fit_constraints==s$fit_constraints,'global and group settings round-trip through a study')
x<-10^seq(-2,2,length.out=40);tab<-data.frame(X=as.character(x),A=as.character(100*x/(5+x)+sin(seq_along(x))*.03),B=as.character(10+80*x/(5+x)+cos(seq_along(x))*.03));n<-pc_normalize(tab,'xy');s$method<-'threepl';s$fit_mode<-'independent';s$fit_constraints<-'{}';r<-pc_analyze(n,'threepl',options=s)
check(max(abs(r$parameters$estimate[r$parameters$parameter=='hill']-log(10)))<1e-12,'3PL fixes conventional Hill=1, not natural-logistic hill=1')
check(max(abs(r$parameters$estimate[r$parameters$parameter=='EC50']-5))<.03,'three-parameter dose response recovers EC50')
s$fit_mode<-'global';s$fit_constraints<-'{"threepl":{"shared":["EC50"]}}';r<-pc_analyze(n,'threepl',options=s)
check(max(abs(r$parameters$estimate[r$parameters$parameter=='EC50']-5))<.03,'nonlinear global 3PL recovers shared EC50 with different plateaus')
check(r$metrics$value[r$metrics$measure=='Joint free parameters']=='5','global 3PL has five free coefficients for two curves sharing EC50')
check(!grepl('assistant_connection_summary',as.character(pc_assistant_ui()),fixed=TRUE),'repeated connection status is absent from Operations and results')
cat(checks,'checks passed\n')
s$method<-'linear';s$fit_mode<-'global';s$fit_weight<-'inv_y2';s$fit_constraints<-'{"linear":{"shared":["slope"]}}'
x<-seq(.2,10,length.out=35);tab<-data.frame(X=as.character(x),A=as.character(1+2*x+sin(x)*.02),B=as.character(5+2*x+cos(x)*.02));n<-pc_normalize(tab,'xy');r<-pc_analyze(n,'linear',options=s);ref<-lm(value~group+x,data=n$data,weights=1/n$data$value^2)
check(max(abs(r$parameters$estimate[r$parameters$parameter=='slope']-coef(ref)['x']))<1e-5,'global inverse-Y weighting agrees with a separate weighted linear-model reference')
s$method<-'fourpl';s$fit_weight<-'none';s$fit_constraints<-'{"fourpl":{"shared":["top","hill"],"bottom":{"fixed":0},"groups":{"B":{"bottom":{"fixed":10},"EC50":{"lower":5,"upper":12}}}}}'
x<-10^seq(-2,2,length.out=40);tab<-data.frame(X=as.character(x),A=as.character(100*plogis(2*(log10(x)-log10(5)))+sin(seq_along(x))*.02),B=as.character(10+90*plogis(2*(log10(x)-log10(8)))+cos(seq_along(x))*.02));n<-pc_normalize(tab,'xy');r<-pc_analyze(n,'fourpl',options=s)
check(max(abs(r$parameters$estimate[r$parameters$parameter=='EC50']-c(5,8)))<.03,'global four-parameter fit respects group-specific plateaus and midpoint bounds')
check(diff(r$parameters$estimate[r$parameters$parameter=='top'])==0&&diff(r$parameters$estimate[r$parameters$parameter=='hill'])==0,'multiple nonlinear parameters can be shared jointly')
csv<-pc_analysis_results_csv(r,n,s);check(identical(names(csv)[-1],c('A','B'))&&max(abs(as.numeric(csv[csv[[1]]=='EC50',-1])-c(5,8)))<.03,'global CSV exports both correctly fitted midpoints')
cat(checks,'total global checks passed\n')
renamed<-tab;names(renamed)[2]<-'Vehicle'
s$fit_constraints<-'{"fourpl":{"groups":{"A":{"bottom":{"fixed":0}}}}}';new_s<-pc_rename_header_settings(s,tab,renamed)
check('Vehicle'%in%names(pc_fit_constraints(new_s$fit_constraints)$fourpl$groups),'group overrides follow a series rename')
s$fit_mode<-'independent';s$fit_constraints<-'{"fourpl":{"groups":{"Missing":{"bottom":{"fixed":0}}}}}'
check(fails(pc_analyze(n,'fourpl','A',options=s)),'missing series overrides cannot silently disappear from an analysis')
cat(checks,'final global checks passed\n')
shiny::testServer(source('app.R')$value,{
 raw(data.frame(X=as.character(1:20),A=as.character(1+2*(1:20)+sin(1:20)*.01),B=as.character(5+2*(1:20)+cos(1:20)*.01)));document_open(TRUE)
 do.call(session$setInputs,modifyList(pc_defaults(),list(layout='xy',graph='scatter',method='linear',group1='A',fit_scope='all')));session$flushReact()
 session$setInputs(fit_constraints_open=1);session$flushReact()
 session$setInputs(constraint_intercept_fixed='0',constraint_intercept_lower='',constraint_intercept_upper='',constraint_slope_fixed='',constraint_slope_lower='',constraint_slope_upper='',constraint_target_choice='B');session$flushReact()
 check(constraint_draft()$intercept$fixed==0,'dialog stores defaults before switching groups')
 session$setInputs(constraint_intercept_override=TRUE,constraint_intercept_fixed='5',constraint_slope_override=FALSE,constraint_target_choice='__defaults__');session$flushReact()
 check(constraint_draft()$groups$B$intercept$fixed==5,'dialog preserves a group override when switching back to Defaults')
 check(settings()$fit_constraints=='{}','draft group edits do not change the study before Apply')
})
cat(checks,'total checks including dialog staging passed\n')
s$fit_mode<-'independent';s$method<-'fourpl';s$fit_constraints<-'{"fourpl":{"groups":{"A":{"bottom":{"fixed":0}}}}}'
r<-pc_analyze(n,'fourpl',options=s);csv<-pc_analysis_results_csv(r,n,s)
check(all(is.finite(as.numeric(csv[csv[[1]]=='EC50',-1])))&&all(is.finite(as.numeric(csv[csv[[1]]=='Top',-1]))),'unconstrained groups retain aligned results beside a constrained group')
cat(checks,'final checks passed\n')
check(length(pc_fit_constraints('{"fourpl":{"EC50":{"lower":0,"upper":20}}}'))==1L,'a zero lower bound is allowed while the model retains its positive scale domain')
cat(checks,'final global checks passed\n')
check(fails(pc_fit_constraints('{"linear":{"groups":{"A":[{"slope":{"fixed":2}}]}}}')),'unnamed parameter arrays cannot silently discard constraints')
s$method<-'threepl';s$fit_scope<-'selected';s$group1<-'A';s$fit_constraints<-'{"threepl":{"bottom":{"fixed":0},"top":{"fixed":100},"EC50":{"fixed":1e-15}}}'
r<-pc_analyze(n,'threepl','A',options=s)
check(r$parameters$estimate[r$parameters$parameter=='EC50']==1e-15,'a small positive fixed value remains exact rather than being clipped')
cat(checks,'final global checks passed\n')
