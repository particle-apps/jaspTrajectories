# Standalone checks: run Rscript tests/observed-fit.R from the module root.
# Requires lcmm and the saved validation/results/*-models.rds reference pack.
# No models are re-estimated. Small modified presentation fixtures isolate the
# aggregation rules; their new observations are not claimed to have been fitted.
script <- grep("^--file=", commandArgs(FALSE), value = TRUE)
moduleRoot <- if (length(script)) normalizePath(file.path(dirname(sub("^--file=", "", script[1L])), "..")) else normalizePath(".")
moduleRoot <- Sys.getenv("TRAJECTORIES_MODULE_DIR", unset = moduleRoot)
source(file.path(moduleRoot, "R", "engine.R"))
predictionSupport <- file.path(moduleRoot, "R", "predictionSupport.R")
if (file.exists(predictionSupport)) source(predictionSupport)
source(file.path(moduleRoot, "R", "observedFit.R"))
stopifnot(requireNamespace("lcmm", quietly = TRUE))
validationRoot <- Sys.getenv("TRAJECTORIES_VALIDATION_DIR", unset =
  if (dir.exists(file.path(moduleRoot, "validation"))) file.path(moduleRoot, "validation") else
    file.path(dirname(moduleRoot), "validation"))
referenceRoot <- file.path(validationRoot, "results")
passed <- 0L
check <- function(ok, label) {
  if (!isTRUE(ok)) stop(label, call. = FALSE)
  passed <<- passed + 1L
  cat(sprintf("PASS %02d: %s\n", passed, label))
}
sameNumbers <- function(actual, expected, tolerance = 1e-8) {
  a <- as.numeric(as.matrix(actual)); b <- as.numeric(as.matrix(expected))
  if (!identical(dim(actual), dim(expected)) || length(a) != length(b) ||
      !identical(is.na(a), is.na(b))) return(FALSE)
  observed <- !is.na(a)
  all(is.finite(a[observed])) && all(is.finite(b[observed])) &&
    all(abs(a[observed] - b[observed]) <= tolerance)
}
expectError <- function(expr, pattern, label) {
  error <- tryCatch({ force(expr); NULL }, error = identity)
  check(inherits(error, "error") && grepl(pattern, conditionMessage(error), ignore.case = TRUE), label)
}
readResult <- function(case) {
  path <- file.path(referenceRoot, paste0(case, "-models.rds"))
  if (!file.exists(path)) stop("Missing reference model: ", path)
  readRDS(path)$module
}

# The reference evaluates the native marginal means separately at EVERY row's
# actual time. Interval membership uses explicit inequalities, not cut(), and
# probabilities are retrieved by named subject identifiers.
manualSummary <- function(result, grouping, intervals = 10L) {
  d <- result$data
  t <- d$.originalTime
  uniqueTimes <- sort(unique(t))
  if (grouping == "auto") grouping <- if (length(uniqueTimes) <= 20L) "times" else "intervals"
  if (grouping == "times") {
    lower <- upper <- uniqueTimes
  } else {
    edges <- seq(min(t), max(t), length.out = intervals + 1L)
    lower <- head(edges, -1L); upper <- tail(edges, -1L)
  }
  transform <- result$settings$timeTransform
  predictions <- as.matrix(lcmm::predictY(result$fit,
    newdata = data.frame(.time = (t - transform$origin) / transform$scale),
    var.time = ".time", draws = FALSE)$pred)
  posterior <- result$fit$pprob
  summaries <- list()
  for (class in seq_len(result$fit$ng)) {
    lookup <- stats::setNames(posterior[[paste0("prob", class)]], as.character(posterior[[1L]]))
    w <- unname(lookup[as.character(d$.id)])
    for (g in seq_along(lower)) {
      included <- if (grouping == "times") t == lower[g] else
        t >= lower[g] & if (g == length(lower)) t <= upper[g] else t < upper[g]
      total <- sum(w[included])
      average <- function(values) if (total == 0) NA_real_ else sum(w[included] * values[included]) / total
      summaries[[length(summaries) + 1L]] <- data.frame(timeGroup = g,
        timeLower = lower[g], timeUpper = upper[g], time = average(t), class = class,
        observed = average(d$.outcome), fitted = average(predictions[, class]),
        rows = sum(included), subjects = length(unique(d$.id[included])), posteriorWeight = total)
    }
  }
  do.call(rbind, summaries)
}

