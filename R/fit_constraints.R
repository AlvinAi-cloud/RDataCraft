# Constraints are data, never R expressions. Saved Hill rules use the solver scale.
pc_fit_parameters <- function(method) switch(method,
 linear=c('intercept','slope'),origin='slope',quadratic=c('a','b','c'),cubic=c('a','b','c','d'),logarithmic=c('a','b'),power=c('A','b'),exponential=c('A','k'),decay=c('plateau','amplitude','rate'),association=c('plateau','amplitude','rate'),michaelis=c('Vmax','Km'),gaussian=c('baseline','amplitude','center','sigma'),fourpl=c('bottom','top','EC50','hill'),threepl=c('bottom','top','EC50'),character())
pc_fit_constraints <- function(text='{}') {
 if(is.null(text))text<-'{}'
 if(!is.character(text)||length(text)!=1L||is.na(text)||nchar(text,type='bytes')>20000||!startsWith(trimws(text),'{'))stop('Invalid parameter constraints.')
 rules<-jsonlite::fromJSON(text,simplifyVector=FALSE)
 if(!is.list(rules)||anyDuplicated(names(rules)))stop('Invalid parameter constraints.')
 validate_parameters<-function(r,pars,override=FALSE) {
  if(!is.list(r)||(length(r)&&is.null(names(r)))||anyDuplicated(names(r))||any(!names(r)%in%pars))stop('Unknown constrained parameter.')
  for(k in names(r)) {
   z<-r[[k]]
   if(override&&is.list(z)&&!length(z))next
   if(!is.list(z)||!length(z)||is.null(names(z))||anyDuplicated(names(z))||any(!names(z)%in%c('fixed','lower','upper'))||any(!vapply(z,function(v)is.numeric(v)&&length(v)==1L&&is.finite(v),logical(1))))stop('Constraints require finite numeric values.')
   lo<-if(is.null(z$lower))-Inf else z$lower;hi<-if(is.null(z$upper))Inf else z$upper
   if(lo>=hi||(!is.null(z$fixed)&&(z$fixed<lo||z$fixed>hi)))stop('Use lower < upper and a fixed value within the bounds.')
   if(k%in%c('A','amplitude','rate','Vmax','Km','sigma','EC50')&&((!is.null(z$fixed)&&z$fixed<=0)||(!is.null(z$upper)&&z$upper<=0)||(!is.null(z$lower)&&z$lower<0)))stop(paste(k,'requires a positive fixed value/upper bound and a nonnegative lower bound.'))
  }
 }
 for(method in names(rules)) {
  pars<-pc_fit_parameters(method);r<-rules[[method]]
  if(!length(pars)||!is.list(r)||is.null(names(r))||anyDuplicated(names(r)))stop('Unknown model or invalid constraints.')
  validate_parameters(r[setdiff(names(r),c('groups','shared'))],pars)
  if(!is.null(r$shared)&&(!is.list(r$shared)&&!is.character(r$shared)||any(!unlist(r$shared)%in%pars)||anyDuplicated(unlist(r$shared))))stop('Select valid shared parameters.')
  if(!is.null(r$groups)) {
   if(!is.list(r$groups)||is.null(names(r$groups))||anyDuplicated(names(r$groups))||any(!nzchar(names(r$groups))))stop('Invalid group constraints.')
   for(g in names(r$groups))validate_parameters(r$groups[[g]],pars,TRUE)
  }
 }
 rules
}
pc_scale_hill_rule <- function(rule, factor) {
  lapply(rule, function(value) value * factor)
}

pc_scale_fit_hill <- function(text, factor) {
  rules <- pc_fit_constraints(text)
  model <- rules$fourpl
  groups <- names(model$groups)[vapply(model$groups, function(group) length(group$hill) > 0L, logical(1))]
  if (!length(model$hill) && !length(groups)) return(text)
  if (length(model$hill)) model$hill <- pc_scale_hill_rule(model$hill, factor)
  for (group in groups) model$groups[[group]]$hill <- pc_scale_hill_rule(model$groups[[group]]$hill, factor)
  rules$fourpl <- model
  as.character(jsonlite::toJSON(rules, auto_unbox=TRUE, digits=17))
}

