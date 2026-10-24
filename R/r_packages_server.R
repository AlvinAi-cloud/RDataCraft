# Approval is session-local and bound to the exact draft/request; never saved or inferred.
pc_pkg_server <- function(input,output,session,request,blocked,status,job=NULL) {
  if(is.null(job)) job<-pc_pkg_job()
  phase<-shiny::reactiveVal('idle');pending<-shiny::reactiveVal(NULL);log<-shiny::reactiveVal('')
  fingerprint<-function(x) digest::digest(x,algo='sha256')
  clear<-function(message=NULL) {if(identical(phase(),'approval')) shiny::removeModal();pending(NULL);phase('idle');if(!is.null(message)) status(message)}
  fail<-function(e) {if(job$busy()) job$cancel();clear(conditionMessage(e));invisible(NULL)}
  show_approval<-function(plan) {
    rows<-lapply(plan$packages,function(p) shiny::tags$tr(shiny::tags$td(p$name),shiny::tags$td(p$version),shiny::tags$td(if(nzchar(p$previous)) p$previous else 'Not installed'),shiny::tags$td(p$required_by)))
    shiny::showModal(shiny::modalDialog(title='Approve R package installation?',fade=FALSE,easyClose=FALSE,size='l',
      shiny::p('These packages are required by the Advanced R draft. Nothing has been installed yet.'),
      shiny::div(class='r-package-review',shiny::tags$table(class='table',shiny::tags$thead(shiny::tags$tr(lapply(c('Package','Version to install','Current version','Required by'),shiny::tags$th))),shiny::tags$tbody(rows))),
      shiny::p(shiny::strong('Repository: '),plan$repository),shiny::p(shiny::strong('Install location: '),shiny::tags$code(plan$library)),
      shiny::p('Only compatible CRAN binaries and their listed required dependencies will be installed for your user account. Bundled app packages and system R stay unchanged. Downloaded packages can run code with your account permissions.'),
      shiny::p('This approves package installation only. After it finishes, review the analysis and choose Run reviewed script.'),
      footer=shiny::tagList(shiny::actionButton('r_pkg_decline','Cancel',class='btn-outline-secondary'),shiny::actionButton('r_pkg_approve','Approve & install',class='btn-primary'))))
  }
  poll<-function() {
    if(!phase() %in% c('checking','installing')) return()
    log(job$log());result<-job$poll()
    if(is.null(result)) {later::later(function() shiny::withReactiveDomain(session,shiny::isolate(tryCatch(poll(),error=fail))),.2);return()}
    if(!is.null(result$log)) log(result$log)
    if(identical(result$status,'planned')) {
      proposal<-pending()
      if(is.null(proposal) || !identical(proposal$fingerprint,fingerprint(request()))) {clear('The draft changed while checking packages. Check packages again.');return()}
      pc_pkg_validate_plan(result$plan)
      if(!length(result$plan$packages)) {clear('All required packages are already installed. Choose Run reviewed script.');return()}
      proposal$plan<-result$plan;pending(proposal);phase('approval');status('Review the package list. Installation requires your approval.');show_approval(result$plan)
    } else clear(if(is.null(result$message)) 'The package operation did not complete.' else result$message)
  }
  check<-function() {
    if(blocked() || phase() %in% c('checking','installing')) {status('Finish or stop the current operation first.');return(invisible(FALSE))}
    tryCatch({
    x<-request();needed<-pc_pkg_missing(x$packages)
    if(!length(needed)) {clear('All required packages are installed. Choose Run reviewed script.');return(invisible(FALSE))}
    clear();pending(list(fingerprint=fingerprint(x),request=x));phase('checking');log('')
    status('Checking compatible CRAN packages and required dependencies. Nothing is being installed…')
    job$start('plan',packages=x$packages);later::later(function() shiny::withReactiveDomain(session,shiny::isolate(tryCatch(poll(),error=fail))),.2)
    invisible(TRUE)
  },error=fail)}
  shiny::observeEvent(input$r_pkg_check,check())
  shiny::observeEvent(input$r_pkg_decline,{if(identical(phase(),'approval')) clear('Installation cancelled. No packages were installed.')})
  shiny::observeEvent(input$r_pkg_approve,tryCatch({
    if(phase() %in% c('checking','installing')) {status('The current package operation is already running. Use Stop to cancel.');return()}
    p<-pending()
    if(!identical(phase(),'approval') || is.null(p) || is.null(p$plan)) stop('Check packages and review the list before approving installation.')
    if(blocked()) stop('Stop the running analysis before installing packages.')
    if(!identical(p$fingerprint,fingerprint(request()))) stop('The draft changed. Check packages and approve the new list.')
    pc_pkg_validate_plan(p$plan);p$plan$approved_at<-as.numeric(Sys.time())
    pending(NULL);shiny::removeModal();phase('installing');status('Installing the approved packages. You can stop this operation.');log('')
    job$start('install',plan=p$plan);later::later(function() shiny::withReactiveDomain(session,shiny::isolate(tryCatch(poll(),error=fail))),.2)
  },error=fail))
  cancel<-function() {result<-if(job$busy()) job$cancel() else NULL;clear(if(is.null(result)) 'Package operation cancelled. Nothing was installed.' else result$message);if(!is.null(result$log)) log(result$log)}
  reset<-function() {job$cleanup();clear();log('')}
  output$r_pkg_log<-shiny::renderText(log())
  session$onSessionEnded(job$cleanup)
  list(check=check,cancel=cancel,reset=reset,busy=shiny::reactive(phase() %in% c('checking','installing')),phase=phase,pending=pending)
}
