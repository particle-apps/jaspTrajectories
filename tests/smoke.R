# Standalone integration checks: Rscript tests/smoke.R from the module root.
# Uses the installed lcmm package; a JASP installation is not required.
# These small fixtures verify the adapter, not scientific performance or
# recovery of a global maximum for arbitrary mixture models.
args <- commandArgs(trailingOnly = FALSE)
scriptArg <- grep("^--file=", args, value = TRUE)
moduleRoot <- if (length(scriptArg)) {
  normalizePath(file.path(dirname(sub("^--file=", "", scriptArg[[1L]])), ".."))
} else normalizePath(".")
moduleRoot <- Sys.getenv("TRAJECTORIES_MODULE_DIR", unset = moduleRoot)
if (!requireNamespace("lcmm", quietly = TRUE)) stop("Install lcmm before running these tests.")
source(file.path(moduleRoot, "R", "engine.R"))
source(file.path(moduleRoot, "R", "predictionSupport.R"))

passed <- 0L
check <- function(condition, message) {
  if (!isTRUE(condition)) stop(message, call. = FALSE)
  passed <<- passed + 1L
  cat(sprintf("PASS %02d: %s\n", passed, message))
}
closeEnough <- function(actual, expected, tolerance = 1e-6) {
  isTRUE(all.equal(unname(actual), unname(expected), tolerance = tolerance,
    check.attributes = FALSE))
}
expectError <- function(expr, pattern, label) {
  error <- tryCatch({ force(expr); NULL }, error = identity)
  check(inherits(error, "error") && grepl(pattern, conditionMessage(error),
    ignore.case = TRUE), label)
  invisible(error)
}
examplePath <- file.path(moduleRoot, "examples", "trajectories-long.csv")
beforeHash <- unname(tools::md5sum(examplePath))
sampleData <- read.csv(examplePath, check.names = FALSE)
beforeData <- sampleData
cat(sprintf("R %s; lcmm %s\n", getRversion(), packageVersion("lcmm")))

# The caller helper below deliberately names all identifying variables: the
# adapter must never depend on a particular user's column names or ID encoding.
runFit <- function(data = sampleData, ...) {
  defaults <- list(data = data, id = "subject", time = "time",
    outcome = "continuousOutcome", outcomeType = "continuous",
    model = "lcga", classes = 1L, degree = 1L,
    starts = 3L, startIterations = 10L, maxIterations = 300L, seed = 3821L)
  supplied <- list(...)
  defaults[names(supplied)] <- supplied
  do.call(fitTrajectories, defaults)
}

# Available-outcome likelihood must match the same native lcmm model. The native
# reference is constructed independently from the user data, including its NAs.
one <- runFit()
nativeData <- sampleData
nativeData$numericId <- match(nativeData$subject, unique(nativeData$subject))
nativeData$scaledTime <- (nativeData$time - min(nativeData$time)) /
  diff(range(nativeData$time))
native <- lcmm::hlme(continuousOutcome ~ scaledTime, random = ~ -1,
  subject = "numericId", data = nativeData, ng = 1L, maxiter = 300L,
  na.action = 1L, verbose = FALSE)
check(closeEnough(one$fit$loglik, native$loglik),
  "available-outcome Gaussian likelihood agrees with native hlme")
check(closeEnough(one$fit$best, native$best),
  "Gaussian coefficient estimates agree with native hlme")
check(length(one$fit$cholesky) == 0L && one$fit$N[[3L]] == 0L,
  "LCGA contains no subject random effects")
check(one$counts$inputRows == 600L && one$counts$inputSubjects == 100L &&
  one$counts$missingOutcomes == 10L && one$counts$retainedRows == 590L &&
  one$counts$retainedSubjects == 100L && one$counts$excludedRows == 10L &&
  one$counts$excludedSubjects == 0L,
  "available-outcome counts retain partially observed subjects")
check(identical(one$data$.outcome,
  sampleData$continuousOutcome[one$data$.originalRow]) &&
  identical(one$data$.originalTime, sampleData$time[one$data$.originalRow]),
  "prepared observations retain correct links to original rows and times")

complete <- runFit(missing = "completeSubjects")
missingIds <- unique(sampleData$subject[is.na(sampleData$continuousOutcome)])
check(complete$counts$retainedRows == 540L && complete$counts$retainedSubjects == 90L &&
  complete$counts$excludedSubjects == 10L,
  "complete-subject mode drops only subjects with missing selected outcomes")
completeClassification <- trajectoryClassification(complete)
check(!any(completeClassification$id %in% missingIds),
  "complete-subject classification excludes removed subject IDs")

