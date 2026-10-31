# Presentation only: preserve complete analysis objects and export precision.
pc_curve_results <- function(result, normalized, settings) {
  models <- c("linear", "fourpl", unname(pc_regression_methods()))
  if (is.null(result) || normalized$layout != "xy" || !settings$method %in% models) return(NULL)
  series <- if (identical(settings$fit_scope, "all")) normalized$groups else settings$group1
  status <- if (is.null(result$fit_status)) data.frame(series=series,status="Fitted",detail="") else result$fit_status
  series <- as.character(status$series)
  parameters <- result$parameters
  rows <- list()
  number <- function(x) if (length(x)!=1L || !is.finite(x)) NA_real_ else unname(x)
  get_parameter <- function(group, name, field="estimate") {
    if (is.null(parameters) || !field %in% names(parameters)) return(NA_real_)
    p <- parameters
    if ("series" %in% names(p)) p <- p[p$series==group,,drop=FALSE]
    number(p[p$parameter==name,field])
  }
  add <- function(label, fun, ci=NULL, se=FALSE) {
    rows[[length(rows)+1L]] <<- list(label=label,se=se,cells=lapply(series,function(group) {
      if (!identical(as.character(status$status[match(group,status$series)]),"Fitted")) return(list(value=NA_real_,ci=NULL))
      list(value=number(fun(group)),ci=if(is.null(ci)) NULL else ci(group))
    }))
  }
  if (identical(settings$method,"fourpl")) {
    add("Bottom",function(g) get_parameter(g,"bottom"))
    add("Top",function(g) get_parameter(g,"bottom")+exp(get_parameter(g,"logSpan")))
    add("EC50",function(g) 10^get_parameter(g,"logEC50"),function(g) 10^c(get_parameter(g,"logEC50","ci_low"),get_parameter(g,"logEC50","ci_high")))
    # nls fits log10(EC50). Convert its SE to the EC50 scale by the delta method.
    add("SE of EC50",function(g) log(10)*10^get_parameter(g,"logEC50")*get_parameter(g,"logEC50","se"),se=TRUE)
    add("Hill coefficient",function(g) get_parameter(g,"hill"),function(g) c(get_parameter(g,"hill","ci_low"),get_parameter(g,"hill","ci_high")))
    add("SE of Hill coefficient",function(g) get_parameter(g,"hill","se"),se=TRUE)
  } else if (!is.null(parameters)) {
    labels <- c("(Intercept)"="Intercept","x"="Slope","I(x^2)"="Quadratic coefficient","I(x^3)"="Cubic coefficient","log(x)"="Log coefficient")
    for (key in unique(as.character(parameters$parameter))) local({
      name <- key; label <- if(name %in% names(labels)) unname(labels[name]) else name
      add(label,function(g) get_parameter(g,name),function(g) c(get_parameter(g,name,"ci_low"),get_parameter(g,name,"ci_high")))
    })
  }
  diagnostics <- function(group) {
    z <- result$diagnostics
    if (!is.null(z) && "series" %in% names(z)) z <- z[z$series==group,,drop=FALSE]
    z
  }
  add("R²",function(g) {
    z <- diagnostics(g); if(is.null(z) || !nrow(z)) return(NA_real_)
    sst <- sum((z$observed-mean(z$observed))^2)
    if(sst==0) NA_real_ else 1-sum(z$residual^2)/sst
  })
  # Keep the existing engine's residual-SD definition, including weighting.
  add("Residual SD",function(g) {
    m <- result$metrics; if("series" %in% names(m)) m <- m[m$series==g,,drop=FALSE]
    value <- m$value[m$measure %in% c("Residual SD","RMSE (original Y scale)")]
    if(length(value)==1L) return(suppressWarnings(as.numeric(value)))
    z <- diagnostics(g); p <- parameters
    if(!is.null(p) && "series" %in% names(p)) p <- p[p$series==g,,drop=FALSE]
    df <- if(is.null(z) || is.null(p)) 0 else nrow(z)-nrow(p)
    if(df>0) sqrt(sum(z$residual^2)/df) else NA_real_
  })
  add("Observations (n)",function(g) sum(normalized$data$group==g))
  if (identical(settings$fit_replicates,"mean")) add("Fitted points (n)",function(g) nrow(diagnostics(g)))
  list(series=series,status=status,rows=rows,fourpl=identical(settings$method,"fourpl"))
}