pc_fit_with_retry <- function(fit, start, retry, label) {
  result <- tryCatch(fit(start), error=identity)
  if (inherits(result, "error") && !is.null(retry) && !identical(start, retry)) {
    result <- tryCatch(fit(retry), error=identity)
  }
  if (inherits(result, "error")) stop(label, conditionMessage(result), call.=FALSE)
  result
}

# With EC50 and Hill fixed, the plateaus are linear coefficients. The weighted
# minimum under box bounds and Bottom <= Top is either the unrestricted
# solution or a minimum along one of those boundaries.
pc_profile_plateau_sse <- function(design, y, w, lower, upper) {
  candidates <- list()
  add <- function(p) {
    if (all(is.finite(p)) && all(p >= lower & p <= upper) && p[1] <= p[2])
      candidates[[length(candidates) + 1L]] <<- p
  }
  scale <- apply(design, 2L, max)
  if (all(scale > 0)) {
    scaled <- sweep(design, 2L, scale, "/")
    add(stats::lm.wfit(scaled, y, w, tol=1e-12)$coefficients / scale)
  }
  clip <- function(x, lo, hi) min(max(x, lo), hi)
  for (i in 1:2) {
    j <- 3L - i
    for (edge in unique(c(lower[i], upper[i]))) {
      if (!is.finite(edge)) next
      lo <- if (i == 1L) max(lower[j], edge) else lower[j]
      hi <- if (i == 2L) min(upper[j], edge) else upper[j]
      if (lo > hi) next
      column <- design[, j]
      factor <- max(column)
      estimate <- if (factor > 0) {
        z <- column / factor
        sum(w * z * (y - design[, i] * edge)) / sum(w * z^2) / factor
      } else mean(y)
      p <- numeric(2)
      p[i] <- edge
      p[j] <- clip(estimate, lo, hi)
      add(p)
    }
  }
  lo <- max(lower)
  hi <- min(upper)
  if (lo <= hi) add(rep(clip(weighted.mean(y, w), lo, hi), 2L))
  if (!length(candidates)) return(NA_real_)
  min(vapply(candidates, function(p) sum(w * (y - drop(design %*% p))^2), numeric(1)))
}

pc_nonlinear_methods <- function() c("power","exponential","decay","association","michaelis","gaussian","fourpl","threepl")

pc_profile_note <- function() paste(
  "Profile-likelihood intervals refit the other free coefficients with the original weights and bounds.",
  "A limit is unavailable when the refit or the 95% threshold crossing cannot be resolved.")

pc_profile_limits <- function(objective, center, domain, step, max_step) {
  limits <- c(NA_real_, NA_real_)
  at_center <- objective(center)
  if (!is.finite(at_center) || at_center >= 0 || center <= domain[1] || center >= domain[2]) return(limits)
  endpoint <- function(direction, bound) {
    inner <- center
    stride <- step
    for (attempt in seq_len(60L)) {
      outer <- if (direction < 0) max(bound, inner - stride) else min(bound, inner + stride)
      if (!is.finite(outer) || outer == inner) break
      value <- objective(outer)
      if (!is.finite(value)) break
      if (value >= 0) {
        crossing <- tryCatch(stats::uniroot(objective, sort(c(inner, outer)), tol=1e-9),
                             error=function(e) NULL)
        # A discontinuity or failed nuisance fit is not a threshold crossing.
        if (!is.null(crossing) && is.finite(crossing$f.root) &&
            abs(crossing$f.root) <= 1e-3 * abs(at_center)) return(crossing$root)
        break
      }
      inner <- outer
      stride <- min(stride * 1.8, max_step)
    }
    NA_real_
  }
  c(endpoint(-1, domain[1]), endpoint(1, domain[2]))
}

