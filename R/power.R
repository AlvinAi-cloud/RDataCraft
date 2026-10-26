# Prospective planning with the functions shipped in R's stats package.
pc_power <- function(design="two.sample", solve="n", effect=0.5, alpha=0.05,
                     target=0.8, n=20, groups=3, p1=0.3, p2=0.5, dropout=0) {
  scalar <- function(x,label,lower,upper,strict=TRUE) {
    if(!is.numeric(x)||length(x)!=1L||!is.finite(x)||
       (if(strict) x<=lower||x>=upper else x<lower||x>upper)) stop(paste("Invalid",label),call.=FALSE)
  }
  if(!design %in% c("two.sample","one.sample","paired","anova","proportions") || !solve %in% c("n","power")) stop("Choose a supported design and calculation.",call.=FALSE)
  scalar(alpha,"alpha",0,1);scalar(dropout,"dropout fraction",0,1,FALSE)
  if(dropout>=1) stop("Dropout must be below 100%.",call.=FALSE)
  if(solve=="n") {scalar(target,"target power",alpha,1)} else {
    scalar(n,"sample size",2,1e7,FALSE);if(n!=floor(n)) stop("Sample size must be a whole number.",call.=FALSE)
  }
  if(design=="proportions") {
    scalar(p1,"first proportion",0,1);scalar(p2,"second proportion",0,1)
    if(p1==p2) stop("Specify two different anticipated proportions.",call.=FALSE)
  } else {scalar(effect,"standardized effect size",0,1e4)}
  if(design=="anova" && (length(groups)!=1||!is.finite(groups)||groups<2||groups>100||groups!=floor(groups))) stop("Choose 2 to 100 whole groups.",call.=FALSE)
  calc <- function(size=NULL,power=NULL) {
    if(design=="anova") stats::power.anova.test(groups=groups,n=size,between.var=effect^2*groups/(groups-1),within.var=1,sig.level=alpha,power=power)
    else if(design=="proportions") stats::power.prop.test(n=size,p1=p1,p2=p2,sig.level=alpha,power=power,alternative="two.sided",strict=TRUE)
    else stats::power.t.test(n=size,delta=effect,sd=1,sig.level=alpha,power=power,type=design,alternative="two.sided",strict=TRUE)
  }
  fit <- tryCatch(if(solve=="n") calc(power=target) else calc(size=n),error=function(e) stop("No solution for these planning assumptions: ",conditionMessage(e),call.=FALSE))
  count <- if(solve=="n") max(2,ceiling(fit$n)) else n
  if(!is.finite(count)||count>1e7) stop("Required sample size exceeds the supported planning range.",call.=FALSE)
  achieved <- calc(size=count)$power
  # Protect against root-finder tolerance when rounding very near an integer.
  if(solve=="n") while(achieved<target && count<1e7) {count<-count+1;achieved<-calc(size=count)$power}
  units <- if(design=="paired") "complete pairs" else if(design=="one.sample") "observations" else "observations per group"
  multiplier <- if(design=="anova") groups else if(design %in% c("two.sample","proportions")) 2 else 1
  recruit <- ceiling(count/(1-dropout))
  metrics <- data.frame(Measure=c("Design","Calculation","Alpha (two-sided / omnibus)","Number of groups","Target power","Effect assumptions",paste("Analyzable",units),"Achieved power at integer N",paste("Recruit",units),"Total analyzable units","Total recruitment units","Expected dropout"),
    Value=c(switch(design,two.sample="Two independent means",one.sample="One mean",paired="Paired means",anova="Balanced one-way ANOVA",proportions="Two independent proportions"),if(solve=="n") "Required sample size" else "Power at chosen sample size",alpha,multiplier,if(solve=="n") target else "Not requested",if(design=="proportions") paste("p1 =",p1,"; p2 =",p2) else paste(if(design=="anova") "Cohen f =" else if(design=="paired") "Paired dz =" else "Cohen d =",effect),count,signif(achieved,6),recruit,count*multiplier,recruit*multiplier,paste0(100*dropout,"%")),stringsAsFactors=FALSE)
  sizes <- unique(pmax(2,round(seq(max(2,count/2),min(1e7,count*1.5),length.out=25))))
  list(metrics=metrics,n=count,power=achieved,recruit=recruit,units=units,
    curve=data.frame(N=sizes,Power=vapply(sizes,function(x) calc(size=x)$power,numeric(1))),
    assumptions=paste("Prospective planning using R stats; independent experimental units.",
      switch(design,two.sample="Equal group sizes and common population SD; this plans a pooled-variance t test, not Welch's test.",
        one.sample="One-sample t test with normally distributed observations.",paired="Paired t test; effect = anticipated mean difference / SD of within-pair differences. N counts complete pairs, not individual measurements.",
        anova="Balanced ordinary one-way ANOVA with independent normal errors and common within-group variance. Cohen f describes the spread of anticipated means relative to within-group SD.",
        proportions="Equal independent group sizes; normal approximation for two proportions, not an exact/Fisher design. Rare events and small samples may require simulation."),
      "Do not use an observed P value or post-hoc observed effect as evidence of adequate power. Choose a scientifically meaningful anticipated effect. No multiplicity adjustment is automatic. Save the CSV to retain this planning result; it is separate from the study's analyses."))
}

