# Original count-design example and review-only drafts; no script executes here.
source('app.R')
counts<-pc_check_table(data.frame(Response=c(2,3,5,7,4,5,8,9,3,4,6,8),Treatment=rep(c('A','B'),each=6),Batch=rep(c('X','Y'),6)))
s<-pc_defaults();s$layout<-'multiple';s$method<-'descriptive';s$graph<-'variables';s$show_p<-FALSE;s$title<-'Count design for a custom GLM'
columns<-pc_example('column')$table;sc<-pc_defaults();sc$method<-'descriptive';sc$show_p<-FALSE
book<-list(D1=pc_sheet(counts,s,'Count design'),D2=pc_sheet(columns,sc,'Independent groups'))
templates<-pc_r_templates()
records<-list(pc_r_record(templates$glm$title,templates$glm$code,'stats',counts,'Count design'),pc_r_record(templates$summary$title,templates$summary$code,'',columns,'Independent groups'),pc_r_record(templates$wilcoxon$title,templates$wilcoxon$code,'stats',columns,'Independent groups'))
pc_write_project(pc_project(counts,s,book,study_name='Advanced R teaching example',r_analyses=records),'examples/Advanced R teaching example.rdatacraft')
stopifnot(length(pc_load_project('examples/Advanced R teaching example.rdatacraft')$r_analyses)==3)
write.csv(counts,'examples/Advanced R count example.csv',row.names=FALSE)
page<-htmltools::tags$html(htmltools::tags$head(htmltools::tags$title('RDataCraft v0.33 — Advanced R analysis guide'),htmltools::tags$meta(charset='utf-8'),htmltools::tags$style('body{font:16px system-ui;line-height:1.65;max-width:880px;margin:40px auto;padding:0 24px;color:#263b32}h1,h2,h3{color:#247763}.inline-note{background:#f1f5f2;padding:16px}li{margin-bottom:12px}')),
 htmltools::tags$body(htmltools::tags$h1('RDataCraft v0.33'),pc_r_help(),htmltools::tags$h3('Numeric P labels and significance stars'),htmltools::tags$p('Graph settings offers numeric P labels (four significant digits, with P < 10⁻⁶ below one millionth) or significance stars: ns for P > 0.05; * for P ≤ 0.05; ** for P ≤ 0.01; *** for P ≤ 0.001; **** for P ≤ 0.0001. Multiple-comparison labels use adjusted P values. These are display choices and do not change the analysis.')))
htmltools::save_html(page,'examples/Advanced R analysis guide.html')
cat('Created Advanced R example, CSV and guide. No custom code executed.\n')
