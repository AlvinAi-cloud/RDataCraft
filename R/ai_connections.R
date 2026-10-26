# Shared desktop AI bridge. Tokens and remembered keys remain in the private helper.
pc_ai_profile <- function() {
  override<-Sys.getenv('RDATACRAFT_AI_PROFILE')
  if(nzchar(override)) return(normalizePath(override,winslash='/',mustWork=FALSE))
  file.path(tools::R_user_dir('RDataCraft','config'),'ai')
}
pc_ai_helper <- function() {
  override<-Sys.getenv('RDATACRAFT_AI_HELPER')
  candidates<-c(override,file.path('desktop','ai-helper','bin',if(.Platform$OS.type=='windows') 'rdatacraft-ai.exe' else 'rdatacraft-ai'))
  found<-candidates[nzchar(candidates) & file.exists(candidates)]
  if(length(found)) normalizePath(found[1],winslash='/',mustWork=TRUE) else NULL
}
pc_ai_response_text <- function(value) {
  # Provider bodies stay in memory; only validated textual proposals enter the app.
  if(!is.null(value$stop_reason) && value$stop_reason %in% c('max_tokens','refusal')) stop('The provider stopped before completing the proposal.')
  if(identical(value$status,'incomplete') || identical(value$status,'failed') || !is.null(value$error)) stop('The provider did not complete the response. Try again with a shorter request.')
  text<-character()
  if(is.character(value$output_text)) text<-value$output_text
  if(!length(text) && is.list(value$output)) for(item in value$output) for(part in item$content) if(identical(part$type,'output_text') && is.character(part$text)) text<-c(text,part$text)
  if(!length(text) && is.list(value$content)) for(part in value$content) if(identical(part$type,'text') && is.character(part$text)) text<-c(text,part$text)
  if(!length(text) && length(value$candidates)) {
    candidate<-value$candidates[[1]]
    if(!is.null(candidate$finishReason) && candidate$finishReason!='STOP') stop('The provider stopped before completing the proposal.')
    for(part in candidate$content$parts) if(is.character(part$text)) text<-c(text,part$text)
  }
  if(!length(text) && length(value$choices)) {
    choice<-value$choices[[1]]
    if(!is.null(choice$finish_reason) && choice$finish_reason!='stop') stop('The provider stopped before completing the proposal.')
    text<-choice$message$content
  }
  if(!length(text) || !is.character(text)) stop('The provider returned no supported text response.')
  text<-trimws(paste(text,collapse='\n'))
  if(startsWith(text,'```')) text<-sub('\n```[[:space:]]*$','',sub('^```(?:json)?[[:space:]]*','',text,perl=TRUE),perl=TRUE)
  if(nchar(text,type='bytes')>100000) stop('The assistant response is too large.')
  plan<-jsonlite::fromJSON(text,simplifyVector=FALSE)
  if(!is.list(plan) || !is.character(plan$answer) || length(plan$answer)!=1L || !is.list(plan$operations)) stop('The model did not return a valid operation plan. Try again.')
  text
}
pc_connected_ai <- function(deliver,connection_event=function(...) NULL,helper=pc_ai_helper(),profile=pc_ai_profile()) {
  worker<-NULL;callbacks<-list();counter<-0L;generation<-0L;request_id<-NULL;connected<-NULL;model<-'';account_id<-NULL;connection_info<-NULL;restoring<-FALSE;queued<-list();discovery_seq<-0L
  status_text<-function() {
    if(is.null(connected)) 'Choose Accounts and Models to connect your own AI provider. Local tools work offline.' else paste('Connected ·',connected,'·',if(nzchar(model)) model else 'choose a model')
  }
  receive<-function(message) {
    cb<-callbacks[[message$id]];callbacks[[message$id]]<<-NULL
    if(!is.null(cb)) tryCatch(cb(message),error=function(e) connection_event(list(error='Could not read the AI connection response.')))
  }
  poll<-function(token) {
    if(token!=generation || is.null(worker)) return(invisible(NULL))
    lines<-tryCatch(worker$read_output_lines(),error=function(e) character())
    for(line in lines) if(nchar(line,type='bytes')<=1500000) tryCatch(receive(jsonlite::fromJSON(line,simplifyVector=FALSE)),error=function(e) NULL)
    if(worker$is_alive()) later::later(function() poll(token),.1) else {
      worker<<-NULL;connected<<-NULL
      pending<-callbacks;callbacks<<-list()
      for(cb in pending) cb(list(ok=FALSE,error='The AI connection service stopped. Reopen Accounts and Models to reconnect.'))
    }
  }
  send<-function(action,body=list(),callback=function(...) NULL) {
    if(is.null(worker) || !worker$is_alive()) stop('The bundled AI connection service is unavailable. Rebuild or reinstall RDataCraft v0.33.')
    counter<<-counter+1L;id<-paste0('c',counter);callbacks[[id]]<<-callback
    value<-c(list(id=id,action=action),body)
    worker$write_input(paste0(jsonlite::toJSON(value,auto_unbox=TRUE,null='null',digits=NA),'\n'))
    invisible(id)
  }
  publish<-function(message) {
    if(isTRUE(message$ok)) {
      value<-message$value
      if(!is.null(value$chatgpt) && is.null(value$chatgpt$activeId) && !is.null(connection_info)) value$connection<-connection_info
      if(!is.null(value$connection)) {connected<<-value$connection$provider;model<<-value$connection$model;account_id<<-NULL;connection_info<<-value$connection}
      if(!is.null(value$chatgpt)) {
        account_id<<-value$chatgpt$activeId
        if(!is.null(account_id)) {connected<<-'ChatGPT account';connection_info<<-NULL} else if(identical(connected,'ChatGPT account')) connected<<-NULL
      }
      if(is.character(value$model)) model<<-value$model
      connection_event(c(value,list(status=status_text())))
    } else connection_event(list(error=message$error,status=status_text()))
  }
  ensure<-function() {
    if(!is.null(worker) && worker$is_alive()) return(invisible(NULL))
    if(is.null(helper)) stop('This copy does not include the AI connection service. Rebuild or reinstall RDataCraft v0.33.')
    dir.create(profile,recursive=TRUE,showWarnings=FALSE,mode='0700');Sys.chmod(profile,'0700')
    worker<<-processx::process$new(helper,c('--profile',normalizePath(profile,winslash='/',mustWork=TRUE)),stdin='|',stdout='|',stderr='|',cleanup_tree=TRUE)
    generation<<-generation+1L;later::later(local({token<-generation;function() poll(token)}),.1)
    restoring<<-TRUE
    send('restore',callback=function(message) {restoring<<-FALSE;publish(message);waiting<-queued;queued<<-list();for(item in waiting) send(item$action,item$body,item$callback)})
  }
  command<-function(action,body=list()) {
    if(action=='discard_models') {discovery_seq<<-discovery_seq+1L;return(invisible(NULL))}
    ensure()
    if(action %in% c('connect','sign_in','activate','sign_out','disconnect','forget')) {
      if(!is.null(request_id)) stop('Stop the current AI request before changing accounts.')
    }
    if(action=='disconnect') {connected<<-NULL;account_id<<-NULL;connection_info<<-NULL}
    if(action=='forget' && !identical(connected,'ChatGPT account')) {connected<<-NULL;account_id<<-NULL;connection_info<<-NULL}
    if(action=='set_model') model<<-body$model
    callback<-publish
    if(action %in% c('models','account_models')) {discovery_seq<<-discovery_seq+1L;callback<-local({token<-discovery_seq;function(message) if(token==discovery_seq) publish(message)})}
    if(restoring) queued<<-c(queued,list(list(action=action,body=body,callback=callback))) else send(action,body,callback)
  }
  start<-function(body) {
    tryCatch({
      ensure()
      if(restoring) stop('Reconnecting your saved AI account. Please wait briefly and send again.')
      if(is.null(connected) || !nzchar(model)) stop('Open Accounts and Models, connect a provider and choose a model before sending.')
      if(!is.null(request_id)) stop('Another assistant request is running.')
      current<-body$id;request_id<<-current
      payload<-jsonlite::toJSON(list(user_request=body$prompt,context=body$context,recent_conversation=body$history),auto_unbox=TRUE,null='null')
      if(nchar(payload,type='bytes')>350000) stop('The assistant context is too large.')
      instruction<-paste(body$instructions,'Return only one JSON object with answer and operations matching this schema. Do not use Markdown fences.',jsonlite::toJSON(body$schema,auto_unbox=TRUE,null='null'))
      send('request',list(model=model,system=instruction,prompt=payload),function(message) {
        if(!identical(request_id,current)) return(invisible(NULL))
        request_id<<-NULL
        response<-tryCatch({if(!isTRUE(message$ok)) stop(message$error);pc_ai_response_text(message$value)},error=identity)
        if(inherits(response,'error')) deliver(list(type='ai-result',id=current,ok=FALSE,message=conditionMessage(response))) else deliver(list(type='ai-result',id=current,ok=TRUE,response=response))
      })
    },error=function(e) {request_id<<-NULL;deliver(list(type='ai-result',id=body$id,ok=FALSE,message=conditionMessage(e)))})
  }
  cancel<-function(id=NULL,announce=FALSE) {
    current<-request_id
    if(!is.null(id) && !identical(id,current)) return(invisible(NULL))
    request_id<<-NULL
    if(!is.null(worker) && worker$is_alive()) try(send('cancel'),silent=TRUE)
    if(announce && !is.null(current)) deliver(list(type='ai-result',id=current,ok=FALSE,message='Request stopped. No changes were applied.'))
  }
  close<-function() {
    cancel();generation<<-generation+1L
    if(!is.null(worker) && worker$is_alive()) {try(worker$close_input(),silent=TRUE);p<-worker;later::later(function() {if(p$is_alive()) try(p$kill_tree(),silent=TRUE)},35)}
    callbacks<<-list();worker<<-NULL
  }
  list(start=start,cancel=cancel,close=close,status=status_text,command=command,account=function() account_id)
}