pc_analysis_results_ui <- function(result, normalized, settings) {
  display <- pc_curve_results(result,normalized,settings)
  if (is.null(display)) {
    m <- result$metrics
    return(shiny::tags$table(class="table shiny-table table-spacing-m",shiny::tags$tbody(lapply(seq_len(nrow(m)),function(i) shiny::tags$tr(lapply(m[i,,drop=FALSE],shiny::tags$td))))))
  }
  fmt <- function(x) if(length(x)!=1L || !is.finite(x)) "—" else format(signif(x,4),trim=TRUE,scientific=abs(x)>=1e6 || (x!=0 && abs(x)<1e-4))
  shiny::tagList(
    shiny::div(class="curve-results-scroll",role="region",tabindex="0",`aria-label`="Results by fitted curve; scroll horizontally to compare series",
      shiny::tags$table(class="table shiny-table curve-results-table",
        shiny::tags$thead(shiny::tags$tr(shiny::tags$th(scope="col","Parameter / measure"),lapply(seq_along(display$series),function(i) {
          state <- display$status[i,]
          shiny::tags$th(scope="col",shiny::span(class="curve-series-name",display$series[i]),
            shiny::span(class=if(state$status=="Fitted") "curve-fit-status" else "curve-fit-failed",state$status),
            if(state$status!="Fitted") shiny::span(class="curve-fit-reason",state$detail))
        }))),
        shiny::tags$tbody(lapply(display$rows,function(row) shiny::tags$tr(class=if(row$se) "curve-se-row" else NULL,
          shiny::tags$th(scope="row",row$label,if(any(vapply(row$cells,function(x) !is.null(x$ci),logical(1)))) shiny::span(class="curve-ci-label","Estimate · 95% CI")),
          lapply(row$cells,function(cell) shiny::tags$td(shiny::span(class="curve-estimate",fmt(cell$value)),
            if(!is.null(cell$ci)) shiny::span(class="curve-ci",if(length(cell$ci)==2L && all(is.finite(cell$ci))) paste(vapply(cell$ci,fmt,character(1)),collapse=" to ") else "CI unavailable")))))))),
    if(display$fourpl) shiny::p(class="curve-results-note","SE = standard error. EC50 is on the entered X scale; no concentration unit is inferred. Hill coefficient uses the model’s natural-logistic scale; EC50 SE is a delta-method approximation."))
}

# CSV cells retain numerical precision; display rounding is applied only in HTML.
pc_export_cell <- function(x) {
  if(length(x)!=1L || is.na(x)) return("")
  if(is.numeric(x)) return(if(is.finite(x)) sprintf("%.17g",x) else "")
  as.character(x)
}

pc_analysis_results_csv <- function(result, normalized, settings) {
  d <- pc_curve_results(result,normalized,settings)
  if(is.null(d)) return(result$metrics)
  labels <- "Fit status"
  cells <- list(as.character(d$status$status))
  for(row in d$rows) {
    labels <- c(labels,row$label)
    cells[[length(cells)+1L]] <- vapply(row$cells,function(x) pc_export_cell(x$value),character(1))
    if(any(vapply(row$cells,function(x) !is.null(x$ci),logical(1)))) {
      for(i in 1:2) {
        labels <- c(labels,paste(row$label,"95% CI",c("lower","upper")[i]))
        cells[[length(cells)+1L]] <- vapply(row$cells,function(x) pc_export_cell(if(length(x$ci)==2L) x$ci[i] else NA_real_),character(1))
      }
    }
  }
  out <- data.frame(Measure=labels,do.call(rbind,cells),check.names=FALSE,stringsAsFactors=FALSE)
  names(out) <- c("Parameter / measure",d$series)
  # Reasons for failed fits belong in the CSV as well as the visible column headers.
  if(any(d$status$status!="Fitted")) out[nrow(out)+1L,] <- c("Fit detail",as.character(d$status$detail))
  out
}