oddNames <- sampleData
names(oddNames)[match(c("subject", "time", "continuousOutcome"), names(oddNames))] <-
  c("Subject ID ()", "Time / years", "Outcome ' score")
odd <- runFit(oddNames, id = "Subject ID ()", time = "Time / years", outcome = "Outcome ' score")
check(closeEnough(odd$fit$loglik, one$fit$loglik),
  "non-syntactic column names and text IDs preserve the fitted likelihood")
check(setequal(trajectoryClassification(odd)$id, sampleData$subject),
  "classification restores original text subject IDs")

# A cubic no-random-effects model is ordinary Gaussian regression for one class.
# Comparing to lm verifies every polynomial term independently of hlme formulas.
cubic <- runFit(degree = 3L)
ols <- stats::lm(continuousOutcome ~ scaledTime + I(scaledTime^2) + I(scaledTime^3),
  data = nativeData)
check(closeEnough(cubic$fit$best[seq_len(4L)], stats::coef(ols), tolerance = 1e-5),
  "cubic trajectory includes all three time powers with correct scaling")

gmm <- runFit(model = "gmm", random = "slope", covariance = "unstructured")
check(length(gmm$fit$cholesky) == 3L && gmm$fit$N[[3L]] == 3L,
  "GMM supports correlated random intercepts and slopes")
diagonal <- runFit(model = "gmm", random = "slope", covariance = "diagonal")
check(diagonal$fit$idiag == 1L && diagonal$fit$N[[3L]] == 2L,
  "diagonal GMM omits the random intercept-slope covariance")

# Repeating a multistart fit with a fixed seed must be deterministic, while not
# altering the caller's RNG stream. No claim of a global optimum is made here.
set.seed(1964)
rngBefore <- .Random.seed
mixture <- runFit(classes = 2L)
check(identical(.Random.seed, rngBefore), "fitting restores the caller's random-number state")
mixtureRepeat <- runFit(classes = 2L)
check(closeEnough(mixture$fit$best, mixtureRepeat$fit$best, tolerance = 1e-10) &&
  closeEnough(mixture$fit$loglik, mixtureRepeat$fit$loglik, tolerance = 1e-10),
  "identical multistart seeds reproduce estimates and likelihood")
classification <- trajectoryClassification(mixture)
probabilityColumns <- grep("^prob[0-9]+$", names(classification), value = TRUE)
check(nrow(classification) == 100L && length(probabilityColumns) == 2L &&
  all(abs(rowSums(classification[probabilityColumns]) - 1) < 1e-8) &&
  all(as.matrix(classification[probabilityColumns]) >= 0) &&
  all(as.matrix(classification[probabilityColumns]) <= 1),
  "mixture posterior probabilities are valid for every retained subject")

predictionTimes <- c(0, 1.25, 2.5, 3.75, 5)
predictions <- trajectoryPredictions(mixture, times = predictionTimes,
  confidence = FALSE)
check(nrow(predictions) == 2L * length(predictionTimes) &&
  setequal(predictions$time, predictionTimes) && all(is.finite(predictions$predicted)),
  "continuous predictions have one value per requested original time and class")
intervals <- trajectoryPredictions(one, times = predictionTimes, confidence = TRUE,
  ndraws = 200L)
check(all(is.finite(intervals$lower)) && all(is.finite(intervals$upper)) &&
  all(intervals$lower <= intervals$upper), "continuous prediction intervals are finite and ordered")
statistics <- trajectoryFitStatistics(mixture)
check(all(c("G", "loglik", "conv", "npm", "AIC", "BIC", "SABIC", "entropy",
  "ICL1", "ICL2") %in% names(statistics)) &&
  closeEnough(statistics$loglik, mixture$fit$loglik) &&
  closeEnough(statistics$AIC, mixture$fit$AIC) &&
  closeEnough(statistics$BIC, mixture$fit$BIC),
  "reported model statistics match native lcmm output")
parameters <- trajectoryParameters(one)
invisible(utils::capture.output(nativeParameters <- summary(native)))
check(all(c("term", "estimate", "se", "statistic", "p") %in% names(parameters)) &&
  nrow(parameters) == nrow(nativeParameters) &&
  closeEnough(as.matrix(parameters[, c("estimate", "se", "statistic", "p")]),
    nativeParameters),
  "coefficient table retains the native longitudinal estimates, SEs, tests and p values")

# Ordered factor labels must follow the declared order, not lexical order.
ordinalData <- sampleData
labels <- c("Very low", "Low", "Middle", "High", "Very high")
ordinalData$ordinalOutcome <- ordered(ordinalData$ordinalOutcome, levels = 1:5,
  labels = labels)
