# Public beta validation

Open `START-HERE.html` for the completed report, full model settings, references, regression results, plot examples, build evidence and desktop checklist. The report records its module, lcmm and R versions from the actual run. It is regenerated only after every required automated stage passes. A failed run removes the previous success page and leaves `RUN-FAILED.txt`, the stage status and its execution log.

## One command

After preparing the clean environment and installing the matching source as described in [BUILDING.md](../BUILDING.md), run this from the public repository/package root:

```sh
sh scripts/run-tests.sh
```

The public repository puts `DESCRIPTION`, `scripts/` and this `validation/` folder at the package root. If using an alternative private library, supply its absolute path:

```sh
R_LIBS_USER=/absolute/path/to/clean/library sh scripts/run-tests.sh
```

The default private library is `build/clean-macos-arm64/library` beneath the repository root, matching the clean build script. `TRAJECTORIES_BUILD_DIR` can override that build root; `TRAJECTORIES_MODULE_DIR`, `TRAJECTORIES_PROJECT_DIR` and `TRAJECTORIES_VALIDATION_DIR` can select source/output roots explicitly. The default R is the embedded Apple Silicon R 4.5 in `/Applications/JASP.app`. Set `JASP_R_HOME` to the matching R home and, if required, `TRAJECTORIES_R` to its R wrapper executable when the app is installed elsewhere. A `python3` executable is required to assemble the report. Changing lcmm from 2.2.2 is deliberately rejected because the prediction correction depends on its model representation.

The runner sets an empty site-library path and unsets `R_LIBS`. Preflight requires the installed `jaspTrajectories` version to match the source `DESCRIPTION`, requires lcmm 2.2.2, and checks the required packages resolve from the chosen library or embedded R. It does not install packages or modify the module in JASP's user library.

## What runs

1. Preflight and runtime metadata capture.
2. `tests/smoke.R`: numerical agreement and data handling.
3. `tests/prediction-support.R`: analytical ordinal prediction and confidence-draw regression checks.
4. `build-reference.R`: fresh native lcmm and exported JASP fits for all 14 specified cases, independent `lm`, `nlme::lme` and `MASS::polr` anchors where applicable, and additional mixture seeds.
5. `check-independent.R`: independent Gaussian/ordinal LCGA density and posterior reconstruction at the native estimates. Ordinal GMM integration is explicitly outside this checker.
6. `tests/observed-fit.R`: independently summed posterior-weighted observed/fitted summaries and grouping edge cases using the newly generated fits.
7. `tests/jasp-output.R`: actual native JASP tables, plots, factor ordering and cached-fit reuse.
8. `tests/observed-plot.R`: plot coordinates, panels, gaps and PNG exports.
9. Portable report and SHA-256 manifest generation, including every log and fitted object.

The five standalone tests are deliberately excluded from automatic `R CMD check` because they use JASP's embedded libraries and reference fixtures. **Run this complete command as well as the package check.** No historical reference models are reused; a successful source-package check is not a substitute for these validations.

The runner replaces generated references and execution logs in this folder. Archive a copy first when retaining an earlier result matters. `jasp-checklist.csv` is preserved for manual notes. Build/desktop evidence supplied separately in `results/release-checks.csv` and `results/desktop-checks.csv` is included with its explicit status; absent evidence is never inferred to have passed. Those CSVs use `check,status,evidence,notes,moduleVersion,sourceFingerprint`, with evidence paths relative to this folder. `sourceFingerprint` is the SHA-256 of `results/source-file-hashes.csv` for this run. Evidence with a missing or mismatching version/fingerprint is displayed as historical/unverified. Add `installerSHA256` for installer/desktop checks to identify the tested artifact. Regenerate the HTML after updating that evidence:

```sh
python3 validation/make-report.py
```

## Interpreting the results

The datasets and benchmarks assess implemented calculations and integration for the stated models. They do not establish a global maximum, correct class-number selection, or statistical confidence-band coverage. Additional seed nonconvergence or local-optimum variability is reported rather than hidden. Confidence-draw regression tests check the calculation on controlled examples, not coverage.

Compare desktop results with sufficient displayed precision. The reference HTML specifies tolerances, measurement scales and category order. Native fixed-effect summaries are rounded; class labels may permute. Save `.jasp` files during desktop checks and record what was actually performed. Operating systems and UI interactions not listed as passed remain unverified.

## Desktop column types

Before assigning the imported columns, set `subject` to **Nominal**, `time` to **Scale**, and `outcome` to **Scale** for continuous tests or **Ordinal** for ordinal tests. JASP may import numeric IDs as Scale. The tested JASP version's automatic nominal conversion has a default 100-level limit; manually setting the ID column to Nominal resolves the assignment error for the 300-subject ordinal fixture without changing a global preference. This is a JASP import/assignment constraint, not a module sample-size limit.
