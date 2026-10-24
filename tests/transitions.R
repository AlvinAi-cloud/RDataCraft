app<-source("app.R")$value
checks<-0L
check<-function(ok,label){if(!isTRUE(ok))stop("FAIL: ",label,call.=FALSE);checks<<-checks+1L;cat("PASS:",label,"\n")}
shiny::testServer(app,{
  # Explicit fixture: production startup is intentionally empty.
  raw(pc_example("column")$table);sheet_name("Treatment groups");project_name("Example study");document_open(TRUE)
 do.call(session$setInputs,pc_defaults());session$flushReact()
 session$setInputs(worksheet_layout="grouped",worksheet_name="Grouped",worksheet_example=TRUE,confirm_worksheet=1);session$flushReact()
 session$setInputs(layout="grouped",method="",graph="");session$flushReact()
 check(settings()$method=="twoway" && settings()$graph=="groupbar","empty controls during a switch retain authoritative grouped settings")
 check(normalized()$layout=="grouped" && is.null(analysis_state()$error),"new grouped observations never use the previous table contract")
 session$setInputs(worksheet_layout="contingency",worksheet_name="Counts",worksheet_example=TRUE,confirm_worksheet=2);session$flushReact()
 session$setInputs(layout="contingency",method="",graph="");session$flushReact()
 check(settings()$method=="fisher" && normalized()$layout=="contingency","rapid switch to counts retains the contingency contract")
 check(workbook()$D2$settings$layout=="grouped" && workbook()$D3$settings$layout=="contingency","incomplete client updates cannot corrupt inactive worksheet formats")
 # A delayed selection event from the previous dropdown followed by the intended target.
 session$setInputs(worksheet="D2");session$flushReact()
 session$setInputs(worksheet="D3");session$flushReact()
 target<-restoring_settings();do.call(session$setInputs,target);session$flushReact()
 check(is.null(restoring_settings()) && settings()$method=="fisher","acknowledged controls return to normal live editing")
 pc_write_project(snapshot(),"artifacts/views/transition.rdatacraft")
 p<-pc_load_project("artifacts/views/transition.rdatacraft")
 check(p$worksheets$D2$settings$layout=="grouped" && p$worksheets$D3$settings$method=="fisher","rapid-switch project saves and reopens with valid worksheet contracts")
 session$setInputs(worksheet_layout="survival",worksheet_name="Blank survival",worksheet_example=FALSE,confirm_worksheet=3);session$flushReact()
 target<-restoring_settings();do.call(session$setInputs,target);session$flushReact()
 pc_write_project(snapshot(),"artifacts/views/blank-survival.rdatacraft")
 check(nrow(pc_load_project("artifacts/views/blank-survival.rdatacraft")$table)==1,"blank survival templates save without invalid group identifiers")
})
cat("\n",checks," transition integrity checks passed.\n",sep="")
