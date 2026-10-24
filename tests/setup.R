source("app.R")
dir.create("artifacts/tests",recursive=TRUE,showWarnings=FALSE)
pc_write_project(pc_project(pc_example("column")$table,pc_defaults()),"artifacts/tests/project.json")
