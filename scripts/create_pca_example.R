# Original synthetic PCA teaching data, a reusable study and a readable guide.
source('app.R')
e<-pc_tutorial('pca');n<-pc_normalize(e$table,'multiple');z<-pc_pca(n,e$settings)
layout<-pc_layout_defaults();layout$selected<-paste0('D1:',names(e$views));layout$columns<-2
layout$width<-180;layout$height<-160;layout$title<-'PCA: samples, variables and explained variance'
project<-pc_project(e$table,e$settings,list(D1=pc_sheet(e$table,e$settings,e$name,e$views)),
  figure_layout=layout,study_name='PCA teaching example')
pc_write_project(project,'examples/PCA teaching example.rdatacraft')
write.csv(e$table,'examples/PCA teaching data.csv',row.names=FALSE)
page<-htmltools::tags$html(htmltools::tags$head(htmltools::tags$title('RDataCraft PCA analysis guide'),
  htmltools::tags$meta(charset='utf-8'),htmltools::tags$style('body{font:16px system-ui;line-height:1.65;max-width:880px;margin:40px auto;padding:0 24px;color:#263b32}h1,h2,h3,h4{color:#247763}li{margin-bottom:12px}.inline-note{background:#f1f5f2;padding:16px}')),
  htmltools::tags$body(htmltools::tags$h1('RDataCraft 0.3 · PCA analysis guide'),pc_tutorial_guide(e$guide),
  htmltools::tags$h3('Reference values for the supplied synthetic data'),
  htmltools::tags$p(sprintf('With all five measurements centered and SD-scaled, PC1 explains %.4f%% and PC2 %.4f%% of variation; together they explain %.4f%%. All 12 samples are included. These percentages describe this invented dataset, not general biological expectations.',z$scree$variance_percent[1],z$scree$variance_percent[2],sum(z$scree$variance_percent[1:2])))))
htmltools::save_html(page,'examples/PCA analysis guide.html')
cat('Created PCA teaching study, CSV and HTML guide.\n')
