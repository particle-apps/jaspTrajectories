#!/bin/sh
# Clean, locked build for the tested macOS/arm64 JASP release.
set -eu
module_dir=${TRAJECTORIES_MODULE_DIR:-$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)}
module_dir=$(CDPATH= cd -- "$module_dir" && pwd)
if [ -d "$module_dir/validation" ]; then
  project_dir="$module_dir"
else
  project_dir=$(dirname -- "$module_dir")
fi
project_dir=${TRAJECTORIES_PROJECT_DIR:-$project_dir}
build_dir=${TRAJECTORIES_BUILD_DIR:-"$project_dir/build/clean-macos-arm64"}
dist_dir=${TRAJECTORIES_DIST_DIR:-"$project_dir/dist"}
cache_dir=${TRAJECTORIES_CACHE_DIR:-"$project_dir/build/downloads"}
source_cache=${TRAJECTORIES_SOURCE_CACHE_DIR:-"$project_dir/build/dependency-sources"}
jasp_app=${JASP_APP:-/Applications/JASP.app}
mkdir -p "$build_dir" "$dist_dir" "$cache_dir"
build_dir=$(CDPATH= cd -- "$build_dir" && pwd)
dist_dir=$(CDPATH= cd -- "$dist_dir" && pwd)
cache_dir=$(CDPATH= cd -- "$cache_dir" && pwd)

# An existing nonempty library is rejected: every build restores the same inputs.
python3 "$module_dir/scripts/prepare-library.py" \
  --library "$build_dir/library" --cache "$cache_dir" --jasp "$jasp_app"

# Replace the app's jaspBase with a build whose Common/JSON input is explicit.
python3 "$module_dir/scripts/rebuild-jaspbase.py" \
  --library "$build_dir/library" --cache "$source_cache" --jasp "$jasp_app"
# ragg statically includes libdeflate. Carry its upstream notice with that binary.
cp "$module_dir/inst/third-party/LICENSE.libdeflate" "$build_dir/library/ragg/LICENSE.libdeflate"
python3 - "$module_dir" "$build_dir" <<'PY'
import importlib.util
import json
from pathlib import Path
import sys
module, build = map(Path, sys.argv[1:])
spec = importlib.util.spec_from_file_location('restore', module / 'scripts/prepare-library.py')
restore = importlib.util.module_from_spec(spec)
spec.loader.exec_module(restore)
path = build / 'dependency-provenance.json'
provenance = json.loads(path.read_text())
provenance['post_restore_changes'] = {
    'jaspBase': 'Rebuilt from pinned package and Common sources; see source-build-provenance.json.',
    'ragg': 'Added upstream libdeflate copyright and MIT permission notice; native code unchanged.',
}
provenance['final_dependency_tree_sha256'] = {
    p['name']: restore.tree_hash(build / 'library' / p['name'])
    for p in provenance['packages'] if p['installed_in_private_library']
}
provenance['libdeflate_notice_sha256'] = restore.sha256(build / 'library/ragg/LICENSE.libdeflate')
provenance['source_build_provenance_sha256'] = restore.sha256(build / 'source-build-provenance.json')
path.write_text(json.dumps(provenance, indent=2) + '\n')
PY

export JASP_R_HOME="$jasp_app/Contents/Frameworks/R.framework/Versions/4.5-arm64/Resources"
export R_HOME="$JASP_R_HOME"
export R_LIBS=""
export R_LIBS_USER="$build_dir/library"
export R_LIBS_SITE="$build_dir/empty-site"
export TRAJECTORIES_MODULE_DIR="$module_dir"
export TRAJECTORIES_PROJECT_DIR="$project_dir"
export TRAJECTORIES_DIST_DIR="$dist_dir"
export TRAJECTORIES_JASP_APP="$jasp_app"
export TRAJECTORIES_BUILD_DIR="$build_dir"

"$JASP_R_HOME/bin/R" --vanilla --slave -e '
  paths <- normalizePath(.libPaths(), mustWork=TRUE)
  allowed <- normalizePath(c(Sys.getenv("R_LIBS_USER"), file.path(R.home(), "library")))
  stopifnot(all(paths %in% allowed), as.character(getRversion()) == "4.5.2",
            as.character(packageVersion("lcmm")) == "2.2.2")
  library(jaspBase)
  cat("Building against", R.version.string, "and lcmm", as.character(packageVersion("lcmm")), "\n")
'
"$JASP_R_HOME/bin/R" CMD INSTALL --no-html --no-multiarch --with-keep.source \
  --library="$build_dir/library" "$module_dir"

"$JASP_R_HOME/bin/R" --vanilla --slave -e '
  installed <- find.package("jaspTrajectories")
  for (directory in c("icons", "qml"))
    if (!dir.exists(file.path(installed, directory)))
      stop("Missing required JASP module directory: ", directory)
  for (file in c("DESCRIPTION", "Description.qml", "qml/Trajectories.qml", "icons/trajectories.svg")) {
    target <- file.path(installed, file)
    if (!file.exists(target) || is.na(file.info(target)$size) || file.info(target)$size == 0)
      stop("Missing or empty JASP module resource: ", file)
  }
  cat("Installed JASP module resources verified.\n")
  capture.output(sessionInfo(), file=file.path(Sys.getenv("TRAJECTORIES_BUILD_DIR"), "build-session-info.txt"))
'

"$JASP_R_HOME/bin/R" --vanilla --slave -e '
  tool <- file.path(Sys.getenv("TRAJECTORIES_JASP_APP"), "Contents/Modules/Tools/jaspModuleBundleManager_library")
  .libPaths(c(tool, .libPaths()))
  jaspModuleBundleManager::createJaspModuleBundle(
    moduleLib = Sys.getenv("R_LIBS_USER"), moduleName = "jaspTrajectories",
    resultdir = Sys.getenv("TRAJECTORIES_DIST_DIR"), packageAll = TRUE
  )
'
printf '%s\n' "Created $dist_dir/jaspTrajectories.JASPModule" \
  "Build provenance: $build_dir/dependency-provenance.json"
