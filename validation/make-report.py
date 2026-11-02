"""Build the portable HTML guide from executed validation results."""
from pathlib import Path
import csv
import hashlib
import html
import json
import re as regex
import copy
import os

root = Path(os.environ.get("TRAJECTORIES_VALIDATION_DIR", Path(__file__).resolve().parent)).resolve()
project = Path(os.environ.get("TRAJECTORIES_PROJECT_DIR", root.parent)).resolve()
module = Path(os.environ.get("TRAJECTORIES_MODULE_DIR", project if (project / "DESCRIPTION").is_file() else project / "jaspTrajectories")).resolve()


def read(name):
    with (root / name).open(newline="") as stream:
        return list(csv.DictReader(stream))


def esc(value):
    return html.escape(str(value))


def table(rows, columns=None):
    if not rows:
        return "<p>No rows.</p>"
    columns = columns or list(rows[0])
    headers = "".join(f"<th>{esc(c)}</th>" for c in columns)
    body = []
    for row in rows:
        cells = []
        for c in columns:
            value = row[c]
            try:
                number = float(value)
                value = f"{number:.6f}".rstrip("0").rstrip(".")
            except (ValueError, TypeError):
                pass
            cells.append(f"<td>{esc(value)}</td>")
        body.append("<tr>" + "".join(cells) + "</tr>")
    return '<div class="scroll"><table><thead><tr>' + headers + "</tr></thead><tbody>" + "".join(body) + "</tbody></table></div>"


metadata = json.loads((root / "results/run-metadata.json").read_text())
stages = read("results/test-stages.csv")
expected_stages = {"preflight", "smoke", "prediction-support", "build-reference", "check-independent", "observed-fit", "jasp-output", "observed-plot"}
assert {r["stage"] for r in stages} == expected_stages
assert all(r["status"] == "PASS" and r["exitCode"] == "0" for r in stages)
assert metadata["freshReferenceFits"] and metadata["sourceVersionMatchesInstalled"]
# Logs remain verbatim apart from replacing this checkout's absolute location.
# This keeps the public artifact portable without disclosing a home-directory name.
for log in (root / "logs").glob("*.log"):
    log.write_text(log.read_text().replace(str(project), "<project>"))
settings = read("model-settings.csv")
fits = read("results/expected-fit.csv")
samples = read("results/expected-sample.csv")
coefs = read("results/expected-coefficients.csv")
classes = read("results/expected-classification.csv")
anchors = read("results/independent-estimators.csv")
seeds = read("results/seed-stability.csv")
checks = read("results/automated-checks.csv")
likelihood_checks = read("results/independent-likelihood-checks.csv")
assert all(row["passed"] == "TRUE" for row in checks + likelihood_checks)

