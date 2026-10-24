pc_regression_methods <- function() c("Line through origin"="origin","Quadratic polynomial"="quadratic","Cubic polynomial"="cubic",
  "Logarithmic: a + b ln(X)"="logarithmic","Power: A × X^b"="power","Exponential: A × exp(kX)"="exponential",
  "One-phase exponential decay"="decay","One-phase exponential association"="association",
  "Michaelis–Menten saturation"="michaelis","Gaussian peak + baseline"="gaussian")
pc_fit_data <- function(n,group,options=list()) {
  a <- n$data[n$data$group==group,,drop=FALSE]
  if (!nrow(a)) stop("Select a populated Y series.",call.=FALSE)
  mode <- if(is.null(options$fit_replicates)) "individual" else options$fit_replicates
  weighting <- if(is.null(options$fit_weight)) "none" else options$fit_weight
  if(!mode %in% c("individual","mean") || !weighting %in% c("none","inv_y2","replicate_sd")) stop("Choose valid fitting and weighting options.",call.=FALSE)
  raw_n <- nrow(a)
  if(weighting=="replicate_sd") {
    variance <- tapply(a$value,a$x,stats::var)
    if(any(!is.finite(variance) | variance<=0)) stop("Replicate-SD weighting needs at least two observed replicates and nonzero SD at every X.",call.=FALSE)
    a$.weight <- 1/as.numeric(variance[as.character(a$x)])
  } else a$.weight <- 1
  if(mode=="mean") {
    a <- do.call(rbind,lapply(split(a,a$x),function(z) data.frame(x=z$x[1],value=mean(z$value),.weight=z$.weight[1]*if(weighting=="replicate_sd") nrow(z) else 1)))
  }
  if(weighting=="inv_y2") {
    if(any(a$value==0)) stop("1/Y² weighting requires nonzero fitted observations.",call.=FALSE)
    a$.weight <- 1/a$value^2
  }
  a$.weight <- a$.weight/mean(a$.weight)
  if(any(!is.finite(a$.weight) | a$.weight<=0)) stop("Fitting weights are not finite and positive.",call.=FALSE)
  list(data=a,raw_n=raw_n,mode=mode,weighting=weighting)
}
pc_regression <- function(n,method,group,options=list()) {
  prep <- pc_fit_data(n,group,options); a <- prep$data
  degree <- switch(method,origin=1L,linear=1L,quadratic=2L,cubic=3L,logarithmic=1L,NA_integer_)
  required <- switch(method,origin=3L,linear=3L,logarithmic=3L,cubic=5L,gaussian=6L,decay=5L,association=5L,4L)
  distinct_required <- if(is.na(degree)) required-1L else degree+1L
  if(nrow(a)<required || length(unique(a$x))<distinct_required || stats::sd(a$value)==0)
    stop("Add more observations with distinct X values and variation in Y for this model.",call.=FALSE)
  if(method %in% c("power","logarithmic") && any(a$x<=0)) stop("This model requires positive X values.",call.=FALSE)
  if(method %in% c("decay","association","michaelis") && any(a$x<0)) stop("This model requires nonnegative X values.",call.=FALSE)
  equation <- switch(method,linear="Y = intercept + slope × X",origin="Y = slope × X",quadratic="Y = a + bX + cX²",cubic="Y = a + bX + cX² + dX³",
    logarithmic="Y = a + b ln(X)",power="Y = A × X^b",exponential="Y = A × exp(kX)",decay="Y = plateau + amplitude × exp(−rate × X)",
    association="Y = plateau − amplitude × exp(−rate × X)",michaelis="Y = Vmax × X / (Km + X)",gaussian="Y = baseline + amplitude × exp(−0.5 × ((X − center) / sigma)²)")
  if(!is.na(degree)) {
    formula <- switch(method,linear=value~x,origin=value~0+x,quadratic=value~x+I(x^2),cubic=value~x+I(x^2)+I(x^3),logarithmic=value~log(x))
    fit <- stats::lm(formula,data=a,weights=.weight)
    if(fit$rank != length(coef(fit))) stop("The model is rank deficient. Use distinct X values and a simpler polynomial.",call.=FALSE)
  } else {
    span <- diff(range(a$value)); xr <- max(diff(range(a$x)),1e-8)
    positive <- all(a$value>0)
    initial <- if(positive) coef(lm(log(value)~x,a)) else c(log(max(abs(a$value))),0)
    specs <- switch(method,
      power=list(formula=value~exp(logA)*x^b,start=list(logA=if(positive) coef(lm(log(value)~log(x),a))[1] else log(max(abs(a$value))),b=if(positive) coef(lm(log(value)~log(x),a))[2] else 1)),
      exponential=list(formula=value~exp(logA+k*x),start=list(logA=initial[1],k=initial[2])),
      decay=list(formula=value~plateau+exp(logAmplitude)*exp(-exp(logRate)*x),start=list(plateau=min(a$value),logAmplitude=log(span),logRate=log(1/xr))),
      association=list(formula=value~plateau-exp(logAmplitude)*exp(-exp(logRate)*x),start=list(plateau=max(a$value),logAmplitude=log(span),logRate=log(1/xr))),
      michaelis=list(formula=value~exp(logVmax)*x/(exp(logKm)+x),start=list(logVmax=log(max(a$value)),logKm=log(max(median(a$x),xr/10)))),
      gaussian=list(formula=value~baseline+exp(logAmplitude)*exp(-0.5*((x-center)/exp(logSigma))^2),
        start=list(baseline=min(a$value),logAmplitude=log(span),center=a$x[which.max(a$value)],logSigma=log(xr/5))))
    if(method=="michaelis" && max(a$value)<=0) stop("Michaelis–Menten fitting requires positive responses.",call.=FALSE)
    specs$start<-lapply(specs$start,function(value) if(abs(value)<1e-8) 0 else unname(value))
    lower <- vapply(names(specs$start),function(k) if(startsWith(k,"log")) -40 else if(k=="center") min(a$x)-xr else -Inf,numeric(1))
    upper <- vapply(names(specs$start),function(k) if(startsWith(k,"log")) 40 else if(k=="center") max(a$x)+xr else Inf,numeric(1))
    if(method=="exponential") {lower["k"] <- -600/max(1,max(abs(a$x)));upper["k"] <- -lower["k"]}
    fit <- tryCatch(stats::nls(specs$formula,data=a,start=specs$start,weights=a$.weight,algorithm="port",lower=lower,upper=upper,
      control=stats::nls.control(maxiter=500,warnOnly=FALSE)),error=function(e) stop("The fit did not converge reliably: ",conditionMessage(e),". Check the model, data range and starting shape.",call.=FALSE))
  }
  co <- coef(fit); covariance <- tryCatch(vcov(fit),error=function(e) NULL)
  if(is.null(covariance) || any(!is.finite(covariance))) stop("Parameter uncertainty is not identifiable. Use a simpler model or add data spanning the curve.",call.=FALSE)
  se <- sqrt(diag(covariance)); df <- df.residual(fit)
  if(df<=0 || any(!is.finite(se))) stop("There are too few residual degrees of freedom to estimate uncertainty.",call.=FALSE)
  crit <- qt(.975,df); estimate <- co; low <- co-crit*se; high <- co+crit*se
  positive_parameters <- startsWith(names(co),"log")
  estimate[positive_parameters] <- exp(co[positive_parameters]);low[positive_parameters] <- exp(low[positive_parameters]);high[positive_parameters] <- exp(high[positive_parameters]);se[positive_parameters] <- se[positive_parameters]*estimate[positive_parameters]
  parameter_names <- names(co);parameter_names[positive_parameters] <- sub("^log","",parameter_names[positive_parameters])
  grid <- data.frame(x=seq(min(a$x),max(a$x),length.out=240))
  r <- pc_result(n,method);r$n <- nrow(a)
  r$parameters <- data.frame(parameter=parameter_names,estimate=as.numeric(estimate),se=as.numeric(se),ci_low=as.numeric(low),ci_high=as.numeric(high))
  r$curve <- data.frame(x=grid$x,fit=as.numeric(predict(fit,grid)))
  if(any(!is.finite(r$curve$fit))) stop("The fitted curve contains nonfinite predictions.",call.=FALSE)
  if(inherits(fit,"lm")) {
    ci <- predict(fit,grid,interval="confidence");r$curve$lower <- ci[,"lwr"];r$curve$upper <- ci[,"upr"]
    if(method %in% c("linear","origin")) r$p <- summary(fit)$coefficients["x","Pr(>|t|)"]
  }
  predicted <- as.numeric(fitted(fit));resid <- a$value-predicted;sse <- sum(resid^2);sst <- sum((a$value-mean(a$value))^2)
  r$diagnostics <- data.frame(x=a$x,observed=a$value,fitted=predicted,residual=resid,weight=a$.weight)
  r$metrics <- rbind(pc_metric("Series",group),pc_metric("Equation",equation),pc_metric("Source observations / fitted points",paste(prep$raw_n,nrow(a),sep=" / ")),
    pc_metric("Replicates / weighting",paste(prep$mode,prep$weighting,sep=" / ")),pc_metric("Residual degrees of freedom",df),
    pc_metric("SSE (original Y scale)",pc_fmt(sse)),pc_metric("RMSE (original Y scale)",pc_fmt(sqrt(sse/df))),pc_metric("R squared (1 − SSE/SST)",pc_fmt(1-sse/sst)),
    pc_metric("Weighted SSE",pc_fmt(sum(a$.weight*resid^2))),pc_metric("AIC",pc_fmt(AIC(fit))))
  r$notes <- c(paste("Least squares on the original Y scale.",equation),
    if(inherits(fit,"lm")) "Parameter t intervals and a 95% confidence band for the fitted mean are shown. This is not a prediction band." else "Parameter intervals are approximate local t/Wald intervals. No nonlinear curve confidence or prediction band is implied.",
    "Fits assume independent observations. Technical repeats are not independent biological replicates. Inspect residuals and parameter uncertainty; R squared alone does not establish model adequacy.",
    "AIC values are comparable only for models fit to the same observations, response scale and weighting convention. No automatic best-model claim is made.")
  r
}
