# Testing the public beta

After the [clean build](BUILDING.md), run this from the public repository/package root:

```sh
sh scripts/run-tests.sh
```

The public source checkout includes `validation/` beneath the package root. The default private library matches the build script (`build/clean-macos-arm64/library`); `TRAJECTORIES_BUILD_DIR` or `R_LIBS_USER` can select another prepared library. `TRAJECTORIES_MODULE_DIR`, `TRAJECTORIES_PROJECT_DIR` and `TRAJECTORIES_VALIDATION_DIR` can explicitly select these locations.

This command runs all five standalone test scripts, regenerates all 14 native/module reference cases without reusing saved fits, checks independent likelihoods/posteriors and eligible independent estimators, exercises additional mixture seeds, and writes the [public validation report](validation/START-HERE.html). Each stage records its actual exit status, elapsed time and log. Failed runs remove the previous success report and leave the failing log and `RUN-FAILED.txt`.

The five scripts are intentionally excluded from `R CMD check` because they require JASP's libraries and generated reference fixtures. Run the complete command in addition to the R package check; a successful package check alone is insufficient.

See [validation instructions](validation/README.md) for the environment, stage order, references, data provenance and interpretation limits. Native JASP objects are exercised outside the desktop. Actual desktop interaction, installation and file-persistence results are reported separately with explicit evidence; missing or outdated records are not treated as passed. A machine-readable source fingerprint and optional installer hash bind those records to the tested build.

## Preparing columns in JASP

Set **subject** to Nominal, **time** to Scale, and **outcome** to Scale for continuous tests or Ordinal for ordinal tests before assignment. Numeric IDs may be imported as Scale. The tested JASP version limits automatic scale-to-nominal conversion to 100 distinct values by default; set the ID column to Nominal explicitly in the data editor when this prevents assignment. This does not limit the module to 100 subjects, and no global preference change is required. The ordinal reference CSV has 300 subjects and exercises this setup.
