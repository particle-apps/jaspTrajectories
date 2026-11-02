# Statistical adapter for lcmm. All model syntax is constructed from fixed,
# internal names: user-supplied column names are never parsed as R expressions.

.trajectoryInteger <- function(x, name, minimum = 1L, maximum = .Machine$integer.max) {
  if (!is.numeric(x) || length(x) != 1L || is.na(x) || !is.finite(x) ||
      x != floor(x) || x < minimum || x > maximum)
    stop(name, " must be an integer between ", minimum, " and ", maximum, ".", call. = FALSE)
  as.integer(x)
}

.trajectoryLogical <- function(x, name) {
  if (!is.logical(x) || length(x) != 1L || is.na(x))
    stop(name, " must be TRUE or FALSE.", call. = FALSE)
  x
}

.trajectoryWithSeed <- function(seed, expression) {
  hadSeed <- exists(".Random.seed", envir = .GlobalEnv, inherits = FALSE)
  if (hadSeed) previousSeed <- get(".Random.seed", envir = .GlobalEnv, inherits = FALSE)
  on.exit({
    if (hadSeed) {
      assign(".Random.seed", previousSeed, envir = .GlobalEnv)
    } else if (exists(".Random.seed", envir = .GlobalEnv, inherits = FALSE)) {
      rm(".Random.seed", envir = .GlobalEnv)
    }
  }, add = TRUE)
  set.seed(seed)
  force(expression)
}

.trajectoryConverged <- function(fit, stage) {
  if (!identical(as.integer(fit$conv), 1L) || !is.finite(fit$loglik)) {
    message <- paste0(stage, " did not converge successfully (lcmm convergence code ",
                      fit$conv, "). No alternative model has been substituted. ",
                      "Review the model and data, or increase the iteration limit or number of starts.")
    stop(structure(list(message = message, call = NULL, fit = fit, stage = stage),
                   class = c("trajectoryConvergenceError", "error", "condition")))
  }
  invisible(fit)
}

.trajectoryResult <- function(result) {
  if (!inherits(result, "trajectoryFit"))
    stop("result must be returned by fitTrajectories().", call. = FALSE)
  .trajectoryConverged(result$fit, "Selected model")
  invisible(result)
}

