# Validation record for Trajectories for JASP

Public beta: **jaspTrajectories 0.1.0**, 2 November 2026.

This is the first public release. The source repository contains the package,
reproducible build tools, numerical validation and native installer evidence.

## Automated validation

The automated suite was executed with **JASP 0.99.0.0, embedded R 4.5.2,
lcmm 2.2.2 and macOS arm64**. All eight stages passed, recording 440 seconds.
The [public report](validation/START-HERE.html) provides model settings,
full-precision results, plots, data provenance, execution logs and checksums.

- 38 numerical and data-handling checks passed.
- 26 ordinal prediction checks passed, including the retained-diagonal
  random-intercept confidence-band regression.
- 128 native/module, sample and independent-estimator assertions passed across
  14 freshly fitted reference cases.
- 22 independent likelihood/posterior checks passed.
- 43 observed-versus-fitted numerical checks passed.

Together these constitute **257 numerical assertions**, alongside native JASP
output, caching and plot-export checks. The reference cases cover continuous
and ordinal outcomes, LCGA/GMM, polynomial time effects and missing-data policies.
The source fingerprint and run metadata identify the tested analysis code;
documentation files are checked separately against the installed package.

The primary native and module fits converged and matched. Additional-seed case
O02 with seed 3821 returned convergence code 2; this diagnostic is retained in
[the seed results](validation/results/seed-stability.csv). Other model settings
and datasets may encounter local optima or nonconvergence.

## Package and installer checks

The build verified 111 locked package inputs and restored 101 non-base dependencies.
jaspBase 0.20.4 was compiled from pinned package sources, using all 49 Common/JSON
files at JASP desktop commit `1204d1892b1233af145bb548fe80719f331ea693` and matching
Rcpp 1.1.1 headers. The source recipe, inputs and provenance are supplied in the
[dependency-source record](DEPENDENCY-SOURCES.md). The required libdeflate notices
are included in the module and ragg dependency.

The R source-package check completed with **zero errors, zero notes and one
`inst/help` warning**. This directory contains the in-app help used by JASP.

JASP's native bundle manager installed the installer into an empty isolated
location. Its complete manifest, 101 dependency trees, Common source files,
licence notices, 21 runtime definitions and seven installed resources matched
the checked source and build records. Native continuous/ordinal output, caching
and plot-export checks passed. The NEWS file and help page match the source.

Installer SHA-256:

```text
553249c926ab3aad8d7b05c46df67cf481c923f71d16708ffb2284ca62d8e42c
```

The [build checklist](validation/results/release-checks.csv) identifies evidence
for the current installer and source fingerprint. Build records use a neutral
temporary directory and contain no identified personal home/workspace paths.

## Desktop validation status

**The full desktop walkthrough has not been performed for this installer.**
Interactive CSV import, control manipulation, and saving/reopening JASP documents
are not claimed as verified for this release. Isolated native installation and
output checks are distinct from desktop interaction. See
[the desktop checklist](validation/results/desktop-checks.csv).

The public kit includes automated plots and public reference data. It does not
include desktop screenshots or saved JASP examples as release-validation evidence.
Subject ID should be set to Nominal and measurement time to Scale in JASP.

## Reproduction and limits

From the repository root, follow [BUILDING.md](BUILDING.md), then run
`sh scripts/run-tests.sh`; see [TESTING.md](TESTING.md). A plain `R CMD check`
does not run this JASP-dependent validation suite.

Validation does not establish global maxima, correct class-number selection,
confidence-band coverage, or performance on every dataset and option combination.
Independent density calculations evaluate fitted estimates; they do not
independently optimize all mixture models. Other platforms remain unverified.
Pinned inputs and a repeatable procedure do not imply byte-identical builds.
