# Refit references for the installed module matching the adjacent source version.
# Native reference fits are built from imported CSVs without module helpers.
# Independent one-class anchors use stats::lm, nlme::lme and MASS::polr.
options(digits = 15)
script <- sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1L])
root <- Sys.getenv("TRAJECTORIES_VALIDATION_DIR", unset = dirname(normalizePath(script)))
project <- Sys.getenv("TRAJECTORIES_PROJECT_DIR", unset = dirname(root))
module <- Sys.getenv("TRAJECTORIES_MODULE_DIR", unset =
  if (file.exists(file.path(project, "DESCRIPTION"))) project else file.path(project, "jaspTrajectories"))
dir.create(file.path(root, "data"), showWarnings = FALSE)
dir.create(file.path(root, "results"), showWarnings = FALSE)
dir.create(file.path(root, "plots"), showWarnings = FALSE)
for (p in c("lcmm", "jaspTrajectories", "jaspBase", "nlme", "MASS", "ggplot2"))
  stopifnot(requireNamespace(p, quietly = TRUE))
sourceVersion <- read.dcf(file.path(module, "DESCRIPTION"), fields = "Version")[[1L]]
stopifnot(as.character(packageVersion("lcmm")) == "2.2.2",
          as.character(packageVersion("jaspTrajectories")) == sourceVersion)
cat("Reference generation: jaspTrajectories ", sourceVersion, "; lcmm 2.2.2; fresh fits only.\n", sep = "")
writeCsv <- function(x, path) write.csv(x, file.path(root, path), row.names = FALSE, na = "")

# These are package example datasets, both simulated, not patient observations.
data("data_hlme", package = "lcmm")
data("data_lcmm", package = "lcmm")
data("paquid", package = "lcmm")
continuous <- data.frame(subject = data_hlme$ID, time = data_hlme$Time,
                         outcome = data_hlme$Y)
ordinal <- data.frame(subject = data_lcmm$ID, time = data_lcmm$Time,
                      outcome = data_lcmm$Ydep3)
stopifnot(!anyNA(continuous), !anyNA(ordinal))
writeCsv(continuous, "data/lcmm-continuous.csv")
writeCsv(ordinal, "data/lcmm-ordinal.csv")
writeCsv(data.frame(subject = paquid$ID, time = paquid$age, outcome = paquid$HIER),
         "data/paquid-ordinal.csv")
# Retain rows and remove exactly one response from each of the first ten IDs.
missing <- continuous
missingRows <- match(unique(missing$subject)[seq_len(10L)], missing$subject)
missing$outcome[missingRows] <- NA_real_
writeCsv(missing, "data/lcmm-continuous-missing.csv")
writeCsv(data.frame(row = missingRows, subject = continuous$subject[missingRows],
                    time = continuous$time[missingRows],
                    removedOutcome = continuous$outcome[missingRows]),
         "results/missingness-audit.csv")

cases <- data.frame(
  case = c("C01", "C02", "C03", "C04", "C05", "C06", "C07", "O01", "O02", "O03", "M01", "M02"),
  file = c(rep("lcmm-continuous.csv", 7), rep("lcmm-ordinal.csv", 3),
           rep("lcmm-continuous-missing.csv", 2)),
  outcomeType = c(rep("continuous", 7), rep("ordinal", 3), rep("continuous", 2)),
  model = c(rep("lcga", 4), rep("gmm", 3), "lcga", "lcga", "gmm", "lcga", "lcga"),
  classes = c(1L, 1L, 1L, 2L, 1L, 2L, 1L, 1L, 2L, 1L, 1L, 1L),
  degree = c("linear", "quadratic", "cubic", rep("linear", 4), rep("quadratic", 3), rep("linear", 2)),
  randomEffects = c(rep("intercept", 4), rep("interceptSlope", 3), rep("intercept", 5)),
  covariance = c(rep("unstructured", 6), "diagonal", rep("unstructured", 5)),
  missing = c(rep("available", 11), "completeSubjects"),
  classVariance = FALSE, starts = 30L, startIterations = 50L,
  maxIterations = 1000L, seed = 12345L, stringsAsFactors = FALSE)
