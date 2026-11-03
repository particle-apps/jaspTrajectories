# Contributing to Trajectories for JASP

Contributions to this independent community project are welcome: reproducible
bug reports, documentation improvements, model-validation cases and code changes.

## Report a problem

Search [existing issues](https://github.com/particle-apps/jaspTrajectories/issues)
before opening a new report. Include:

- JASP version, module version, operating system and processor architecture.
- Model settings, variable types and the smallest steps that reproduce the problem.
- The exact error or unexpected result and what you expected to happen.
- A small synthetic or anonymised dataset, where useful.

For numerical discrepancies, include the seed, start settings and convergence
status. If comparing with an `lcmm` fit, use the same data, model specification,
time scaling and package version. See [USAGE.md](USAGE.md) for interpretation.

Do not upload identifiable participant data or confidential study files.
Contact [particleapps@proton.me](mailto:particleapps@proton.me) when a report
cannot be shared publicly.

## Propose a change

Use an issue to describe the use case and expected behaviour for a new analysis
or a substantial change. For a small documentation correction, a pull request
can go directly to review.

The current beta supports long-format continuous and ordinal LCGA/GMM on
Apple Silicon macOS with JASP 0.99.0.0. Other platform contributions should
identify the environment and checks performed; portability is not assumed.

## Submit a pull request

1. Fork the repository and create a branch for the change.
2. Follow the existing R, QML and Python conventions. Keep changes focused.
3. Update documentation when behaviour or supported options change.
4. Run checks appropriate to the change and describe the results in the pull request.

For code affecting estimation, prediction or output, follow [BUILDING.md](BUILDING.md)
and [TESTING.md](TESTING.md), including the complete validation command:

```sh
sh scripts/run-tests.sh
```

A successful `R CMD check` alone does not exercise the JASP-dependent suite.
Documentation-only changes should have their links, examples and stated behaviour
checked; they do not require a new statistical validation run.

Explain the problem, the resulting behaviour and the checks performed in the
pull request. State untested platforms or desktop interactions explicitly.
Keep generated libraries, local caches and installers out of the source repository.

## Statistical and release changes

The module pins `lcmm` to 2.2.2 because its ordinal prediction correction depends
on model internals. A dependency update needs code review and renewed validation.
Preserve convergence reporting, seed controls and documented interpretation limits.

Validation evidence must identify the code and installer that were tested.
Distinguish native-object checks from interaction with the JASP desktop.
Retain upstream copyright and licence notices in any dependency changes.
