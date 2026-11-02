# lcmm 2.2.2's threshold predictY method calculates diagonal random-slope
# variances incorrectly. It uses unsquared random-effect design values and then
# takes diag() of an n-by-1 matrix, retaining only its first entry. Both point
# predictions and parameter-draw predictions take this path.
# Diagonal random-intercept models have a separate uncertainty issue: the
# method replaces signed Cholesky parameters by positive square roots without
# transforming their covariance with the other estimated parameters.
#
# An equivalent unstructured representation takes the correct native prediction
# path. A single random effect needs only that representation flag; two random
# effects also need a fixed zero cross-covariance. Use this copy for prediction:
# estimation, stored fitted models, coefficients and fit statistics are unchanged.
.trajectoryPredictionModel <- function(fit) {
  if (!inherits(fit, "lcmm") || !isTRUE(fit$linktype == 3L) ||
      !isTRUE(fit$idiag == 1L))
    return(fit)
  # This workaround depends on the fitted-object layout and signed covariance
  # convention of the tested engine. A newer engine needs explicit revalidation.
  if (as.character(utils::packageVersion("lcmm")) != "2.2.2")
    stop("Diagonal ordinal predictions require the validated lcmm 2.2.2 engine. Reinstall the dependency-complete JASP module.",
         call. = FALSE)
  randomCount <- sum(fit$idea0)
  if (!randomCount %in% c(1L, 2L))
    return(fit)

  if (length(fit$N) < 3L || fit$N[3L] != randomCount)
    stop("Unexpected diagonal ordinal prediction parameter layout.", call. = FALSE)
  parameterCount <- length(fit$best)
  offset <- fit$N[1L] + fit$N[2L]
  variancePositions <- offset + seq_len(randomCount)
  variances <- fit$best[variancePositions]
  if (any(!is.finite(variances)) || any(variances < 0))
    stop("Ordinal prediction requires finite nonnegative random-effect variances.", call. = FALSE)
  if (length(fit$V) != parameterCount * (parameterCount + 1L) / 2L)
    stop("Unexpected ordinal prediction covariance layout.", call. = FALSE)
  diagonalPositions <- cumsum(seq_len(randomCount))
  if (length(fit$cholesky) != sum(seq_len(randomCount)) ||
      any(!is.finite(fit$cholesky)) ||
      (randomCount == 2L && fit$cholesky[2L] != 0) ||
      !isTRUE(all.equal(unname(fit$cholesky[diagonalPositions]^2),
                        unname(variances), tolerance = 1e-8)))
    stop("Unexpected diagonal ordinal Cholesky parameter layout.", call. = FALSE)

  converted <- fit
  converted$idiag <- 0L
  converted$call$idiag <- FALSE
  # In one dimension diagonal and unstructured covariance are identical. This
  # flag makes native prediction use the original signed Cholesky parameter and
  # its unchanged uncertainty matrix, without adding or removing parameters.
  if (randomCount == 1L)
    return(converted)

  # Preserve parameter order while inserting the fixed cross-covariance between
  # the intercept and slope variances. V is on lcmm's Cholesky parameter scale.
  inserted <- offset + 2L
  mapping <- seq_len(parameterCount) + as.integer(seq_len(parameterCount) >= inserted)
  originalFixed <- if (is.null(fit$call$posfix)) integer() else
    eval(fit$call$posfix, envir = parent.frame())
  if (!is.numeric(originalFixed) || anyNA(originalFixed) ||
      any(originalFixed != as.integer(originalFixed)) ||
      any(originalFixed < 1L | originalFixed > parameterCount))
    stop("Unexpected fixed-parameter indices for ordinal prediction.", call. = FALSE)

  converted$best <- append(fit$best, 0, after = offset + 1L)
  if (!is.null(names(converted$best)))
    names(converted$best)[offset + seq_len(3L)] <- paste("varcov", seq_len(3L))
  converted$N[3L] <- 3L
  # Keep optimizer signs: V is expressed around these signed parameters.
  # Replacing them with positive square roots would change correlated draws.
  converted$cholesky <- fit$cholesky

  covariance <- matrix(0, parameterCount, parameterCount)
  covariance[upper.tri(covariance, diag = TRUE)] <- fit$V
  covariance[lower.tri(covariance)] <- t(covariance)[lower.tri(covariance)]
  expanded <- matrix(0, parameterCount + 1L, parameterCount + 1L)
  expanded[mapping, mapping] <- covariance
  converted$V <- expanded[upper.tri(expanded, diag = TRUE)]
  # Native prediction removes fixed parameters before Cholesky decomposition;
  # this keeps the inserted zero-variance parameter fixed in confidence draws.
  converted$call$posfix <- sort(unique(c(inserted, mapping[originalFixed])))
  converted
}