pc_profile_ec50 <- function(data, estimates, lower, upper, fixed, sse, df) {
  if (!is.finite(sse) || sse <= 0 || df <= 0) return(c(NA_real_, NA_real_))
  plateaus <- c("bottom", "top")
  fixed_plateaus <- intersect(plateaus, fixed)
  lower[fixed_plateaus] <- upper[fixed_plateaus] <- estimates[fixed_plateaus]
  center <- log(estimates[["EC50"]])
  domain <- log(c(lower[["EC50"]], min(upper[["EC50"]], .Machine$double.xmax)))
  if (center - domain[1] <= 1e-8 || domain[2] - center <= 1e-8) return(c(NA_real_, NA_real_))
  dose <- log(data$x)
  hill <- estimates[["hill"]] / log(10)
  # Invert the extra sum-of-squares F test, profiling one parameter at a time.
  threshold <- 1 + stats::qf(.95, 1, df) / df
  objective <- function(midpoint) {
    eta <- hill * (dose - midpoint)
    design <- cbind(plogis(-eta), plogis(eta))
    pc_profile_plateau_sse(design, data$value, data$.weight, lower[plateaus], upper[plateaus]) / sse - threshold
  }
  if (!isTRUE(abs(objective(center) + threshold - 1) <= 1e-6)) return(c(NA_real_, NA_real_))
  exp(pc_profile_limits(objective, center, domain, .025, 1))
}

# Profile the same weighted objective as the original fit. Recenter and scale
# the nuisance coefficients so a large plateau and a small rate can move together.
pc_profile_parameters <- function(estimate, se, lower, upper, free, targets, predict, y, weights, df,
                                  positive=character(), valid=function(p) TRUE) {
  limits <- matrix(NA_real_, length(targets), 2L, dimnames=list(targets, NULL))
  if (!length(targets) || df <= 0) return(limits)
  sse <- sum(weights * (y - predict(estimate))^2)
  if (!is.finite(sse) || sse <= 0) return(limits)
  threshold <- 1 + stats::qf(.95, 1, df) / df
  scale <- ifelse(is.finite(se) & se > 0, se, pmax(abs(estimate) * .1, 1e-6))
  scale <- pmax(scale, abs(estimate) * 1e-8)
  objective <- function(p) sum(weights * (y - predict(p))^2) / sse
  for (key in targets) {
    if (!is.finite(se[[key]]) || se[[key]] <= 0) next
    nuisance <- setdiff(free, key)
    baseline <- estimate[[key]]
    on_log <- key %in% positive
    unit <- if (on_log) min(1, scale[[key]] / baseline) else scale[[key]]
    if (!is.finite(unit) || unit <= 0) next
    transform <- if (on_log) function(x) (log(x) - log(baseline)) / unit else function(x) (x - baseline) / unit
    invert <- if (on_log) function(z) exp(log(baseline) + z * unit) else function(z) baseline + z * unit
    domain <- transform(c(lower[[key]], upper[[key]]))
    profile <- function(z) {
      if (z == 0) return(1 - threshold)
      p <- estimate
      p[[key]] <- min(max(invert(z), lower[[key]]), upper[[key]])
      if (!is.finite(p[[key]])) return(NA_real_)
      if (length(nuisance)) {
        unpack <- function(offset) {
          p[nuisance] <- pmin(upper[nuisance], pmax(lower[nuisance], estimate[nuisance] + offset * scale[nuisance]))
          p
        }
        cost <- function(offset) {
          value <- objective(unpack(offset))
          if (is.finite(value)) value else 1e30
        }
        fit <- tryCatch(suppressWarnings(stats::nlminb(
          rep(0, length(nuisance)), cost,
          lower=(lower[nuisance] - estimate[nuisance]) / scale[nuisance],
          upper=(upper[nuisance] - estimate[nuisance]) / scale[nuisance],
          control=list(iter.max=150L, eval.max=250L, rel.tol=1e-10))), error=function(e) NULL)
        if (is.null(fit) || fit$convergence != 0L) return(NA_real_)
        p <- unpack(fit$par)
      }
      value <- objective(p)
      if (!is.finite(value) || value < 1 - 1e-5 || !valid(p)) return(NA_real_)
      value - threshold
    }
    limits[key, ] <- invert(pc_profile_limits(profile, 0, domain, .25, 2))
  }
  limits
}