paquidCases <- cases[rep(10L, 2L), ]
paquidCases$case <- c("P01", "P02")
paquidCases$file <- "paquid-ordinal.csv"
paquidCases$degree <- "linear"
paquidCases$missing <- c("available", "completeSubjects")
cases <- rbind(cases, paquidCases)
writeCsv(cases, "model-settings.csv")

prepareNative <- function(d, s) {
  use <- !is.na(d$outcome)
  if (s$missing == "completeSubjects")
    use <- !d$subject %in% d$subject[is.na(d$outcome)]
  kept <- d[use, , drop = FALSE]
  ids <- match(kept$subject, unique(d$subject))
  origin <- min(kept$time)
  span <- diff(range(kept$time))
  y <- kept$outcome
  if (s$outcomeType == "ordinal") y <- match(y, sort(unique(y)))
  x <- data.frame(id = ids, originalSubject = kept$subject, originalTime = kept$time,
                  t = (kept$time - origin) / span, y = y)
  x <- x[order(x$id, x$t), , drop = FALSE]
  list(data = x, origin = origin, span = span,
       counts = c(inputRows = nrow(d), inputSubjects = length(unique(d$subject)),
                  missingOutcomes = sum(is.na(d$outcome)), retainedRows = nrow(x),
                  retainedSubjects = length(unique(x$id)), excludedRows = sum(!use),
                  excludedSubjects = length(unique(d$subject)) - length(unique(x$id))))
}

fitNative <- function(x, s, requireConvergence = TRUE) {
  # Explicit no-random-effects formula, rather than the module's omitted argument.
  fixed <- switch(s$degree, linear = y ~ t, quadratic = y ~ t + I(t^2),
                  cubic = y ~ t + I(t^2) + I(t^3))
  random <- if (s$model == "lcga") ~ -1 else if (s$randomEffects == "intercept") ~ 1 else ~ t
  hlme <- lcmm::hlme
  lcmm <- lcmm::lcmm
  fun <- if (s$outcomeType == "continuous") "hlme" else "lcmm"
  args <- list(fixed = fixed, random = random, subject = "id", data = quote(x),
               ng = 1L, idiag = s$covariance == "diagonal", nwg = FALSE,
               maxiter = s$maxIterations, na.action = 2L, verbose = FALSE,
               returndata = TRUE, var.time = "t")
  if (s$outcomeType == "ordinal") args$link <- "thresholds"
  set.seed(s$seed)
  base <- eval(as.call(c(list(as.name(fun)), args)))
  stopifnot(base$conv == 1L)
  if (s$classes == 1L) return(base)
  args$ng <- s$classes
  args$mixture <- switch(s$degree, linear = ~ t, quadratic = ~ t + I(t^2),
                         cubic = ~ t + I(t^2) + I(t^3))
  args$nwg <- s$classVariance
  modelCall <- as.call(c(list(as.name(fun)), args))
  fit <- eval(substitute(lcmm::gridsearch(m = MODEL, rep = STARTS,
                       maxiter = ITERATIONS, minit = base),
                       list(MODEL = modelCall, STARTS = s$starts,
                            ITERATIONS = s$startIterations)))
  if (requireConvergence) stopifnot(fit$conv == 1L)
  fit
}

fitModule <- function(d, s) {
  # Exercise the real exported JASP analysis and option-name mapping.
  opts <- as.list(s[, setdiff(names(s), c("case", "file")), drop = FALSE])
  opts <- c(opts, list(subjectID = "subject", time = "time", outcome = "outcome",
                       parameterTable = TRUE, classTable = TRUE,
                       trajectoryPlot = TRUE, confidenceBands = FALSE))
  if (s$outcomeType == "ordinal")
    d$outcome <- ordered(d$outcome, levels = sort(unique(d$outcome)))
  cpp <- jaspBase:::create_cpp_jaspResults("Trajectories", NULL)
  cpp$setOptions(jsonlite::toJSON(opts, auto_unbox = TRUE))
  results <- jaspBase:::jaspResultsR$new(cpp)
  jaspTrajectories::Trajectories(results, d, opts)
  if (is.null(results[["fittedModel"]])) stop("JASP analysis produced no model for ", s$case)
  stopifnot(inherits(results[["trajectories"]]$plotObject, "ggplot"))
  ggplot2::ggsave(file.path(root, "plots", paste0(s$case, ".png")),
                  results[["trajectories"]]$plotObject, width = 7, height = 4.5, dpi = 110)
  results[["fittedModel"]]$object
}

