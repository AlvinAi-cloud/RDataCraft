source('app.R')
k<-0;check<-function(x,label){stopifnot(isTRUE(x));k<<-k+1;cat('PASS:',label,'\n')}
fail<-function(expr)inherits(tryCatch(force(expr),error=identity),'error')
s<-pc_defaults();s$layout<-'xy';s$method<-'linear';s$graph<-'scatter';s$group1<-'Y'
tab<-data.frame(X=as.character(1:20),Y=as.character(2+3*(1:20)+sin(1:20)*.2));n<-pc_normalize(tab,'xy')
s$fit_constraints<-'{"linear":{"intercept":{"fixed":0},"slope":{"lower":0,"upper":4}}}'
r<-pc_analyze(n,'linear','Y',options=s)
check(r$parameters$estimate[1]==0 && is.na(r$parameters$se[1]),'fixed intercept is exact and has no estimated SE')
check(r$parameters$estimate[2]>=0&&r$parameters$estimate[2]<=4,'slope obeys requested bounds')
check(r$metrics$value[r$metrics$measure=='Residual degrees of freedom']=='19','degrees of freedom count only the free slope')
p<-pc_decode_project(pc_project(tab,s));check(p$settings$fit_constraints==s$fit_constraints,'constraints survive study round trip')
check(fail(pc_fit_constraints('{"linear":{"slope":{"lower":3,"upper":1}}}')),'reversed bounds reject')
check(fail(pc_fit_constraints('{"fourpl":{"EC50":{"fixed":-1}}}')),'nonpositive EC50 rejects')
check(fail(pc_fit_constraints('{"linear":{"other":{"fixed":1}}}')),'unknown parameter rejects')
s$method<-'fourpl';s$fit_constraints<-'{"fourpl":{"bottom":{"fixed":0},"top":{"fixed":100},"EC50":{"lower":1,"upper":20},"hill":{"lower":0.1,"upper":8}}}'
x<-10^seq(-2,2,length.out=35);tab<-data.frame(X=as.character(x),Y=as.character(100*plogis(2*(log10(x)-log10(5)))+sin(seq_along(x))*.05));n<-pc_normalize(tab,'xy')
r<-pc_analyze(n,'fourpl','Y',options=s)
check(max(abs(r$parameters$estimate-c(0,100,5,2)))<.03,'four-parameter curve recovers free EC50 and hill with two fixed plateaus')
d<-pc_curve_results(r,n,s);check(abs(d$rows[[3]]$cells[[1]]$value-5)<.03,'result table reports natural-scale EC50 correctly')
s$fit_scope<-'all';tab$Z<-tab$Y;r<-pc_analyze(pc_normalize(tab,'xy'),'fourpl',options=s)
check(nrow(r$parameters)==8&&all(r$fit_status$status=='Fitted'),'constraints apply independently to all series')
s$fit_scope<-'selected';s$group1<-'Y';s$fit_constraints<-'{"fourpl":{"bottom":{"fixed":0},"top":{"fixed":100},"EC50":{"fixed":5},"hill":{"fixed":2}}}'
r<-pc_analyze(n,'fourpl','Y',options=s);check(all(is.na(r$parameters$se))&&r$n==35,'all-fixed model evaluates without invented uncertainty')
s$fit_constraints<-'{"fourpl":{"bottom":{"fixed":0},"top":{"fixed":100}}}'
plan<-list(answer='Fix plateaus as requested.',operations=list(list(type='analysis',title='Constrained curve',parameters=list(list(key='method',value='fourpl'),list(key='fit_constraints',value=s$fit_constraints)))))
check(length(pc_ai_prepare(tab,s,'Synthetic',plan)$operations)==1,'AI constraints pass the same validation and create only a reviewable preview')
plan$operations[[1]]$parameters[[2]]$value <- '{"fourpl":{"hill":{"fixed":1},"groups":{"Y":{"hill":{"fixed":1}}}}}'
prepared <- pc_ai_prepare(tab,s,'Synthetic',plan)
hill <- prepared$reports[[1]]$result$parameters
check(abs(hill$estimate[hill$parameter=='hill']-1)<1e-14,'AI requests and reports use the standard Hill coefficient')
shiny::testServer(source('app.R')$value,{
 raw(tab);document_open(TRUE)
 old <- '{"fourpl":{"hill":{"fixed":1}}}'
 do.call(session$setInputs,modifyList(s,list(fit_constraints=old)));session$flushReact()
 session$setInputs(fit_constraints_open=1);session$flushReact()
 check(grepl(as.character(1/log(10)),output$constraint_fields$html,fixed=TRUE),'saved Hill constraints display their standard equivalent')
 session$setInputs(constraint_hill_fixed='1',fit_constraints_apply=1);session$flushReact()
 check(constraint_draft()$hill$fixed==log(10),'constraint dialog fixes the standard Hill coefficient at one')
})
shiny::testServer(source('app.R')$value,{
 raw(data.frame(X=as.character(1:20),Y=as.character(2+3*(1:20)+sin(1:20)*.2)));document_open(TRUE)
 do.call(session$setInputs,modifyList(pc_defaults(),list(layout='xy',graph='scatter',method='linear',group1='Y')));session$flushReact()
 session$setInputs(fit_constraints_open=1);session$flushReact()
 session$setInputs(constraint_intercept_fixed='0',constraint_intercept_lower='',constraint_intercept_upper='',constraint_slope_fixed='',constraint_slope_lower='0',constraint_slope_upper='4',fit_constraints_apply=1);session$flushReact()
 # updateTextInput normally comes back from the browser; the mock checks its payload.
 check(identical(constraint_method(),'linear'),'constraint dialog is bound to the selected fitting model')
})