cat(sprintf("R %s; lcmm %s\n", getRversion(), packageVersion("lcmm")))
cases <- c("C04", "C06", "C07", "O02", "O03", "M01", "M02")
for (case in cases) {
  result <- readResult(case)
  for (grouping in c("auto", "intervals")) {
    actual <- trajectoryObservedFit(result, grouping = grouping, intervals = 4L)
    expected <- manualSummary(result, grouping = grouping, intervals = 4L)
    check(identical(names(actual), names(expected)) && sameNumbers(actual, expected),
      paste(case, grouping, "means, times, counts and weights match independent sums/native predictions"))
  }
  check(all(vapply(split(actual$rows, actual$class), sum, numeric(1L)) == nrow(result$data)),
    paste(case, "every retained record contributes to exactly one interval per class"))
}
for (case in c("C04", "O02")) {
  result <- readResult(case)
  exact <- trajectoryObservedFit(result, grouping = "times")
  check(sameNumbers(exact, manualSummary(result, "times")),
    paste(case, "exact-time means match manual aggregation, including repeated times"))
}

result <- readResult("C04")
before <- serialize(result, NULL)
set.seed(324)
beforeRng <- .Random.seed
original <- trajectoryObservedFit(result, grouping = "intervals", intervals = 6L)
check(identical(beforeRng, .Random.seed), "summaries do not alter the caller's random-number state")
check(identical(before, serialize(result, NULL)), "summaries do not modify the saved fit or its data")
permuted <- result
permuted$data <- result$data[rev(seq_len(nrow(result$data))), , drop = FALSE]
permuted$fit$pprob <- result$fit$pprob[rev(seq_len(nrow(result$fit$pprob))), , drop = FALSE]
check(sameNumbers(original, trajectoryObservedFit(permuted, "intervals", 6L)),
  "data and posterior-row permutations preserve ID-matched summaries")

# Two subjects, unequal probabilities and deliberate boundary ties. The fitted
# coefficients remain unchanged: only observations used in a summary are varied.
toy <- readResult("C04")
ids <- unique(toy$data$.id)[1:2]
transform <- toy$settings$timeTransform
normalized <- c(0, 0.25, 0.5, 0.75, 1, 0.125, 0.25, 0.5, 0.625, 1)
toy$data <- data.frame(.id = rep(ids, each = 5L), .time = normalized,
  .outcome = c(1, 2, 4, 8, 16, 3, 6, 9, 12, 15),
  .originalTime = transform$origin + normalized * transform$scale, .originalRow = seq_along(normalized))
toy$fit$pprob <- toy$fit$pprob[match(ids, toy$fit$pprob[[1L]]), , drop = FALSE]
toy$fit$pprob$prob1 <- c(0.25, 0.75); toy$fit$pprob$prob2 <- c(0.75, 0.25)
toy$fit$pprob[[2L]] <- c(2L, 1L)
edge <- trajectoryObservedFit(toy, "intervals", 4L)
check(sameNumbers(edge, manualSummary(toy, "intervals", 4L)),
  "interval endpoints and ties use left-closed/right-open bins with final maximum included")
check(identical(as.integer(edge$rows[edge$class == 1L]), c(2L, 2L, 3L, 3L)),
  "minimum, exact internal boundaries and maximum occur in the intended bins")
check(abs(edge$observed[1L] - 2.5) < 1e-10 && abs(edge$posteriorWeight[1L] - 1) < 1e-10,
  "posterior-weighted observed means differ appropriately from unweighted or modal means")
check(attr(trajectoryObservedFit(toy), "grouping") == "times",
  "automatic grouping keeps a small number of distinct scheduled times exact")

# Exact endpoints constructed from the helper's own original time range must
# still work when intermediate bins contain no observations.
sparse <- toy
sparse$data <- toy$data[c(1L, 5L, 10L), , drop = FALSE]
empty <- trajectoryObservedFit(sparse, "intervals", 4L)
check(all(empty$rows[empty$timeGroup %in% 2:3] == 0L) &&
  all(empty$subjects[empty$timeGroup %in% 2:3] == 0L) &&
  all(empty$posteriorWeight[empty$timeGroup %in% 2:3] == 0) &&
  all(is.na(as.matrix(empty[empty$timeGroup %in% 2:3, c("time", "observed", "fitted")]))),
  "empty intervals retain zero counts and undefined means instead of fabricated zeros")
