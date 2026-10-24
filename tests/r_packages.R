app<-source('app.R')$value
checks<-0L
check<-function(x,label) {if(!isTRUE(x)) stop('FAIL: ',label,call.=FALSE);checks<<-checks+1L;cat('PASS:',label,'\n')}
fails<-function(expr) inherits(tryCatch(force(expr),error=identity),'error')
base<-normalizePath('artifacts',winslash='/',mustWork=TRUE);fixture<-file.path(base,'package-approval-fixtures');dir.create(fixture,showWarnings=FALSE)
user<-tempfile('personal-library-',tmpdir=fixture);original_env<-Sys.getenv('RDATACRAFT_USER_LIBRARY',unset=NA_character_);Sys.setenv(RDATACRAFT_USER_LIBRARY=user)
restore_env<-function() {if(is.na(original_env)) Sys.unsetenv('RDATACRAFT_USER_LIBRARY') else Sys.setenv(RDATACRAFT_USER_LIBRARY=original_env)}
original_paths<-.libPaths()
needed<-pc_pkg_requirements('library(rdatacraftfixture);requireNamespace("stats");f<-function(x,y=1) x+y; z <- ggplot2::ggplot(data); data[,1]','utils')
check(all(c('utils','rdatacraftfixture','stats','ggplot2') %in% needed),'package discovery parses literal library and namespace use without running code')
check(!dir.exists(user) && !'rdatacraftfixture' %in% loadedNamespaces(),'checking requirements does not create a library or load missing packages')
check(!pc_pkg_script_info('message("install.packages(ignored)")')$installs && pc_pkg_script_info('utils::install.packages("x")')$installs,'installation detection distinguishes code from quoted text')
check(fails(pc_r_script('install.packages("x");result<-list()')) && fails(pc_r_script('BiocManager::install("x")')),'analysis scripts direct package installation to the separate approval workflow')
check(fails(pc_r_packages('https://example.com/code.R')) && fails(pc_r_packages('../anything')),'package requests accept names rather than arbitrary URLs or paths')
# Build two original pure-R binary fixtures locally; no external packages are installed.
installed<-file.path(fixture,'build-library');dir.create(installed,showWarnings=FALSE)
make_package<-function(name,imports='',code) {
 src<-file.path(fixture,'source',name);dir.create(file.path(src,'R'),recursive=TRUE,showWarnings=FALSE)
 writeLines(c(paste('Package:',name),'Version: 0.0.1','Title: Original RDataCraft Package Approval Test Fixture','Description: Original, local-only package used by the RDataCraft test suite.','Author: RDataCraft contributors','Maintainer: RDataCraft Test <test@example.invalid>','License: GPL-3','Encoding: UTF-8',if(nzchar(imports)) paste('Imports:',imports)),file.path(src,'DESCRIPTION'))
 writeLines('export(plus)',file.path(src,'NAMESPACE'));writeLines(code,file.path(src,'R/plus.R'))
 engine<-file.path(R.home('bin'),if(.Platform$OS.type=='windows') 'R.exe' else 'R')
 run<-processx::run(engine,c('CMD','INSTALL','--build',paste0('--library=',installed),src),wd=fixture,error_on_status=FALSE)
 if(run$status!=0) stop(paste(run$stdout,run$stderr))
 archives<-list.files(fixture,pattern=paste0('^',name,'_0.0.1.*\\.(tgz|zip|tar.gz)$'),full.names=TRUE)
 if(!length(archives)) stop('Local fixture binary was not produced.')
 archives[1]
}
dep_archive<-make_package('rdatacraftfixturedep',code='plus <- function(x) x + 7')
root_archive<-make_package('rdatacraftfixture','rdatacraftfixturedep (>= 0.0.1)',code='plus <- function(x) rdatacraftfixturedep::plus(x) * 2')
fields<-c('Package','Version','Depends','Imports','LinkingTo','License','MD5sum')
db<-matrix(NA_character_,2,length(fields),dimnames=list(c('rdatacraftfixture','rdatacraftfixturedep'),fields))
db[,'Package']<-rownames(db);db[,'Version']<-'0.0.1';db[,'License']<-'GPL-3';db['rdatacraftfixture','Imports']<-'rdatacraftfixturedep (>= 0.0.1)';db[,'MD5sum']<-unname(tools::md5sum(c(root_archive,dep_archive)))
plan<-pc_pkg_plan('rdatacraftfixture',db)
check(identical(vapply(plan$packages,function(p)p$name,character(1)),c('rdatacraftfixturedep','rdatacraftfixture')),'approval plan includes required dependencies in install order')
check(all(vapply(plan$packages,function(p) nzchar(p$md5),logical(1))) && identical(plan$library,pc_pkg_library()),'approval identifies exact versions, archive checksums and personal install location')
check(!dir.exists(user),'planning a complete dependency list does not create or change the personal library')
old<-pc_pkg_installed();old<-rbind(old,old[1,,drop=FALSE]);rownames(old)[nrow(old)]<-'rdatacraftfixturedep';old[nrow(old),'Package']<-'rdatacraftfixturedep';old[nrow(old),'Version']<-'0.0.0'
updated<-pc_pkg_plan('rdatacraftfixture',db,installed=old)
check(updated$packages[[1]]$previous=='0.0.0','required dependency upgrades disclose the existing version')
conflict<-db[c(1,1,2),,drop=FALSE];rownames(conflict)<-c('rdatacraftfixture','rdatacraftfixtureother','rdatacraftfixturedep');conflict[2,'Package']<-'rdatacraftfixtureother';conflict[2,'Imports']<-'rdatacraftfixturedep (< 0.0.1)'
check(fails(pc_pkg_plan(c('rdatacraftfixture','rdatacraftfixtureother'),conflict,installed=old)),'selected dependency versions must satisfy every requested package, including installed lower versions')
stale<-plan;stale$created<-as.numeric(Sys.time())-901
check(fails(pc_pkg_validate_plan(stale)),'expired approval plans cannot start installation')
bad<-plan;bad$packages[[1]]$url<-'https://example.com/anything'
check(fails(pc_pkg_validate_plan(bad)),'approval cannot be reused for an unreviewed repository or archive')
bad<-plan;bad$library<-tempdir();check(fails(pc_pkg_validate_plan(bad)),'approval cannot change its install destination')
fetch<-function(url,dest) {source<-if(grepl('rdatacraftfixturedep_',url,fixed=TRUE)) dep_archive else root_archive;stopifnot(file.copy(source,dest,overwrite=TRUE))}
check(fails(pc_pkg_install(plan,'fixture-unapproved',fetch=fetch)) && !dir.exists(user),'an unresolved approval cannot directly enter the installer')
plan$approved_at<-as.numeric(Sys.time())
receipt<-pc_pkg_install(plan,'fixture-approved',fetch=fetch)
check(receipt$status=='success' && file.exists(file.path(user,'rdatacraftfixture','DESCRIPTION')),'approved binary fixtures install into the personal library')
pc_pkg_recover(plan,'fixture-approved')
check(identical(.libPaths(),original_paths) && !'rdatacraftfixture' %in% loadedNamespaces(),'installation leaves app library order and loaded app namespaces unchanged')
record<-pc_r_record('Use approved add-on','result<-list(tables=list(Check=data.frame(Value=rdatacraftfixture::plus(3))))','',pc_example('column')$table,'Fixture input')
runner<-pc_r_runner();runner$start(record);repeat {Sys.sleep(.05);result<-runner$poll();if(!is.null(result)) break}
check(result$result$status=='success' && as.numeric(pc_read_text(result$result$tables[[1]]$data_tsv,'\t')$Value)==20,'a new Advanced R worker uses approved add-on packages without an app restart')
check(any(vapply(result$result$packages,function(p) p$name=='rdatacraftfixture' && p$version=='0.0.1',logical(1))),'analysis results retain the installed add-on version')
# A changed download cannot replace a working installed package.
bad<-plan;bad$packages[[1]]$md5<-paste(rep('0',32),collapse='')
check(fails(pc_pkg_install(bad,'fixture-bad-download',fetch=fetch)) && file.exists(file.path(user,'rdatacraftfixture','DESCRIPTION')),'failed or changed downloads do not replace existing packages')
check(!dir.exists(pc_pkg_transaction(bad,'fixture-bad-download')$lock),'failed installation releases its own transaction lock')
# Simulate termination midway through promotion: restore an old package, remove only a new one.
transaction<-pc_pkg_transaction(plan,'fixture-rollback');dir.create(transaction$lock);writeLines('fixture-rollback',file.path(transaction$lock,'owner'));dir.create(file.path(transaction$stage,'backup'),recursive=TRUE);dir.create(file.path(transaction$stage,'library'))
name<-plan$packages[[1]]$name;stopifnot(file.rename(file.path(user,name),file.path(transaction$stage,'backup',name)));dir.create(file.path(user,name));writeLines('new',file.path(user,name,'temporary'))
# The second package is still staged, so it must remain untouched by recovery.
file.copy(file.path(user,'rdatacraftfixture'),file.path(transaction$stage,'library'),recursive=TRUE)
file.create(file.path(transaction$stage,'promoting'));pc_pkg_recover(plan,'fixture-rollback')
check(file.exists(file.path(user,name,'DESCRIPTION')) && !file.exists(file.path(user,name,'temporary')),'interrupted promotion restores the previous working package')
transaction<-pc_pkg_transaction(plan,'fixture-retry');dir.create(transaction$lock);writeLines('fixture-retry',file.path(transaction$lock,'owner'))
dir.create(file.path(transaction$stage,'restoring'),recursive=TRUE);dir.create(file.path(transaction$stage,'library'))
file.create(file.path(transaction$stage,'promoting'));file.create(file.path(transaction$stage,'restoring',name))
file.copy(file.path(user,'rdatacraftfixture'),file.path(transaction$stage,'library'),recursive=TRUE)
dir.create(file.path(transaction$lock,'recovering'))
check(fails(pc_pkg_recover(plan,'fixture-retry')) && file.exists(file.path(user,name,'DESCRIPTION')),'a concurrent recovery claim prevents a second caller from changing packages')
unlink(file.path(transaction$lock,'recovering'),recursive=TRUE);pc_pkg_recover(plan,'fixture-retry')
check(file.exists(file.path(user,name,'DESCRIPTION')) && !dir.exists(transaction$lock),'retrying a partially completed rollback preserves an already restored package')
# Recorded crash recovery must never remove a transaction owned by a live worker.
transaction<-pc_pkg_transaction(plan,'fixture-crash');dir.create(transaction$lock);writeLines('fixture-crash',file.path(transaction$lock,'owner'))
metadata<-list(id='fixture-crash',library=user,packages=lapply(plan$packages,function(p) list(name=p$name)),pid=Sys.getpid(),started=as.numeric(ps::ps_create_time(ps::ps_handle())))
jsonlite::write_json(metadata,file.path(transaction$lock,'transaction.json'),auto_unbox=TRUE)
check(fails(pc_pkg_recover_stale(user)) && dir.exists(transaction$lock),'crash recovery leaves a live installer and its lock untouched')
dir.create(file.path(transaction$stage,'backup'),recursive=TRUE);dir.create(file.path(transaction$stage,'library'))
stopifnot(file.rename(file.path(user,name),file.path(transaction$stage,'backup',name)));dir.create(file.path(user,name));writeLines('incomplete',file.path(user,name,'temporary'));file.copy(file.path(user,'rdatacraftfixture'),file.path(transaction$stage,'library'),recursive=TRUE);file.create(file.path(transaction$stage,'promoting'))
metadata$started<-metadata$started-100 # Simulate the OS reusing an ended owner's PID.
jsonlite::write_json(metadata,file.path(transaction$lock,'transaction.json'),auto_unbox=TRUE)
pc_pkg_recover_stale(user)
check(file.exists(file.path(user,name,'DESCRIPTION')) && !file.exists(file.path(user,name,'temporary')) && !dir.exists(transaction$lock),'an ended owner or reused PID recovers old packages and releases the stale lock')
dir.create(transaction$lock)
check(fails(pc_pkg_recover_stale(user)) && dir.exists(transaction$lock),'unrecognized recovery locks are preserved for review')
unlink(transaction$lock,recursive=TRUE)
# Consent state is tested with a fake metadata/installer transport; no network or actual install.
probe<-new.env(parent=emptyenv());probe$started<-character();probe$active<-FALSE;probe$result<-NULL
fake<-list(start=function(action,packages=NULL,plan=NULL){probe$started<-c(probe$started,action);probe$active<-TRUE;probe$result<-if(action=='plan') list(status='planned',plan=updated) else list(status='success',message='Approved fixture installation complete.')},poll=function(){x<-probe$result;probe$result<-NULL;probe$active<-FALSE;x},log=function()'',busy=function()probe$active,cancel=function(){probe$active<-FALSE;list(status='cancelled',message='Stopped fixture operation.')},cleanup=function(){probe$active<-FALSE})
wrapper<-function(input,output,session) {
 scope<-shiny::reactiveVal(list(code='result<-list()',packages='RDataCraftNotInstalledFixture'))
 status<-shiny::reactiveVal('');manager<-pc_pkg_server(input,output,session,request=function()scope(),blocked=function()FALSE,status=status,job=fake)
}
flush_later<-function(session) {for(i in 1:10) {Sys.sleep(.05);later::run_now(0);session$flushReact()}}
shiny::testServer(wrapper,{
 session$setInputs(r_pkg_approve=1);session$flushReact();check(!length(probe$started),'an approval event without a reviewed plan cannot install')
 session$setInputs(r_pkg_check=1);flush_later(session)
 check(manager$phase()=='approval' && identical(probe$started,'plan'),'metadata resolution stops at approval without installing anything')
 session$setInputs(r_pkg_decline=1);session$flushReact();check(is.null(manager$pending()) && !'install' %in% probe$started,'Cancel clears the pending approval without installation')
 session$setInputs(r_pkg_approve=2);session$flushReact();check(!'install' %in% probe$started,'a cancelled approval cannot be reused')
 session$setInputs(r_pkg_check=2);flush_later(session);scope(list(code='result<-list(text="changed")',packages='OtherFixture'))
 session$setInputs(r_pkg_approve=3);session$flushReact();check(!'install' %in% probe$started,'changing the script invalidates approval for the earlier package list')
 session$setInputs(r_pkg_check=3);flush_later(session);session$setInputs(r_pkg_approve=4);session$flushReact()
 session$setInputs(r_pkg_approve=5);session$flushReact();check(manager$phase()=='installing' && manager$busy() && sum(probe$started=='install')==1,'duplicate clicks during installation preserve the running job and Stop control')
 session$setInputs(r_pkg_decline=2);session$flushReact();check(manager$phase()=='installing','an old Cancel button cannot silently orphan an approved installation')
 flush_later(session)
 check(sum(probe$started=='install')==1 && manager$phase()=='idle','explicit approval starts exactly one installation job and does not start an analysis')
 session$setInputs(r_pkg_approve=6);session$flushReact();check(sum(probe$started=='install')==1,'duplicate approval clicks cannot repeat an installation')
})
restore_env();check(identical(.libPaths(),original_paths),'app library configuration remains unchanged after all package operations')
cat(checks,'approved package installation checks passed.\n')
