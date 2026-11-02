\name{trajectoryObservedFit}
\alias{trajectoryObservedFit}
\title{Posterior-weighted observed and fitted trajectory means}
\usage{trajectoryObservedFit(result, grouping = "auto", intervals = 10L)}
\arguments{
  \item{result}{A converged object returned by \code{fitTrajectories}.}
  \item{grouping}{\code{"times"} uses exact retained measurement times;
    \code{"intervals"} uses equal-width time intervals. \code{"auto"} uses exact
    times when at most 20 distinct times are retained, and intervals otherwise.}
  \item{intervals}{Number of intervals, from 2 to 100. Used when grouping into intervals.}
}
\description{Compare observed and fitted means using the same retained records
and posterior class-membership probabilities. No model is re-estimated.}
\details{For each class and time group, a record receives its subject's posterior
class probability as weight. Observed values, marginal fitted values, and original
times are averaged with those weights. Fitted values are evaluated at the actual
record times using \code{lcmm::predictY}, without parameter draws. They are not
predictions evaluated at an interval midpoint or at the mean time. GMM predictions
are marginal, not subject-specific. Repeated records within an interval contribute
separately; participants with more records contribute more total weight.

Intervals are left-closed and right-open, except that the last includes its upper
endpoint. Empty or zero-weight groups return missing weighted means. Ordinal
outcomes use the consecutive category codes in the fitted model's category table,
not the latent-process scale or arbitrary numeric gaps between original labels.

This is a descriptive comparison using the data that estimated class membership.
It is not an independent validation, formal goodness-of-fit test, or assessment
of the complete ordinal category distribution. No confidence intervals are computed.}
\value{A data frame with \code{timeGroup}, \code{timeLower}, \code{timeUpper},
\code{time} (weighted mean original time), \code{class}, \code{observed},
\code{fitted}, \code{rows}, \code{subjects}, and \code{posteriorWeight}.
The row and subject counts describe all retained records in the time group and
are repeated across classes. Posterior weight sums are over records, not unique
subjects. Attributes record the actual/requested grouping, interval count and
outcome scale.}
\seealso{\code{fitTrajectories}, \code{trajectoryPredictions}, \code{lcmm::predictY}}
