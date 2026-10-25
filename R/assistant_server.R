pc_assistant_server <- function(input,output,session,capture,apply_result,open_r=NULL) {
  connection_value<-shiny::reactiveVal(list())
  transport<-pc_connected_ai(function(message) session$sendCustomMessage('rdatacraft-ai-delivery',message),function(value) {shiny::isolate({
    connection_value(value)
    if(!is.null(value$chatgpt)) {
      accounts<-value$chatgpt$accounts
      choices<-if(length(accounts)) stats::setNames(vapply(accounts,function(x) x$id,character(1)),vapply(accounts,function(x) x$label,character(1))) else character()
      shiny::updateSelectInput(session,'ai_account',choices=choices,selected=value$chatgpt$activeId)
      if(!is.null(value$chatgpt$activeId) && !busy()) {
        shiny::updateRadioButtons(session,'ai_mode',selected='chatgpt')
        transport$command('account_models',list(registrationId=value$chatgpt$activeId))
      }
    }
    if(!is.null(value$connection)) {
      shiny::updateRadioButtons(session,'ai_mode',selected='api')
      shiny::updateSelectInput(session,'ai_provider',selected=value$connection$provider)
      shiny::updateTextInput(session,'ai_endpoint',value=value$connection$endpoint)
      shiny::updateTextInput(session,'ai_model',value=value$connection$model)
    }
    if(!is.null(value$model) && !identical(input$ai_model,value$model)) shiny::updateTextInput(session,'ai_model',value=value$model)
    if(!is.null(value$models)) {
      models<-value$models
      choices<-stats::setNames(vapply(models,function(x) if(is.null(x$id)) x$slug else x$id,character(1)),vapply(models,function(x) if(is.null(x$name)) x$display_name else x$name,character(1)))
      selected<-if(!is.null(input$ai_model) && input$ai_model %in% choices) input$ai_model else if(length(choices)) choices[1] else ''
      shiny::updateSelectInput(session,'ai_model_list',choices=choices,selected=selected)
    }
    session$sendCustomMessage('rdatacraft-ai-connection',c(value,list(loginBusy=FALSE)))
    if(!is.null(value$status)) notify(value$status)
    if(!is.null(value$error)) notify(value$error)
  })})
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
  shiny::observeEvent(input$assistant_connection,{
    shiny::showModal(pc_ai_connections_ui())
    tryCatch(transport$command('status'),error=function(e) notify(conditionMessage(e)))
  })
  shiny::observeEvent(input$assistant_status_check,{notify(transport$status());tryCatch(transport$command('status'),error=function(e) notify(conditionMessage(e)))})
  shiny::observeEvent(input$assistant_native_status,notify(pc_ai_text(input$assistant_native_status$message,1000)))
  shiny::observeEvent(input$assistant_send,tryCatch({
    if(busy()) {notify("Finish or stop the current request first.");return()}
    prompt<-trimws(pc_ai_text(input$assistant_prompt,6000));if(!nzchar(prompt)) stop("Enter a question or describe the change you want.")
    state<-capture();context<-pc_ai_context(state$table,state$settings,state$name,isTRUE(input$assistant_share))
    id<-paste0(as.integer(Sys.time()),"-",sample.int(1e8,1));pending(list(id=id,state=state));ready(NULL);busy(TRUE)
    prior<-tail(history(),10);record("user",prompt);notify("Thinking with the connected model…")
    request<-list(id=id,instructions=pc_ai_instructions(),prompt=prompt,context=context,history=prior,schema=pc_ai_schema())
    transport$start(request)
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
    p<-pending();if(!is.null(p)) {transport$cancel(p$id,announce=FALSE)}
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
  api_body<-function() list(connection=list(provider=input$ai_provider,endpoint=if(identical(input$ai_provider,'compatible')) input$ai_endpoint else '',apiKey=if(is.null(input$ai_key)) '' else input$ai_key))
  op<-function(action,body=list()) tryCatch({if(action=='sign_in') session$sendCustomMessage('rdatacraft-ai-connection',list(notice='Complete sign-in and consent in your browser, then return here.',loginBusy=TRUE));transport$command(action,body)},error=function(e) {notify(conditionMessage(e));session$sendCustomMessage('rdatacraft-ai-connection',list(error=conditionMessage(e),loginBusy=FALSE))})
  shiny::observeEvent(input$ai_sign_in,op('sign_in'))
  shiny::observeEvent(input$ai_cancel_login,op('cancel_login'))
  shiny::observeEvent(input$ai_activate,op('activate',list(registrationId=input$ai_account)))
  shiny::observeEvent(input$ai_reauthorize,op('sign_in',list(registrationId=input$ai_account)))
  shiny::observeEvent(input$ai_sign_out,op('sign_out',list(registrationId=input$ai_account)))
  shiny::observeEvent(list(input$ai_models,input$ai_discover),{
    if(is.null(input$ai_provider)) return()
    if(identical(input$ai_mode,'chatgpt') && !is.null(transport$account())) op('account_models',list(registrationId=transport$account()))
    else op('models',if(nzchar(if(is.null(input$ai_key)) '' else input$ai_key) || identical(input$ai_provider,'compatible')) api_body() else list())
  })
  shiny::observeEvent(input$ai_connect,{
    op('connect',c(api_body(),list(model=input$ai_model,remember=isTRUE(input$ai_remember))))
    shiny::updateTextInput(session,'ai_key',value='')
    session$sendCustomMessage('rdatacraft-ai-clear-key',list())
  })
  shiny::observeEvent(input$ai_model_list,{if(nzchar(input$ai_model_list)) shiny::updateTextInput(session,'ai_model',value=input$ai_model_list)})
  shiny::observeEvent(input$ai_model,{if(nzchar(input$ai_model) && identical(input$ai_mode,'chatgpt') && !is.null(transport$account())) op('set_model',list(model=input$ai_model))},ignoreInit=TRUE)
  shiny::observeEvent(input$ai_provider,{shiny::updateTextInput(session,'ai_key',value='');shiny::updateSelectInput(session,'ai_model_list',choices=character());transport$command('discard_models')},ignoreInit=TRUE)
  shiny::observeEvent(input$ai_test,op('test',list(model=input$ai_model)))
  shiny::observeEvent(input$ai_disconnect,op('disconnect'))
  shiny::observeEvent(input$ai_forget,op('forget'))
  shiny::observeEvent(input$ai_settings_closed,{shiny::updateTextInput(session,'ai_key',value='');op('cancel_login')})
  session$onSessionEnded(function() transport$close())
  invisible(list(pending=pending,ready=ready,history=history,busy=busy))
}