parts = ["""<!doctype html><html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>JASP Trajectories — reference validation</title>
<style>
body{font:16px/1.6 system-ui,sans-serif;color:#18313c;max-width:1160px;margin:40px auto;padding:0 24px;background:#f8fafb}
h1{font-size:36px;line-height:1.15}h2{margin-top:38px}h3{margin-bottom:6px}
a{color:#12647a}code{background:#eaf0f2;padding:2px 5px;border-radius:4px}
section{background:white;border:1px solid #dbe4e8;border-radius:12px;padding:20px 24px;margin:24px 0}
.note{border-left:4px solid #17777d;padding:12px 18px;background:#edf6f5}
.scroll{overflow-x:auto}table{border-collapse:collapse;font-size:14px;margin:12px 0;width:100%}
th,td{text-align:left;white-space:nowrap;border-bottom:1px solid #dbe4e8;padding:8px 12px}
th{background:#edf3f5}img{display:block;max-width:760px;width:100%;height:auto}
.muted{color:#536976}.tag{font-weight:600;color:#13736a}
@media print{body{margin:0;background:white}section{break-inside:avoid}a{color:inherit}}
</style></head><body>
<p class="tag">PUBLIC BETA VALIDATION · __RUN_DATE__</p>
<h1>Trajectories for JASP: validation report</h1>
<p>Executed for <strong>jaspTrajectories __MODULE_VERSION__</strong>, lcmm __LCMM_VERSION__,
R __R_VERSION__ on __PLATFORM__. All reference models were refitted during this run;
previously saved estimates were not used as evidence for this build.</p>
<p>Source checks, independently constructed reference fits, native JASP result objects and desktop
interaction are distinguished below. Passing these tests supports the implemented calculations on the
listed cases; it does not establish model suitability for every dataset or prove a global maximum.</p>
<p class="note">Start with <strong>C01</strong>, then <strong>C04</strong>, <strong>C05</strong>,
<strong>O01</strong> and <strong>P01/P02</strong>. These establish basic continuous fitting,
multiple classes, random effects, ordinal fitting and missing-data handling before testing the remaining cases.
Install the matching public beta before comparing the desktop results.</p>
<h2>What these references establish</h2>
<p>The CSV files come from established datasets distributed with lcmm. Each reference result was fitted
directly in lcmm, separately from the module. Eligible one-class cases were also fitted with independent
estimators: Gaussian regression with <code>lm</code>, Gaussian mixed models with <code>nlme::lme(method="ML")</code>,
and ordered probit regression with <code>MASS::polr(method="probit")</code>.</p>
<p>These are newly calculated benchmarks for the exact models listed here, not copied published model estimates.
The examples omit covariates unsupported by this first module. They do not establish the true number of classes, statistical coverage, or recovery of the original generating models.</p>
<h2>Data and provenance</h2>
<ul>
<li><a href="data/lcmm-continuous.csv">lcmm-continuous.csv</a>: <code>data_hlme</code>, Y/Time/ID renamed to
outcome/time/subject; 326 records, 100 participants. This is simulated data with covariates and three generating
classes. Our reduced models do not attempt to recover that generating specification.
<a href="https://cecileproust-lima.github.io/lcmm/reference/data_hlme.html">Official documentation</a>.</li>
<li><a href="data/lcmm-ordinal.csv">lcmm-ordinal.csv</a>: <code>data_lcmm</code>, Ydep3/Time/ID renamed;
1,678 records, 300 participants. Simulated ordinal data from a more complex joint model.
<a href="https://cecileproust-lima.github.io/lcmm/reference/data_lcmm.html">Official documentation</a>.</li>
<li><a href="data/paquid-ordinal.csv">paquid-ordinal.csv</a>: real Paquid cohort subsample, HIER/age/ID renamed;
2,250 records, 500 participants, 46 missing HIER responses. HIER codes 0, 1, 2 and 3 represent increasing physical dependency.
<a href="https://cecileproust-lima.github.io/lcmm/reference/paquid.html">Official documentation</a>.</li>
<li><a href="data/lcmm-continuous-missing.csv">lcmm-continuous-missing.csv</a>: controlled modification of the continuous file,
with the first recorded outcome for each of the first ten participants blanked. No rows were removed.
<a href="results/missingness-audit.csv">Exact changes</a>.</li>
</ul>
<h2>How to run each test</h2>
<ol>
<li>Open the indicated CSV in JASP. Use <strong>subject</strong> as Subject ID, <strong>time</strong> as Measurement Time,
and <strong>outcome</strong> as Outcome. First set subject to <strong>Nominal</strong>, time to Scale,
and outcome to Scale for continuous tests or Ordinal for ordinal tests. Numeric IDs may import as Scale;
JASP's default automatic nominal conversion has a 100-level limit. Explicitly set the ID column to Nominal
in the data editor for larger samples; this requires no global preference change and is not a module sample-size limit.
Verify ordinal categories are ordered numerically, including 0 where present.</li>
<li>Open Trajectories → LCGA and GMM. Apply the test's outcome type, analysis, class count, polynomial,
random effects and missing-data policy. A one-class model is an intentional reference case.</li>
<li>Under Estimation set <strong>Random Starts = 30</strong>, <strong>Iterations per Preliminary Start = 50</strong>,
<strong>Maximum Final Iterations = 1000</strong>, <strong>Random Seed = 12345</strong>.
Leave <strong>Proportional Random-Effects Variance by Class unchecked</strong>.</li>
<li>Enable Growth Coefficients, Class Sizes and Classification, and Class Trajectories.
Leave <strong>95% Pointwise Confidence Bands unchecked</strong> for these comparisons.</li>
<li>Compare the results below. Record observations in <a href="jasp-checklist.csv">jasp-checklist.csv</a>,
and save each tested analysis in a .jasp file. Changing CSVs should start a new JASP data session.</li>
</ol>
<h2>Comparison rules</h2>
<ul>
<li>Counts and numbers of parameters must match exactly. Compare log-likelihood, AIC and BIC within <strong>0.001</strong>
using sufficient displayed decimal places. Rounded display values may differ in their final digit.</li>
<li>Compare growth coefficients and SEs within <strong>0.0001</strong> when enough decimals are visible.
The native summaries round coefficients to five decimals. The reference term <code>t</code> corresponds to the
module's <code>.time</code>; both use the reported scaled time, not the CSV's raw time.</li>
<li>Class labels may swap. Match complete trajectories, then compare the corresponding coefficient and
classification rows. A class-number swap alone is not a failure. Match integer class counts exactly after relabelling.</li>
<li>Check plotted directions, curvature, endpoints and original-time axes. Precise trajectory values are in
<a href="results/expected-predictions.csv">expected-predictions.csv</a>. Ordinal graphs show expected consecutive
category codes; Paquid 0–3 is mapped to 1–4. Ordinal coefficients are on the latent probit scale.</li>
<li>Use the same rows, missingness policy, covariance restriction and scaled-time origin. Complete-subject
deletion can change the time transform. BIC here uses participants, not observation rows.</li>
<li>If a mixture's likelihood differs by more than 0.001, verify settings and category order, then repeat with more starts
and another seed. A different local maximum must be investigated; it is not automatically a wrapper defect.</li>
</ul>
<h2>Quick reference</h2>
"""]
header = parts[0]
for marker, value in {"__RUN_DATE__": metadata["startedUTC"], "__MODULE_VERSION__": metadata["moduleVersion"],
                      "__LCMM_VERSION__": metadata["lcmmVersion"], "__R_VERSION__": metadata["rVersion"],
                      "__PLATFORM__": metadata["platform"]}.items():
    header = header.replace(marker, esc(value))