#' Fit a Gaussian or ordinal latent class growth model
#'
#' LCGA omits random effects. GMM uses a random intercept, optionally with a
#' random linear slope, independently of the degree of the mean trajectory.
#' Ordinal outcomes use lcmm's threshold link; numeric categories are ordered
#' numerically and ordered factors retain their declared order. Category scores
#' are recoded to consecutive integers and their mapping is returned.
#'
#' Available-case estimation removes missing outcome records while retaining
#' other measurements from the same participant. Complete-subject estimation
#' excludes participants with any missing outcome among their supplied records;
#' it does not infer an unrecorded visit schedule. IDs and times must be complete.
#'
#' Time is transformed to (time - origin) / scale, where origin and scale are
#' the minimum and range of retained measurement times. Polynomial coefficients
#' and random slopes refer to this transformed time. The fit uses native lcmm
#' maximum likelihood and its native multistart grid search, not a new estimator.
#'
#' @export
fitTrajectories <- function(data, id, time, outcome, classes = 2L, degree = 1L,
                            model = "lcga", random = "intercept",
                            covariance = "unstructured", classVariance = FALSE,
                            starts = 10L, startIterations = 20L,
                            maxIterations = 500L, seed = 12345L,
                            missing = "available", outcomeType = "continuous") {
  if (!requireNamespace("lcmm", quietly = TRUE))
    stop("The lcmm package must be installed to estimate trajectories.", call. = FALSE)
  model <- match.arg(model, c("lcga", "gmm"))
  random <- match.arg(random, c("intercept", "slope"))
  covariance <- match.arg(covariance, c("unstructured", "diagonal"))
  missing <- match.arg(missing, c("available", "completeSubjects"))
  outcomeType <- match.arg(outcomeType, c("continuous", "ordinal"))
  classes <- .trajectoryInteger(classes, "classes")
  degree <- .trajectoryInteger(degree, "degree", maximum = 3L)
  starts <- .trajectoryInteger(starts, "starts")
  startIterations <- .trajectoryInteger(startIterations, "startIterations")
  maxIterations <- .trajectoryInteger(maxIterations, "maxIterations")
  seed <- .trajectoryInteger(seed, "seed", minimum = 0L)
  classVariance <- .trajectoryLogical(classVariance, "classVariance")
  if (classVariance && (model != "gmm" || classes == 1L))
    stop("Class-specific proportional random-effect variances require a GMM with at least two classes.", call. = FALSE)

  if (!is.data.frame(data) || nrow(data) == 0L)
    stop("data must be a nonempty data frame in long format.", call. = FALSE)
  if (anyDuplicated(names(data)))
    stop("Column names in data must be unique.", call. = FALSE)
  columns <- list(id = id, time = time, outcome = outcome)
  for (name in names(columns)) {
    column <- columns[[name]]
    if (!is.character(column) || length(column) != 1L || is.na(column) ||
        !column %in% names(data))
      stop(name, " must name one column in data.", call. = FALSE)
  }
  if (anyDuplicated(unlist(columns, use.names = FALSE)))
    stop("ID, time, and outcome must be different columns.", call. = FALSE)
  ids <- data[[id]]
  times <- data[[time]]
  outcomes <- data[[outcome]]
  if (!is.atomic(ids) || is.matrix(ids) || anyNA(ids) ||
      any(!nzchar(trimws(as.character(ids)))) ||
      (is.numeric(ids) && any(!is.finite(ids))))
    stop("IDs must be nonmissing, nonblank atomic values.", call. = FALSE)
  if (!is.numeric(times) || is.matrix(times) || anyNA(times) || any(!is.finite(times)))
    stop("Time must be numeric, finite, and nonmissing for every record.", call. = FALSE)
  idValues <- unique(ids)
  internalIds <- match(ids, idValues)
  if (anyDuplicated(data.frame(id = internalIds, time = times)))
    stop("Each participant must have at most one record at each measurement time; duplicate ID/time records were found.", call. = FALSE)
  if (outcomeType == "continuous") {
    if (!is.numeric(outcomes) || is.matrix(outcomes))
      stop("A continuous outcome must be numeric.", call. = FALSE)
  } else if (!is.ordered(outcomes) && (!is.numeric(outcomes) || is.matrix(outcomes))) {
    stop("An ordinal outcome must be an ordered factor or numeric categories with a known increasing order.", call. = FALSE)
  }
  if (is.numeric(outcomes) && any(!is.finite(outcomes[!is.na(outcomes)])))
    stop("Observed outcomes must be finite.", call. = FALSE)

  outcomeMissing <- is.na(outcomes)
  keep <- !outcomeMissing
  if (missing == "completeSubjects")
    keep <- !internalIds %in% unique(internalIds[outcomeMissing])
  if (!any(keep))
    stop("No observations remain after applying the missing-data rule.", call. = FALSE)
  retainedSubjects <- length(unique(internalIds[keep]))
  if (retainedSubjects < 2L || classes > retainedSubjects)
    stop("At least two retained participants, and at least as many participants as classes, are required.", call. = FALSE)
  if (length(unique(times[keep])) < degree + 1L)
    stop("The requested polynomial degree requires at least ", degree + 1L,
         " distinct retained measurement times.", call. = FALSE)

  outcomeLevels <- NULL
  if (outcomeType == "ordinal") {
    if (is.ordered(outcomes)) {
      observedLabels <- unique(as.character(outcomes[keep]))
      labels <- levels(outcomes)[levels(outcomes) %in% observedLabels]
      codedOutcome <- match(as.character(outcomes), labels)
    } else {
      labels <- sort(unique(outcomes[keep]))
      codedOutcome <- match(outcomes, labels)
    }
    if (length(labels) < 2L)
      stop("An ordinal outcome requires at least two observed categories after exclusions.", call. = FALSE)
    outcomeLevels <- data.frame(code = seq_along(labels), label = as.character(labels),
                                stringsAsFactors = FALSE)
  } else {
    codedOutcome <- outcomes
    if (length(unique(outcomes[keep])) < 2L)
      stop("The retained continuous outcome must vary.", call. = FALSE)
  }
  origin <- min(times[keep])
  scale <- max(times[keep]) - origin
  if (!is.finite(scale) || scale <= 0)
    stop("The range of retained measurement times must be finite and positive.", call. = FALSE)
  analysisData <- data.frame(.id = internalIds[keep],
                             .time = (times[keep] - origin) / scale,
                             .outcome = codedOutcome[keep],
                             .originalTime = times[keep],
                             .originalRow = which(keep))
  analysisData <- analysisData[order(analysisData$.id, analysisData$.time), , drop = FALSE]
  rownames(analysisData) <- NULL
  counts <- list(inputRows = nrow(data), inputSubjects = length(idValues),
                 missingOutcomes = sum(outcomeMissing), retainedRows = nrow(analysisData),
                 retainedSubjects = retainedSubjects, excludedRows = sum(!keep),
                 excludedSubjects = length(idValues) - retainedSubjects)
  settings <- list(id = id, time = time, outcome = outcome, classes = classes,
                   degree = degree, model = model, random = if (model == "gmm") random else "none",
                   covariance = covariance, classVariance = classVariance,
                   starts = starts, startIterations = startIterations,
                   maxIterations = maxIterations, seed = seed, missing = missing,
                   outcomeType = outcomeType, engine = if (outcomeType == "continuous") "hlme" else "lcmm",
                   lcmmVersion = as.character(utils::packageVersion("lcmm")),
                   timeTransform = list(origin = origin, scale = scale),
                   idMap = data.frame(internalId = seq_along(idValues), id = idValues),
                   outcomeLevels = outcomeLevels)

  # gridsearch uses match.call() and do.call(as.character(call[[1]])); it needs
  # an unqualified function symbol bound in its calling environment.
  evaluation <- new.env(parent = environment())
  evaluation$.analysisData <- analysisData
  evaluation$hlme <- lcmm::hlme
  evaluation$lcmm <- lcmm::lcmm
  terms <- c(".time", if (degree >= 2L) "I(.time^2)", if (degree >= 3L) "I(.time^3)")
  fixed <- stats::as.formula(paste(".outcome ~", paste(terms, collapse = " + ")), env = baseenv())
  arguments <- list(fixed = fixed, subject = ".id", ng = 1L,
                    data = quote(.analysisData), maxiter = maxIterations,
                    idiag = covariance == "diagonal", nwg = FALSE,
                    na.action = 2L, verbose = FALSE, returndata = TRUE, var.time = ".time")
  if (model == "gmm")
    arguments$random <- stats::as.formula(if (random == "intercept") "~ 1" else "~ .time", env = baseenv())
  if (outcomeType == "ordinal") arguments$link <- "thresholds"
  baselineCall <- as.call(c(list(as.name(settings$engine)), arguments))
  warningMessages <- character()
  result <- withCallingHandlers(.trajectoryWithSeed(seed, {
    baseline <- eval(baselineCall, envir = evaluation)
    .trajectoryConverged(baseline, "One-class starting model")
    fit <- baseline
    if (classes > 1L) {
      evaluation$.baseline <- baseline
      mixtureCall <- baselineCall
      mixtureCall$ng <- classes
      mixtureCall$nwg <- classVariance
      mixtureCall$mixture <- stats::as.formula(paste("~", paste(terms, collapse = " + ")), env = baseenv())
      searchCall <- substitute(lcmm::gridsearch(m = MODEL, rep = STARTS,
                                               maxiter = ITERATIONS, minit = .baseline),
                               list(MODEL = mixtureCall, STARTS = starts, ITERATIONS = startIterations))
      fit <- eval(searchCall, envir = evaluation)
      .trajectoryConverged(fit, "Requested mixture model")
    }
    list(fit = fit, baseline = baseline, data = analysisData, counts = counts,
         settings = settings)
  }), warning = function(warning) {
    warningMessages <<- c(warningMessages, conditionMessage(warning))
    invokeRestart("muffleWarning")
  })
  result$warnings <- unique(warningMessages)
  class(result) <- "trajectoryFit"
  result
}