x<-seq(.2,6,length.out=40)
cases<-list(origin=list(slope=2),quadratic=list(a=1,b=2,c=.1),cubic=list(a=1,b=2,c=.1,d=.02),logarithmic=list(a=1,b=2),power=list(A=2,b=1.3),exponential=list(A=2,k=.2),decay=list(plateau=1,amplitude=5,rate=.5),association=list(plateau=6,amplitude=5,rate=.5),michaelis=list(Vmax=5,Km=2),gaussian=list(baseline=1,amplitude=5,center=3,sigma=1))
for(method in names(cases)){
 p<-cases[[method]]
 y<-with(p,switch(method,origin=slope*x,quadratic=a+b*x+c*x^2,cubic=a+b*x+c*x^2+d*x^3,logarithmic=a+b*log(x),power=A*x^b,exponential=A*exp(k*x),decay=plateau+amplitude*exp(-rate*x),association=plateau-amplitude*exp(-rate*x),michaelis=Vmax*x/(Km+x),gaussian=baseline+amplitude*exp(-.5*((x-center)/sigma)^2)))+sin(seq_along(x))*.001
 rules<-setNames(list(setNames(list(list(fixed=p[[1]])),names(p)[1])),method)
 s<-pc_defaults();s$fit_constraints<-as.character(jsonlite::toJSON(rules,auto_unbox=TRUE))
 r<-pc_analyze(pc_normalize(data.frame(X=as.character(x),Y=as.character(y)),'xy'),method,'Y',options=s)
 check(max(abs(r$parameters$estimate-unlist(p)))<.03,paste(method,'recovers free parameters with a fixed value'))
}

x<-1:20;y<-2+3*x+sin(x)*.2;n<-pc_normalize(data.frame(X=as.character(x),Y=as.character(y)),'xy')
r<-pc_analyze(n,'linear','Y',options=list(fit_constraints='{"linear":{"intercept":{"fixed":0},"slope":{"upper":2}}}'))
check(abs(r$parameters$estimate[2]-2)<1e-6&&is.na(r$parameters$se[2]),'an active bound is respected and its Wald interval is omitted')

x <- seq(.2, 10, length.out=35)
y <- 28*x/(4+x) + .42*sin(seq_along(x))
n <- pc_normalize(data.frame(X=x,Y=y),'xy')
r <- pc_analyze(n,'michaelis','Y',options=list(fit_weight='inv_y2'))
km <- subset(r$parameters, parameter=='Km')
w <- r$diagnostics$weight
ss <- sum(w*r$diagnostics$residual^2)
conditional_sse <- function(km) {
  fraction <- x/(km+x)
  vmax <- sum(w*fraction*y)/sum(w*fraction^2)
  sum(w*(y-vmax*fraction)^2)
}
f <- (vapply(c(km$ci_low,km$ci_high),conditional_sse,numeric(1))/ss-1)*(length(x)-2L)
check(km$ci_method=='Profile likelihood' && km$ci_low<km$estimate && km$estimate<km$ci_high &&
      max(abs(f-qf(.95,1,length(x)-2L)))<1e-5,
      'weighted Michaelis–Menten Km limits match independent analytical refits')
cat(k,'checks passed\n')
