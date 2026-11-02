# LCGA and GMM

This module fits existing `lcmm` models to **long-format data**: one row for each
subject and measurement time. Assign a subject ID, numeric time, and one outcome.

## Models

- **Continuous:** Gaussian models using `lcmm::hlme()`.
- **Ordinal:** latent-process threshold models using `lcmm::lcmm(link="thresholds")`.
- **LCGA:** class-specific polynomial mean trajectories without individual random effects.
- **GMM:** adds a random intercept or a random intercept and linear slope.

Linear, quadratic, and cubic describe the mean trajectory; the random-effects
choice is separate. Every class has the same polynomial degree, with separate
mean coefficients. One class provides a baseline model. Fit each requested class
count in a separate JASP analysis; this initial module does not automate enumeration.

The Gaussian residual variance is common across classes. GMM covariance may be
shared or differ by a proportional multiplier. The latter does not provide a
separate unrestricted covariance matrix for each class.

## Data and missingness

IDs may be numeric or text. ID and time must be observed and every ID/time pair
must be unique. Available outcomes uses the subject's observed measurements under
ignorable/MAR missingness assumptions; it does not impute cells. Subjects with no
observed outcomes contribute no fit information and are excluded. Complete subjects
excludes a subject with a missing outcome at any recorded visit. Neither choice
infers an unrecorded measurement schedule or resolves MNAR dropout.

For ordinal data, set the category order in JASP before fitting. Numeric outcomes
are ordered by their numeric values; ordered factors use the displayed level order.
The **Ordinal Category Order** table records the model's category mapping.
Only observed categories after exclusions enter the model. The ordinal model is
a threshold model, not an adjacent-category logit model.

## Estimation

A one-class model supplies starting values for native `lcmm::gridsearch()`.
The requested preliminary starts are run for the selected number of iterations;
the best preliminary solution is optimized to completion. The seed is reproducible.
Only full convergence (code 1) is accepted. Increase iterations or reconsider the
model when fitting fails. Compare different seeds and starting counts before
interpreting a substantive solution; a successful fit does not establish a global
maximum or an appropriate number of classes. Ordinal GMMs with random slopes can
be slow because they require numerical integration.

## Output

**Model Fit:** native log-likelihood, parameter count, AIC, BIC, sample-size adjusted
BIC and normalized entropy. BIC uses retained subjects. Entropy is undefined for
one class and is not a test of the number of classes.

**Growth Coefficients:** the native fixed-effect summary, with estimates, SEs and
Wald statistics. Time is scaled to `(time - minimum) / range`; the exact transform
is reported. These are not original-time coefficients. For ordinal models they
describe the latent process and the first-class intercept is fixed for identification.
This initial table does not report random-effect variances or ordinal cutpoints.

**Class Sizes and Classification:** modal-assignment counts, posterior expected
counts, and mean assigned-class probabilities. Labels are arbitrary and can switch
across fits. Assignments do not eliminate classification uncertainty.

**Class Trajectories:** native class predictions plotted against original time.
Ordinal plots show marginal expected category codes, not category probabilities;
consult the category-order table. Optional 95% bands use native `predictY()`.
For ordinal bands the displayed line is the median of parameter-draw predictions.
Bands are conditional on the chosen class count and model.

**Observed vs Fitted Trajectories:** filled points show posterior-probability-weighted
observed means; open points joined by lines show fitted means. Both use the same
retained records and weights. Fitted values are marginal class predictions at the
actual measurement times, averaged within each time group; they do not use
subject-specific random-effect predictions. Missing outcomes are not filled.

Automatic time grouping uses exact measurement times when there are at most 20
distinct retained times; otherwise it uses 10 equal-width intervals by default.
The grouping and interval count can be changed. Intervals include their left
endpoint; the last also includes the final time. Points are placed at each class's
weighted mean time. Empty or zero-weight groups are left as gaps. Within an
interval, a participant with multiple retained records contributes multiple times.
Sparse groups or groups with little posterior weight should be interpreted cautiously.

Ordinal observed and fitted values are means of the same model category codes
(1 through K). A mean-code comparison does not check the full category distribution.
The plot uses the fitting data and fitted class probabilities; it is a descriptive
diagnostic, not independent validation or a formal test. Confidence bands from
Class Trajectories do not apply to this plot. Changing these plot options reuses
the fitted model. Separate class panels share a common outcome scale.

The module corrects an lcmm 2.2.2 prediction issue for ordinal GMMs with
diagonal random intercept-and-slope covariance. Both plots use an equivalent
covariance representation during prediction; estimation and fit statistics are
unchanged.

The prediction-only correction also covers ordinal random-intercept confidence
draws with a retained diagonal covariance setting. Point predictions, estimation
and fit statistics are unchanged by this correction.

## Public beta scope

This public beta has one outcome, long data, one specified class count, and no
covariates, imputation, bootstrap class tests, weights, or other analyses.

## Reference

Proust-Lima, C., Philipps, V., & Liquet, B. (2017). Estimation of extended mixed
models using latent classes and latent processes: The R package lcmm.
*Journal of Statistical Software, 78*(2), 1–56. https://doi.org/10.18637/jss.v078.i02

## Support

Maintainer: Daniel Corcoran. Report issues to [particleapps@proton.me](mailto:particleapps@proton.me). Include the module and JASP versions, model settings, the error text and a small non-sensitive example when possible.
