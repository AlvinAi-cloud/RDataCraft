app<-source('app.R')$value
checks<-0L
check<-function(x,label) {if(!isTRUE(x)) stop('FAIL: ',label,call.=FALSE);checks<<-checks+1L;cat('PASS:',label,'\n')}
topics<-pc_help_topics()
check(length(topics)>=11 && !anyDuplicated(vapply(topics,function(t)t$title,character(1))),'help provides distinct task-oriented topics')
for(id in names(topics)) check(nchar(as.character(pc_help_body(id)))>200,paste(id,'help renders offline instructions'))
check('tables' %in% pc_help_matches('paste') && 'pca' %in% pc_help_matches('PCA'),'help search finds pasting and PCA')
check(identical(pc_help_matches('package recovery'),'recovery'),'help search matches multiple words without evaluating regular expressions')
check(!length(pc_help_matches('no-such-help-topic')) && !length(pc_help_matches('[')),'unmatched and special-character searches return no results safely')
check(length(pc_help_matches(''))==length(topics),'clearing help search restores all topics')
shiny::testServer(app,{
 do.call(session$setInputs,pc_defaults());session$flushReact()
 before<-raw();was_open<-document_open()
 session$setInputs(show_help=list(nonce=1),help_topic='tables',help_search='paste');session$flushReact()
 check(grepl('top-left destination cell',output$help_content$html,fixed=TRUE),'Help displays direct grid-paste instructions')
 check(identical(raw(),before) && identical(document_open(),was_open),'opening and searching Help does not create a study or alter observations')
 session$setInputs(help_search='no-such-help-topic');session$flushReact()
 check(grepl('No matching topics',output$help_content$html,fixed=TRUE),'Help displays a useful empty-search message')
 session$setInputs(help_search='',help_topic='advanced');session$flushReact()
 check(grepl('Approve &amp; install',output$help_content$html,fixed=TRUE) && grepl('not an operating-system security sandbox',output$help_content$html,fixed=TRUE),'Advanced R help retains package approval and code-permission guidance')
})
cat(checks,'Help checks passed.\n')
