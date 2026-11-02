# Fail before fitting if the installed package and checked-out source versions differ.
project <- Sys.getenv("TRAJECTORIES_PROJECT_DIR", unset = Sys.getenv("TRAJECTORIES_PROJECT"))
stopifnot(nzchar(project))
module <- Sys.getenv("TRAJECTORIES_MODULE_DIR", unset =
  if (file.exists(file.path(project, "DESCRIPTION"))) project else file.path(project, "jaspTrajectories"))
validation <- Sys.getenv("TRAJECTORIES_VALIDATION_DIR", unset = file.path(project, "validation"))
version <- read.dcf(file.path(module, "DESCRIPTION"), fields = "Version")[[1L]]
required <- c("jaspTrajectories", "lcmm", "jaspBase", "ggplot2", "nlme", "MASS", "jsonlite")
for (package in required) stopifnot(requireNamespace(package, quietly = TRUE))
stopifnot(as.character(packageVersion("jaspTrajectories")) == version,
          as.character(packageVersion("lcmm")) == "2.2.2")
allowed <- normalizePath(c(Sys.getenv("R_LIBS_USER"), .Library), mustWork = TRUE)
for (package in required) {
  resolved <- normalizePath(find.package(package))
  stopifnot(any(vapply(allowed, function(path) startsWith(resolved, paste0(path, .Platform$file.sep)), logical(1L))))
}
metadata <- list(moduleVersion = version, lcmmVersion = as.character(packageVersion("lcmm")),
  rVersion = as.character(getRversion()), platform = R.version$platform,
  startedUTC = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
  freshReferenceFits = TRUE, sourceVersionMatchesInstalled = TRUE,
  packages = setNames(lapply(required, function(p) as.character(packageVersion(p))), required))
dependencyFiles <- c(file.path(find.package("jaspBase"), "libs", "jaspBase.so"),
                     file.path(find.package("ragg"), "LICENSE.libdeflate"))
stopifnot(all(file.exists(dependencyFiles)))
metadata$dependencyFileMD5 <- as.list(setNames(unname(tools::md5sum(dependencyFiles)),
  c("jaspBase/libs/jaspBase.so", "ragg/LICENSE.libdeflate")))
provenance <- file.path(dirname(Sys.getenv("R_LIBS_USER")), "source-build-provenance.json")
if (file.exists(provenance))
  metadata$sourceBuildProvenance <- jsonlite::read_json(provenance, simplifyVector = FALSE)
jsonlite::write_json(metadata, file.path(validation, "results", "run-metadata.json"),
                     pretty = TRUE, auto_unbox = TRUE)
sourceFiles <- sort(unlist(lapply(file.path(module, c("R", "inst", "man", "tests")),
  list.files, pattern = "\\.(R|qml|Rd)$", recursive = TRUE, full.names = TRUE)))
buildInputs <- file.path(module, c("scripts/dependencies-macos-arm64.lock.json",
  "scripts/jaspbase-source-build.lock.json", "scripts/rebuild-jaspbase.py",
  "scripts/build-macos.sh", "scripts/prepare-library.py",
  "inst/third-party/LICENSE.libdeflate", "inst/third-party/README.txt"))
stopifnot(all(file.exists(buildInputs)))
sourceFiles <- sort(unique(c(sourceFiles, buildInputs)))
sourceHashes <- tools::md5sum(sourceFiles)
write.csv(data.frame(file = substring(sourceFiles, nchar(module) + 2L),
                     md5 = unname(sourceHashes)),
          file.path(validation, "results", "source-file-hashes.csv"), row.names = FALSE)
print(metadata)
cat("PASS: required packages resolve from the selected library or embedded R; source/installed versions match.\n")