pc_result_labels <- function(keys) {
  labels <- c(group="Group / series",condition="Factor level",category="Category",n="Observations (n)",
    mean="Mean",sd="SD",sem="SE of mean",median="Median",ci_low="95% CI lower",ci_high="95% CI upper",
    median_ci_low="Median 95% CI lower",median_ci_high="Median 95% CI upper",median_followup="Median observed time",
    events="Events",censored="Censored",x_min="Minimum X",x_max="Maximum X",auc="AUC",W="Shapiro–Wilk W",
    status="Status",total="Total",group1="First group",group2="Second group",estimate="Estimate",
    p="P value",p_raw="Unadjusted P value",significance="Significance",effect="Effect",df="Degrees of freedom",
    sum_squares="Sum of squares",mean_square="Mean square",F="F statistic",parameter="Coefficient",
    se="Standard error",series="Series",detail="Detail",time="Time",at_risk="At risk",survival="Survival probability",
    x="X",observed="Observed Y",fitted="Fitted Y",residual="Residual",weight="Weight")
  ifelse(keys %in% names(labels),unname(labels[keys]),keys)
}

pc_transpose_results <- function(tab,keys=intersect(c("condition","group","category"),names(tab)),label_keys=TRUE) {
  if(is.null(tab) || !nrow(tab) || !length(keys)) return(tab)
  measures <- setdiff(names(tab),keys)
  headers <- vapply(seq_len(nrow(tab)),function(i) paste(vapply(keys,function(k) as.character(tab[[k]][i]),character(1)),collapse=" · "),character(1))
  out <- data.frame(Measure=if(label_keys) pc_result_labels(measures) else ifelse(measures=="total","Total",measures),check.names=FALSE,stringsAsFactors=FALSE)
  for(i in seq_len(nrow(tab))) out[[length(out)+1L]] <- vapply(measures,function(k) pc_export_cell(tab[[k]][i]),character(1))
  names(out) <- c("Measure",headers)
  attr(out,"p_rows")<-if(label_keys) which(measures %in% c("p","p_raw")) else integer()
  out
}

pc_result_table_ui <- function(tab,label,wide=FALSE,first_label=NULL,p_values=TRUE) {
  if(is.null(tab) || !nrow(tab)) return(NULL)
  headers <- if(wide || !p_values) names(tab) else pc_result_labels(names(tab))
  if(!is.null(first_label)) headers[1] <- first_label
  pcols <- if(p_values && !wide) which(names(tab) %in% c("p","p_raw","P value","Adjusted P value")) else integer()
  fmt <- function(x,i,j) {
    if(length(x)!=1L || is.na(x) || identical(x,"")) return("—")
    is_p <- p_values && (j %in% pcols || (wide && j>1L && i %in% attr(tab,"p_rows")))
    numeric_value <- suppressWarnings(as.numeric(as.character(x)))
    if(is_p && is.finite(numeric_value)) return(pc_p_value(numeric_value))
    if((is.numeric(x) || (wide && j>1L)) && is.finite(numeric_value)) return(format(signif(numeric_value,5),trim=TRUE))
    as.character(x)
  }
  shiny::div(class="result-table-scroll",role="region",tabindex="0",`aria-label`=label,
    shiny::tags$table(class=paste("table shiny-table result-table",if(wide) "result-table-wide"),
      shiny::tags$thead(shiny::tags$tr(lapply(headers,function(x) shiny::tags$th(scope="col",x)))),
      shiny::tags$tbody(lapply(seq_len(nrow(tab)),function(i) shiny::tags$tr(lapply(seq_len(ncol(tab)),function(j) {
        value <- fmt(tab[[j]][i],i,j)
        if(j==1L) shiny::tags$th(scope="row",value) else shiny::tags$td(value)
      }))))))
}

