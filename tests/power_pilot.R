app<-source('app.R')$value
checks<-0L
check<-function(x,label) {if(!isTRUE(x)) stop('FAIL: ',label,call.=FALSE);checks<<-checks+1L;cat('PASS:',label,'\n')}
s<-pc_defaults();s$layout<-'column';s$method<-'student';s$group1<-'A';s$group2<-'B'
tab<-pc_check_table(data.frame(A=c(1,2,3,NA),B=c(3,5,7,9)))
r<-pc_power_pilot(tab,s);expected<-abs(mean(1:3)-mean(c(3,5,7,9)))/sqrt((2*var(1:3)+3*var(c(3,5,7,9)))/5)
check(abs(r$proposal$effect-expected)<1e-12&&r$proposal$n==3,'independent pilot uses pooled SD with unequal pilot N')
s$method<-'paired';r<-pc_power_pilot(tab,s)
check(abs(r$proposal$effect-3)<1e-12&&r$proposal$n==3,'paired pilot uses complete matched differences, not marginal SD')
s$method<-'onesample';s$null_mean<-1;r<-pc_power_pilot(tab,s)
check(r$proposal$design=='one.sample'&&abs(r$proposal$effect-1)<1e-12,'one-sample pilot respects the selected reference mean')
s$method<-'anova';r<-pc_power_pilot(tab,s)
check(r$proposal$design=='anova'&&r$proposal$groups==2,'ANOVA pilot supports two groups and computes equal-weight f')
s$method<-'mann';check(is.null(pc_power_pilot(tab,s)$proposal),'rank analysis is not silently converted to t-test planning')
s$method<-'student';zero<-pc_check_table(data.frame(A=1:3,B=1:3));check(is.null(pc_power_pilot(zero,s)$proposal),'zero effect is not replaced with an invented planning effect')
for(layout in c('xy','grouped','survival','multiple')) {
 s<-pc_defaults();s$layout<-layout;s$method<-pc_example(layout)$method
 r<-pc_power_pilot(pc_example(layout)$table,s)
 check(nrow(r$metrics)>4&&is.null(r$proposal),paste(layout,'has layout-specific pilot summaries without an incompatible power substitution'))
}
s<-pc_defaults();s$layout<-'contingency';s$method<-'fisher';s$group1<-'Control';s$group2<-'Drug'
r<-pc_power_pilot(pc_example('contingency')$table,s,outcome='Response')
check(abs(r$proposal$p1-0.3)<1e-12&&abs(r$proposal$p2-0.625)<1e-12,'count pilot uses selected outcome and correct population denominators')
r<-pc_power_pilot(pc_example('contingency')$table,s,outcome='No response')
check(abs(r$proposal$p1-0.7)<1e-12,'changing count outcome updates success definition explicitly')
shiny::testServer(app,{
 do.call(session$setInputs,pc_defaults());session$flushReact()
 session$setInputs(paste_data='A,B\n1,3\n2,5\n3,7',paste_delimiter=',',apply_paste=1,method='paired',group1='A',group2='B');session$flushReact()
 before<-raw()
 session$setInputs(power_open=1);session$flushReact()
 session$setInputs(power_use_pilot=1);session$flushReact()
 check(grepl('Fill planning inputs',output$power_pilot_review$html,fixed=TRUE),'active worksheet offers explicit review before filling planning values')
 session$setInputs(power_apply_pilot=1);session$flushReact()
 session$setInputs(power_design='paired',power_solve='n',power_effect=3,power_alpha=.05,power_target=.8,power_n=3,power_groups=2,power_p1=.3,power_p2=.5,power_dropout=0,power_calculate=1);session$flushReact()
 check(grepl('Pilot snapshot',output$power_metrics,fixed=TRUE),'calculated planning result retains pilot provenance for export')
 check(identical(raw(),before),'pilot capture, fill and calculation never modify observations')
 session$setInputs(power_manual=1);session$flushReact()
 check(grepl('Enter assumptions',output$power_status$html,fixed=TRUE),'manual entry clears pilot calculation context')
})
chrome<-as.character(pc_chrome())
check(grepl('data-command="power"',chrome,fixed=TRUE)&&grepl('data-command="advanced"',chrome,fixed=TRUE),'Power and Advanced R are available on the top toolbar')
cat(checks,'pilot-planning checks passed.\n')
