# Trajectories for JASP — public beta 0.1.0

Trajectories provides **LCGA and GMM for long-format continuous and ordinal data**
inside JASP. It uses the existing `lcmm` estimators: `hlme()` for Gaussian outcomes
and `lcmm(link = "thresholds")` for ordinal outcomes. One row represents one
subject at one measurement time. Wide-format input is deferred.

The supplied installer targets **JASP 0.99.0.0 on Apple Silicon macOS**, using its
embedded **R 4.5.2** and pinned **lcmm 2.2.2**. Dependencies are included. Windows,
Intel macOS and Linux installers are not supplied or tested in this beta.

Author and maintainer: **Daniel Corcoran**. For support and bug reports, email
[particleapps@proton.me](mailto:particleapps@proton.me). Include the module/JASP
versions, model settings, error text and a small non-sensitive example when
possible. A public repository link will be added when the repository exists.

## Install and start

Download `jaspTrajectories.JASPModule` from this repository's **Releases**
section. The installer is supplied separately from the source-code archives.

1. In JASP, open the **+** module menu and choose **Install Module**.
2. Select the supplied **`jaspTrajectories.JASPModule` file**. Enable
   **Trajectories**, then choose **LCGA and GMM**.
3. Import a long-format file and assign **Subject ID**, **Measurement Time** and
   **Outcome**. Set the ID column to Nominal and time to Scale; select the intended
   outcome type and verify ordinal category ordering before fitting.
4. Choose LCGA or GMM, the number of classes and the polynomial degree. Review
   convergence, sample counts and class sizes before interpreting a solution.

If local module installation is hidden, enable JASP's developer-mode controls in
Preferences → Advanced. The source package `.tar.gz` is for R/source builds;
select the dependency-complete `.JASPModule` when installing through JASP.

JASP can import numeric IDs as Scale. In the tested JASP version, automatic
conversion to nominal is limited to 100 distinct values by default, so assigning
an ID column with more subjects can produce a type-conversion error. Set that
column to **Nominal** explicitly in the data editor; no global preference change
is needed. This is an import/assignment constraint, not a 100-subject model limit.

For a first continuous example, import `examples/trajectories-long.csv` and set
Outcome = `continuousOutcome`, Measurement Time = `time`, Subject ID = `subject`,
LCGA, two classes and a linear trajectory. This file contains 100 simulated
subjects at six times; it is a demonstration, not an empirical study.

For an ordinal example, create another analysis, choose **Ordinal (Threshold
Model)** and Outcome = `ordinalOutcome`, ordered 1–5. Start with one class, then
try two. The **Ordinal Category Order** table records the categories used.

## Included analyses and output

- One continuous or ordinal outcome, with user-supplied numeric measurement times.
  Unequal spacing and different observed times across subjects are supported.
- LCGA or GMM; linear, quadratic or cubic class-specific mean trajectories.
- GMM random intercept, or random intercept and linear slope; diagonal or
  unstructured covariance and optional proportional covariance differences by class.
- Available-outcome likelihood or exclusion of subjects with a missing recorded
  outcome; native multistart estimation, seed control and explicit convergence errors.
- Fit indices, longitudinal fixed-effect coefficients, class sizes and posterior
  classification; class trajectories with optional pointwise confidence bands.
- **Observed vs Fitted Trajectories**, using posterior-probability-weighted means
  for both outcome types, with exact-time or interval grouping and optional class panels.

Log-likelihood, AIC, BIC and sample-size adjusted BIC use ordinary notation with
three decimal places; underlying values retain full precision. An explicitly set
JASP global decimal preference can override this display setting.

Each analysis fits **one chosen class count**. Create separate analyses to compare
counts. This beta has no covariates, weights, multiple imputation, bootstrap class
tests or other analysis families.

## Interpretation and plotting

Missing outcomes contribute through each subject's observed measurements under
ignorable/MAR assumptions; missing cells are not imputed. Entirely unobserved
subjects are excluded. Missing IDs or times and duplicate subject/time rows are
rejected. Complete-subject deletion checks recorded visits only: absent rows do
not establish a missing measurement schedule.

The model uses scaled time `(time - minimum retained time) / retained time range`.
Coefficients use that scale; plots retain the original time scale. The transform
is reported. Ordinal coefficients describe the underlying latent process, while
ordinal plots show expected consecutive category codes 1 through K. These are
not category probabilities and depend on the coding. With confidence bands, the
native ordinal prediction line is the median across parameter draws.

Observed and fitted comparison means use the same posterior class probabilities
and retained records. Fitted values are evaluated at each record's actual time
before averaging. Automatic grouping uses exact times when at most 20 distinct
times remain; otherwise it uses equal-width intervals, ten by default. Within
intervals, subjects with more records contribute more weight. Unsupported groups
remain gaps. This comparison is descriptive, uses the fitting data and has no
confidence intervals; it does not test the complete ordinal distribution.

The coefficient table contains the native rounded longitudinal fixed-effect
summary, not variance parameters or ordinal cutpoints. Gaussian residual variance
is common across classes. Class-varying GMM covariance is proportional, rather
than a separate unrestricted covariance matrix for each class.