ordinal <- runFit(ordinalData, outcome = "ordinalOutcome", outcomeType = "ordinal")
nativeOrdinal <- lcmm::lcmm(ordinalOutcome ~ scaledTime, random = ~ -1,
  subject = "numericId", data = nativeData, ng = 1L, link = "thresholds",
  maxiter = 300L, na.action = 1L, verbose = FALSE)
check(closeEnough(ordinal$fit$loglik, nativeOrdinal$loglik, tolerance = 1e-5),
  "ordinal threshold likelihood agrees with native lcmm")
check(identical(as.character(ordinal$settings$outcomeLevels$label), labels) &&
  identical(as.integer(ordinal$settings$outcomeLevels$code), 1:5),
  "ordered outcome category labels retain their declared order")
check(ordinal$counts$retainedRows == 590L && ordinal$counts$retainedSubjects == 100L &&
  length(ordinal$fit$cholesky) == 0L,
  "ordinal LCGA handles missing outcomes without introducing random effects")
ordinalPrediction <- trajectoryPredictions(ordinal, times = predictionTimes,
  confidence = FALSE)
nativeOrdinalPrediction <- lcmm::predictY(nativeOrdinal,
  newdata = data.frame(scaledTime = predictionTimes / 5), var.time = "scaledTime",
  draws = FALSE)
check(nrow(ordinalPrediction) == length(predictionTimes) &&
  all(ordinalPrediction$predicted >= 1 & ordinalPrediction$predicted <= 5) &&
  closeEnough(ordinalPrediction$predicted, nativeOrdinalPrediction$pred[, 1L], tolerance = 1e-5),
  "ordinal predictions match native expected category scores")
ordinalGmm <- runFit(outcome = "ordinalOutcome", outcomeType = "ordinal",
  model = "gmm", random = "intercept")
check(ordinalGmm$fit$N[[3L]] == 1L && length(ordinalGmm$fit$cholesky) == 1L,
  "ordinal GMM includes the selected subject random intercept")
ordinalMixture <- runFit(outcome = "ordinalOutcome", outcomeType = "ordinal", classes = 2L)
ordinalClasses <- trajectoryClassification(ordinalMixture)
ordinalProbabilityColumns <- grep("^prob[0-9]+$", names(ordinalClasses), value = TRUE)
check(nrow(ordinalClasses) == 100L && length(ordinalProbabilityColumns) == 2L &&
  all(abs(rowSums(ordinalClasses[ordinalProbabilityColumns]) - 1) < 1e-8),
  "ordinal mixture returns a valid posterior classification per subject")
ordinalMixturePrediction <- trajectoryPredictions(ordinalMixture, times = predictionTimes,
  confidence = FALSE)
check(nrow(ordinalMixturePrediction) == 2L * length(predictionTimes) &&
  all(is.finite(ordinalMixturePrediction$predicted)) &&
  all(ordinalMixturePrediction$predicted >= 1 & ordinalMixturePrediction$predicted <= 5),
  "ordinal mixture predictions cover each class and stay within category-code range")

expectError(runFit(classes = 0L), "class", "zero classes are rejected")
expectError(runFit(degree = 4L), "degree|polynomial", "unsupported polynomial degree is rejected")
expectError(runFit(outcome = "not a column"), "column|outcome|variable", "unknown outcome columns are rejected")
expectError(runFit(classVariance = TRUE), "variance|LCGA|class", "class covariance scaling is rejected for LCGA")
expectError(runFit(model = "gmm", classVariance = TRUE), "variance|class", "class covariance scaling needs multiple classes")
missingId <- sampleData; missingId$subject[[1L]] <- NA_character_
expectError(runFit(missingId), "ID|subject|missing", "missing subject identifiers are rejected")
badTime <- sampleData; badTime$time[[1L]] <- Inf
expectError(runFit(badTime), "time|finite", "nonfinite observation times are rejected")
duplicate <- rbind(sampleData, sampleData[1L, ])
expectError(runFit(duplicate), "duplicate|same|repeated", "duplicate subject-time observations are rejected")
unordered <- sampleData; unordered$ordinalOutcome <- factor(unordered$ordinalOutcome)
expectError(runFit(unordered, outcome = "ordinalOutcome", outcomeType = "ordinal"),
  "order", "unordered ordinal factor levels require an explicit order")
noOutcome <- sampleData; noOutcome$continuousOutcome[] <- NA_real_
expectError(runFit(noOutcome), "observ|missing|data|outcome", "an outcome with no observed values is rejected")

check(identical(sampleData, beforeData), "input data frame is unchanged after fitting and prediction")
check(identical(unname(tools::md5sum(examplePath)), beforeHash),
  "input CSV is unchanged after fitting and prediction")
cat(sprintf("\nAll %d checks passed. These checks do not replace an in-JASP installation/UI test.\n", passed))
