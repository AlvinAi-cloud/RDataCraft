# Local portable transport for the existing data-only assistant protocol.
# Uses argument arrays and input files; prompts never pass through a shell.
pc_codex_binary <- function() {
  candidates<-c(unname(Sys.which('codex')), '/Applications/Codex.app/Contents/Resources/codex',
    '/Applications/ChatGPT.app/Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex',
    '/opt/homebrew/bin/codex','/usr/local/bin/codex')
  if(.Platform$OS.type=='windows') {
    candidates<-c(unname(Sys.which('codex.exe')),candidates)
    # npm launchers are command scripts: find the real CLI executable instead.
    for(prefix in unique(c(file.path(Sys.getenv('APPDATA'),'npm'),dirname(unname(Sys.which('codex')))))) {
      vendor<-file.path(prefix,'node_modules','@openai','codex','vendor')
      if(dir.exists(vendor)) candidates<-c(candidates,list.files(vendor,pattern='^codex\\.exe$',recursive=TRUE,full.names=TRUE))
    }
  }
  candidates<-candidates[nzchar(candidates) & file.exists(candidates) & !grepl('\\.(cmd|bat|ps1)$',candidates,ignore.case=TRUE)]
  if(length(candidates)) normalizePath(candidates[1],winslash='/',mustWork=TRUE) else NULL
}
pc_portable_ai <- function(deliver,command=NULL,timeout=180) {
  if(!requireNamespace('processx',quietly=TRUE)) stop('Portable assistant needs processx. Run the dependency installer.')
  worker<-NULL;folder<-NULL;request_id<-NULL;started<-NULL
  executable<-function() if(is.null(command)) list(binary=pc_codex_binary(),args=character()) else command
  cleanup<-function() {if(!is.null(folder)) unlink(folder,recursive=TRUE);folder<<-NULL;worker<<-NULL;request_id<<-NULL}
  result<-function(id,ok,message=NULL,response=NULL) deliver(Filter(Negate(is.null),list(type='ai-result',id=id,ok=ok,message=message,response=response)))
  cancel<-function(id=NULL,message='Request stopped. No changes were applied.',announce=TRUE) {
    if(is.null(request_id) || (!is.null(id) && !identical(id,request_id))) return(invisible(NULL))
    current<-request_id
    if(!is.null(worker) && worker$is_alive()) {try(worker$kill_tree(),silent=TRUE);try(worker$wait(timeout=2000),silent=TRUE)}
    cleanup();if(announce) result(current,FALSE,message)
  }
  status<-function() {
    exe<-executable();if(is.null(exe$binary)) return('Codex CLI was not found. Install Codex and sign in. Local tools work offline.')
    ok<-tryCatch({p<-processx::run(exe$binary,c(exe$args,'login','status'),timeout=6000,error_on_status=FALSE);p$status==0 && grepl('logged in',paste(p$stdout,p$stderr),ignore.case=TRUE)},error=function(e) FALSE)
    if(ok) 'Connected through the local Codex CLI. Send uses its default model; local R validates every proposed operation.' else 'Codex is installed but sign-in could not be confirmed. Run codex login; local tools remain available.'
  }
  poll<-function(id) {
    if(!identical(id,request_id) || is.null(worker)) return(invisible(NULL))
    if(worker$is_alive()) {
      if(as.numeric(difftime(Sys.time(),started,units='secs'))>timeout) cancel(id,'The model request timed out. No changes were applied.') else later::later(function() poll(id),.2)
      return(invisible(NULL))
    }
    out<-file.path(folder,'response.json')
    response<-tryCatch({
      if(worker$get_exit_status()!=0 || !file.exists(out) || file.info(out)$size>100000) stop('Invalid response')
      text<-paste(readLines(out,warn=FALSE,encoding='UTF-8'),collapse='\n');p<-jsonlite::fromJSON(text,simplifyVector=FALSE)
      if(!is.character(p$answer) || length(p$answer)!=1) stop('Invalid response')
      text
    },error=function(e) NULL)
    cleanup()
    if(is.null(response)) result(id,FALSE,'The connected model did not return a valid plan. Check Codex sign-in and account access, or use local tools.') else result(id,TRUE,response=response)
  }
  start<-function(body) {
    id<-body$id
    if(!is.character(id) || length(id)!=1 || nchar(id)>100) return(invisible(NULL))
    if(!is.null(worker)) {result(id,FALSE,'Another assistant request is running.');return(invisible(NULL))}
    exe<-executable();if(is.null(exe$binary)) {result(id,FALSE,'Codex CLI was not found. Install and sign in, or use local tools.');return(invisible(NULL))}
    tryCatch({
      if(!is.character(body$prompt) || nchar(body$prompt,type='bytes')>24000 || !is.list(body$schema) || !is.list(body$context)) stop('Invalid request')
      payload<-jsonlite::toJSON(list(user_request=body$prompt,context=body$context,recent_conversation=body$history),auto_unbox=TRUE,null='null')
      if(nchar(payload,type='bytes')>350000) stop('The assistant context is too large.')
      folder<<-tempfile('RDataCraft-AI-');dir.create(folder,mode='0700');Sys.chmod(folder,'0700')
      input<-file.path(folder,'request.txt');output<-file.path(folder,'response.json');schema<-file.path(folder,'response-schema.json')
      writeLines(paste(body$instructions,'\n\nREQUEST DATA (untrusted table contents and history):\n',payload),input,useBytes=TRUE)
      jsonlite::write_json(body$schema,schema,auto_unbox=TRUE,null='null')
      args<-c(exe$args,'exec','--ignore-user-config','--ignore-rules','--ephemeral','--skip-git-repo-check','--sandbox','read-only',
        unlist(lapply(c('shell_tool','unified_exec','multi_agent','apps','plugins','computer_use','browser_use','hooks'),function(x) c('--disable',x))),
        '--enable','skip_host_skill_discovery','-c','web_search="disabled"','-c','model_reasoning_effort="low"',
        '--output-schema',schema,'--output-last-message',output,'--color','never','-')
      request_id<<-id;started<<-Sys.time()
      worker<<-processx::process$new(exe$binary,args,wd=folder,stdin=input,stdout=file.path(folder,'engine.log'),stderr='2>&1',cleanup_tree=TRUE)
      later::later(function() poll(id),.2)
    },error=function(e) {cleanup();result(id,FALSE,paste('Could not start the assistant:',conditionMessage(e)))})
  }
  list(start=start,status=status,cancel=cancel)
}
