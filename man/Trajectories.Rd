\name{Trajectories}
\alias{Trajectories}
\title{JASP interface for latent class growth and growth mixture models}
\usage{Trajectories(jaspResults, dataset = NULL, options)}
\arguments{
  \item{jaspResults}{The native JASP results container.}
  \item{dataset}{A long-format data frame supplied by JASP.}
  \item{options}{The named list of options from the module's QML form.}
}
\description{Calls the existing lcmm estimators and populates JASP tables and plots.
This is the entry point used by JASP; for direct R use see \code{fitTrajectories}.}
\value{Invisibly returns NULL; updates the supplied JASP results container.}
\seealso{\code{\link{fitTrajectories}}}