parts[0] = header
parts.append(table(fits, ["case", "G", "loglik", "npm", "AIC", "BIC", "entropy"]))
parts.append('<h2>Exact settings and expected output</h2>')
for s in settings:
    key = s["case"]
    f = next(r for r in fits if r["case"] == key)
    model = "LCGA" if s["model"] == "lcga" else "GMM"
    re = "None" if model == "LCGA" else ("Intercept and Linear Slope" if s["randomEffects"] == "interceptSlope" else "Intercept")
    policy = "Complete Subjects" if s["missing"] == "completeSubjects" else "Available Outcomes (Observed-Data Likelihood)"
    parts.append(f'<section id="{key}"><h2>{key} · {model} · {s["classes"]} class(es) · {s["degree"].title()}</h2>')
    parts.append(f'<p>File: <a href="data/{s["file"]}">{s["file"]}</a><br>'
                 f'Outcome: {s["outcomeType"].title()} · Random Effects: {re} · Covariance: {s["covariance"].title()}<br>'
                 f'Missing data: {policy}<br>Scaled time: (time − {f["timeOrigin"]}) / {f["timeScale"]}.</p>')
    if any(r["case"] == key and r["sameLikelihoodWithin0_001"] != "TRUE" for r in seeds):
        parts.append('<p class="note">The reference fit with seed 12345 converged and matched the module. '
                     'At least one additional seed failed to converge or gave a different likelihood. '
                     'Treat this as an advanced starting-value sensitivity check; see the seed table below.</p>')
    parts.append('<h3>Model Fit</h3>' + table([f], ["loglik", "npm", "AIC", "BIC", "SABIC", "entropy", "convergence"]))
    parts.append('<h3>Analysis Sample</h3>' + table([r for r in samples if r["case"] == key], ["measure", "count"]))
    parts.append('<h3>Growth Coefficients</h3>' + table([r for r in coefs if r["case"] == key], ["term", "estimate", "se", "statistic", "p"]))
    if s["outcomeType"] == "ordinal":
        input_rows = read("data/" + s["file"])
        excluded = {r["subject"] for r in input_rows if r["outcome"] == ""} if s["missing"] == "completeSubjects" else set()
        levels = sorted({float(r["outcome"]) for r in input_rows if r["outcome"] != "" and r["subject"] not in excluded})
        parts.append('<h3>Ordinal Category Order</h3>' + table([{"Model code": i + 1, "Original category": value} for i, value in enumerate(levels)]))
    parts.append('<h3>Class Sizes and Classification</h3>' + table([r for r in classes if r["case"] == key], ["class", "assigned", "assignedPercent", "posteriorCount", "averagePosterior"]))
    parts.append(f'<img src="plots/{key}.png" alt="Expected trajectory plot for test {key}" loading="lazy"></section>')

parts.append(f'<h2>Executed automated checks</h2><p><strong>{len(checks)} direct-reference, sample and independent-estimator checks passed</strong>, '
             f'plus <strong>{len(likelihood_checks)} independent likelihood/posterior checks</strong>. '
             'The full numeric differences and tolerances are recorded below. This does not replace checking CSV import and controls in the desktop application.</p>')