pc_fit_rules<-function(options,method,group) {
 r<-pc_fit_constraints(options$fit_constraints)[[method]]
 base<-r[setdiff(names(r),c('groups','shared'))]
 for(k in names(r$groups[[group]])) {z<-r$groups[[group]][[k]];base[[k]]<-if(length(z))z else NULL}
 if(method%in%c('fourpl','threepl')&&!is.null(base$bottom$fixed)&&!is.null(base$top$fixed)&&base$top$fixed<=base$bottom$fixed)stop('Top must exceed Bottom.')
 base
}

pc_constrained_fit <- function(n,method,group,options,spec_only=FALSE) {
 original_method<-method
 rules<-pc_fit_rules(options,method,group)
 if(method=='threepl') {method<-'fourpl';rules$hill<-list(fixed=log(10))}
 keys<-pc_fit_parameters(method)
 prep<-pc_fit_data(n,group,options);a<-prep$data;x<-a$x;y<-a$value;span<-max(diff(range(y)),1e-6);xr<-max(diff(range(x)),1e-6)
 if(any(x<=0)&&method%in%c('fourpl','power','logarithmic'))stop('This model requires positive X values.')
 if(any(x<0)&&method%in%c('decay','association','michaelis'))stop('This model requires nonnegative X values.')
 start<-switch(method,linear=c(mean(y),0),origin=mean(y)/max(mean(x),1e-6),quadratic=c(mean(y),0,0),cubic=c(mean(y),0,0,0),logarithmic=c(mean(y),0),power=c(max(y),1),exponential=c(max(y),0),decay=c(min(y),span,1/xr),association=c(max(y),span,1/xr),michaelis=c(max(y),max(median(x),xr/10)),gaussian=c(min(y),span,x[which.max(y)],xr/5),fourpl=c(min(y),max(y),10^mean(range(log10(x))),if(cor(x,y)>=0)1 else -1));names(start)<-keys
 data_start <- start
 # Seed from the established unconstrained engine when identifiable; a failed
 # unrestricted fit must not prevent a simpler constrained fit from being tried.
 seed_options<-options;seed_options$fit_constraints<-'{}';seed_options$fit_scope<-'selected';seed_options$fit_mode<-'independent';seed_options$profile_ci<-FALSE
 seed<-tryCatch(pc_analyze(n,method,group,options=seed_options)$parameters,error=function(e)NULL)
 if(!is.null(seed)) {
  if(method=='fourpl') {
   co<-setNames(seed$estimate,seed$parameter)
   initial<-c(bottom=co[['bottom']],top=co[['bottom']]+exp(co[['logSpan']]),EC50=10^co[['logEC50']],hill=co[['hill']])
  }else initial<-setNames(seed$estimate,keys)
  if(length(initial)==length(start)&&all(is.finite(initial)))start<-initial
 }
 lower<-setNames(rep(-Inf,length(keys)),keys);upper<--lower
 positive<-intersect(keys,c('A','amplitude','rate','Vmax','Km','sigma','EC50'));lower[positive]<-.Machine$double.xmin
 for(k in names(rules)) {z<-rules[[k]];if(!is.null(z$lower))lower[k]<-max(lower[k],z$lower);if(!is.null(z$upper))upper[k]<-min(upper[k],z$upper);if(!is.null(z$fixed))start[k]<-z$fixed}
 fixed<-names(rules)[vapply(rules,function(z)!is.null(z$fixed),logical(1))];free<-setdiff(keys,fixed)
 start<-pmin(pmax(start,lower),upper)
 # The unrestricted seed can put EC50 far beyond the data when its Hill slope
 # differs from the fixed slope. Retry with plateaus and a midpoint from the data.
 retry <- NULL
 if (method == 'fourpl' && 'hill' %in% fixed) {
   data_start[fixed] <- start[fixed]
   retry <- pmin(pmax(data_start, lower), upper)
 }
 predict_values<-function(x,p) {with(as.list(p),switch(method,linear=intercept+slope*x,origin=slope*x,quadratic=a+b*x+c*x^2,cubic=a+b*x+c*x^2+d*x^3,logarithmic=a+b*log(x),power=A*x^b,exponential=A*exp(k*x),decay=plateau+amplitude*exp(-rate*x),association=plateau-amplitude*exp(-rate*x),michaelis=Vmax*x/(Km+x),gaussian=baseline+amplitude*exp(-.5*((x-center)/sigma)^2),fourpl=bottom+(top-bottom)*plogis(hill*(log10(x)-log10(EC50)))))}
 predict_curve<-function(x,...) {p<-start;p[free]<-unlist(list(...));predict_values(x,p)}
 if(spec_only)return(list(start=start,retry=retry,lower=lower,upper=upper,fixed=fixed,keys=keys,predict=predict_values,prep=prep,rules=rules))
 df<-nrow(a)-length(free);if(df<=0||length(unique(x))<max(2,length(free)))stop('Add more distinct X values to estimate the free parameters.')
 estimates<-start;se<-ci_low<-ci_high<-setNames(rep(NA_real_,length(keys)),keys);at_bound<-character()
 if(length(free)) {
  form<-as.formula(paste('value ~ predict_curve(x,',paste(free,collapse=','),')'))
  fit_model <- function(seed) stats::nls(form,data=a,start=as.list(seed),weights=a$.weight,algorithm='port',lower=lower[free],upper=upper[free],control=nls.control(maxiter=1000))
  fit <- pc_fit_with_retry(fit_model, start[free], retry[free], 'Constrained fit did not converge: ')
  estimates[free]<-coef(fit);cov<-tryCatch(vcov(fit),error=function(e)NULL)
  if(!is.null(cov)&&all(is.finite(cov))) {se[free]<-sqrt(diag(cov));ci_low[free]<-estimates[free]-qt(.975,df)*se[free];ci_high[free]<-estimates[free]+qt(.975,df)*se[free]}
  at_bound<-free[abs(estimates[free]-lower[free])<=1e-6*pmax(1,abs(estimates[free]))|abs(estimates[free]-upper[free])<=1e-6*pmax(1,abs(estimates[free]))]
  se[at_bound]<-ci_low[at_bound]<-ci_high[at_bound]<-NA_real_
 }
 if(method=='fourpl'&&estimates['top']<=estimates['bottom'])stop('Top must exceed Bottom; revise the constraints.')
 predicted<-predict_values(x,estimates);grid<-if(method=='fourpl')10^seq(min(log10(x)),max(log10(x)),length.out=240)else seq(min(x),max(x),length.out=240)
 curve<-predict_values(grid,estimates);if(any(!is.finite(c(predicted,curve))))stop('Constraints produced nonfinite predictions.')
 residual<-y-predicted;r<-pc_result(n,original_method);r$n<-nrow(a)
 profile <- method %in% pc_nonlinear_methods() && !isFALSE(options$profile_ci)
 profile_ec50 <- profile && method == 'fourpl' && 'hill' %in% fixed && 'EC50' %in% free
 if (profile) {
   targets <- setdiff(free, c(at_bound, if (profile_ec50) 'EC50'))
   limits <- pc_profile_parameters(estimates,se,lower,upper,free,targets,
     function(p) predict_values(x,p), y,a$.weight,df,positive,
     valid=function(p) method != 'fourpl' || p[['bottom']] <= p[['top']])
   ci_low[targets] <- limits[,1]
   ci_high[targets] <- limits[,2]
 }
 if (profile_ec50) {
   ci <- pc_profile_ec50(a, estimates, lower, upper, fixed, sum(a$.weight*residual^2), df)
   ci_low['EC50'] <- ci[1]
   ci_high['EC50'] <- ci[2]
 }
 r$parameters<-data.frame(parameter=keys,estimate=as.numeric(estimates),se=as.numeric(se),ci_low=as.numeric(ci_low),ci_high=as.numeric(ci_high),constraint=ifelse(keys%in%fixed,'Fixed',ifelse(keys%in%names(rules),'Bounded','Free')))
 if (profile) r$parameters$ci_method <- ifelse(keys %in% free, 'Profile likelihood', NA_character_)
 r$curve<-data.frame(x=grid,fit=curve);r$diagnostics<-data.frame(x=x,observed=y,fitted=predicted,residual=residual,weight=a$.weight)
 if (length(rules$hill)) rules$hill <- pc_scale_hill_rule(rules$hill, 1 / log(10))
 r$metrics<-rbind(pc_metric('Series',group),pc_metric('Free / fixed parameters',paste(length(free),length(fixed),sep=' / ')),pc_metric('Residual degrees of freedom',df),pc_metric('SSE (original Y scale)',pc_fmt(sum(residual^2))),pc_metric('Weighted SSE',pc_fmt(sum(a$.weight*residual^2))),pc_metric('RMSE (original Y scale)',pc_fmt(sqrt(sum(residual^2)/df))),pc_metric('Parameter constraints',jsonlite::toJSON(rules,auto_unbox=TRUE)),pc_metric('Replicates / weighting',paste(prep$mode,prep$weighting,sep=' / ')))
 r$notes<-c('Constrained least squares on the original Y scale. Fixed values are not estimated; their SE and confidence intervals are not reported. Degrees of freedom count only free parameters.',
   if(profile) pc_profile_note() else 'Local Wald intervals are conditional on fixed values.',
   'Intervals are omitted at active bounds. No confidence band or unconstrained slope P value is implied.',
   'Independent-observation assumptions still apply; inspect residuals and sensitivity to constraints.',if(original_method=='threepl') 'Three-parameter dose response fixes the Hill coefficient at +1 for an increasing response.',if(length(at_bound))paste('Parameters at a bound:',paste(at_bound,collapse=', ')))
 r
}