pc_fit_metrics_table <- function(result,normalized,settings,detail=FALSE) {
  curves <- pc_curve_results(result,normalized,settings)
  if(is.null(curves)) return(NULL)
  m <- result$metrics
  if(is.null(m) || !nrow(m)) return(NULL)
  keep <- if(detail) c("Equation","Replicates / weighting","Source observations / fitted points","P value (slope = 0)","Conventional Hill slope (base 10)") else
    c("Residual degrees of freedom","SSE","SSE (original Y scale)","Weighted SSE","AIC")
  rows <- keep[keep %in% m$measure]
  if(!length(rows)) return(NULL)
  out <- data.frame(Measure=rows,check.names=FALSE)
  for(g in curves$series) {
    part <- if("series" %in% names(m)) m[m$series==g,,drop=FALSE] else m
    out[[length(out)+1L]] <- vapply(rows,function(k) {v<-part$value[part$measure==k];if(length(v)) as.character(v[1]) else ""},character(1))
  }
  names(out) <- c("Measure",curves$series)
  attr(out,"p_rows")<-which(grepl("^P value",rows))
  out
}

pc_summary_results_csv <- function(result,normalized,settings) {
  fit <- pc_fit_metrics_table(result,normalized,settings)
  if(!is.null(fit)) fit else pc_transpose_results(result$summary,label_keys=normalized$layout!="contingency")
}

pc_summary_results_ui <- function(result,normalized,settings) {
  summary <- pc_transpose_results(result$summary,label_keys=normalized$layout!="contingency")
  curve <- pc_curve_results(result,normalized,settings)
  if(!is.null(curve)) return(shiny::tagList(
    shiny::p(class="muted","Fit diagnostics by curve. SSE is on the scale indicated; weighted SSE uses the chosen weights. Compare AIC only for models using the same observations, response scale and weighting. AIC is unavailable when the fitting engine does not provide it."),
    pc_result_table_ui(pc_fit_metrics_table(result,normalized,settings),"Fit diagnostics by curve",wide=TRUE),
    shiny::tags$details(shiny::tags$summary("Source observation summaries"),
      shiny::p(class="muted","Each column summarizes one source series, pooling its Y observations across all entered X values. These are descriptive summaries, not measures of curve fit."),
      pc_result_table_ui(summary,"Source observations by series",wide=TRUE))))
  note <- if(settings$method=="normality") "Normality diagnostics by group. P values are unadjusted; a nonsignificant result does not establish normality." else
    if(settings$method=="auc") "AUC by series over its observed X range. Different integration ranges are not directly comparable. No AUC confidence interval or between-series test is implied." else
    switch(normalized$layout,
      contingency="Observed counts and category totals; no mean or SD is implied.",
      survival=if(settings$method=="descriptive") "Subject counts and observed times by group. Median observed time is not median survival." else "Kaplan–Meier summaries by group. A median or confidence limit is blank when it is not estimable.",
      multiple=if(settings$method=="pca") "Selected variables, restricted to the observations retained in PCA. Scores, loadings and preprocessing are in PCA results below." else "Numeric variables are summarized separately; text columns are metadata.",
      grouped="One column per factor-level and group combination. Mean intervals are individual Student’s t 95% intervals.",
      xy="Source Y observations by series, pooled across X. Mean intervals are individual Student’s t 95% intervals; these are not fitted-curve intervals.",
      "Source observations by group. Mean intervals are individual Student’s t 95% intervals. Matched tests may use fewer complete pairs or subjects; check Analysis results.")
  shiny::tagList(shiny::p(class="muted",note),pc_result_table_ui(summary,"Summary by group or variable",wide=TRUE))
}

