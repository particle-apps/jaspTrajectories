# Native ordinal prediction workaround checks. Run with the module's lcmm library.
# Known-parameter objects use maxiter=0 deliberately: these check the prediction
# equation, not estimation. Separate simulated models below must fully converge.
args <- commandArgs(trailingOnly = FALSE)
scriptArg <- grep("^--file=", args, value = TRUE)
moduleRoot <- if (length(scriptArg)) {
  normalizePath(file.path(dirname(sub("^--file=", "", scriptArg[[1L]])), ".."))
} else normalizePath(".")
moduleRoot <- Sys.getenv("TRAJECTORIES_MODULE_DIR", unset = moduleRoot)
source(file.path(moduleRoot, "R", "predictionSupport.R"))
stopifnot(requireNamespace("lcmm", quietly = TRUE))
passed <- 0L
check <- function(condition, label) {
  if (!isTRUE(condition)) stop(label, call. = FALSE)
  passed <<- passed + 1L
  cat(sprintf("PASS %02d: %s\n", passed, label))
}
near <- function(actual, expected, tolerance = 1e-10) {
  identical(dim(actual), dim(expected)) && length(actual) == length(expected) &&
    all(is.finite(actual)) && max(abs(actual - expected)) < tolerance
}

d <- expand.grid(id = seq_len(12L), t = c(0, .25, .5, .75, 1))
d <- d[order(d$id, d$t), ]
d$y <- 1L + as.integer((d$id + seq_len(nrow(d))) %% 3L == 0L)
toy <- lcmm::lcmm(y ~ t, random = ~t, subject = "id", data = d,
  idiag = TRUE, link = "thresholds", B = c(.5, 1, 4, 0), maxiter = 0)
# maxiter=0 omits a full Hessian. Point predictions do not use V; supply the
# structurally valid zero placeholder needed by the prediction-copy contract.
toy$V <- numeric(length(toy$best) * (length(toy$best) + 1L) / 2L)
before <- serialize(toy, NULL)
set.seed(77)
rng <- .Random.seed
copy <- .trajectoryPredictionModel(toy)
check(identical(serialize(toy, NULL), before), "prediction copy leaves the original fitted object unchanged")
check(identical(.Random.seed, rng), "prediction reparameterization does not consume random numbers")
check(copy$idiag == 0L && copy$N[3L] == 3L && copy$best[3L] == 0,
  "prediction copy adds a fixed zero random-effect covariance")

new <- data.frame(t = c(0, .25, .5, .75, 1))
# For a binary probit outcome coded 1/2, E[Y]=1+Phi(mu/sqrt(1+z'Dz)).
expected <- 1 + stats::pnorm(.5 * new$t / sqrt(2 + 4 * new$t^2))
pred <- lcmm::predictY(copy, newdata = new, var.time = "t", draws = FALSE)$pred[, 1L]
check(near(pred, expected), "binary ordinal predictions agree with the analytic marginal mean")
reversed <- lcmm::predictY(copy, newdata = new[5:1, , drop = FALSE],
  var.time = "t", draws = FALSE)$pred[, 1L]
check(near(reversed, rev(expected)), "ordinal predictions do not depend on prediction-row order")
single <- lcmm::predictY(copy, newdata = data.frame(t = .5),
  var.time = "t", draws = FALSE)$pred[, 1L]
check(near(single, expected[3L]), "a single prediction time preserves the analytic variance")

# Test native parameter draws against independently computed binary probit means.
# This positive covariance is synthetic uncertainty, not fitted inferential output.
uncertain <- toy
uncertain$conv <- 1L
V <- diag(.01, 4L)
uncertain$V <- V[upper.tri(V, diag = TRUE)]
uncertainCopy <- .trajectoryPredictionModel(uncertain)
set.seed(12)
nativeDraws <- lcmm::predictY(uncertainCopy, newdata = new,
  var.time = "t", draws = TRUE, ndraws = 1000L)$pred
set.seed(12)
z <- matrix(stats::rnorm(5000L), nrow = 5L)
parameters <- c(.5, 1, 0, 2, 0) + diag(c(.1, .1, 0, .1, .1)) %*% z
scores <- vapply(seq_len(ncol(parameters)), function(j) {
  1 + stats::pnorm((parameters[1L, j] * new$t - parameters[5L, j]) /
    sqrt(1 + parameters[2L, j]^2 + parameters[4L, j]^2 * new$t^2))
}, numeric(nrow(new)))
expectedDraws <- t(apply(scores, 1L, stats::quantile, c(.5, .025, .975)))
check(near(nativeDraws, expectedDraws), "native confidence draws agree with analytic probit draw calculations")