pc_ai_connections_ui <- function() shiny::modalDialog(title='Accounts and Models',size='l',easyClose=TRUE,
  shiny::div(id='ai_connection_dialog',
    shiny::p('Connect your own account. Codex is not required. Your connection is saved on this computer, separately from studies.'),
    shiny::tags$div(id='ai_connection_notice',role='status',`aria-live`='polite'),
    shiny::radioButtons('ai_mode','Connection type',choices=c('ChatGPT account'='chatgpt','API or local service'='api'),selected='chatgpt',inline=TRUE),
    shiny::conditionalPanel("input.ai_mode === 'chatgpt'",shiny::tags$section(shiny::h3('ChatGPT account'),
      shiny::p('Continue in your browser to sign in and grant access. Available models depend on your account and OpenAI eligibility.'),
      shiny::div(class='ai-connection-actions',shiny::actionButton('ai_sign_in','Continue with ChatGPT',class='btn-primary'),shiny::actionButton('ai_cancel_login','Cancel sign-in')),
      shiny::selectInput('ai_account','Saved ChatGPT account',choices=character()),
      shiny::div(class='ai-connection-actions',shiny::actionButton('ai_activate','Use saved account'),shiny::actionButton('ai_reauthorize','Sign in again / grant plan access'),shiny::actionButton('ai_sign_out','Sign out selected account')))),
    shiny::conditionalPanel("input.ai_mode === 'api'",shiny::tags$section(shiny::h3('API or local service'),
      shiny::selectInput('ai_provider','Provider',choices=c('OpenAI API'='openai','Anthropic / Claude API'='anthropic','Google Gemini API'='gemini','OpenAI-compatible / local server'='compatible')),
      shiny::passwordInput('ai_key','API key',value=''),
      shiny::conditionalPanel("input.ai_provider === 'compatible'",shiny::textInput('ai_endpoint','API base URL',value='http://localhost:11434/v1')),
      shiny::checkboxInput('ai_remember','Remember this connection on this computer',TRUE),
      shiny::div(class='ai-connection-actions',shiny::actionButton('ai_connect','Save and connect',class='btn-primary')))),
    shiny::selectInput('ai_model_list','Available models',choices=character()),
    shiny::actionButton('ai_models','Refresh model list'),
    shiny::conditionalPanel("input.ai_mode === 'api'",shiny::textInput('ai_model','Selected model ID (or enter manually)',value='')),
    shiny::p('Model discovery sends no study data. Test connection makes a small AI request and may use quota or incur provider charges.'),
    shiny::div(class='ai-connection-actions',shiny::actionButton('ai_test','Test connection'),shiny::actionButton('ai_disconnect','Disconnect for now'),shiny::actionButton('ai_forget','Forget saved API connection')),
    shiny::p('Remembered API keys and ChatGPT sessions are stored in your local app settings with access restricted to your user account. They are excluded from studies and exports.')),
  footer=shiny::modalButton('Done'))