parts.append('<p><a href="results/automated-checks.csv">All automated checks</a> · '
             '<a href="results/independent-likelihood-checks.csv">Independent likelihood calculations</a> · '
             '<a href="results/session-info.txt">Runtime/package versions</a> · '
             '<a href="results/test-stages.csv">Execution status and log index</a> · '
             '<a href="results/run-metadata.json">Recorded run metadata</a></p>')
parts.append('<p>The independent density calculations evaluate the fitted parameter vectors. They independently reconstruct likelihoods and posterior probabilities; they do not independently optimize the mixture models.</p>')
parts.append('<h3>Independent estimators</h3>' + table(anchors))
parts.append('''<p>These independent estimator tolerances are absolute: 0.001 for likelihood and raw fixed effects.
Gaussian likelihoods use ML, not REML. lm residual standard errors and t tests are not the module’s ML variance and normal Wald tests.
No independent ordinal GMM integration reference was fitted.</p>'''.replace('\n', ' '))
parts.append('''<h3>Mixture starting-seed checks</h3><p>Each mixture reference was refitted with two additional seeds, using the same 30 starts and iteration settings.
Matching likelihoods support repeatability on these datasets, not proof of a global optimum. Native random starts can emit a numerical warning before the selected final fit converges.</p>'''.replace('\n', ' '))
parts.append(table(seeds))
if any(r["sameLikelihoodWithin0_001"] != "TRUE" for r in seeds):
    parts.append('''<p class="note"><strong>Seed variability or nonconvergence detected.</strong> Some seed runs did not converge or found a different likelihood.
Use the table above to identify affected cases; the reference values specify seed 12345.</p>'''.replace('\n', ' '))
# Evidence from the five standalone regression scripts is separate from model comparisons.
parts.append('<h2>Complete regression suite</h2><p>Every script is run by the documented command. '
             'Source-level checks exercise the current checkout; the JASP/plot scripts exercise the installed package. '
             'The preflight requires their version numbers to match and constrains package lookup to the selected '
             'library and embedded R. Exit status and wall time are retained for every stage.</p>')
parts.append(table(stages, ["stage", "status", "exitCode", "elapsedSeconds"]))
parts.append('<ul>' + ''.join(f'<li><a href="{esc(r["log"])}">{esc(r["stage"])} execution log</a></li>' for r in stages) + '</ul>')
regression_counts = []
for stage in ["smoke", "observed-fit", "prediction-support", "jasp-output", "observed-plot"]:
    log = (root / "logs" / (stage + ".log")).read_text()
    count = sum(bool(regex.match(r"^PASS(?:\s|:)", line)) for line in log.splitlines())
    regression_counts.append({"script": stage + ".R", "passed assertions/groups": count})
parts.append(table(regression_counts))
prediction_log = (root / "logs/prediction-support.log").read_text()
confidence_evidence = next((line for line in prediction_log.splitlines()
                            if line.startswith("Random-intercept regression evidence:")), None)
if confidence_evidence:
    parts.append('<h3>Ordinal random-intercept confidence-band regression</h3><p>' +
                 esc(confidence_evidence) + '</p><p>The converged fixture retains a diagonal covariance '
                 'setting and a negative signed random-effect parameter. Its interval draws are compared '
                 'with independently calculated ordinal marginal expectations using the same draws. '
                 'The test also checks that the fitted object, likelihood, fit statistics and point predictions '
                 'remain unchanged. See <a href="logs/prediction-support.log">the complete regression log</a>.</p>')
parts.append('<p>For the JASP and plot scripts, a PASS line denotes a group of native-object/plot assertions; '
             'the counts should not be interpreted as independent statistical experiments. The confidence-band '
             'regression checks include the diagonal ordinal random-intercept case and independent analytical '
             'marginal expectations. They check computation, not frequentist coverage.</p>')
parts.append('<h3>Observed versus fitted plot examples</h3>')
for name, label in [("continuous-observed-fitted", "Continuous, posterior-weighted observed and fitted means"),
                    ("ordinal-observed-fitted", "Ordinal, posterior-weighted observed and fitted category codes")]:
    parts.append(f'<figure><img src="plots/{name}.png" alt="{esc(label)}"><figcaption>{esc(label)}</figcaption></figure>')