zero <- toy
zero$fit$pprob$prob1 <- 0; zero$fit$pprob$prob2 <- 1; zero$fit$pprob[[2L]] <- 2L
zeroSummary <- trajectoryObservedFit(zero, "intervals", 4L)
zeroClass <- zeroSummary$class == 1L
check(all(zeroSummary$posteriorWeight[zeroClass] == 0) &&
  all(is.na(as.matrix(zeroSummary[zeroClass, c("time", "observed", "fitted")]))) &&
  identical(zeroSummary$rows[zeroClass], edge$rows[edge$class == 1L]) &&
  identical(zeroSummary$subjects[zeroClass], edge$subjects[edge$class == 1L]),
  "zero class weights leave means undefined while retaining all-record group counts")

for (nTimes in c(20L, 21L)) {
  many <- toy
  st <- seq(0, 1, length.out = nTimes)
  many$data <- data.frame(.id = rep(ids, length.out = nTimes), .time = st,
    .outcome = seq_len(nTimes), .originalTime = transform$origin + st * transform$scale,
    .originalRow = seq_len(nTimes))
  grouped <- trajectoryObservedFit(many, "auto", 5L)
  check(attr(grouped, "grouping") == if (nTimes == 20L) "times" else "intervals",
    paste("automatic grouping selects the documented rule for", nTimes, "distinct times"))
}

curved <- readResult("C03")
curveSummary <- trajectoryObservedFit(curved, "intervals", 2L)
atMeanTime <- trajectoryPredictions(curved, times = curveSummary$time, confidence = FALSE)$predicted
check(sameNumbers(curveSummary, manualSummary(curved, "intervals", 2L)) &&
  max(abs(curveSummary$fitted - atMeanTime)) > 0.01,
  "curved fitted values are averages over actual times, not predictions at mean time")

ordinal <- readResult("O02")
ordinalSummary <- trajectoryObservedFit(ordinal, "intervals", 5L)
labelsChanged <- ordinal
labelsChanged$settings$outcomeLevels$label <- paste0("Category ", rev(seq_len(nrow(ordinal$settings$outcomeLevels))))
check(sameNumbers(ordinalSummary, trajectoryObservedFit(labelsChanged, "intervals", 5L)) &&
  attr(ordinalSummary, "scale") == "category code" &&
  all(ordinalSummary$observed >= 1 & ordinalSummary$observed <= nrow(ordinal$settings$outcomeLevels)) &&
  all(ordinalSummary$fitted >= 1 & ordinalSummary$fitted <= nrow(ordinal$settings$outcomeLevels)),
  "ordinal summaries use the fitted consecutive category codes independently of display labels")

bad <- toy; bad$fit$pprob <- bad$fit$pprob[1L, , drop = FALSE]
expectError(trajectoryObservedFit(bad), "missing", "missing subject posterior probabilities are rejected")
bad <- toy; bad$fit$pprob <- rbind(bad$fit$pprob, bad$fit$pprob[1L, ])
expectError(trajectoryObservedFit(bad), "layout|invalid", "duplicate posterior subject IDs are rejected")
bad <- toy; bad$fit$pprob$prob1[1L] <- NA_real_
expectError(trajectoryObservedFit(bad), "finite|probabil", "nonfinite posterior probabilities are rejected")
bad <- toy; bad$fit$pprob$prob1[1L] <- 0.9
expectError(trajectoryObservedFit(bad), "sum|probabil", "posterior probabilities that do not sum to one are rejected")
expectError(trajectoryObservedFit(toy, intervals = 1L), "intervals", "too few intervals are rejected")
expectError(trajectoryObservedFit(toy, intervals = 2.5), "integer|intervals", "noninteger interval counts are rejected")
expectError(trajectoryObservedFit(toy, grouping = "unknown"), "arg|group", "unknown grouping modes are rejected")
cat(sprintf("\nAll %d observed-versus-fitted checks passed. No models were re-estimated.\n", passed))
