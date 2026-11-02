# Exercise the actual jaspBase results objects outside the desktop UI.
library(jaspTrajectories)
library(jaspBase)

script <- grep("^--file=", commandArgs(FALSE), value = TRUE)
module <- if (length(script)) normalizePath(file.path(dirname(sub("^--file=", "", script[1L])), "..")) else normalizePath(".")
module <- Sys.getenv("TRAJECTORIES_MODULE_DIR", unset = module)
project <- Sys.getenv("TRAJECTORIES_PROJECT_DIR", unset = Sys.getenv("TRAJECTORIES_PROJECT", unset =
  if (dir.exists(file.path(module, "validation"))) module else dirname(module)))
data <- read.csv(file.path(module, "examples", "trajectories-long.csv"),
                 stringsAsFactors = FALSE)
options <- list(outcome = "continuousOutcome", time = "time", subjectID = "subject",
  outcomeType = "continuous", model = "lcga", classes = 2L, degree = "linear",
  randomEffects = "intercept", covariance = "unstructured", classVariance = FALSE,
  missing = "available", starts = 3L, startIterations = 10L, maxIterations = 500L,
  seed = 12345L, parameterTable = TRUE, classTable = TRUE,
  trajectoryPlot = TRUE, confidenceBands = TRUE, observedFitPlot = TRUE,
  observedFitGrouping = "auto", observedFitIntervals = 10L, observedFitPanels = TRUE)

runOutput <- function(opts, dataset) {
  cpp <- jaspBase:::create_cpp_jaspResults("Trajectories", NULL)
  cpp$setOptions(jsonlite::toJSON(opts, auto_unbox = TRUE))
  results <- jaspBase:::jaspResultsR$new(cpp)
  Trajectories(results, dataset, opts)
  # Inspect actual JASP objects instead of a mock implementation.
  stopifnot(!is.null(results[["fittedModel"]]), !is.null(results[["modelFit"]]),
            !is.null(results[["sample"]]), !is.null(results[["parameters"]]),
            !is.null(results[["classification"]]), !is.null(results[["trajectories"]]),
            !is.null(results[["observedFit"]]))
  stopifnot(inherits(results[["trajectories"]]$plotObject, "ggplot"))
  stopifnot(inherits(results[["observedFit"]]$plotObject, "ggplot"))
  # Output-only changes must reuse the cached fitted model.
  first <- results[["fittedModel"]]$object$fit$best
  Trajectories(results, dataset, opts)
  stopifnot(identical(first, results[["fittedModel"]]$object$fit$best))
  # A plot-only update can run with no dataset: it must reuse the cached model.
  results[["observedFit"]] <- NULL
  opts$observedFitGrouping <- "intervals"
  opts$observedFitIntervals <- 3L
  opts$observedFitPanels <- FALSE
  cpp$setOptions(jsonlite::toJSON(opts, auto_unbox = TRUE))
  Trajectories(results, dataset = NULL, opts)
  stopifnot(identical(first, results[["fittedModel"]]$object$fit$best),
            nrow(results[["observedFit"]]$plotObject$data) == 3L * opts$classes)
  results
}

continuous <- runOutput(options, data)
cat("PASS: real JASP continuous tables, confidence-band plot and cached model\n")
options$outcome <- "ordinalOutcome"
options$outcomeType <- "ordinal"
options$classes <- 1L
options$confidenceBands <- FALSE
data$ordinalOutcome <- factor(data$ordinalOutcome, levels = 1:5)
ordinal <- runOutput(options, data)
stopifnot(!is.null(ordinal[["categories"]]))
cat("PASS: real JASP ordinal tables, factor-order adapter and trajectory plot\n")

output <- file.path(project, "build", "preview")
dir.create(output, recursive = TRUE, showWarnings = FALSE)
ggplot2::ggsave(file.path(output, "continuous-trajectories.png"),
               continuous[["trajectories"]]$plotObject, width = 7, height = 4.5, dpi = 120)
ggplot2::ggsave(file.path(output, "ordinal-trajectories.png"),
               ordinal[["trajectories"]]$plotObject, width = 7, height = 4.5, dpi = 120)
ggplot2::ggsave(file.path(output, "continuous-observed-fitted.png"),
               continuous[["observedFit"]]$plotObject, width = 8, height = 5.5, dpi = 120)
ggplot2::ggsave(file.path(output, "ordinal-observed-fitted.png"),
               ordinal[["observedFit"]]$plotObject, width = 8, height = 5.5, dpi = 120)
cat("PASS: plot export\n")