pc_power_server <- function(input,output,session,capture=function() NULL) {
  result<-shiny::reactiveVal(NULL);error<-shiny::reactiveVal(NULL)
  pilot<-shiny::reactiveVal(NULL);applied_pilot<-shiny::reactiveVal(NULL)
  open <- function() {
    result(NULL);error(NULL);pilot(NULL);applied_pilot(NULL)
    shiny::showModal(shiny::modalDialog(title="Power & sample-size planning",size="l",easyClose=TRUE,fade=FALSE,
      shiny::p("Enter planning assumptions manually, or review estimates from the active table as pilot data. All planning inputs remain editable."),
      shiny::div(class="power-pilot-actions",shiny::actionButton("power_use_pilot","Use active table as pilot data",class="btn-outline-secondary"),shiny::actionButton("power_manual","Manual entry",class="btn-outline-secondary")),
      shiny::uiOutput("power_pilot_selectors"),shiny::uiOutput("power_pilot_review"),
      shiny::div(class="power-controls",
        shiny::selectInput("power_design","Design",c("Two independent means (equal N, common SD)"="two.sample","Paired means"="paired","One mean"="one.sample","Balanced one-way ANOVA"="anova","Two independent proportions"="proportions")),
        shiny::selectInput("power_solve","Calculate",c("Required sample size"="n","Power at a chosen sample size"="power")),
        shiny::conditionalPanel("input.power_design !== 'proportions'",shiny::numericInput("power_effect","Standardized effect (d; paired dz; ANOVA f)",0.5,min=0.0001)),
        shiny::conditionalPanel("input.power_design === 'anova'",shiny::numericInput("power_groups","Number of groups",3,min=2,max=100,step=1)),
        shiny::conditionalPanel("input.power_design === 'proportions'",shiny::numericInput("power_p1","Anticipated proportion 1",0.3,min=0.001,max=0.999),shiny::numericInput("power_p2","Anticipated proportion 2",0.5,min=0.001,max=0.999)),
        shiny::numericInput("power_alpha","Alpha",0.05,min=0.0001,max=0.999),
        shiny::conditionalPanel("input.power_solve === 'n'",shiny::numericInput("power_target","Target power",0.8,min=0.01,max=0.999)),
        shiny::conditionalPanel("input.power_solve === 'power'",shiny::numericInput("power_n","Analyzable N (per group; complete pairs for paired)",20,min=2,step=1)),
        shiny::numericInput("power_dropout","Expected dropout (%)",0,min=0,max=99)),
      shiny::uiOutput("power_effect_hint"),
      shiny::actionButton("power_calculate","Calculate",class="btn-primary"),
      shiny::uiOutput("power_status"),shiny::tableOutput("power_metrics"),shiny::plotOutput("power_curve",height="230px"),
      shiny::uiOutput("power_assumptions"),shiny::downloadButton("power_export","Export planning CSV"),
      footer=shiny::modalButton("Close")))
  }
  shiny::observeEvent(input$power_open,open())
  shiny::observeEvent(input$power_help_open,open())
  shiny::observeEvent(input$power_use_pilot, {
    error(NULL);result(NULL);applied_pilot(NULL)
    tryCatch({
      snapshot<-capture()
      if(is.null(snapshot)||!isTRUE(snapshot$open)) stop("Open a populated data table first, or use manual entry.")
      pc_normalize(snapshot$table,snapshot$settings$layout)
      pilot(snapshot)
    },error=function(e) {pilot(NULL);error(conditionMessage(e))})
  })
  shiny::observeEvent(input$power_manual,{pilot(NULL);applied_pilot(NULL);result(NULL);error(NULL)})
  output$power_pilot_selectors<-shiny::renderUI({
    shiny::req(pilot());s<-pilot();n<-pc_normalize(s$table,s$settings$layout)
    if(!s$settings$layout %in% c("column","contingency")) return(NULL)
    if(s$settings$layout=="column" && (s$settings$method=="anova" || (s$settings$method=="descriptive" && length(n$groups)>2))) return(shiny::p(paste("Pilot snapshot:",s$name,"· all",length(n$groups),"groups are used for balanced one-way ANOVA estimates.")))
    shiny::tagList(shiny::p(paste("Pilot snapshot:",s$name,"·",s$settings$method)),
      shiny::div(class="power-controls",
        shiny::selectInput("power_pilot_g1","Pilot group / first population",choices=n$groups,selected=s$settings$group1),
        if(s$settings$method!="onesample" && length(n$groups)>1) shiny::selectInput("power_pilot_g2","Second group / population",choices=n$groups,selected=s$settings$group2),
        if(s$settings$layout=="contingency") shiny::selectInput("power_pilot_outcome","Outcome counted as success",choices=rownames(n$counts))))
  })
  pilot_estimate<-shiny::reactive({
    shiny::req(pilot());s<-pilot()
    pc_power_pilot(s$table,s$settings,s$name,input$power_pilot_g1,input$power_pilot_g2,input$power_pilot_outcome)
  })
  output$power_pilot_review<-shiny::renderUI({
    shiny::req(pilot());r<-tryCatch(pilot_estimate(),error=identity)
    if(inherits(r,"error")) return(shiny::p(role="alert",conditionMessage(r)))
    shiny::tagList(shiny::p(r$note),shiny::tags$details(shiny::tags$summary("Review pilot estimates"),shiny::tableOutput("power_pilot_metrics")),
      if(!is.null(r$proposal)) shiny::actionButton("power_apply_pilot","Fill planning inputs from these estimates",class="btn-outline-secondary"))
  })
  output$power_pilot_metrics<-shiny::renderTable(pilot_estimate()$metrics,striped=TRUE)
  shiny::observeEvent(input$power_apply_pilot, {
    tryCatch({r<-pilot_estimate();p<-r$proposal;if(is.null(p)) stop("No compatible automatic estimate is available.")
      shiny::updateSelectInput(session,"power_design",selected=p$design)
      for(key in intersect(names(p),c("effect","groups","p1","p2","n"))) shiny::updateNumericInput(session,paste0("power_",key),value=signif(p[[key]],6))
      applied_pilot(r);result(NULL);error(NULL)
    },error=function(e) error(conditionMessage(e)))
  })
  shiny::observeEvent(input$power_calculate, {
    error(NULL);result(NULL)
    tryCatch({r<-pc_power(input$power_design,input$power_solve,input$power_effect,input$power_alpha,input$power_target,input$power_n,input$power_groups,input$power_p1,input$power_p2,input$power_dropout/100)
      if(!is.null(applied_pilot())) {p<-applied_pilot();r$metrics<-rbind(r$metrics,data.frame(Measure=paste("Pilot snapshot:",p$metrics$Measure),Value=p$metrics$Estimate));r$assumptions<-paste(r$assumptions,p$note,"Planning inputs were editable after filling; the values above are the final assumptions used.")}
      result(r)
    },error=function(e) error(conditionMessage(e)))
  })
  output$power_effect_hint<-shiny::renderUI(shiny::p(class="muted",switch(if(is.null(input$power_design)) "two.sample" else input$power_design,
    paired="Paired dz = anticipated mean within-pair difference / SD of within-pair differences. N counts complete pairs.",
    anova="Enter Cohen f (spread of anticipated group means relative to within-group SD). Groups have equal planned N.",
    proportions="Enter proportions between 0 and 1 (for example, 0.3 means 30%). Both groups have equal planned N.",
    "Cohen d = anticipated mean difference / population SD. For example, a difference of 5 with SD 10 gives d = 0.5.")))
  output$power_status<-shiny::renderUI({if(!is.null(error())) shiny::p(role="alert",error()) else if(is.null(result())) shiny::p(role="status","Enter assumptions and choose Calculate.") else shiny::div(role="status",shiny::h4(paste(result()$n,result()$units,"·",sprintf("%.1f%% power",100*result()$power))),shiny::p("Last calculated result. Recalculate after changing assumptions."))})
  output$power_metrics<-shiny::renderTable({shiny::req(result());result()$metrics},striped=TRUE)
  output$power_curve<-shiny::renderPlot({shiny::req(result());r<-result();graphics::plot(r$curve$N,r$curve$Power,type="l",ylim=c(0,1),xlab="Analyzable N (per group or complete pairs)",ylab="Power");graphics::points(r$n,r$power,pch=19,col="#247763")})
  output$power_assumptions<-shiny::renderUI({shiny::req(result());shiny::p(result()$assumptions)})
  output$power_export<-shiny::downloadHandler(filename=function() "RDataCraft-power-planning.csv",content=function(file) {shiny::req(result());r<-result();utils::write.csv(rbind(r$metrics,data.frame(Measure="Assumptions",Value=r$assumptions)),file,row.names=FALSE)})
}
