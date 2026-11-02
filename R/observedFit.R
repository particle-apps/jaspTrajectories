# Descriptive observed-versus-fitted summaries. The model is never re-estimated.
# Both averages use the same retained records and subject posterior weights.

#' Posterior-weighted observed and fitted means
#' @export
trajectoryObservedFit <- function(result, grouping = "auto", intervals = 10L) {
  .trajectoryResult(result)
  grouping <- match.arg(grouping, c("auto", "times", "intervals"))
  intervals <- .trajectoryInteger(intervals, "intervals", minimum = 2L, maximum = 100L)
  data <- result$data
  times <- sort(unique(data$.originalTime))
  actualGrouping <- if (grouping == "auto") {
    if (length(times) <= 20L) "times" else "intervals"
  } else grouping

  if (actualGrouping == "times") {
    group <- match(data$.originalTime, times)
    lower <- upper <- times
  } else {
    breaks <- seq(min(times), max(times), length.out = intervals + 1L)
    if (anyDuplicated(breaks))
      stop("The time range is too narrow for the requested number of intervals.", call. = FALSE)
    # Intervals are [left, right), except that the final endpoint is included.
    group <- as.integer(cut(data$.originalTime, breaks = breaks,
                            right = FALSE, include.lowest = TRUE))
    lower <- utils::head(breaks, -1L)
    upper <- utils::tail(breaks, -1L)
  }
  if (anyNA(group)) stop("Could not group every retained measurement time.", call. = FALSE)
  groups <- seq_along(lower)
  rowsByGroup <- split(seq_len(nrow(data)), factor(group, levels = groups))

  k <- result$fit$ng
  posterior <- result$fit$pprob
  probabilityColumns <- paste0("prob", seq_len(k))
  if (!all(probabilityColumns %in% names(posterior)) || anyDuplicated(posterior[[1L]]))
    stop("The fitted model has an invalid posterior-probability layout.", call. = FALSE)
  matched <- match(data$.id, posterior[[1L]])
  if (anyNA(matched)) stop("Posterior probabilities are missing for retained subjects.", call. = FALSE)
  weights <- as.matrix(posterior[matched, probabilityColumns, drop = FALSE])
  if (any(!is.finite(weights)) || any(weights < 0) || any(weights > 1) ||
      any(abs(rowSums(weights) - 1) > 1e-6))
    stop("Posterior class probabilities must be finite and sum to one.", call. = FALSE)

  # Predict at actual times, not at an interval midpoint. In nonlinear models
  # the prediction at mean time is not the mean of the record-level predictions.
  native <- trajectoryPredictions(result, times = times, confidence = FALSE)
  predictions <- matrix(native$predicted, nrow = length(times), ncol = k)
  predictions <- predictions[match(data$.originalTime, times), , drop = FALSE]
  if (any(!is.finite(predictions))) stop("Fitted means are not finite.", call. = FALSE)

  summaries <- vector("list", k * length(groups))
  for (class in seq_len(k)) {
    for (g in groups) {
      rows <- rowsByGroup[[g]]
      w <- weights[rows, class]
      total <- sum(w)
      # Undefined weighted means remain NA; no artificial zero is plotted.
      value <- function(x) if (total > 0) sum((w / total) * x[rows]) else NA_real_
      summaries[[(class - 1L) * length(groups) + g]] <- data.frame(
        timeGroup = g, timeLower = lower[g], timeUpper = upper[g],
        time = value(data$.originalTime), class = class,
        observed = value(data$.outcome), fitted = value(predictions[, class]),
        rows = length(rows), subjects = length(unique(data$.id[rows])),
        posteriorWeight = total)
    }
  }
  output <- do.call(rbind, summaries)
  rownames(output) <- NULL
  attr(output, "grouping") <- actualGrouping
  attr(output, "requestedGrouping") <- grouping
  attr(output, "intervals") <- if (actualGrouping == "intervals") intervals else NULL
  attr(output, "scale") <- if (result$settings$outcomeType == "ordinal") "category code" else "outcome"
  output
}
