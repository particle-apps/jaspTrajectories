# Model guide

Detailed model behaviour and interpretation for Trajectories for JASP 0.1.0.
For installation and a first example, see [README.md](README.md).

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

