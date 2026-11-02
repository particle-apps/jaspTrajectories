# Changes in Trajectories for JASP

## 0.1.0 — first public beta

- Latent class growth analysis and growth mixture models for continuous and
  ordinal outcomes in long-format data, using lcmm 2.2.2.
- Linear, quadratic and cubic time effects, missing-data handling, posterior
  classification, class trajectories and pointwise confidence bands.
- Posterior-weighted observed versus fitted plots, with exact-time or interval
  grouping and optional panels for each class.
- Corrected ordinal diagonal-covariance predictions and random-intercept
  confidence calculations, verified against numerical reference cases.
- Model-fit statistics displayed in ordinary notation with three decimal places.
- Dependency-complete installer for JASP 0.99.0.0 on Apple Silicon macOS.
- Reproducible build instructions, dependency sources and automated validation
  with 257 numerical assertions and 14 freshly fitted reference cases.

This beta supports one outcome and one specified class count per analysis.
Wide-format input, covariates, weights, imputation and bootstrap class tests
are not supported. Other platforms and the full desktop walkthrough remain
unverified for this release.
