module <- Sys.getenv("TRAJECTORIES_MODULE_DIR")
stopifnot(nzchar(module), as.character(packageVersion("jaspTrajectories")) == "0.1.0")
namespace <- asNamespace("jaspTrajectories")
reference <- new.env(parent = namespace)
for (path in list.files(file.path(module, "R"), full.names = TRUE, pattern = "\\.R$"))
  sys.source(path, envir = reference)
definitions <- ls(reference, all.names = TRUE)
for (name in definitions) {
  expected <- get(name, reference, inherits = FALSE)
  actual <- get(name, namespace, inherits = FALSE)
  if (is.function(expected)) {
    stopifnot(identical(formals(expected), formals(actual)),
              identical(deparse(body(expected)), deparse(body(actual))))
  } else stopifnot(identical(expected, actual))
}
installed <- find.package("jaspTrajectories")
resources <- list.files(file.path(module, "inst"), full.names = TRUE, recursive = TRUE)
for (source in resources) {
  relative <- substring(source, nchar(file.path(module, "inst")) + 2L)
  target <- file.path(installed, relative)
  stopifnot(file.exists(target), unname(tools::md5sum(source)) == unname(tools::md5sum(target)))
}
sourceDescription <- read.dcf(file.path(module, "DESCRIPTION"))
installedDescription <- read.dcf(file.path(installed, "DESCRIPTION"))
stopifnot(all(sourceDescription[1L, ] == installedDescription[1L, colnames(sourceDescription)]))
cat("PASS:", length(definitions), "runtime definitions and", length(resources), "installed resources match source.\n")
cat("PASS: DESCRIPTION fields match, including public Version 0.1.0.\n")
for (package in c("jaspTrajectories", "lcmm", "jaspBase", "ggplot2"))
  cat(package, as.character(packageVersion(package)), "\n")
