# Evaluate independently implemented densities at the saved native estimates.
script <- sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1L])
root <- Sys.getenv("TRAJECTORIES_VALIDATION_DIR", unset = dirname(normalizePath(script)))
source(file.path(root, "independent-likelihood.R"))
settings <- read.csv(file.path(root, "model-settings.csv"), stringsAsFactors = FALSE)
checks <- list()
for (key in settings$case) {
  saved <- readRDS(file.path(root, "results", paste0(key, "-models.rds")))
  result <- independentLikelihoodChecks(saved$native, saved$native$data, saved$settings)
  if (nrow(result)) {
    stopifnot(all(result$passed))
    checks[[length(checks) + 1L]] <- cbind(case = key, result)
    cat("PASS: ", key, " independent likelihood and posterior probabilities\n", sep = "")
  } else {
    cat("NOT CHECKED independently: ", key, " ordinal GMM integration\n", sep = "")
  }
}
checks <- do.call(rbind, checks)
write.csv(checks, file.path(root, "results", "independent-likelihood-checks.csv"), row.names = FALSE)
cat(nrow(checks), "independent density checks passed.\n")