#' Native lcmm model fit and classification indices
#' @export
trajectoryFitStatistics <- function(result, includeBaseline = FALSE) {
  .trajectoryResult(result)
  includeBaseline <- .trajectoryLogical(includeBaseline, "includeBaseline")
  fit <- result$fit
  indices <- c("G", "loglik", "conv", "npm", "AIC", "BIC", "SABIC", "entropy", "ICL1", "ICL2")
  if (includeBaseline && fit$ng > 1L) {
    baseline <- result$baseline
    values <- lcmm::summarytable(baseline, fit, which = indices, display = FALSE)
  } else {
    values <- lcmm::summarytable(fit, which = indices, display = FALSE)
  }
  as.data.frame(values, check.names = FALSE)
}

#' Native longitudinal coefficient table
#'
#' Values use the rounding in summary.hlme/summary.lcmm. Ordinal coefficients
#' describe the latent process, with its first-class intercept fixed to zero.
#' @export
trajectoryParameters <- function(result) {
  .trajectoryResult(result)
  output <- utils::capture.output(values <- summary(result$fit, long = 1000L))
  if (is.null(values) || ncol(values) != 4L)
    stop("lcmm did not return a longitudinal coefficient table.", call. = FALSE)
  data.frame(term = rownames(values), estimate = values[, 1L], se = values[, 2L],
             statistic = values[, 3L], p = values[, 4L], row.names = NULL,
             stringsAsFactors = FALSE)
}