# One joint least-squares problem: shared coefficients occur only once in theta.
pc_global_fit<-function(n,method,options) {
 groups<-n$groups
 if(length(groups)<2L)stop('Global fitting requires at least two populated series.')
 shared<-unlist(pc_fit_constraints(options$fit_constraints)[[method]]$shared,use.names=FALSE)
 if(!length(shared))stop('Choose shared parameters in Parameter constraints before global fitting.')
 specs<-setNames(lapply(groups,function(g)pc_constrained_fit(n,method,g,options,spec_only=TRUE)),groups)
 keys<-specs[[1]]$keys;ids<-matrix('',nrow=length(groups),ncol=length(keys),dimnames=list(groups,keys));start<-retry<-lower<-upper<-numeric();fixed<-logical()
 for(k in keys)for(block in if(k%in%shared)list(groups)else as.list(groups)) {
  id<-paste0('p',length(start)+1L);idx<-vapply(block,function(g)specs[[g]]$start[k],numeric(1));lo<-max(vapply(block,function(g)specs[[g]]$lower[k],numeric(1)));hi<-min(vapply(block,function(g)specs[[g]]$upper[k],numeric(1)))
  values<-vapply(block,function(g)if(k%in%specs[[g]]$fixed)specs[[g]]$start[k]else NA_real_,numeric(1));values<-unique(values[is.finite(values)])
  if(lo>=hi||length(values)>1L||length(values)&& (values<lo||values>hi))stop(paste('Conflicting fixed values or bounds for shared parameter',k))
  start[id]<-if(length(values))values else min(max(mean(idx),lo),hi);lower[id]<-lo;upper[id]<-hi;fixed[id]<-length(values)>0L;ids[block,k]<-id
  data_starts <- vapply(block, function(g) {
    seed <- specs[[g]]$retry
    if (is.null(seed)) seed <- specs[[g]]$start
    seed[[k]]
  }, numeric(1))
  retry[id] <- if (fixed[id]) start[id] else min(max(mean(data_starts), lo), hi)
 }
 free<-names(start)[!fixed];data<-do.call(rbind,lapply(groups,function(g)specs[[g]]$prep$data));rownames(data)<-NULL
 weights<-unlist(lapply(groups,function(g) {
  a<-specs[[g]]$prep$data;mode<-specs[[g]]$prep$mode;weight<-specs[[g]]$prep$weighting
  if(weight=='none')return(rep(1,nrow(a)))
  if(weight=='inv_y2')return(1/a$value^2)
  raw<-n$data[n$data$group==g,,drop=FALSE];v<-tapply(raw$value,raw$x,var);w<-1/as.numeric(v[as.character(a$x)])
  if(mode=='mean')w<-w*as.numeric(table(raw$x)[as.character(a$x)])
  w
 }));weights<-weights/mean(weights)
 evaluate<-function(theta)unlist(lapply(groups,function(g){p<-theta[ids[g,]];names(p)<-keys;specs[[g]]$predict(specs[[g]]$prep$data$x,p)}),use.names=FALSE)
 joint<-function(row,...){p<-start;p[free]<-unlist(list(...));evaluate(p)[row]}
 frame<-data.frame(row=seq_len(nrow(data)),value=data$value);df<-nrow(frame)-length(free);if(df<=0)stop('Not enough observations for the joint free parameters.')
 estimates<-start;se<-ci_low<-ci_high<-setNames(rep(NA_real_,length(start)),names(start));active<-character()
 if(length(free)) {
  form<-as.formula(paste('value ~ joint(row,',paste(free,collapse=','),')'))
  fit_model <- function(seed) nls(form,data=frame,start=as.list(seed),weights=weights,algorithm='port',lower=lower[free],upper=upper[free],control=nls.control(maxiter=1000))
  fit <- pc_fit_with_retry(fit_model, start[free], retry[free], 'Global fit did not converge: ')
  estimates[free]<-coef(fit);cov<-tryCatch(vcov(fit),error=function(e)NULL)
  if(!is.null(cov)&&all(is.finite(cov))) {se[free]<-sqrt(diag(cov));ci_low[free]<-estimates[free]-qt(.975,df)*se[free];ci_high[free]<-estimates[free]+qt(.975,df)*se[free]}
  active<-free[abs(estimates[free]-lower[free])<=1e-6*pmax(1,abs(estimates[free]))|abs(estimates[free]-upper[free])<=1e-6*pmax(1,abs(estimates[free]))];se[active]<-ci_low[active]<-ci_high[active]<-NA_real_
 }
 profile <- method %in% pc_nonlinear_methods() && length(free) <= 12L && !isFALSE(options$profile_ci)
 if (profile) {
   targets <- setdiff(free, active)
   positive <- unique(as.vector(ids[,intersect(keys,c('A','amplitude','rate','Vmax','Km','sigma','EC50')),drop=FALSE]))
   limits <- pc_profile_parameters(estimates,se,lower,upper,free,targets,evaluate,data$value,weights,df,positive,
     valid=function(p) !all(c('bottom','top') %in% keys) || all(p[ids[,'bottom']] <= p[ids[,'top']]))
   ci_low[targets] <- limits[,1]
   ci_high[targets] <- limits[,2]
 }
 r<-pc_result(n,method);r$n<-nrow(data);r$parameters<-r$curve<-r$diagnostics<-NULL
 for(g in groups) {
  ix<-ids[g,];p<-estimates[ix];names(p)<-keys;a<-specs[[g]]$prep$data
  if(method%in%c('fourpl','threepl')&&p['top']<=p['bottom'])stop('Top must exceed Bottom in every series.')
  grid<-if(method%in%c('fourpl','threepl'))10^seq(min(log10(a$x)),max(log10(a$x)),length.out=240)else seq(min(a$x),max(a$x),length.out=240)
  pred<-specs[[g]]$predict(a$x,p);curve<-specs[[g]]$predict(grid,p);if(any(!is.finite(c(pred,curve))))stop('Global fit produced nonfinite predictions.')
  parameters<-data.frame(series=g,parameter=keys,estimate=as.numeric(p),se=as.numeric(se[ix]),ci_low=as.numeric(ci_low[ix]),ci_high=as.numeric(ci_high[ix]),constraint=ifelse(fixed[ix],'Fixed',ifelse(keys%in%shared,'Shared','Local')))
  if (profile) parameters$ci_method <- ifelse(fixed[ix], NA_character_, "Profile likelihood")
  r$parameters<-rbind(r$parameters,parameters)
  r$curve<-rbind(r$curve,data.frame(series=g,group=g,x=grid,fit=curve));r$diagnostics<-rbind(r$diagnostics,data.frame(series=g,x=a$x,observed=a$value,fitted=pred,residual=a$value-pred))
 }
 residual<-data$value-evaluate(estimates)
 r$metrics<-rbind(pc_metric('Fit design','Global joint least squares'),pc_metric('Shared parameters',paste(shared,collapse=', ')),pc_metric('Joint free parameters',length(free)),pc_metric('Residual degrees of freedom',df),pc_metric('SSE (original Y scale)',pc_fmt(sum(residual^2))),pc_metric('Weighted SSE',pc_fmt(sum(weights*residual^2))),pc_metric('Joint residual SD',pc_fmt(sqrt(sum(weights*residual^2)/df))))
 r$fit_status<-data.frame(series=groups,status='Fitted',detail='Global fit; shared and local coefficients estimated jointly')
 r$notes<-c('Global fit: shared parameters have one joint estimated value; other parameters are local to each series. Bounds for a shared parameter are intersected across groups; conflicting fixed values reject the analysis.','Residual degrees of freedom count each joint free parameter once. Local Wald intervals use the joint covariance and joint residual degrees of freedom, conditional on fixed values. Fixed and active-bound intervals are omitted. No automatic group-difference P value or confidence band is provided.',if(any(!is.finite(se[setdiff(free,active)]))) 'Parameter uncertainty is unavailable for one or more free coefficients; check model identifiability and data coverage.',
    'Global fitting assumes independent residuals; it is not a repeated-measures or mixed-effects analysis.',if(method=='threepl')'Three-parameter dose response fixes the Hill coefficient at +1 for an increasing response.',if(length(active))'One or more parameters reached a bound; their uncertainty is not reported.')
 if (profile) r$notes[2] <- paste('Residual degrees of freedom count each joint free parameter once.', pc_profile_note(), 'Fixed and active-bound intervals are omitted.')
 if (method %in% pc_nonlinear_methods() && length(free)>12L) r$notes <- c(r$notes, 'Shared fits with more than 12 free parameters use Wald intervals.')
 r
}

pc_rename_fit_groups<-function(s,old,new) {
 if(is.null(s$fit_constraints)||s$fit_constraints=='{}')return(s)
 rules<-pc_fit_constraints(s$fit_constraints)
 for(method in names(rules)) {
  names_old<-names(rules[[method]]$groups)
  if(length(names_old)) {ix<-match(names_old,old);names_old[!is.na(ix)]<-new[ix[!is.na(ix)]];names(rules[[method]]$groups)<-names_old}
 }
 s$fit_constraints<-as.character(jsonlite::toJSON(rules,auto_unbox=TRUE));s
}
