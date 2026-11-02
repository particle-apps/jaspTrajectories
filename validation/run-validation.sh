#!/bin/sh
# Regenerate the references, run every standalone test, and create the public report.
# No historical models are reused. This command does not install the module.
set -eu
validation_dir=${TRAJECTORIES_VALIDATION_DIR:-$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)}
validation_dir=$(CDPATH= cd -- "$validation_dir" && pwd)
project_dir=${TRAJECTORIES_PROJECT_DIR:-$(dirname -- "$validation_dir")}
project_dir=$(CDPATH= cd -- "$project_dir" && pwd)
if [ -f "$project_dir/DESCRIPTION" ]; then
  module_dir="$project_dir"
else
  module_dir="$project_dir/jaspTrajectories"
fi
module_dir=${TRAJECTORIES_MODULE_DIR:-$module_dir}
module_dir=$(CDPATH= cd -- "$module_dir" && pwd)
export TRAJECTORIES_PROJECT="$project_dir"
export TRAJECTORIES_PROJECT_DIR="$project_dir"
export TRAJECTORIES_MODULE_DIR="$module_dir"
export TRAJECTORIES_VALIDATION_DIR="$validation_dir"
export JASP_R_HOME="${JASP_R_HOME:-/Applications/JASP.app/Contents/Frameworks/R.framework/Versions/4.5-arm64/Resources}"
export R_HOME="$JASP_R_HOME"
build_dir="${TRAJECTORIES_BUILD_DIR:-$project_dir/build/clean-macos-arm64}"
export R_LIBS_USER="${R_LIBS_USER:-$build_dir/library}"
export R_LIBS_SITE="$project_dir/build/empty-site-library"
unset R_LIBS
r_executable="${TRAJECTORIES_R:-$JASP_R_HOME/bin/R}"
if [ ! -x "$r_executable" ]; then
  printf '%s\n' 'R executable not found. See validation/README.md for JASP_R_HOME and TRAJECTORIES_R.' >&2
  exit 1
fi
mkdir -p "$R_LIBS_SITE" "$validation_dir/logs" "$validation_dir/results" "$validation_dir/plots/observed-fitted"
export TRAJECTORIES_PLOT_OUTPUT="$validation_dir/plots/observed-fitted"
status_file="$validation_dir/results/test-stages.csv"
printf '%s\n' 'stage,status,exitCode,elapsedSeconds,log' > "$status_file"
# Remove a previous success page before testing; a failed run cannot leave it current.
rm -f "$validation_dir/START-HERE.html" "$validation_dir/RUN-FAILED.txt"
run_stage() {
  stage=$1
  shift
  start=$(date +%s)
  printf 'RUN %s\n' "$stage"
  if "$@" > "$validation_dir/logs/$stage.log" 2>&1; then
    code=0
    outcome=PASS
  else
    code=$?
    outcome=FAIL
  fi
  elapsed=$(( $(date +%s) - start ))
  printf '%s,%s,%s,%s,logs/%s.log\n' "$stage" "$outcome" "$code" "$elapsed" "$stage" >> "$status_file"
  printf '%s %s (%ss)\n' "$outcome" "$stage" "$elapsed"
  if [ "$code" -ne 0 ]; then
    printf 'Validation stopped at %s (exit %s). Read logs/%s.log.\n' "$stage" "$code" "$stage" > "$validation_dir/RUN-FAILED.txt"
    cat "$validation_dir/RUN-FAILED.txt" >&2
    exit "$code"
  fi
}
run_stage preflight "$r_executable" --vanilla --slave --file="$validation_dir/preflight.R"
run_stage smoke "$r_executable" --vanilla --slave --file="$module_dir/tests/smoke.R"
run_stage prediction-support "$r_executable" --vanilla --slave --file="$module_dir/tests/prediction-support.R"
run_stage build-reference "$r_executable" --vanilla --slave --file="$validation_dir/build-reference.R"
run_stage check-independent "$r_executable" --vanilla --slave --file="$validation_dir/check-independent.R"
run_stage observed-fit "$r_executable" --vanilla --slave --file="$module_dir/tests/observed-fit.R"
run_stage jasp-output "$r_executable" --vanilla --slave --file="$module_dir/tests/jasp-output.R"
run_stage observed-plot "$r_executable" --vanilla --slave --file="$module_dir/tests/observed-plot.R"
# Keep native result examples in the portable report rather than only build/preview.
cp "$project_dir/build/preview/continuous-trajectories.png" "$validation_dir/plots/continuous-trajectories.png"
cp "$project_dir/build/preview/ordinal-trajectories.png" "$validation_dir/plots/ordinal-trajectories.png"
cp "$project_dir/build/preview/continuous-observed-fitted.png" "$validation_dir/plots/continuous-observed-fitted.png"
cp "$project_dir/build/preview/ordinal-observed-fitted.png" "$validation_dir/plots/ordinal-observed-fitted.png"
if ! python3 "$validation_dir/make-report.py"; then
  printf '%s\n' 'Validation computations passed, but report assembly failed. Read the command output.' > "$validation_dir/RUN-FAILED.txt"
  exit 1
fi
printf 'Completed: %s/START-HERE.html\n' "$validation_dir"
