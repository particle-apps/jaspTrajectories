# Synthetic demonstration data only; not observations from a study.
# Run from the module root with Rscript examples/generate-example.R.
# Both outcomes contain missing values, and every subject retains observations.
# The two generating groups are intentionally well separated for the continuous
# outcome. Their ordinal response distributions overlap more substantially.
set.seed(20261021)
n <- 100L
waves <- 0:5
group <- rep(1:2, each = n / 2L)
subjectIntercept <- rnorm(n, 0, 0.25)
subjectSlope <- rnorm(n, 0, 0.045)
ordinalIntercept <- rnorm(n, 0, 0.35)
subjectIndex <- rep(seq_len(n), each = length(waves))
time <- rep(waves, times = n)
class <- group[subjectIndex]
continuous <- ifelse(class == 1L, 1.2 + 0.30 * time, 4.4 - 0.14 * time) +
  subjectIntercept[subjectIndex] + subjectSlope[subjectIndex] * time +
  rnorm(length(time), 0, 0.38)
ordinalLatent <- ifelse(class == 1L, -0.9 + 0.25 * time, 0.9 - 0.10 * time) +
  ordinalIntercept[subjectIndex] + rnorm(length(time), 0, 0.9)
ordinal <- as.integer(cut(ordinalLatent,
  breaks = c(-Inf, -1.2, -0.3, 0.4, 1.2, Inf), labels = FALSE))
continuous[c(3L, 21L, 39L, 99L, 153L, 207L, 303L, 381L, 459L, 543L)] <- NA_real_
ordinal[c(8L, 26L, 62L, 116L, 170L, 224L, 314L, 386L, 476L, 566L)] <- NA_integer_
example <- data.frame(subject = sprintf("S%03d", subjectIndex), time = time,
  continuousOutcome = continuous, ordinalOutcome = ordinal)
write.csv(example, "examples/trajectories-long.csv", row.names = FALSE, na = "")
cat("Wrote 600 observations from 100 simulated subjects to examples/trajectories-long.csv\n")
