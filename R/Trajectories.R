# Native JASP output adapter. Statistical fitting stays in the lcmm package.
utils::globalVariables(c("time", "predicted", "class", "lower", "upper",
                         "observed", "fitted", ".plotTime", ".segment"))
.trajectoryModelOptions <- c(
  "subjectID", "time", "outcome", "outcomeType", "model", "classes", "degree",
  "randomEffects", "covariance", "classVariance", "missing", "starts",
  "startIterations", "maxIterations", "seed"
)

.trajectoryCitation <- paste(
  "Proust-Lima, C., Philipps, V., & Liquet, B. (2017). Estimation of extended",
  "mixed models using latent classes and latent processes: The R package lcmm.",
  "Journal of Statistical Software, 78(2), 1-56. doi:10.18637/jss.v078.i02"
)

Trajectories <- function(jaspResults, dataset = NULL, options) {
  selected <- vapply(c("subjectID", "time", "outcome"), function(name) {
    length(options[[name]]) == 1L && nzchar(options[[name]])
  }, logical(1L))

  if (is.null(jaspResults[["modelFit"]])) {
    table <- createJaspTable(title = "Model Fit")
    table$dependOn(.trajectoryModelOptions)
    table$addCitation(.trajectoryCitation)
    jaspResults[["modelFit"]] <- table
  }
  if (!all(selected))
    return(invisible(NULL))

  if (is.null(jaspResults[["fittedModel"]])) {
    result <- tryCatch({
      if (is.null(dataset))
        stop("The dataset was not supplied by JASP. Reopen the analysis and assign the three variables.")
      # JASP ordinal columns can arrive as factors; retain the displayed level order.
      if (identical(options$outcomeType, "ordinal") && is.factor(dataset[[options$outcome]]))
        dataset[[options$outcome]] <- ordered(dataset[[options$outcome]],
                                            levels = levels(dataset[[options$outcome]]))
      degree <- c(linear = 1L, quadratic = 2L, cubic = 3L)[[options$degree]]
      fitTrajectories(
        dataset, id = options$subjectID, time = options$time, outcome = options$outcome,
        outcomeType = options$outcomeType, classes = options$classes, degree = degree,
        model = options$model,
        random = if (identical(options$randomEffects, "interceptSlope")) "slope" else "intercept",
        covariance = options$covariance,
        classVariance = identical(options$model, "gmm") && options$classes > 1L && isTRUE(options$classVariance),
        missing = options$missing, starts = options$starts,
        startIterations = options$startIterations,
        maxIterations = options$maxIterations, seed = options$seed
      )
    }, error = function(e) e)
    if (inherits(result, "error")) {
      jaspResults[["modelFit"]]$setError(conditionMessage(result))
      return(invisible(NULL))
    }
    state <- createJaspState()
    state$dependOn(.trajectoryModelOptions)
    state$object <- result
    jaspResults[["fittedModel"]] <- state
    .trajectoryFillFit(jaspResults[["modelFit"]], result)
  }
  result <- jaspResults[["fittedModel"]]$object

  if (is.null(jaspResults[["sample"]])) {
    counts <- result$counts
    sample <- data.frame(
      measure = c("Input rows", "Input subjects", "Missing outcome values",
                  "Retained outcome rows", "Retained subjects", "Excluded rows", "Excluded subjects"),
      count = as.integer(unlist(counts[c("inputRows", "inputSubjects", "missingOutcomes",
                                         "retainedRows", "retainedSubjects", "excludedRows", "excludedSubjects")]))
    )
    .trajectoryTable(jaspResults, "sample", "Analysis Sample", sample,
                     c(measure = "Measure", count = "Count"))
    jaspResults[["sample"]]$addFootnote(
      if (identical(options$missing, "available"))
        "Observed outcomes contribute under ignorable/MAR missingness assumptions. No missing cells are imputed."
      else "Subjects with any missing outcome at a recorded visit are excluded. Unrecorded visits are not inferred."
    )
  }

  if (isTRUE(options$parameterTable) && is.null(jaspResults[["parameters"]])) {
    parameters <- trajectoryParameters(result)
    .trajectoryTable(jaspResults, "parameters", "Growth Coefficients", parameters,
      c(term = "Term", estimate = "Estimate", se = "SE", statistic = "Wald statistic", p = "p"),
      "parameterTable")
    transform <- result$settings$timeTransform
    jaspResults[["parameters"]]$addFootnote(sprintf(
      "Coefficients use scaled time t = (time - %.6g) / %.6g. Plots use the original time scale. Estimates and uncertainty are supplied by lcmm's fixed-effect summary.",
      transform$origin, transform$scale))
    if (identical(options$outcomeType, "ordinal"))
      jaspResults[["parameters"]]$addFootnote("Ordinal coefficients refer to the underlying latent process, not changes in category scores. The first-class intercept is fixed for identification.")
  }

  if (isTRUE(options$classTable) && is.null(jaspResults[["classification"]])) {
    posterior <- trajectoryClassification(result)
    k <- result$fit$ng
    probs <- as.matrix(posterior[paste0("prob", seq_len(k))])
    modal <- tabulate(posterior$class, nbins = k)
    average <- vapply(seq_len(k), function(g) {
      if (modal[g] == 0L) NA_real_ else mean(probs[posterior$class == g, g])
    }, numeric(1L))
    classes <- data.frame(class = seq_len(k), assigned = modal,
                          assignedPercent = 100 * modal / nrow(posterior),
                          posteriorCount = colSums(probs), averagePosterior = average)
    .trajectoryTable(jaspResults, "classification", "Class Sizes and Classification", classes,
      c(class = "Class", assigned = "Assigned subjects", assignedPercent = "Assigned %",
        posteriorCount = "Posterior expected count", averagePosterior = "Mean assigned-class probability"),
      "classTable")
    jaspResults[["classification"]]$addFootnote("Modal assignments and posterior expected counts describe different quantities. Class labels are arbitrary; assess solution stability across starts.")
  }

  if (identical(options$outcomeType, "ordinal") && is.null(jaspResults[["categories"]])) {
    .trajectoryTable(jaspResults, "categories", "Ordinal Category Order", result$settings$outcomeLevels,
                     c(code = "Model code", label = "Category"))
    jaspResults[["categories"]]$addFootnote("The threshold model uses this order. The trajectory plot shows expected model codes; numeric gaps in the original labels are not used.")
  }

  if (isTRUE(options$trajectoryPlot) && is.null(jaspResults[["trajectories"]])) {
    plot <- createJaspPlot(title = "Class Trajectories", width = 640, height = 440)
    plot$dependOn(c(.trajectoryModelOptions, "trajectoryPlot", "confidenceBands"))
    plot$addCitation(.trajectoryCitation)
    jaspResults[["trajectories"]] <- plot
    tryCatch({
      predictions <- trajectoryPredictions(result, confidence = isTRUE(options$confidenceBands))
      plot$plotObject <- .trajectoryGraph(predictions, result, options$time, options$outcome)
    }, error = function(e) plot$setError(conditionMessage(e)))
  }

  if (isTRUE(options$observedFitPlot) && is.null(jaspResults[["observedFit"]])) {
    plot <- createJaspPlot(title = "Observed vs Fitted Trajectories", width = 720, height = 500)
    plot$dependOn(c(.trajectoryModelOptions, "observedFitPlot", "observedFitGrouping",
                   "observedFitIntervals", "observedFitPanels"))
    plot$addCitation(.trajectoryCitation)
    jaspResults[["observedFit"]] <- plot
    tryCatch({
      grouping <- if (is.null(options$observedFitGrouping)) "auto" else options$observedFitGrouping
      intervals <- if (is.null(options$observedFitIntervals)) 10L else options$observedFitIntervals
      means <- trajectoryObservedFit(result, grouping = grouping, intervals = intervals)
      panels <- is.null(options$observedFitPanels) || isTRUE(options$observedFitPanels)
      if (panels) plot$height <- 180 + 220 * ceiling(result$fit$ng / 2)
      plot$plotObject <- .trajectoryObservedGraph(means, result, options$time, options$outcome, panels)
    }, error = function(e) plot$setError(conditionMessage(e)))
  }
  invisible(NULL)
}

