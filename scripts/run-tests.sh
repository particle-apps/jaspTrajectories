#!/bin/sh
# Complete source-level and native-JASP validation; see validation/README.md.
set -eu
module_dir=${TRAJECTORIES_MODULE_DIR:-$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)}
module_dir=$(CDPATH= cd -- "$module_dir" && pwd)
if [ -d "$module_dir/validation" ]; then
  project_dir="$module_dir"
else
  project_dir=$(dirname -- "$module_dir")
fi
project_dir=${TRAJECTORIES_PROJECT_DIR:-$project_dir}
export TRAJECTORIES_MODULE_DIR="$module_dir"
export TRAJECTORIES_PROJECT_DIR="$project_dir"
export TRAJECTORIES_VALIDATION_DIR="${TRAJECTORIES_VALIDATION_DIR:-$project_dir/validation}"
exec sh "$TRAJECTORIES_VALIDATION_DIR/run-validation.sh"