#' Class trajectories in original measurement time
#'
#' Ordinal predictions are expected recoded category scores (1 through K), not
#' category probabilities. With confidence=TRUE, lcmm's ordinal prediction is
#' the median of parameter draws, with 2.5% and 97.5% limits. Gaussian intervals
#' are the native analytical 95% confidence intervals for the class mean.
#' @export
trajectoryPredictions <- function(result, times = NULL, confidence = TRUE, ndraws = 2000L) {
  .trajectoryResult(result)
  confidence <- .trajectoryLogical(confidence, "confidence")
  ndraws <- .trajectoryInteger(ndraws, "ndraws", minimum = 2L)
  if (is.null(times))
    times <- seq(min(result$data$.originalTime), max(result$data$.originalTime), length.out = 101L)
  if (!is.numeric(times) || !length(times) || anyNA(times) || any(!is.finite(times)))
    stop("Prediction times must be a nonempty finite numeric vector.", call. = FALSE)
  transform <- result$settings$timeTransform
  newdata <- data.frame(.time = (times - transform$origin) / transform$scale)
  predictionFit <- .trajectoryPredictionModel(result$fit)
  predictions <- .trajectoryWithSeed(result$settings$seed, {
    # Native ordinal prediction can allocate a square matrix of prediction times.
    # Bound memory for irregular data without changing the order or estimand.
    if (!confidence && result$settings$outcomeType == "ordinal" && nrow(newdata) > 200L) {
      chunks <- split(seq_len(nrow(newdata)), ceiling(seq_len(nrow(newdata)) / 200L))
      values <- lapply(chunks, function(rows) lcmm::predictY(predictionFit,
        newdata = newdata[rows, , drop = FALSE], var.time = ".time", draws = FALSE)$pred)
      list(pred = do.call(rbind, values))
    } else lcmm::predictY(predictionFit, newdata = newdata, var.time = ".time",
                          draws = confidence, ndraws = ndraws)
  })
  values <- as.matrix(predictions$pred)
  classes <- result$fit$ng
  if (nrow(values) != length(times) || ncol(values) != classes * if (confidence) 3L else 1L)
    stop("lcmm returned an unexpected prediction layout.", call. = FALSE)
  resultTable <- data.frame(time = rep(times, times = classes),
                            class = rep(seq_len(classes), each = length(times)),
                            predicted = as.vector(values[, seq_len(classes), drop = FALSE]),
                            lower = NA_real_, upper = NA_real_)
  if (confidence) {
    resultTable$lower <- as.vector(values[, classes + seq_len(classes), drop = FALSE])
    resultTable$upper <- as.vector(values[, 2L * classes + seq_len(classes), drop = FALSE])
  }
  attr(resultTable, "scale") <- if (result$settings$outcomeType == "ordinal") "expected category code" else "outcome"
  resultTable
}

#' Posterior class assignments and probabilities with original participant IDs
#' @export
trajectoryClassification <- function(result) {
  .trajectoryResult(result)
  values <- result$fit$pprob
  mapping <- result$settings$idMap
  resultTable <- data.frame(id = mapping$id[match(values[[1L]], mapping$internalId)],
                            class = values[[2L]])
  for (class in seq_len(result$fit$ng))
    resultTable[[paste0("prob", class)]] <- values[[class + 2L]]
  resultTable
}
