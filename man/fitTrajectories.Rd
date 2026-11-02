\name{fitTrajectories}
\alias{fitTrajectories}
\alias{trajectoryFitStatistics}
\alias{trajectoryParameters}
\alias{trajectoryPredictions}
\alias{trajectoryClassification}
\title{Fit and summarize lcmm growth models}
\usage{
fitTrajectories(data, id, time, outcome, classes = 2L, degree = 1L,
  model = "lcga", random = "intercept", covariance = "unstructured",
  classVariance = FALSE, starts = 10L, startIterations = 20L,
  maxIterations = 500L, seed = 12345L, missing = "available",
  outcomeType = "continuous")
trajectoryFitStatistics(result, includeBaseline = FALSE)
trajectoryParameters(result)
trajectoryPredictions(result, times = NULL, confidence = TRUE, ndraws = 2000L)
trajectoryClassification(result)
}
\arguments{
  \item{data}{A long-format data frame, one row per subject and measurement time.}
  \item{id, time, outcome}{Names of distinct columns containing subject IDs,
    numeric measurement times, and outcomes.}
  \item{classes}{Number of latent classes, including one for a baseline model.}
  \item{degree}{Polynomial degree: 1, 2, or 3.}
  \item{model}{\code{"lcga"} or \code{"gmm"}. LCGA has no individual random effects.}
  \item{random}{For GMM: \code{"intercept"} or \code{"slope"} (intercept and slope).}
  \item{covariance}{\code{"unstructured"} or \code{"diagonal"} random-effect covariance.}
  \item{classVariance}{Allow class-specific proportional random-effect covariance.
    Requires a GMM with more than one class.}
  \item{starts, startIterations}{Native gridsearch preliminary starts and iterations.}
  \item{maxIterations}{Maximum iterations for baseline and final fits.}
  \item{seed}{Random seed; the caller's RNG state is restored afterwards.}
  \item{missing}{\code{"available"} removes missing outcome rows;
    \code{"completeSubjects"} removes subjects with any missing recorded outcome.}
  \item{outcomeType}{\code{"continuous"} uses \code{lcmm::hlme};
    \code{"ordinal"} uses \code{lcmm::lcmm} with \code{link = "thresholds"}.}
  \item{result}{A fitted object returned by \code{fitTrajectories}.}
  \item{includeBaseline}{Include the fitted one-class starting model in the fit table.}
  \item{times}{Original-scale numeric prediction times. Defaults to 101 equally spaced
    points over retained times.}
  \item{confidence}{Request native 95 percent confidence bands.}
  \item{ndraws}{Number of parameter draws used for ordinal prediction intervals.}
}
\description{A small validation and data-preparation layer around existing lcmm
functions. It does not implement a new estimator.}
\details{Time is transformed to (time - minimum retained time) / retained time range.
Coefficients use that scale; predictions use original times. Ordinal numeric
categories are sorted numerically; ordered factors retain their declared order.
Observed categories are recoded to consecutive integers and the mapping is returned.
Ordinal predictions are expected recoded category scores. With confidence bands,
lcmm returns median predictions from parameter draws. Missing IDs or times and
duplicate subject-time pairs are rejected. Missing outcomes use the observed-data
likelihood under ignorable/MAR assumptions. Unrecorded visits are not inferred.
Only convergence code 1 is accepted. Multiple starts do not establish global optimality.}
\value{\code{fitTrajectories} returns a \code{trajectoryFit} list containing
\code{fit}, \code{baseline}, \code{data}, \code{counts}, \code{settings}, and
\code{warnings}. Other functions return data frames with native fit indices,
rounded longitudinal fixed-effect summaries, class trajectories, or posterior
classification. Parameters are on the scaled-time and, for ordinal outcomes,
latent-process scale.}
\references{Proust-Lima C, Philipps V, Liquet B (2017).
Estimation of Extended Mixed Models Using Latent Classes and Latent Processes:
The R Package lcmm. Journal of Statistical Software, 78(2), 1--56.
\doi{10.18637/jss.v078.i02}}
\seealso{\code{lcmm::hlme}, \code{lcmm::lcmm}, \code{lcmm::gridsearch},
\code{lcmm::predictY}}
