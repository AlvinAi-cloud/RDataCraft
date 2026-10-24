pc_assistant_server <- function(input,output,session,capture,apply_result,open_r=NULL) {
  portable<-identical(Sys.getenv('RDATACRAFT_PORTABLE'),'1')
  transport<-if(portable) pc_portable_ai(function(message) session$sendCustomMessage('rdatacraft-ai-delivery',message)) else NULL
  pending<-shiny::reactiveVal(NULL); ready<-shiny::reactiveVal(NULL); history<-shiny::reactiveVal(list())
  busy<-shiny::reactiveVal(FALSE); status<-shiny::reactiveVal("Check connection to use the connected model. Local tools work offline.")
  notify<-function(message) {status(message);session$sendCustomMessage("rdatacraft-ai-state",list(busy=busy(),message=message))}
  fingerprint<-function(state) digest::digest(list(state$sheet,state$view,state$table,state$settings),algo="xxhash64")
  record<-function(role,text) {h<-isolate(history());history(tail(c(h,list(list(role=role,text=substr(text,1,20000)))),30))}
  show_plan<-function(state,plan) {
    result<-pc_ai_prepare(state$table,state$settings,state$name,plan)
    ready(if(length(result$operations)) list(source=fingerprint(state),result=result) else NULL)
    record("assistant",result$answer);notify(if(length(result$operations)) "Preview ready. Review the operations before applying to a new table copy." else "Response ready.")
  }
  fail<-function(e) {busy(FALSE);pending(NULL);ready(NULL);notify(conditionMessage(e))}
  shiny::observeEvent(input$assistant_connection,{if(portable) notify(transport$status()) else session$sendCustomMessage("rdatacraft-ai-status",list())})
  shiny::observeEvent(input$assistant_native_status,notify(pc_ai_text(input$assistant_native_status$message,1000)))
  shiny::observeEvent(input$assistant_send,tryCatch({
    if(busy()) {notify("Finish or stop the current request first.");return()}
    prompt<-trimws(pc_ai_text(input$assistant_prompt,6000));if(!nzchar(prompt)) stop("Enter a question or describe the change you want.")
    state<-capture();context<-pc_ai_context(state$table,state$settings,state$name,isTRUE(input$assistant_share))
    id<-paste0(as.integer(Sys.time()),"-",sample.int(1e8,1));pending(list(id=id,state=state));ready(NULL);busy(TRUE)
    prior<-tail(history(),10);record("user",prompt);notify("Thinking with the connected model…")
    request<-list(id=id,instructions=pc_ai_instructions(),prompt=prompt,context=context,history=prior,schema=pc_ai_schema())
    if(portable) transport$start(request) else session$sendCustomMessage("rdatacraft-ai-request",request)
  },error=fail))
  shiny::observeEvent(input$assistant_response,tryCatch({
    value<-input$assistant_response;request<-pending()
    if(is.null(request) || !identical(value$id,request$id)) return()
    busy(FALSE);pending(NULL)
    if(!isTRUE(value$ok)) stop(pc_ai_text(value$message,1500))
    text<-pc_ai_text(value$response,100000)
    plan<-jsonlite::fromJSON(text,simplifyVector=FALSE)
    if(!identical(fingerprint(request$state),fingerprint(capture()))) stop("The active table or graph changed during the request. Send again to use its current state.")
    show_plan(request$state,plan)
  },error=fail))
  shiny::observeEvent(input$assistant_stop,{
    p<-pending();if(!is.null(p)) {if(portable) transport$cancel(p$id,announce=FALSE) else session$sendCustomMessage("rdatacraft-ai-cancel",list(id=p$id))}
    pending(NULL);busy(FALSE);notify("Request stopped. No changes were applied.")
  })
  shiny::observeEvent(input$assistant_local,tryCatch({
    if(busy()) {notify("Stop the connected request before using a local tool.");return()}
    state<-capture();kind<-input$assistant_local$kind
    if(identical(kind,"check")) {
      n<-pc_normalize(state$table,state$settings$layout)
      counts<-table(n$data$group);missing<-sum(is.na(state$table) | trimws(as.matrix(state$table))=="")
      response<-paste0("Local data check: ",nrow(state$table)," rows, ",ncol(state$table)," columns; ",nrow(n$data)," usable observations. ",missing," blank cells. Observations by group: ",paste(names(counts),as.integer(counts),sep=" = ",collapse=", "),". ",pc_layout_help(state$settings$layout))
      show_plan(state,list(answer=response,operations=list()))
    } else show_plan(state,pc_ai_local_plan(kind,state$settings))
  },error=fail))
  shiny::observeEvent(input$assistant_apply,tryCatch({
    proposed<-ready();if(is.null(proposed)) stop("Preview an operation first.")
    if(!identical(proposed$source,fingerprint(capture()))) stop("The source table or graph changed. Generate a fresh preview first.")
    if(!is.null(proposed$result$r_draft)) {
      if(is.null(open_r)) stop('Advanced R is unavailable in this session.')
      open_r(proposed$result$r_draft);ready(NULL);notify('Draft opened in Advanced R. Review the script and choose Run reviewed script to execute it.');return()
    }
    apply_result(proposed$result);ready(NULL);notify("Applied to a new table copy. Save the study when you want to keep it.")
  },error=function(e) notify(conditionMessage(e))))
  shiny::observeEvent(input$assistant_clear,{
    if(busy()) {notify("Stop the current request before clearing history.");return()}
    history(list());ready(NULL);notify("Conversation cleared from this session.")
  })
  output$assistant_history<-shiny::renderUI({
    h<-history();if(!length(h)) return(shiny::p(class="muted","Describe a graph, ask about your analysis, or arrange a figure. Use a local tool below to start without a model."))
    lapply(h,function(m) shiny::div(class=paste("assistant-message",m$role),shiny::strong(if(m$role=="user") "You" else "Assistant"),shiny::p(m$text)))
  })
  output$assistant_operations<-shiny::renderUI({
    p<-ready();if(is.null(p)) return(shiny::p(class="muted","No pending operations."))
    r<-p$result
    if(!is.null(r$r_draft)) return(shiny::tagList(shiny::p('R script draft only: it has not executed.'),shiny::tags$pre(r$r_draft$code),shiny::p(paste('Required packages:',r$r_draft$packages)),shiny::actionButton('assistant_apply','Open in Advanced R',class='btn-primary')))
    shiny::tagList(shiny::p("Source observations stay in the original table. The preview creates a new table copy."),
      shiny::tags$ol(lapply(r$operations,function(op) shiny::tags$li(shiny::strong(op$title),shiny::tags$ul(lapply(op$parameters,function(v) shiny::tags$li(paste(v$key,"=",v$value))))))),
      lapply(r$reports,function(a) shiny::tags$details(shiny::tags$summary(a$title," · calculated by R"),shiny::tags$pre(jsonlite::toJSON(a$result,auto_unbox=TRUE,pretty=TRUE,na="null",digits=7)))),
      shiny::tags$img(class="assistant-preview",src=paste0("data:image/svg+xml;base64,",jsonlite::base64_enc(charToRaw(r$preview))),alt="Preview of proposed graph or figure layout"),
      shiny::actionButton("assistant_apply","Apply to new table copy",class="btn-primary"))
  })
  output$assistant_context<-shiny::renderText({s<-capture();paste(s$name,"·",nrow(s$table),"rows ·",s$settings$layout,"·",s$settings$graph)})
  output$assistant_status<-shiny::renderText(status())
  for(id in c("assistant_history","assistant_operations","assistant_context","assistant_status")) shiny::outputOptions(output,id,suspendWhenHidden=FALSE)
  session$onSessionEnded(function() {p<-isolate(pending());if(!is.null(p)) {if(portable) transport$cancel(p$id,announce=FALSE) else session$sendCustomMessage("rdatacraft-ai-cancel",list(id=p$id))}})
  invisible(list(pending=pending,ready=ready,history=history,busy=busy))
}