Only full convergence code 1 is accepted. Native `gridsearch()` optimizes the best
preliminary start to completion, but does not establish a global maximum. Assess
multiple starts and seeds. Class assignments are uncertain and class labels can
switch. Confidence bands condition on the selected model and class count.
Ordinal GMMs with random slopes can require appreciably longer computation.

## Ordinal prediction correction

The beta includes corrections for lcmm 2.2.2 diagonal ordinal random-slope
predictions and random-intercept confidence draws. Prediction uses an equivalent
unstructured representation of a copy of the fitted model, preserving signed
random-effect parameters and their uncertainty. Estimation, stored fitted
parameters and likelihoods are unchanged; random-intercept point predictions are
also unchanged. Both plots use the corrected prediction path.

Because this correction uses internal model fields, the package requires exactly
**lcmm 2.2.2** and checks that version at runtime on the affected prediction path.
A new lcmm version requires code review and renewed validation before support is
extended. The regression suite includes a converged negative-signed-SD fixture
and independent analytical checks of the confidence draws.

## Repository layout

This folder is the Git repository and R package root, following the
[JASP module structure](https://github.com/jasp-stats/jasp-desktop/blob/development/Docs/development/jasp-module-structure.md).

```text
jaspTrajectories/
├── DESCRIPTION, NAMESPACE, LICENSE, NEWS.md
├── jaspTrajectories.Rproj
├── R/                       # Analysis and fitting code
├── inst/
│   ├── Description.qml      # JASP ribbon/menu definition
│   ├── qml/                 # Analysis controls
│   ├── help/                # In-app help
│   ├── icons/               # Module icons
│   └── third-party/         # Bundled licence notices
├── man/                     # R function documentation
├── examples/                # Synthetic example data
├── tests/                   # Standalone regression checks
├── scripts/                 # Pinned build and release tools
└── validation/              # Public validation scripts and evidence
```

`jaspTrajectories.Rproj` provides editor/project settings. Use the documented
JASP build commands below to select the tested R environment and dependencies.
Generated libraries and installers are excluded from Git. Download installers
and dependency archives from GitHub Releases.

## Validation and reproducible builds

Open the [public validation report](validation/START-HERE.html) locally for the actual
run versions, model settings, expected results, execution logs, plot examples and
explicit desktop/build check statuses. The report separates native-engine
comparisons, independent calculations, regression tests and desktop interaction.
Only actions recorded as passed are claimed; omitted or untested actions remain
unverified. See [VALIDATION.md](VALIDATION.md) for the release validation record.

These tests assess the listed computations and integration cases. They do not
establish a global optimum, correct class-number selection, confidence-band
coverage or performance on every dataset and option combination.

The public repository and complete source-validation archive put `DESCRIPTION`,
`R/`, `inst/`, `scripts/` and `validation/` at the package root. From that root,
build with:

```sh
sh scripts/build-macos.sh
```

The build starts from an empty private library and verifies locked dependency
versions and hashes. It uses the matching JASP app and official CRAN binary
inputs, then rebuilds jaspBase with pinned Common/JSON and Rcpp source headers.
Python 3.9 or newer and Xcode Command Line Tools with a C++20 compiler are
required. The source cache can use the extracted dependency-source archive.
The build does not read a separate system/user R library. See
[BUILDING.md](BUILDING.md) for prerequisites, cache inputs, location overrides and
repeat-build instructions. Reproducibility here means locked inputs and a
repeatable procedure on the stated platform, not byte-identical installer files.

After building, run the complete validation with:

```sh
sh scripts/run-tests.sh
```

This runs all five standalone test scripts, refits the 14 native/module reference
cases, checks independent estimators and likelihood calculations, and generates
the report. These JASP-dependent tests are excluded from automatic `R CMD check`;
a package check alone does not run them. See [TESTING.md](TESTING.md) and the
[validation instructions](validation/README.md). Desktop interaction and
`.jasp` save/reopen are recorded separately in the report.

The original workspace layout, with `jaspTrajectories/` and `validation/` as
siblings, is also supported. Run the same commands from its `jaspTrajectories/`
folder; its validation files are at `../validation/`. Generated `build/` and
`dist/` folders live at the public package root, or at the parent workspace root
in the sibling layout. A module-source-only archive omits validation evidence;
use the complete source-validation archive to reproduce the full test run.

## Licence and citation

The module is licensed under **GPL version 2 or later**; see [LICENSE](LICENSE).
Dependencies retain their own licences and notices. Changes are listed in
[NEWS.md](NEWS.md).

The separate dependency-source download includes every bundled R dependency,
additional native-library sources and a checked source index. The installer
carries libdeflate's full copyright and MIT notice with both the module and ragg.
Read [DEPENDENCY-SOURCES.md](DEPENDENCY-SOURCES.md) for the pinned jaspBase/Common
build, source verification and remaining native build-provenance limits.

Cite the estimation methods as:

Proust-Lima, C., Philipps, V., & Liquet, B. (2017). Estimation of extended mixed
models using latent classes and latent processes: The R package lcmm.
*Journal of Statistical Software, 78*(2), 1–56.
[doi:10.18637/jss.v078.i02](https://doi.org/10.18637/jss.v078.i02).

GitHub account: [particle-apps](https://github.com/particle-apps). Until a module repository is available, use the support email above.
