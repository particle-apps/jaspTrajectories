# Render representative saved fits and check that plot layers contain the
# independently tested summaries. Run after installing the current source.
library(jaspTrajectories)
library(ggplot2)
script <- grep("^--file=", commandArgs(FALSE), value = TRUE)
module <- if (length(script)) normalizePath(file.path(dirname(sub("^--file=", "", script[1L])), "..")) else normalizePath(".")
module <- Sys.getenv("TRAJECTORIES_MODULE_DIR", unset = module)
project <- Sys.getenv("TRAJECTORIES_PROJECT_DIR", unset = Sys.getenv("TRAJECTORIES_PROJECT", unset =
  if (dir.exists(file.path(module, "validation"))) module else dirname(module)))
validation <- Sys.getenv("TRAJECTORIES_VALIDATION_DIR", unset = file.path(project, "validation"))
output <- Sys.getenv("TRAJECTORIES_PLOT_OUTPUT", unset = file.path(project, "build", "preview"))
dir.create(output, recursive = TRUE, showWarnings = FALSE)

for (case in c("C04", "C06", "O02", "O03", "P01", "P02")) {
  result <- readRDS(file.path(validation, "results",
                              paste0(case, "-models.rds")))$module
  means <- trajectoryObservedFit(result)
  plot <- jaspTrajectories:::.trajectoryObservedGraph(means, result, panels = TRUE)
  built <- ggplot_build(plot)
  stopifnot(isTRUE(all.equal(built$data[[2L]]$y, means$fitted, tolerance = 1e-12)),
            isTRUE(all.equal(built$data[[3L]]$y, means$observed, tolerance = 1e-12)),
            isTRUE(all.equal(built$data[[3L]]$x, means$time, tolerance = 1e-12)),
            nrow(built$layout$layout) == result$fit$ng)
  write.csv(means, file.path(output, paste0(case, "-observed-fitted.csv")),
            row.names = FALSE, na = "")
  ggsave(file.path(output, paste0(case, "-observed-fitted.png")), plot,
         width = 9, height = 6, dpi = 120)
  cat("PASS:", case, "plot coordinates, panels and PNG export\n")
}

# A missing group must break the fitted line, including when classes share a panel.
means <- trajectoryObservedFit(result)
means$observed[3L] <- means$fitted[3L] <- means$time[3L] <- NA_real_
means$rows[3L] <- means$subjects[3L] <- 0L
means$posteriorWeight[3L] <- 0
plot <- jaspTrajectories:::.trajectoryObservedGraph(means, result, panels = FALSE)
stopifnot(plot$data$.segment[2L] != plot$data$.segment[4L],
          is.na(plot$data$fitted[3L]), is.na(plot$data$observed[3L]))
cat("PASS: unsupported groups remain gaps in the plotted line\n")