# Negative diagonal Cholesky values are valid optimizer parameters. Retain their
# signs and cross-covariances with other parameters when drawing uncertainty.
signed <- uncertain
signed$cholesky <- c(-1, 0, 2)
signedV <- diag(.01, 4L)
signedV[1L, 2L] <- signedV[2L, 1L] <- .004
signed$V <- signedV[upper.tri(signedV, diag = TRUE)]
signedCopy <- .trajectoryPredictionModel(signed)
check(identical(signedCopy$cholesky, signed$cholesky),
  "signed optimizer Cholesky parameters are preserved for uncertainty draws")
set.seed(92)
signedNative <- lcmm::predictY(signedCopy, newdata = new,
  var.time = "t", draws = TRUE, ndraws = 1000L)$pred
set.seed(92)
signedZ <- matrix(stats::rnorm(5000L), nrow = 5L)[c(1L, 2L, 4L, 5L), ]
signedParameters <- c(.5, -1, 2, 0) + t(chol(signedV)) %*% signedZ
signedScores <- vapply(seq_len(ncol(signedParameters)), function(j) {
  1 + stats::pnorm((signedParameters[1L, j] * new$t - signedParameters[4L, j]) /
    sqrt(1 + signedParameters[2L, j]^2 + signedParameters[3L, j]^2 * new$t^2))
}, numeric(nrow(new)))
signedExpected <- t(apply(signedScores, 1L, stats::quantile, c(.5, .025, .975)))
check(near(signedNative, signedExpected),
  "negative-Cholesky correlated confidence draws match the analytic marginal equation")

# An already fixed parameter after the insertion must be remapped as well.
fixed <- uncertain
fixed$call$posfix <- 4L
V[4L, ] <- V[, 4L] <- 0
fixed$V <- V[upper.tri(V, diag = TRUE)]
fixedCopy <- .trajectoryPredictionModel(fixed)
check(identical(as.integer(fixedCopy$call$posfix), c(3L, 5L)),
  "existing fixed-parameter indices shift around the inserted covariance")
fixedDraws <- lcmm::predictY(fixedCopy, newdata = new,
  var.time = "t", draws = TRUE, ndraws = 50L)$pred
check(all(is.finite(fixedDraws)), "native draws support the expanded fixed-parameter set")

# Verify class-specific proportional variance multipliers and parameter offsets.
d$y <- 1L + (seq_len(nrow(d)) %% 4L)
multi <- lcmm::lcmm(y ~ t, mixture = ~t, random = ~t, ng = 2L,
  subject = "id", data = d, idiag = TRUE, nwg = TRUE, link = "thresholds",
  B = c(log(.4 / .6), .8, .5, -.2, 1, 4, 1.3, -.7, sqrt(1.2), sqrt(.8)),
  maxiter = 0)
multi$V <- numeric(length(multi$best) * (length(multi$best) + 1L) / 2L)
multiCopy <- .trajectoryPredictionModel(multi)
multiPred <- lcmm::predictY(multiCopy, newdata = new, var.time = "t", draws = FALSE)$pred
thresholds <- c(-.7, .5, 1.3)
expectedMulti <- vapply(seq_len(2L), function(g) {
  mean <- if (g == 1L) .5 * new$t else .8 - .2 * new$t
  variance <- 1 + c(1.3^2, 1)[g] * (1 + 4 * new$t^2)
  1 + rowSums(vapply(thresholds, function(cut) stats::pnorm((mean - cut) /
    sqrt(variance)), numeric(nrow(new))))
}, numeric(nrow(new)))
check(near(multiPred, expectedMulti), "multiclass ordinal means preserve proportional random-effect variances")

# This separate ordinal GMM is estimated, not constructed from known parameters.
set.seed(1221)
id <- rep(seq_len(80L), each = 6L)
t <- rep(seq(0, 1, length.out = 6L), 80L)
b0 <- stats::rnorm(80L, 0, 1)
b1 <- stats::rnorm(80L, 0, 1.5)
y <- as.integer(cut(.9 * t + b0[id] + b1[id] * t + stats::rnorm(length(t)),
  c(-Inf, -.7, .5, 1.3, Inf)))
observed <- data.frame(id, t, y)
fitted <- lcmm::lcmm(y ~ t, random = ~t, idiag = TRUE, subject = "id",
  data = observed, link = "thresholds",
  B = c(.9, 1, 2.25, -.7, sqrt(1.2), sqrt(.8)), maxiter = 150L)
