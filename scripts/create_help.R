# Build an offline guide from the same content as the in-app Help center.
source('app.R')
topics<-pc_help_topics()
sections<-lapply(names(topics),function(id) shiny::tags$section(id=id,pc_help_body(id)))
page<-shiny::tags$html(lang='en',
 shiny::tags$head(shiny::tags$meta(charset='UTF-8'),shiny::tags$title('RDataCraft help'),
  shiny::tags$meta(name='viewport',content='width=device-width, initial-scale=1'),
  shiny::tags$style('body{font:16px/1.7 system-ui,sans-serif;color:#25332d;background:#fafcfb;max-width:900px;margin:40px auto;padding:0 24px}a{color:#247763}h1,h2,h3{line-height:1.3}section{border-top:1px solid #d4dfda;margin-top:32px;padding-top:20px}li{margin-bottom:8px}pre,code{overflow-wrap:anywhere}.inline-note{border-left:4px solid #247763;padding:12px;background:#eff5f1}'),
  ),
 shiny::tags$body(shiny::h1('RDataCraft help · v0.3'),
  shiny::p('Offline instructions for data entry, analysis and figures. In the app, Help provides search and access to the teaching examples.'),
  shiny::tags$nav(shiny::tags$ul(lapply(names(topics),function(id) shiny::tags$li(shiny::tags$a(href=paste0('#',id),topics[[id]]$title))))),
  sections))
writeLines(c('<!doctype html>',as.character(page)),'examples/RDataCraft help.html',useBytes=TRUE)