parts.append('<p>The plot-coordinate tests also cover six refitted reference models, including ordinal random-intercept GMMs, '
             'and assert that unsupported groups remain gaps. Their PNGs and exact summary CSVs are in '
             '<a href="plots/observed-fitted/C04-observed-fitted.png">the observed/fitted examples</a>.</p>')

def external_evidence(filename, title):
    parts.append('<h2>' + esc(title) + '</h2>')
    path = root / "results" / filename
    if not path.exists():
        parts.append('<p class="note"><strong>Not recorded in this report.</strong> No completed checks are claimed.</p>')
        return
    original_rows = read("results/" + filename)
    rows = copy.deepcopy(original_rows)
    source_fingerprint = hashlib.sha256((root / "results/source-file-hashes.csv").read_bytes()).hexdigest()
    for row in rows:
        if row.get("moduleVersion") != metadata["moduleVersion"] or row.get("sourceFingerprint") != source_fingerprint:
            row["notes"] = ("Evidence does not match this run's module version and source fingerprint. "
                            "Recorded status: " + row["status"] + ". " + row.get("notes", ""))
            row["status"] = "HISTORICAL / UNVERIFIED"
    parts.append(table(rows, ["check", "status", "notes"]))
    for row in rows:
        evidence = row.get("evidence", "")
        if evidence:
            target = (root / evidence).resolve()
            if root.resolve() not in target.parents or not target.is_file():
                raise ValueError("Missing or nonportable evidence: " + evidence)
            parts.append(f'<p><a href="{esc(evidence)}">{esc(row["check"])}: evidence</a></p>')
    parts.append('<p><a href="results/' + filename + '">Machine-readable checklist</a>. '
                 'Current evidence must match this run’s module version and source fingerprint. '
                 'Installer hashes, where recorded, identify the exact tested artifact.</p>')

external_evidence("release-checks.csv", "Build, package and installer checks")
external_evidence("desktop-checks.csv", "Desktop interaction and file persistence")
parts.append('''<h2>Scope and limitations</h2><p>These checks cover the listed models and regression fixtures only.
They do not establish a global likelihood maximum, valid class-number selection, statistical coverage of
confidence bands or correctness for every possible dataset and option combination.
The reference suite includes ordinal GMMs with one class and a random intercept; no independent ordinal
GMM numerical-integration estimator is supplied. Separate prediction fixtures check ordinal random slopes
and diagonal random-intercept confidence calculations. Missingness checks validate row handling and observed-data
calculations; they do not establish that missingness is ignorable in a substantive dataset.</p>
<p>Desktop outcomes are limited to the explicit checklist above. If a desktop action is absent or marked untested,
it remains unverified. Results were generated on the recorded platform; other operating systems are unverified.</p>
<h2>Reproduce this report</h2><p>From the public package/repository root containing <code>DESCRIPTION</code>,
<code>scripts/</code> and <code>validation/</code>, run <code>sh scripts/run-tests.sh</code> after building/installing the
matching module into the documented clean library.
The command runs all five test scripts, refits all 14 reference
models through separate native and module paths, performs additional seed fits and independent density/estimator
checks, and regenerates this report. It does not install packages or alter JASP's installed user module.
The existing manual checklist is preserved. See <a href="README.md">README.md</a> for environment settings.</p>
<p>The source package's <code>R CMD check</code> intentionally excludes these JASP-dependent standalone tests;
the complete command above is required. A successful package check alone is not this validation suite.</p>
<p>Execution logs are retained with only the checkout's absolute path replaced by <code>&lt;project&gt;</code>.
Data, model settings, full-precision output and fitted objects are included for audit and replay.
Public build records use a neutral temporary directory. The desktop checklist explicitly identifies actions that have not been tested.</p>
<p><a href="build-reference.R">Reference generation script</a> · <a href="independent-likelihood.R">Independent calculation code</a> ·
<a href="model-settings.csv">All model settings</a> · <a href="SHA256SUMS.txt">File checksums</a></p>
</body></html>''')
(root / "START-HERE.html").write_text("\n".join(parts))
files = sorted(p for p in root.rglob("*") if p.is_file() and p.name not in ("SHA256SUMS.txt", ".DS_Store") and "__pycache__" not in p.parts)
(root / "SHA256SUMS.txt").write_text("".join(f"{hashlib.sha256(p.read_bytes()).hexdigest()}  {p.relative_to(root)}\n" for p in files))
print(f"Created START-HERE.html for {metadata['moduleVersion']}: {len(settings)} cases; {len(checks) + len(likelihood_checks)} reference checks and all five regression scripts passed.")