pc_parameters_csv <- function(result,normalized,settings) {
  curves <- pc_curve_results(result,normalized,settings)
  p <- result$parameters
  if(is.null(curves) || is.null(p) || !nrow(p)) return(p)
  labels <- character();cells <- list()
  for(k in unique(as.character(p$parameter))) for(field in intersect(c("estimate","se","ci_low","ci_high"),names(p))) {
    labels <- c(labels,paste(k,pc_result_labels(field),sep=" · "))
    cells[[length(cells)+1L]] <- vapply(curves$series,function(g) {
      z<-p[p$parameter==k,,drop=FALSE];if("series" %in% names(z)) z<-z[z$series==g,,drop=FALSE]
      pc_export_cell(if(nrow(z)==1L) z[[field]] else NA_real_)
    },character(1))
  }
  out <- data.frame(Coefficient=labels,do.call(rbind,cells),check.names=FALSE)
  names(out) <- c("Coefficient / uncertainty",curves$series)
  out
}

pc_comparison_note <- function(result) {
  tab<-result$comparisons
  if(is.null(tab) || !nrow(tab)) return(NULL)
  if(identical(result$method,"anova")) return("Tukey HSD: P values are family-wise adjusted and confidence intervals are simultaneous 95% intervals. The estimate is first group minus second group.")
  if("p_raw" %in% names(tab)) return("Adjusted P values apply to the displayed comparison family; unadjusted P values are shown separately. Confidence intervals, when available, are individual 95% intervals. The estimate is first group minus second group.")
  "P values are unadjusted for additional comparisons. Confidence intervals, when available, are individual 95% intervals. The estimate is first group minus second group."
}

pc_model_details_ui <- function(result,normalized,settings) {
  t <- shiny::tags
  section <- function(title,table,id,wide=FALSE,p_values=TRUE) if(!is.null(table) && nrow(table)) shiny::tagList(t$h4(title),shiny::div(id=id,pc_result_table_ui(table,title,wide,p_values=p_values)))
  curve <- pc_curve_results(result,normalized,settings)
  comparison <- result$comparisons
  if(!is.null(comparison) && nrow(comparison)) {
    names(comparison)[names(comparison)=="p"] <- if("p_raw" %in% names(comparison) || result$method=="anova") "Adjusted P value" else "P value"
  }
  content <- shiny::tagList(
    if(!is.null(curve)) shiny::p(class="muted","Each curve is fitted independently. Differences between fitted coefficients are not tested by this table; no shared-parameter or global comparison is implied."),
    if(!is.null(curve)) pc_result_table_ui(pc_fit_metrics_table(result,normalized,settings,detail=TRUE),"Model settings by curve",TRUE),
    if(!is.null(pc_comparison_note(result))) shiny::p(class="muted",pc_comparison_note(result)),
    section("Comparisons",comparison,"comparison_table"),
    section("Factor effects",result$effects,"effects_table"),
    if(!is.null(result$parameters) && nrow(result$parameters)) t$details(t$summary("Complete model coefficients and uncertainty"),
      if(settings$method=="fourpl") t$p(class="muted","These are the fitted coefficients: logSpan = ln(Top − Bottom), logEC50 = log10(EC50), and hill is the natural-logistic coefficient. The response-scale plateaus and EC50 are in Analysis results above."),
      section("Model coefficients",pc_parameters_csv(result,normalized,settings),"parameters_table",!is.null(curve))),
    section("Fit status",result$fit_status,"fit_status_table"),
    section("Expected counts",pc_expected_counts(result),"expected_counts_table",p_values=FALSE),
    section("Numbers at risk and survival",result$at_risk,"risk_table"))
  if(all(vapply(c("comparisons","effects","parameters","fit_status","expected","at_risk"),function(k) is.null(result[[k]]) || !nrow(result[[k]]),logical(1))))
    content<-t$p(class="muted",if(settings$method=="pca") "PCA component, score and loading tables are shown above. No pairwise tests are implied." else "This analysis does not produce additional comparisons or model coefficients. Review its estimates and assumptions above.")
  content
}

pc_expected_counts <- function(result) {
  x<-result$expected
  if(is.null(x) || !nrow(x)) return(x)
  data.frame(Category=rownames(x),x,check.names=FALSE,row.names=NULL)
}
