# Independent density calculations for the restricted model family in this
# validation pack. No lcmm likelihood, prediction or classification helper is
# called. These checks evaluate an existing estimate; they do not independently
# optimize the model or establish that a mixture solution is a global maximum.
#
# Parameter interpretation was checked against the supplied lcmm 2.2.2 source:
# R/hlme.R reconstructs best's random-effect covariance from its Cholesky factor;
# src/hetmixlin.f90 scales the Gaussian random-effect factor by abs(nwg);
# R/predictY.lcmm.R prepends the fixed zero ordinal intercept, squares nwg
# multipliers, and cumulatively squares threshold increments. Settings here
# allow only an intercept in the class-membership model, all polynomial fixed
# effects varying across classes, and no residual serial-correlation process.

independentLikelihoodChecks <- function(native, x, settings) {
  empty <- data.frame(check = character(), maximumAbsoluteDifference = numeric(),
    tolerance = numeric(), passed = logical(), stringsAsFactors = FALSE)
  requireCondition <- function(ok, message) {
    if (!isTRUE(ok)) stop("Independent likelihood check: ", message, call. = FALSE)
  }
  continuous <- identical(as.character(settings$outcomeType), "continuous")
  ordinal <- identical(as.character(settings$outcomeType), "ordinal")
  gmm <- identical(as.character(settings$model), "gmm")
  lcga <- identical(as.character(settings$model), "lcga")
  requireCondition((continuous || ordinal) && (gmm || lcga), "unsupported model family")
  # Ordinal GMM requires integration over random effects, outside this checker.
  if (ordinal && gmm) return(empty)
  requireCondition(is.data.frame(x) && all(c("id", "t", "y") %in% names(x)),
    "x must contain the independently prepared id, t and y columns")
  requireCondition(nrow(x) > 0L && !anyNA(x[, c("id", "t", "y")]) &&
    all(is.finite(x$t)) && all(is.finite(x$y)), "prepared data must be observed and finite")
  groups <- as.integer(settings$classes)
  requireCondition(length(groups) == 1L && groups >= 1L && native$ng == groups,
    "settings and native class counts disagree")
  degree <- switch(as.character(settings$degree), linear = 1L, quadratic = 2L,
    cubic = 3L, NA_integer_)
  requireCondition(!is.na(degree), "degree must be linear, quadratic or cubic")
  q <- if (lcga) 0L else if (settings$randomEffects == "intercept") 1L else if (
    settings$randomEffects == "interceptSlope") 2L else NA_integer_
  requireCondition(!is.na(q), "unsupported random-effects specification")
  diagonal <- identical(as.character(settings$covariance), "diagonal")
  requireCondition(diagonal || settings$covariance == "unstructured", "unsupported covariance structure")
  classVariance <- isTRUE(settings$classVariance)
  requireCondition(!classVariance || (gmm && groups > 1L), "invalid class variance setting")
  priorCount <- groups - 1L
  fixedCount <- groups * (degree + 1L) - as.integer(ordinal)
  covarianceCount <- if (q == 0L) 0L else if (diagonal) q else q * (q + 1L) / 2L
  scaleCount <- if (classVariance) groups - 1L else 0L
  requireCondition(identical(as.integer(native$N[1:4]),
    as.integer(c(priorCount, fixedCount, covarianceCount, scaleCount))),
    "native parameter layout is outside the supported specification")
  parameters <- as.numeric(native$best)
  requireCondition(all(is.finite(parameters)), "native estimates must be finite")
  cursor <- 0L
  take <- function(n) {
    if (n == 0L) return(numeric())
    positions <- cursor + seq_len(n)
    cursor <<- cursor + n
    requireCondition(max(positions) <= length(parameters), "truncated parameter vector")
    parameters[positions]
  }
  logits <- c(take(priorCount), 0)
  logPrior <- logits - (max(logits) + log(sum(exp(logits - max(logits)))))
  beta <- take(fixedCount)
  if (ordinal) beta <- c(0, beta)
  # Native fixed-effect order is classes within each polynomial term.
  beta <- matrix(beta, nrow = groups, ncol = degree + 1L)
  design <- vapply(0:degree, function(power) x$t^power, numeric(nrow(x)))
  means <- design %*% t(beta)

  covarianceValues <- take(covarianceCount)
  covariance <- matrix(0, q, q)
  if (q > 0L) {
    if (diagonal) {
      diag(covariance) <- covarianceValues
    } else {
      covariance[upper.tri(covariance, diag = TRUE)] <- covarianceValues
      covariance[lower.tri(covariance)] <- t(covariance)[lower.tri(covariance)]
    }
  }
  varianceMultipliers <- if (classVariance) c(take(scaleCount)^2, 1) else rep(1, groups)
  if (continuous) {
    residualVariance <- take(1L)^2
    requireCondition(residualVariance > 0, "nonpositive Gaussian residual variance")
  } else {
    categoryCount <- length(unique(x$y))
    requireCondition(categoryCount >= 2L &&
      identical(sort(unique(as.integer(x$y))), seq_len(categoryCount)) &&
      all(x$y == as.integer(x$y)), "ordinal codes must be consecutive integers starting at one")
    rawThresholds <- take(categoryCount - 1L)
    thresholds <- c(rawThresholds[1L], rawThresholds[1L] + cumsum(rawThresholds[-1L]^2))
    requireCondition(all(diff(thresholds) > 0), "ordinal thresholds are not strictly increasing")
    boundaries <- c(-Inf, thresholds, Inf)
  }
  requireCondition(cursor == length(parameters), "unhandled native model parameters")

  # Difference of normal CDFs in log space, switching to survival probabilities
  # in the upper tail to avoid cancellation when both CDFs are near one.
  logNormalInterval <- function(lower, upper) {
    useSurvival <- lower >= 0
    larger <- stats::pnorm(upper, log.p = TRUE)
    smaller <- stats::pnorm(lower, log.p = TRUE)
    larger[useSurvival] <- stats::pnorm(lower[useSurvival], lower.tail = FALSE, log.p = TRUE)
    smaller[useSurvival] <- stats::pnorm(upper[useSurvival], lower.tail = FALSE, log.p = TRUE)
    larger + log(-expm1(smaller - larger))
  }
  subjectIds <- unique(x$id)
  rowsBySubject <- split(seq_len(nrow(x)), match(x$id, subjectIds))
  logDensities <- matrix(NA_real_, length(subjectIds), groups)
  for (subject in seq_along(subjectIds)) {
    rows <- rowsBySubject[[as.character(subject)]]
    for (group in seq_len(groups)) {
      if (continuous && lcga) {
        logDensities[subject, group] <- sum(stats::dnorm(x$y[rows],
          mean = means[rows, group], sd = sqrt(residualVariance), log = TRUE))
      } else if (continuous) {
        randomDesign <- if (q == 1L) matrix(1, length(rows), 1L) else cbind(1, x$t[rows])
        marginalCovariance <- varianceMultipliers[group] *
          (randomDesign %*% covariance %*% t(randomDesign)) +
          diag(residualVariance, nrow = length(rows))
        upper <- chol(marginalCovariance)
        standardized <- forwardsolve(t(upper), x$y[rows] - means[rows, group])
        logDensities[subject, group] <- -length(rows) * log(2 * pi) / 2 -
          sum(log(diag(upper))) - sum(standardized^2) / 2
      } else {
        codes <- as.integer(x$y[rows])
        logDensities[subject, group] <- sum(logNormalInterval(
          boundaries[codes] - means[rows, group],
          boundaries[codes + 1L] - means[rows, group]))
      }
    }
  }
  requireCondition(all(is.finite(logDensities)), "reconstructed class densities are nonfinite")
  logJoint <- sweep(logDensities, 2L, logPrior, "+")
  rowMax <- apply(logJoint, 1L, max)
  logSubjectLikelihood <- rowMax + log(rowSums(exp(logJoint - rowMax)))
  reconstructedLogLik <- sum(logSubjectLikelihood)
  posterior <- exp(logJoint - logSubjectLikelihood)
  nativeProbabilities <- as.matrix(native$pprob[, 2L + seq_len(groups), drop = FALSE])
  rowMatch <- match(native$pprob[[1L]], subjectIds)
  requireCondition(nrow(nativeProbabilities) == length(subjectIds) &&
    !anyNA(rowMatch) && !anyDuplicated(rowMatch), "native posterior subject IDs do not match the input")
  differences <- c(abs(reconstructedLogLik - native$loglik),
    max(abs(posterior[rowMatch, , drop = FALSE] - nativeProbabilities)))
  tolerances <- c(1e-4, 1e-6)
  data.frame(check = c("independent subject-mixture log-likelihood",
    "independent posterior probabilities"), maximumAbsoluteDifference = differences,
    tolerance = tolerances, passed = is.finite(differences) & differences <= tolerances,
    stringsAsFactors = FALSE)
}
