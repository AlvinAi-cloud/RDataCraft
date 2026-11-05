app<-source('app.R')$value
checks<-0L
check<-function(x,label) {if(!isTRUE(x)) stop('FAIL: ',label);checks<<-checks+1L;cat('PASS:',label,'\n')}
fails<-function(x) inherits(tryCatch(force(x),error=identity),'error')
check(pc_update_newer('v0.6','0.5') && !pc_update_newer('0.6','0.6'),'v0.6 upgrades v0.5 while the current version is not offered as its own update')
check(pc_update_newer('v0.5','0.42') && pc_update_newer('0.42','0.41'),'update ordering respects the project’s historical decimal release numbers')
check(!pc_update_newer('0.41','0.5') && !pc_update_newer('0.5','0.5'),'older and matching releases are not offered as upgrades')
check(pc_update_newer('0.5.1','0.5') && pc_update_newer('1.0','0.99'),'patch and major updates compare correctly')
check(fails(pc_update_version('v0.5/../../malicious')) && fails(pc_update_version('v0.5-beta')),'untrusted and prerelease version paths are rejected')
platforms<-c('macos-x86_64'='RDataCraft-macos-x86_64.dmg','macos-arm64'='RDataCraft-macos-arm64.dmg','windows-x64'='RDataCraft-windows-x64-setup.exe','ubuntu-amd64'='RDataCraft-ubuntu-amd64.deb')
value<-list(tag_name='v0.5',draft=FALSE,prerelease=FALSE,assets=lapply(platforms,function(name) list(name=name,browser_download_url=paste0('https://github.com/AlvinAi-cloud/RDataCraft/releases/download/v0.5/',name),state='uploaded',size=1000)))
for(platform in names(platforms)) {r<-pc_update_release(value,'0.42',platform);check(r$newer && identical(r$asset$name,unname(platforms[platform])),paste(platform,'selects only its matching platform installer'))}
bad<-value;bad$assets[[1]]$browser_download_url<-'https://example.invalid/RDataCraft-macos-x86_64.dmg'
check(is.null(pc_update_release(bad,'0.42','macos-x86_64')$asset),'a substituted download origin is never presented as an installer')
bad<-value;bad$draft<-TRUE;check(fails(pc_update_release(bad,'0.42')),'draft releases cannot be offered for updates')
check(is.null(pc_update_release(value,'0.42','unknown')$asset),'unknown platforms use the release page instead of a guessed installer')
check(pc_update_platform('Darwin','aarch64')=='macos-arm64' && pc_update_platform('Linux','x86_64')=='ubuntu-amd64','platform selection distinguishes Apple Silicon and Ubuntu')
html<-as.character(pc_assistant_ui());check(!grepl('id="assistant_connection"',html,fixed=TRUE),'AI panel has no Accounts and Models button; the native AI menu remains the access point')
shiny::testServer(app,{
 do.call(session$setInputs,pc_defaults());session$flushReact();before<-raw()
 check(grepl('Nothing is installed automatically',output$update_result$html,fixed=TRUE) && identical(raw(),before),'update UI leaves observations untouched and describes explicit installation')
})
cat(checks,'update and assistant UI checks passed.\n')