.trajectoryObservedGraph <- function(means, result, timeLabel = "Time", outcomeLabel = "Outcome", panels = TRUE) {
  grouping <- attr(means, "grouping")
  groupingText <- if (grouping == "times") "Means at each observed measurement time." else
    sprintf("Means within %d equal-width time intervals; x is posterior-weighted mean time.", attr(means, "intervals"))
  # Keep unsupported time groups as gaps rather than connecting across them.
  means$.plotTime <- ifelse(is.finite(means$time), means$time,
                            means$timeLower + (means$timeUpper - means$timeLower) / 2)
  means$.segment <- stats::ave(means$fitted, means$class, FUN = function(x) cumsum(!is.finite(x)))
  means$.segment <- interaction(means$class, means$.segment)
  means$class <- factor(means$class, levels = seq_len(result$fit$ng),
                         labels = paste("Class", seq_len(result$fit$ng)))
  plot <- ggplot2::ggplot(means, ggplot2::aes(x = .plotTime, colour = class)) +
    ggplot2::geom_line(ggplot2::aes(y = fitted, group = .segment), linewidth = 0.8, na.rm = TRUE) +
    ggplot2::geom_point(ggplot2::aes(y = fitted, shape = "Fitted mean"), size = 2.6, stroke = 0.8, na.rm = TRUE) +
    ggplot2::geom_point(ggplot2::aes(y = observed, shape = "Observed mean"), size = 1.9, na.rm = TRUE) +
    ggplot2::scale_shape_manual(name = NULL, values = c("Observed mean" = 16, "Fitted mean" = 1),
                                breaks = c("Observed mean", "Fitted mean"))
  if (panels) plot <- plot + ggplot2::facet_wrap(~ class, ncol = min(2L, result$fit$ng)) +
    ggplot2::guides(colour = "none")
  ordinal <- result$settings$outcomeType == "ordinal"
  caption <- paste(groupingText,
    "Both means use the same retained records and posterior class probabilities; fitted means are marginal.",
    if (ordinal) "Ordinal values use model category codes; see category order." else "",
    "Descriptive comparison on the fitting data; no confidence intervals.")
  plot + ggplot2::labs(x = timeLabel, y = if (ordinal) "Mean ordinal category code" else outcomeLabel,
                        colour = "Class", caption = paste(strwrap(caption, width = 100L), collapse = "\n")) +
    ggplot2::theme_classic(base_size = 12) +
    ggplot2::theme(legend.position = "bottom", plot.caption = ggplot2::element_text(hjust = 0))
}