check(fitted$conv == 1L, "simulated diagonal ordinal random-slope GMM fully converges")
fittedBefore <- serialize(fitted, NULL)
fittedCopy <- .trajectoryPredictionModel(fitted)
fittedPred <- lcmm::predictY(fittedCopy, newdata = new, var.time = "t", draws = FALSE)$pred[, 1L]
cuts <- c(fitted$best[4L], fitted$best[4L] + cumsum(fitted$best[5:6]^2))
fittedExpected <- 1 + rowSums(vapply(cuts, function(cut) {
  stats::pnorm((fitted$best[1L] * new$t - cut) /
    sqrt(1 + fitted$best[2L] + fitted$best[3L] * new$t^2))
}, numeric(nrow(new))))
check(near(fittedPred, fittedExpected), "converged ordinal GMM predictions agree with the analytic marginal mean")
set.seed(433)
fittedDraws <- lcmm::predictY(fittedCopy, newdata = new, var.time = "t",
  draws = TRUE, ndraws = 100L)$pred
check(all(is.finite(fittedDraws)) && all(fittedDraws[, 2L] <= fittedDraws[, 1L]) &&
  all(fittedDraws[, 1L] <= fittedDraws[, 3L]), "converged ordinal GMM supplies finite ordered native confidence limits")
check(identical(serialize(fitted, NULL), fittedBefore), "point and interval predictions do not modify the estimated model")
check(identical(.trajectoryPredictionModel(fittedCopy), fittedCopy),
  "unstructured models bypass the workaround unchanged")

# Random-intercept-only diagonal models must also preserve signed uncertainty.
# Use correlated synthetic parameter uncertainty to expose the sign issue clearly.
binary <- expand.grid(id = seq_len(12L), t = c(0, .25, .5, .75, 1))
binary <- binary[order(binary$id, binary$t), ]
binary$y <- 1L + as.integer((binary$id + seq_len(nrow(binary))) %% 3L == 0L)
interceptToy <- lcmm::lcmm(y ~ t, random = ~1, subject = "id", data = binary,
  idiag = TRUE, link = "thresholds", B = c(.5, 1, 0), maxiter = 0)
interceptToy$conv <- 1L
interceptToy$cholesky <- -1
interceptV <- diag(.04, 3L)
interceptV[1L, 2L] <- interceptV[2L, 1L] <- .03
interceptToy$V <- interceptV[upper.tri(interceptV, diag = TRUE)]
interceptBefore <- serialize(interceptToy, NULL)
interceptCopy <- .trajectoryPredictionModel(interceptToy)
check(interceptCopy$idiag == 0L && identical(interceptCopy$N, interceptToy$N) &&
  identical(interceptCopy$best, interceptToy$best) &&
  identical(interceptCopy$cholesky, interceptToy$cholesky) &&
  identical(interceptCopy$V, interceptToy$V),
  "random-intercept prediction copy preserves all parameters and signed covariance")
interceptPoint <- lcmm::predictY(interceptCopy, newdata = new, var.time = "t", draws = FALSE)$pred
interceptOriginal <- lcmm::predictY(interceptToy, newdata = new, var.time = "t", draws = FALSE)$pred
check(near(interceptPoint, interceptOriginal) &&
  near(interceptPoint[, 1L], 1 + stats::pnorm(.5 * new$t / sqrt(2))),
  "random-intercept point predictions are unchanged and match the analytical mean")
set.seed(218)
interceptNative <- lcmm::predictY(interceptCopy, newdata = new,
  var.time = "t", draws = TRUE, ndraws = 2000L)$pred
set.seed(218)
interceptParameters <- c(.5, -1, 0) + t(chol(interceptV)) %*%
  matrix(stats::rnorm(6000L), nrow = 3L)
interceptScores <- vapply(seq_len(ncol(interceptParameters)), function(j) {
  1 + stats::pnorm((interceptParameters[1L, j] * new$t - interceptParameters[3L, j]) /
    sqrt(1 + interceptParameters[2L, j]^2))
}, numeric(nrow(new)))
interceptExpected <- t(apply(interceptScores, 1L, stats::quantile, c(.5, .025, .975)))
check(near(interceptNative, interceptExpected),
  "signed random-intercept confidence draws match independent analytical calculations")
check(identical(serialize(interceptToy, NULL), interceptBefore),
  "random-intercept prediction leaves the known-parameter model unchanged")