checks <- list()
check <- function(case, test, actual, expected, tolerance) {
  actual <- unlist(actual, use.names = FALSE)
  expected <- unlist(expected, use.names = FALSE)
  delta <- max(abs(as.numeric(actual) - as.numeric(expected)))
  pass <- length(actual) == length(expected) && is.finite(delta) && delta <= tolerance
  checks[[length(checks) + 1L]] <<- data.frame(case = case, check = test,
    maximumAbsoluteDifference = delta, tolerance = tolerance, passed = pass)
  if (!pass) stop(case, ": ", test, " failed; difference ", delta)
}

allMetrics <- allCounts <- allParameters <- allClasses <- allPredictions <- anchors <- stability <- list()
for (i in seq_len(nrow(cases))) {
  s <- cases[i, , drop = FALSE]
  cat("RUN ", s$case, ": ", s$outcomeType, " ", s$model, " ", s$classes,
      " class(es), ", s$degree, "\n", sep = ""); flush.console()
  d <- read.csv(file.path(root, "data", s$file))
  prep <- prepareNative(d, s)
  x <- prep$data
  savedPath <- file.path(root, "results", paste0(s$case, "-models.rds"))
  # Always refit both paths: historical results are not evidence for this build.
  native <- fitNative(x, s)
  module <- fitModule(d, s)
  check(s$case, "native versus module log-likelihood", module$fit$loglik, native$loglik, 1e-5)
  check(s$case, "native versus module full parameter vector (same seed/class order)", module$fit$best, native$best, 1e-4)
  check(s$case, "independent sample counts", unlist(module$counts), prep$counts, 0)
  check(s$case, "convergence code", module$fit$conv, 1, 0)
  p <- length(native$best)
  n <- length(unique(x$id))
  check(s$case, "AIC formula", native$AIC, -2 * native$loglik + 2 * p, 1e-7)
  check(s$case, "BIC formula uses subjects", native$BIC, -2 * native$loglik + p * log(n), 1e-7)
  metrics <- as.data.frame(lcmm::summarytable(native, which = c("G", "loglik", "npm", "AIC", "BIC", "SABIC", "entropy"), display = FALSE))
  allMetrics[[i]] <- cbind(case = s$case, metrics, convergence = native$conv,
                         iterations = native$niter, timeOrigin = prep$origin, timeScale = prep$span)
  allCounts[[i]] <- data.frame(case = s$case, measure = names(prep$counts), count = as.integer(prep$counts))
  invisible(capture.output(parameters <- summary(native, long = 1000L)))
  allParameters[[i]] <- data.frame(case = s$case, term = rownames(parameters), estimate = parameters[, 1],
                                    se = parameters[, 2], statistic = parameters[, 3], p = parameters[, 4], row.names = NULL)
  probs <- as.matrix(native$pprob[, 2L + seq_len(s$classes), drop = FALSE])
  modal <- native$pprob[, 2L]
  allClasses[[i]] <- data.frame(case = s$case, class = seq_len(s$classes),
    assigned = tabulate(modal, nbins = s$classes),
    assignedPercent = 100 * tabulate(modal, nbins = s$classes) / n,
    posteriorCount = colSums(probs),
    averagePosterior = vapply(seq_len(s$classes), function(g) mean(probs[modal == g, g]), numeric(1)))
  times <- seq(min(x$originalTime), max(x$originalTime), length.out = 101L)
  np <- lcmm::predictY(native, newdata = data.frame(t = (times - prep$origin) / prep$span),
                       var.time = "t", draws = FALSE)$pred
  mp <- jaspTrajectories::trajectoryPredictions(module, times = times, confidence = FALSE)
  check(s$case, "mean-trajectory predictions", mp$predicted, as.vector(np), 1e-4)
  check(s$case, "posterior class probabilities", module$fit$pprob[, -(1:2)], probs, 1e-4)
  allPredictions[[i]] <- data.frame(case = s$case, time = rep(times, s$classes),
                                     class = rep(seq_len(s$classes), each = length(times)), predicted = as.vector(np))

  if (s$classes == 1L) {
    f <- switch(s$degree, linear = y ~ t, quadratic = y ~ t + I(t^2), cubic = y ~ t + I(t^2) + I(t^3))
    if (s$outcomeType == "continuous" && s$model == "lcga") {
      anchor <- lm(f, data = x)
      method <- "stats::lm (Gaussian ML likelihood)"
      fixed <- coef(anchor)
      nativeFixed <- native$best[seq_along(fixed)]
    } else if (s$outcomeType == "continuous") {
      re <- if (s$randomEffects == "intercept") ~ 1 else ~ t
      structure <- if (s$covariance == "diagonal") nlme::pdDiag(re) else nlme::pdSymm(re)
      anchor <- nlme::lme(f, random = list(id = structure), data = x, method = "ML",
                          control = nlme::lmeControl(msMaxIter = 1000L))
      method <- "nlme::lme (ML, same random-effects structure)"
      fixed <- nlme::fixed.effects(anchor)
      nativeFixed <- native$best[seq_along(fixed)]
    } else if (s$model == "lcga") {
      x$y <- ordered(x$y)
      anchor <- MASS::polr(f, data = x, method = "probit", Hess = TRUE,
                            control = list(maxit = 2000L, reltol = 1e-12))
      method <- "MASS::polr (ordered probit)"
      fixed <- coef(anchor)
      # lcmm fixes the first intercept at zero; polr absorbs it into cutpoints.
      nativeFixed <- native$best[seq_along(fixed)]
    } else {
      anchor <- NULL
    }
    if (!is.null(anchor)) {
      check(s$case, "independent estimator log-likelihood", native$loglik, as.numeric(logLik(anchor)), 1e-3)
      check(s$case, "independent estimator fixed effects", nativeFixed, fixed, 1e-3)
      anchors[[length(anchors) + 1L]] <- data.frame(case = s$case, method = method,
        nativeLogLik = native$loglik, independentLogLik = as.numeric(logLik(anchor)),
        logLikDifference = native$loglik - as.numeric(logLik(anchor)),
        maximumFixedEffectDifference = max(abs(nativeFixed - fixed)))
    }
  }
  saveRDS(list(settings = s, native = native, module = module), savedPath)
  if (s$classes > 1L) {
    for (otherSeed in c(3821L, 54321L)) {
      other <- s; other$seed <- otherSeed
      refit <- tryCatch(fitNative(x, other, requireConvergence = FALSE), error = identity)
      # Record rather than conceal local-optimum variability.
      failed <- inherits(refit, "error")
      conv <- if (failed) NA_integer_ else refit$conv
      ll <- if (failed) NA_real_ else refit$loglik
      stability[[length(stability) + 1L]] <- data.frame(case = s$case, seed = otherSeed,
        convergence = conv, loglik = ll, differenceFromReference = ll - native$loglik,
        sameLikelihoodWithin0_001 = !failed && conv == 1L && abs(ll - native$loglik) <= 0.001,
        note = if (failed) conditionMessage(refit) else if (conv != 1L) "Did not reach full convergence; likelihood is not a validated solution" else "")
      cat("SEED ", otherSeed, ": convergence = ", conv, "; logLik = ", ll, "\n", sep = ""); flush.console()
    }
  }
  cat("PASS ", s$case, ": logLik = ", format(native$loglik, digits = 12), "\n", sep = ""); flush.console()
}

tables <- list("expected-fit.csv" = allMetrics, "expected-sample.csv" = allCounts,
  "expected-coefficients.csv" = allParameters, "expected-classification.csv" = allClasses,
  "expected-predictions.csv" = allPredictions, "independent-estimators.csv" = anchors,
  "seed-stability.csv" = stability, "automated-checks.csv" = checks)
for (name in names(tables)) writeCsv(do.call(rbind, tables[[name]]), paste0("results/", name))
record <- cbind(do.call(rbind, allMetrics)[, c("case", "loglik", "AIC", "BIC")],
  actualLogLik = "", actualAIC = "", actualBIC = "", sampleCountsMatch = "",
  coefficientsMatch = "", classSizesMatch = "", plotMatches = "", notes = "")
# Preserve the user's manual results on subsequent runs.
if (!file.exists(file.path(root, "jasp-checklist.csv"))) writeCsv(record, "jasp-checklist.csv")
capture.output(sessionInfo(), file = file.path(root, "results", "session-info.txt"))
cat("ALL ", length(checks), " AUTOMATED CHECKS PASSED across ", nrow(cases), " cases.\n", sep = "")