.trajectoryFillFit <- function(table, result) {
  stats <- trajectoryFitStatistics(result)
  keep <- intersect(c("G", "loglik", "npm", "AIC", "BIC", "SABIC", "entropy"), names(stats))
  labels <- c(G = "Classes", loglik = "Log-likelihood", npm = "Parameters", AIC = "AIC",
              BIC = "BIC", SABIC = "Sample-size adjusted BIC", entropy = "Normalized entropy")
  .trajectoryColumns(table, stats[keep], labels)
  # Fixed decimals keep differences between nearby model fits visible.
  for (column in intersect(c("loglik", "AIC", "BIC", "SABIC"), keep))
    table$setColumnFormat(column, "dp:3")
  table$setData(stats[keep])
  table$addFootnote(sprintf("Estimator: lcmm %s, %s. Final convergence code: %s; iterations: %s. One requested class count is fitted; duplicate the analysis to compare another count.",
    as.character(utils::packageVersion("lcmm")),
    if (result$settings$outcomeType == "ordinal") "lcmm (thresholds)" else "hlme (Gaussian)",
    result$fit$conv, result$fit$niter))
  table$addFootnote("Information criteria use the retained subject count. Entropy describes classification and is not a test for the number of classes.")
  if (result$settings$model == "gmm")
    table$addFootnote("Random-effect covariance is shared or proportional across classes.")
  if (result$settings$outcomeType == "continuous")
    table$addFootnote("Gaussian residual variance is common across classes.")
  if (result$fit$ng > 1L)
    table$addFootnote("Native gridsearch optimizes the best preliminary start to completion. Recovery of a global maximum is not established.")
  for (warning in unique(result$warnings))
    table$addFootnote(warning)
}

.trajectoryColumns <- function(table, data, labels) {
  for (name in names(data)) {
    type <- if (name == "p") "pvalue" else if (is.integer(data[[name]])) "integer" else
      if (is.numeric(data[[name]])) "number" else "string"
    label <- if (name %in% names(labels)) labels[[name]] else name
    table$addColumnInfo(name = name, title = label, type = type)
  }
}

.trajectoryTable <- function(results, key, title, data, labels, extra = character()) {
  table <- createJaspTable(title = title)
  table$dependOn(c(.trajectoryModelOptions, extra))
  .trajectoryColumns(table, data, labels)
  results[[key]] <- table
  table$setData(data)
  invisible(table)
}

.trajectoryGraph <- function(predictions, result, timeLabel = "Time", outcomeLabel = "Outcome") {
  predictions$class <- factor(predictions$class)
  # Aesthetics use fixed internal names; original variable names are labels only.
  plot <- ggplot2::ggplot(predictions, ggplot2::aes(x = time, y = predicted,
                                                  colour = class, group = class))
  hasBands <- all(c("lower", "upper") %in% names(predictions)) &&
    any(is.finite(predictions$lower) & is.finite(predictions$upper))
  if (hasBands) {
    plot <- plot + ggplot2::geom_ribbon(ggplot2::aes(ymin = lower, ymax = upper, fill = class),
                                       colour = NA, alpha = 0.15, show.legend = FALSE)
  }
  yLabel <- if (result$settings$outcomeType == "ordinal") "Expected ordinal category code" else outcomeLabel
  caption <- if (result$settings$outcomeType == "ordinal")
    "Marginal expected category scores; see the category-order table." else "Class-specific mean trajectories."
  if (hasBands)
    caption <- paste(caption, "Pointwise 95% confidence bands.")
  if (hasBands && result$settings$outcomeType == "ordinal")
    caption <- paste(caption, "Lines show medians across parameter draws.")
  plot + ggplot2::geom_line(linewidth = 0.9) +
    ggplot2::labs(x = timeLabel, y = yLabel, colour = "Class",
      caption = paste(strwrap(caption, width = 80L), collapse = "\n")) +
    ggplot2::theme_classic(base_size = 12) +
    ggplot2::theme(legend.position = "bottom", plot.caption = ggplot2::element_text(hjust = 0))
}