# Ordinary estimation can produce a negative signed random-intercept SD. This
# fixture exercises a real converged estimate and its fitted covariance matrix.
set.seed(1)
interceptId <- rep(seq_len(40L), each = 5L)
interceptTime <- rep(seq(0, 1, length.out = 5L), 40L)
interceptEffect <- stats::rnorm(40L, 0, .3)
interceptOutcome <- as.integer(cut(.5 * interceptTime + interceptEffect[interceptId] +
  stats::rnorm(length(interceptTime)), c(-Inf, -.5, .6, Inf)))
interceptData <- data.frame(id = interceptId, t = interceptTime, y = interceptOutcome)
interceptFit <- lcmm::lcmm(y ~ t, random = ~1, idiag = TRUE, subject = "id",
  data = interceptData, link = "thresholds", maxiter = 150L)
check(interceptFit$conv == 1L && interceptFit$cholesky < 0,
  "estimated ordinal random-intercept fixture converges with a negative signed SD")
estimatedBefore <- serialize(interceptFit, NULL)
estimatedCopy <- .trajectoryPredictionModel(interceptFit)
estimatedPoint <- lcmm::predictY(estimatedCopy, newdata = new, var.time = "t", draws = FALSE)$pred
originalPoint <- lcmm::predictY(interceptFit, newdata = new, var.time = "t", draws = FALSE)$pred
check(near(estimatedPoint, originalPoint),
  "converged random-intercept point predictions remain unchanged")
estimatedV <- matrix(0, 4L, 4L)
estimatedV[upper.tri(estimatedV, diag = TRUE)] <- interceptFit$V
estimatedV[lower.tri(estimatedV)] <- t(estimatedV)[lower.tri(estimatedV)]
estimatedMean <- interceptFit$best
estimatedMean[2L] <- interceptFit$cholesky
set.seed(12345)
estimatedNative <- lcmm::predictY(estimatedCopy, newdata = new,
  var.time = "t", draws = TRUE, ndraws = 2000L)$pred
set.seed(12345)
estimatedParameters <- estimatedMean + t(chol(estimatedV)) %*%
  matrix(stats::rnorm(8000L), nrow = 4L)
estimatedScores <- vapply(seq_len(ncol(estimatedParameters)), function(j) {
  cuts <- c(estimatedParameters[3L, j],
    estimatedParameters[3L, j] + estimatedParameters[4L, j]^2)
  1 + rowSums(vapply(cuts, function(cut) {
    stats::pnorm((estimatedParameters[1L, j] * new$t - cut) /
      sqrt(1 + estimatedParameters[2L, j]^2))
  }, numeric(nrow(new))))
}, numeric(nrow(new)))
estimatedExpected <- t(apply(estimatedScores, 1L, stats::quantile, c(.5, .025, .975)))
check(near(estimatedNative, estimatedExpected),
  "converged random-intercept confidence draws match the analytical ordinal expectation")
# Demonstrate that this fitted fixture detects the original defect, rather than
# merely confirming agreement between two equivalent implementation paths.
set.seed(12345)
uncorrectedNative <- lcmm::predictY(interceptFit, newdata = new,
  var.time = "t", draws = TRUE, ndraws = 2000L)$pred
uncorrectedLimitError <- max(abs(uncorrectedNative[, 2:3] - estimatedExpected[, 2:3]))
correctedLimitError <- max(abs(estimatedNative[, 2:3] - estimatedExpected[, 2:3]))
check(uncorrectedLimitError > 1e-5 && correctedLimitError < 1e-10,
  "converged random-intercept fixture detects incorrect uncorrected limits and validates their correction")
cat(sprintf("Random-intercept regression evidence: convergence=%d; signed SD=%.12g; uncorrected maximum limit error=%.12g; corrected maximum limit error=%.12g.\n",
            interceptFit$conv, interceptFit$cholesky, uncorrectedLimitError,
            correctedLimitError))
check(identical(serialize(interceptFit, NULL), estimatedBefore) &&
  identical(estimatedCopy$best, interceptFit$best) &&
  identical(estimatedCopy$loglik, interceptFit$loglik) &&
  identical(estimatedCopy$AIC, interceptFit$AIC) &&
  identical(estimatedCopy$BIC, interceptFit$BIC),
  "random-intercept prediction preserves the fitted model, likelihood and fit statistics")
cat(sprintf("ALL %d PREDICTION SUPPORT CHECKS PASSED (lcmm %s).\n", passed, packageVersion("lcmm")))
