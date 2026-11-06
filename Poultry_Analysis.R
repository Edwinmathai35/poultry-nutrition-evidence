# POULTRY NUTRIENT PRODUCTIVITY: FORECASTING, CAUSAL EFFECTS AND AUDIT EVIDENCE Purpose:
# estimate US broiler-feed purchasing-power forecasts and separately estimate whole-diet
# treatment effects in a randomized Canadian broiler trial.  Run from this folder: Rscript
# Poultry_Analysis.R Inputs are bundled immutable source snapshots; no silent refresh or
# imputation.  Each numbered section states its objective, functions, outputs and stop flags.

# 00. SETUP: require explicit dependencies, deterministic settings and directories.
# Functions: requireNamespace(), set.seed(), digest(). Output: run_id, config.
packages <- c("readxl", "forecast", "urca", "sandwich", "digest", "nlme", "jsonlite")
missing <- packages[!vapply(packages, requireNamespace, logical(1), quietly = TRUE)]
if (length(missing)) stop("Install required R packages: ", paste(missing, collapse = ", "))
options(stringsAsFactors = FALSE, warn = 1, scipen = 8)
suppressPackageStartupMessages(library(nlme))
set.seed(20261105)
if (!file.exists("data/raw/usda.xlsx")) stop("Set working directory to the extracted project folder.")
for (d in c("data/processed", "outputs/tables", "outputs/figures", "outputs/models", "outputs/logs",
    "governance")) dir.create(d, recursive = TRUE, showWarnings = FALSE)
config <- list(start = "2010-01-01", end = "2026-08-01", initial_n = 96L, development_end = "2024-08-01",
    test_start = "2024-09-01", horizons = c(1L, 3L), seed = 20261105)
manifest <- read.csv("governance/source_manifest.csv")
run_id <- substr(digest::digest(list(config, manifest, readLines("Poultry_Analysis.R")), algo = "sha256"),
    1, 16)
writeLines(c(paste("Run:", run_id), capture.output(dput(config))), "outputs/logs/config.txt")
saveRDS(config, "outputs/models/config.rds")
write_table <- function(x, name) {
    x$run_id <- rep(run_id, nrow(x))
    write.csv(x, file.path("outputs/tables", paste0(name, ".csv")), row.names = FALSE, na = "NA")
}
assert <- function(ok, msg) if (!isTRUE(ok)) stop(msg, call. = FALSE)

# 01. IMPORT: read the USDA workbook and deposited pen-level performance table.  Functions:
# read_excel(), read.delim(). Preserve raw bytes and source hashes.  Flag: any SHA256 mismatch
# stops execution; refreshed data require a new manifest.
validate_hashes <- function(m) {
    for (i in seq_len(nrow(m))) assert(identical(digest::digest(file = file.path("data/raw", m$file[i]),
        algo = "sha256"), m$sha256[i]), paste("Source hash mismatch:", m$file[i]))
    TRUE
}
validate_hashes(manifest)
repository_metadata <- jsonlite::fromJSON("data/raw/inrae.json")$data$latestVersion$files$dataFile
original_files <- ifelse(is.na(repository_metadata$originalFileName), repository_metadata$filename,
    repository_metadata$originalFileName)
original_hashes <- unname(tools::md5sum(file.path("data/raw", original_files)))
assert(all(original_hashes == repository_metadata$checksum$value), "Repository original-file MD5 mismatch")
write_table(data.frame(file = original_files, expected_MD5 = repository_metadata$checksum$value,
    actual_MD5 = original_hashes, matches = original_hashes == repository_metadata$checksum$value),
    "repository_integrity")
raw_sheet <- as.data.frame(readxl::read_excel("data/raw/usda.xlsx", sheet = "FGYearbookTable15",
    col_names = FALSE, col_types = "text", .name_repair = "minimal"))
trial <- read.delim("data/raw/2-ANIMAL_PERFORMANCE.tab", check.names = FALSE)
# The repository MD5 refers to the original XLSX, not its generated TAB rendition.
assert(unname(tools::md5sum("data/raw/2-ANIMAL_PERFORMANCE.xlsx")) == "a8d7c9656b9420b271ebf0858acb5730",
    "Repository original MD5 mismatch")
original_trial <- as.data.frame(readxl::read_excel("data/raw/2-ANIMAL_PERFORMANCE.xlsx"))
names(original_trial) <- gsub("_", "", names(original_trial))
assert(identical(names(original_trial), names(trial)), "Original/TAB column mismatch")
assert(identical(as.character(original_trial$TREATMENT), as.character(trial$TREATMENT)), "Original/TAB treatment mismatch")
num_cols <- setdiff(names(trial), "TREATMENT")
source_max_difference <- max(abs(as.matrix(original_trial[num_cols]) - as.matrix(trial[num_cols])))
assert(source_max_difference < 1e-10, "Original/TAB numeric discrepancy")
write_table(data.frame(check = "Original XLSX vs downloaded TAB", max_abs_difference = source_max_difference,
    original_MD5_matches = TRUE), "source_rendition_reconciliation")


# 02. CLEAN / RESHAPE: map marketing-year months onto calendar dates.  No annual column,
# interpolation, outlier deletion or automatic NA removal.  Functions: as.Date(), order(),
# validate_months(), validate_trial().
start_row <- which(grepl("^Broiler-feed", raw_sheet[[1]]))[1]
end_row <- which(seq_len(nrow(raw_sheet)) > start_row & !is.na(raw_sheet[[1]]) & nzchar(raw_sheet[[1]]))[1] -
    1L
month_order <- c(9:12, 1:8)
monthly <- do.call(rbind, lapply((start_row:end_row)[!is.na(raw_sheet[start_row:end_row, 2])], function(i) {
    yr <- as.integer(substr(raw_sheet[i, 2], 1, 4))
    data.frame(date = as.Date(sprintf("%04d-%02d-01", yr + (month_order < 9), month_order)), ratio = as.numeric(unlist(raw_sheet[i,
        3:14])))
}))
monthly <- monthly[monthly$date >= as.Date(config$start) & monthly$date <= as.Date(config$end),
    ]
monthly <- monthly[order(monthly$date), ]
rownames(monthly) <- NULL
validate_months <- function(x) {
    assert(nrow(x) == 200L, "Expected 200 monthly observations")
    assert(!anyNA(x), "Missing monthly values")
    assert(!anyDuplicated(x$date), "Duplicate month")
    assert(identical(x$date, seq(as.Date(config$start), as.Date(config$end), by = "month")), "Monthly calendar gap or ordering error")
    assert(all(is.finite(x$ratio) & x$ratio > 0), "Invalid ratio")
    TRUE
}
trt_levels <- c("CT", "MedCP-HighSBM", "MedCP-MedSBM", "MedCP-NoSBM", "LowCP-HighSBM", "LowCP-MedSBM",
    "LowCP-NoSBM")
validate_trial <- function(x) {
    assert(nrow(x) == 63L, "Expected 63 pens")
    assert(!anyDuplicated(x$PEN), "Duplicate pen")
    assert(!anyNA(x), "Missing trial value")
    assert(all(as.character(x$TREATMENT) %in% trt_levels), "Unknown treatment")
    assert(all(table(factor(x$TREATMENT, levels = trt_levels)) == 9L), "Expected nine pens per treatment")
    nums <- x[vapply(x, is.numeric, logical(1))]
    assert(all(is.finite(as.matrix(nums))), "Nonfinite trial value")
    assert(all(x$BWD10 > 0 & x$BWD35 > x$BWD10), "Implausible body weights")
    for (p in c("D1D10", "D11D22", "D23D35", "D11D35", "D1D35")) assert(max(abs(x[[paste0("FCR",
        p)]] - x[[paste0("ADFI", p)]]/x[[paste0("ADG", p)]])) < 1e-10, paste("FCR identity failed:",
        p))
    TRUE
}
validate_months(monthly)
validate_trial(trial)
trial$TREATMENT <- factor(trial$TREATMENT, levels = trt_levels)
trial$baseline_weight <- trial$BWD10 - mean(trial$BWD10)
write.csv(monthly, "data/processed/monthly_ratio.csv", row.names = FALSE)
write.csv(trial, "data/processed/trial_pens.csv", row.names = FALSE)
audit <- data.frame(dataset = c("USDA monthly ratio", "Trial performance"), rows = c(nrow(monthly),
    nrow(trial)), columns = c(ncol(monthly), 22), missing_values = c(sum(is.na(monthly)), sum(is.na(trial))),
    duplicate_keys = c(anyDuplicated(monthly$date), anyDuplicated(trial$PEN)))
write_table(audit, "data_validation")
# Audit other deposited files without including incomplete ancillary endpoints.
ancillary <- do.call(rbind, lapply(list.files("data/raw", pattern = "\\.tab$", full.names = TRUE),
    function(f) {
        d <- read.delim(f, check.names = FALSE)
        data.frame(file = basename(f), rows = nrow(d), columns = ncol(d), missing_values = sum(is.na(d)),
            included = grepl("ANIMAL_PERFORMANCE", f))
    }))
write_table(ancillary, "ancillary_completeness")

# 03. TIME-SERIES EXPLORATION: stationarity and dependence using development data.  Functions:
# ur.df(), ur.kpss(), acf(), pacf(), stl(). Tests do not prove stationarity.  Holdout outcomes
# are excluded from diagnostic-driven model selection.
y <- ts(monthly$ratio, start = c(2010, 1), frequency = 12)
dev_n <- sum(monthly$date <= as.Date(config$development_end))
dev <- window(y, end = time(y)[dev_n])
stationarity <- list()
for (transform in c("level", "first_difference")) {
    z <- if (transform == "level")
        as.numeric(dev) else diff(as.numeric(dev))
    adf <- urca::ur.df(z, type = "drift", lags = 12, selectlags = "AIC")
    kpss <- urca::ur.kpss(z, type = "mu", lags = "short")
    stationarity[[transform]] <- data.frame(series = transform, test = c("ADF: unit-root null",
        "KPSS: level-stationary null"), statistic = c(adf@teststat[1, "tau2"], kpss@teststat), critical_5pct = c(adf@cval["tau2",
        "5pct"], kpss@cval[1, "5pct"]), reject_5pct = c(adf@teststat[1, "tau2"] < adf@cval["tau2",
        "5pct"], kpss@teststat > kpss@cval[1, "5pct"]), lag = c(sum(grepl("z.diff.lag", rownames(adf@testreg$coefficients))),
        kpss@lag))
}
write_table(do.call(rbind, stationarity), "stationarity_tests")
write_table(data.frame(date = monthly$date, ratio = monthly$ratio, rolling_mean_12 = as.numeric(stats::filter(y,
    rep(1/12, 12), sides = 1))), "series_summary")

# 04. MODEL CANDIDATES: bounded ARMA / ARIMA / SARIMA and ETS state-space models.  Functions:
# Arima(), ets(), naive(), snaive(). Fixed list avoids unbounded search.  ETS = Error, Trend,
# Seasonal; ANN = additive error, no trend, no seasonality.  Forecast at each origin uses only
# observations through that origin.
specs <- list(ARMA100 = c(1, 0, 0, 0, 0, 0), ARMA001 = c(0, 0, 1, 0, 0, 0), ARMA101 = c(1, 0, 1,
    0, 0, 0), ARIMA110 = c(1, 1, 0, 0, 0, 0), ARIMA011 = c(0, 1, 1, 0, 0, 0), ARIMA111 = c(1, 1,
    1, 0, 0, 0), SARIMA011011 = c(0, 1, 1, 0, 1, 1), SARIMA110011 = c(1, 1, 0, 0, 1, 1), SARIMA111100 = c(1,
    1, 1, 1, 0, 0))
models <- c("Naive", "SeasonalNaive", names(specs), "ETS_ANN", "ETS_AAN", "ETS_AAdN", "ETS_AAA")
fit_one <- function(z, model) {
    if (model == "Naive")
        return(forecast::naive(z, h = 3, level = c(80, 95)))
    if (model == "SeasonalNaive")
        return(forecast::snaive(z, h = 3, level = c(80, 95)))
    if (model %in% names(specs)) {
        s <- specs[[model]]
        fit <- forecast::Arima(z, order = s[1:3], seasonal = list(order = s[4:6], period = 12),
            include.drift = FALSE, method = "ML")
        assert(is.null(fit$code) || fit$code == 0, "ARIMA optimizer did not converge")
    } else {
        mod <- if (model == "ETS_AAdN")
            "AAN" else sub("ETS_", "", model)
        fit <- forecast::ets(z, model = mod, damped = (model == "ETS_AAdN"), restrict = TRUE)
    }
    forecast::forecast(fit, h = 3, level = c(80, 95))
}
validate_origin <- function(training_dates, origin, target) {
    assert(max(training_dates) <= origin && target > origin, "Future data leakage")
    TRUE
}
failures <- list()
forecasts <- list()
k <- 0L
for (origin in config$initial_n:(nrow(monthly) - 1L)) {
    z <- ts(monthly$ratio[seq_len(origin)], start = c(2010, 1), frequency = 12)
    for (m in models) {
        warnings_here <- character()
        fc <- tryCatch(withCallingHandlers(fit_one(z, m), warning = function(w) {
            warnings_here <<- c(warnings_here, conditionMessage(w))
            invokeRestart("muffleWarning")
        }), error = function(e) e)
        if (inherits(fc, "error")) {
            failures[[length(failures) + 1L]] <- data.frame(origin = as.character(monthly$date[origin]),
                model = m, status = "error", message = conditionMessage(fc))
            next
        }
        if (length(warnings_here))
            failures[[length(failures) + 1L]] <- data.frame(origin = as.character(monthly$date[origin]),
                model = m, status = "warning", message = paste(unique(warnings_here), collapse = "; "))
        for (h in config$horizons) if (origin + h <= nrow(monthly)) {
            target <- monthly$date[origin + h]
            validate_origin(monthly$date[seq_len(origin)], monthly$date[origin], target)
            k <- k + 1L
            forecasts[[k]] <- data.frame(origin = monthly$date[origin], target = target, h = h,
                model = m, actual = monthly$ratio[origin + h], pred = as.numeric(fc$mean[h]), lower80 = fc$lower[h,
                  1], upper80 = fc$upper[h, 1], lower95 = fc$lower[h, 2], upper95 = fc$upper[h,
                  2], split = if (target <= as.Date(config$development_end))
                  "development" else "holdout")
        }
    }
    if (origin%%12 == 0)
        cat("Forecast origin completed:", as.character(monthly$date[origin]), "\n")
}
fcasts <- do.call(rbind, forecasts)
assert(all(is.finite(as.matrix(fcasts[c("actual", "pred", "lower80", "upper80", "lower95", "upper95")]))),
    "Nonfinite forecasts")
write_table(fcasts, "rolling_forecasts")
failtab <- if (length(failures)) do.call(rbind, failures) else data.frame(origin = character(),
    model = character(), status = character(), message = character())
write_table(failtab, "model_warnings_errors")

# 05. EVALUATE: development-selected model per horizon, then locked holdout scoring.
# Functions: aggregate(), split(). MAE is primary, with RMSE, bias and interval scores.  Error
# = forecast - actual. Common expected target counts are enforced.
metrics <- function(d) {
    e <- d$pred - d$actual
    alpha <- 0.05
    data.frame(n = nrow(d), MAE = mean(abs(e)), RMSE = sqrt(mean(e^2)), bias = mean(e), coverage80 = mean(d$actual >=
        d$lower80 & d$actual <= d$upper80), coverage95 = mean(d$actual >= d$lower95 & d$actual <=
        d$upper95), width95 = mean(d$upper95 - d$lower95), interval_score95 = mean(d$upper95 - d$lower95 +
        2/alpha * pmax(d$lower95 - d$actual, 0) + 2/alpha * pmax(d$actual - d$upper95, 0)))
}
metrics_all <- do.call(rbind, lapply(split(fcasts, interaction(fcasts$split, fcasts$h, fcasts$model,
    drop = TRUE)), function(d) cbind(d[1, c("split", "h", "model")], metrics(d))))
rownames(metrics_all) <- NULL
# A model is eligible only if every development target for that horizon succeeded.
expected <- function(h, split) sum(sapply(config$initial_n:(nrow(monthly) - h), function(o) {
    target <- monthly$date[o + h]
    if (split == "development") target <= as.Date(config$development_end) else target > as.Date(config$development_end)
}))
metrics_all$expected_n <- mapply(expected, metrics_all$h, metrics_all$split)
metrics_all$complete <- metrics_all$n == metrics_all$expected_n
selected <- do.call(rbind, lapply(config$horizons, function(hh) {
    d <- metrics_all[metrics_all$split == "development" & metrics_all$h == hh & metrics_all$complete,
        ]
    d <- d[order(d$MAE, d$RMSE, d$model), ]
    assert(nrow(d) > 0, "No complete development model")
    d[1, c("h", "model", "MAE")]
}))
write_table(selected, "selected_models")
metrics_all$selected <- mapply(function(hh, m) m == selected$model[selected$h == hh], metrics_all$h,
    metrics_all$model)
write_table(metrics_all, "forecast_accuracy")
# Equal-weight combination of two best development models: sensitivity only.
comb <- do.call(rbind, lapply(config$horizons, function(hh) {
    a <- metrics_all[metrics_all$split == "development" & metrics_all$h == hh & metrics_all$complete,
        ]
    a <- a[order(a$MAE, a$RMSE, a$model), ]
    z <- fcasts[fcasts$h == hh & fcasts$model %in% a$model[1:2], ]
    zz <- aggregate(cbind(pred, actual) ~ origin + target + h + split, z, mean)
    data.frame(zz, model = paste(a$model[1:2], collapse = " + "))
}))
write_table(comb, "combination_sensitivity_predictions")
combmetrics <- do.call(rbind, lapply(split(comb, interaction(comb$h, comb$split)), function(d) data.frame(h = d$h[1],
    split = d$split[1], model = d$model[1], n = nrow(d), MAE = mean(abs(d$pred - d$actual)), RMSE = sqrt(mean((d$pred -
        d$actual)^2)))))
write_table(combmetrics, "combination_sensitivity_accuracy")
# Residual tests at the development boundary; AICc/BIC are supplementary.
model_fits <- list()
diag <- list()
for (m in models) {
    f <- tryCatch(fit_one(dev, m), error = function(e) NULL)
    if (is.null(f))
        next
    fit <- f$model
    model_fits[[m]] <- fit
    r <- na.omit(as.numeric(residuals(f)))
    df <- if (m %in% names(specs))
        sum(specs[[m]][c(1, 3, 4, 6)]) else if (inherits(fit, "ets"))
        length(fit$par) else 0
    lb <- Box.test(r, lag = 24, type = "Ljung-Box", fitdf = df)
    diag[[m]] <- data.frame(model = m, residual_n = length(r), lag = 24, fitdf = df, Ljung_Box = unname(lb$statistic),
        p = lb$p.value, AICc = if (is.null(fit$aicc))
            NA_real_ else fit$aicc, BIC = if (is.null(fit$bic))
            NA_real_ else fit$bic)
}
write_table(do.call(rbind, diag), "forecast_diagnostics")
saveRDS(model_fits, "outputs/models/development_models.rds")
# Future forecasts are conditional on the last observed month, not 'current' prices.
future <- do.call(rbind, lapply(unique(selected$model), function(m) {
    f <- fit_one(y, m)
    data.frame(model = m, date = seq(tail(monthly$date, 1), by = "month", length.out = 4)[-1], h = 1:3,
        pred = as.numeric(f$mean), lower95 = as.numeric(f$lower[, 2]), upper95 = as.numeric(f$upper[,
            2]))
}))
write_table(future, "future_forecasts_from_august_2026")

# 06. CAUSAL DESIGN: randomized pen assignment; CT is the reference treatment.  Estimand: mean
# whole-diet treatment difference in this trial, not isolated CP.  Assumptions: random
# assignment, consistency, no relevant between-pen interference.  Public block IDs are absent:
# this is not exact replication of the blocked model.  Adjust only pretreatment weight; intake
# is a mediator and is not adjusted away.
write_table(data.frame(treatment = levels(trial$TREATMENT), pens = as.integer(table(trial$TREATMENT)),
    baseline_weight_g = as.numeric(tapply(trial$BWD10, trial$TREATMENT, mean)), FCR_mean = as.numeric(tapply(trial$FCRD11D35,
        trial$TREATMENT, mean)), FCR_SD = as.numeric(tapply(trial$FCRD11D35, trial$TREATMENT, sd)),
    ADG_mean = as.numeric(tapply(trial$ADGD11D35, trial$TREATMENT, mean)), ADG_SD = as.numeric(tapply(trial$ADGD11D35,
        trial$TREATMENT, sd)), mortality_pct_mean = as.numeric(tapply(trial$MORTAD1D35, trial$TREATMENT,
        mean))), "treatment_summary")
contrast_rows <- function(fit, endpoint, spec, robust = TRUE) {
    v <- if (robust)
        sandwich::vcovHC(fit, type = "HC3") else vcov(fit)
    b <- coef(fit)
    ix <- grep("^TREATMENT", names(b))
    se <- sqrt(diag(v))[ix]
    df <- df.residual(fit)
    p <- 2 * pt(-abs(b[ix]/se), df)
    data.frame(endpoint = endpoint, specification = spec, treatment = sub("TREATMENT", "", names(b)[ix]),
        estimate = unname(b[ix]), SE = unname(se), df = df, lower95 = unname(b[ix] - qt(0.975, df) *
            se), upper95 = unname(b[ix] + qt(0.975, df) * se), p = unname(p), p_Holm = p.adjust(p,
            "holm"), SE_type = if (robust)
            "HC3" else "conventional")
}
causal_fits <- list()
effects <- list()
for (endpoint in c("FCRD11D35", "ADGD11D35")) {
    for (adjust in c(FALSE, TRUE)) {
        spec <- if (adjust)
            "baseline_adjusted" else "unadjusted"
        form <- as.formula(paste(endpoint, "~ TREATMENT", if (adjust)
            "+ baseline_weight" else ""))
        fit <- lm(form, trial)
        causal_fits[[paste(endpoint, spec, sep = "_")]] <- fit
        for (robust in c(TRUE, FALSE)) effects[[length(effects) + 1L]] <- contrast_rows(fit, endpoint,
            spec, robust)
    }
}
effects <- do.call(rbind, effects)
write_table(effects, "causal_treatment_effects")
saveRDS(causal_fits, "outputs/models/causal_models.rds")
# Primary: baseline-adjusted FCR HC3, six comparisons with CT, Holm adjustment.  ADG is
# secondary with its own six-comparison family. CIs remain pointwise 95%.

# 07. FACTORIAL AND LONGITUDINAL: connect each measurement to its pen and phase.  Functions:
# subset(), strsplit(), lme(). No artificial daily values are generated.
fac <- trial[trial$TREATMENT != "CT", ]
parts <- strsplit(as.character(fac$TREATMENT), "-")
fac$CP <- factor(vapply(parts, "[", "", 1), levels = c("MedCP", "LowCP"))
fac$SBM <- factor(vapply(parts, "[", "", 2), levels = c("HighSBM", "MedSBM", "NoSBM"))
ff <- lm(FCRD11D35 ~ CP * SBM + baseline_weight, fac)
vv <- sandwich::vcovHC(ff, type = "HC3")
ii <- grep(":", names(coef(ff)))
wald <- as.numeric(t(coef(ff)[ii]) %*% solve(vv[ii, ii]) %*% coef(ff)[ii]/length(ii))
write_table(data.frame(test = "CP by SBM interaction (HC3 Wald F)", F = wald, df1 = length(ii),
    df2 = df.residual(ff), p = pf(wald, length(ii), df.residual(ff), lower.tail = FALSE)), "factorial_interaction")
write_table(data.frame(term = names(coef(ff)), estimate = coef(ff), SE_HC3 = sqrt(diag(vv))), "factorial_coefficients")
long <- rbind(data.frame(PEN = trial$PEN, TREATMENT = trial$TREATMENT, baseline_weight = trial$baseline_weight,
    phase = "Grower 11-22", FCR = trial$FCRD11D22, ADG = trial$ADGD11D22), data.frame(PEN = trial$PEN,
    TREATMENT = trial$TREATMENT, baseline_weight = trial$baseline_weight, phase = "Finisher 23-35",
    FCR = trial$FCRD23D35, ADG = trial$ADGD23D35))
long$phase <- factor(long$phase, levels = c("Grower 11-22", "Finisher 23-35"))
assert(!anyDuplicated(long[c("PEN", "phase")]), "Duplicate pen-phase")
assert(all(table(long$PEN) == 2), "Incomplete pen-phase linkage")
write.csv(long, "data/processed/pen_phase_long.csv", row.names = FALSE)
phase_fits <- list()
phase_tests <- list()
phase_coefs <- list()
for (endpoint in c("FCR", "ADG")) {
    fm <- as.formula(paste(endpoint, "~ TREATMENT * phase + baseline_weight"))
    full <- nlme::lme(fm, random = ~1 | PEN, weights = nlme::varIdent(form = ~1 | phase), data = long,
        method = "ML", control = nlme::lmeControl(opt = "optim"))
    reduced <- update(full, fixed = as.formula(paste(endpoint, "~ TREATMENT + phase + baseline_weight")))
    cmp <- anova(reduced, full)
    final <- update(full, method = "REML")
    phase_fits[[endpoint]] <- final
    phase_tests[[endpoint]] <- data.frame(endpoint = endpoint, LRT = cmp$L.Ratio[2], df = cmp$df[2] -
        cmp$df[1], p = cmp$"p-value"[2])
    tab <- as.data.frame(summary(final)$tTable)
    tab$term <- rownames(tab)
    tab$endpoint <- endpoint
    phase_coefs[[endpoint]] <- tab
}
write_table(do.call(rbind, phase_tests), "phase_interaction_tests")
write_table(do.call(rbind, phase_coefs), "phase_coefficients")
saveRDS(phase_fits, "outputs/models/phase_models.rds")

# 08. SENSITIVITY: all pens retained; assess influence without deleting inconvenient data.
# Functions: cooks.distance(), hatvalues(), leave-one-pen-out refitting.
lopo <- list()
influence <- list()
for (endpoint in c("FCRD11D35", "ADGD11D35")) {
    fit <- causal_fits[[paste(endpoint, "baseline_adjusted", sep = "_")]]
    influence[[endpoint]] <- data.frame(endpoint = endpoint, PEN = trial$PEN, cooks_distance = cooks.distance(fit),
        leverage = hatvalues(fit), standardized_residual = rstandard(fit))
    for (pen in trial$PEN) {
        f <- lm(as.formula(paste(endpoint, "~ TREATMENT + baseline_weight")), trial[trial$PEN !=
            pen, ])
        a <- contrast_rows(f, endpoint, "leave_one_pen_out", TRUE)
        a$omitted_pen <- pen
        lopo[[length(lopo) + 1]] <- a
    }
}
lopo <- do.call(rbind, lopo)
write_table(lopo, "leave_one_pen_out")
write_table(do.call(rbind, influence), "pen_influence")
lopo_summary <- do.call(rbind, lapply(split(lopo, interaction(lopo$endpoint, lopo$treatment)), function(d) data.frame(endpoint = d$endpoint[1],
    treatment = d$treatment[1], estimate_min = min(d$estimate), estimate_max = max(d$estimate),
    Holm_p_min = min(d$p_Holm), Holm_p_max = max(d$p_Holm))))
write_table(lopo_summary, "leave_one_pen_out_summary")

# 09. FIGURES: each chart reads the same in-memory results exported to CSV.  Functions: png(),
# pdf(), plot(), segments(). Light palette, no green.  Every image has an adjacent provenance
# record with its SHA256 and run_id.
navy <- "#18334F"
blue <- "#5688BD"
lav <- "#A29ACD"
coral <- "#C86E60"
ivory <- "#FCFBF7"
gray <- "#687787"
figure <- function(name, draw) {
    for (ext in c("png", "pdf")) {
        final_path <- file.path("outputs/figures", paste0(name, ".", ext))
        path <- tempfile(pattern = name, tmpdir = "outputs/figures", fileext = paste0(".", ext))
        if (ext == "png")
            png(path, width = 1800, height = 1200, res = 160, type = "cairo", bg = ivory) else pdf(path, width = 11.25, height = 7.5, bg = ivory)
        par(mar = c(5, 5, 4, 2), col = navy, col.axis = navy, col.lab = navy, col.main = navy, cex = 1.1,
            las = 1, bty = "l")
        device_id <- dev.cur()
        draw()
        dev.off(which = device_id)
        assert(file.rename(path, final_path), "Could not finalize chart file")
    }
}
figure("01_feed_purchasing_power", function() {
    plot(monthly$date, monthly$ratio, type = "l", lwd = 2.7, col = blue, xlab = "Month", ylab = "lb feed equal in value to 1 lb live broiler",
        main = "US broiler-feed purchasing power, 2010-2026")
    abline(v = as.Date(config$test_start), lty = 2, col = coral)
    legend("topleft", c("USDA monthly ratio", "Holdout begins September 2024"), col = c(blue, coral),
        lty = c(1, 2), bty = "n")
    mtext("Economic price ratio. It does not measure feed conversion or farm profit.", side = 1,
        line = 3.7, cex = 0.85)
})
figure("02_seasonal_decomposition", function() {
    dec <- stl(dev, s.window = "periodic")$time.series
    par(mfrow = c(4, 1), mar = c(3, 6, 2, 2), las = 0)
    plot(dev, ylab = "Observed", xlab = "", main = "Development data: descriptive seasonal decomposition",
        col = blue, lwd = 1.5)
    for (j in 1:3) plot(dec[, j], ylab = c("Seasonal", "Trend", "Remainder")[j], xlab = if (j ==
        3)
        "Year" else "", col = c(lav, blue, gray)[j], lwd = 1.5)
})
figure("03_acf_pacf", function() {
    par(mfrow = c(2, 2), mar = c(4, 4, 3, 1))
    acf(dev, main = "Level: ACF", col = blue)
    pacf(dev, main = "Level: PACF", col = blue)
    acf(diff(dev), main = "First difference: ACF", col = lav)
    pacf(diff(dev), main = "First difference: PACF", col = lav)
})
figure("04_holdout_forecast_accuracy", function() {
    keep <- metrics_all[metrics_all$split == "holdout" & metrics_all$model %in% unique(c("Naive",
        "SeasonalNaive", selected$model)), ]
    mm <- unique(keep$model)
    # Explicit lookup avoids depending on row ordering.
    mat <- sapply(config$horizons, function(hh) vapply(mm, function(m) keep$MAE[keep$h == hh & keep$model ==
        m], numeric(1)))
    rownames(mat) <- mm
    barplot(t(mat), beside = TRUE, names.arg = mm, col = c(blue, lav), ylab = "Mean absolute error (ratio units)",
        main = "Holdout forecast errors: September 2024-August 2026", ylim = c(0, max(mat) * 1.25),
        cex.names = 0.85)
    legend("topleft", c("1 month ahead", "3 months ahead"), fill = c(blue, lav), bty = "n")
})
figure("05_holdout_predictions", function() {
    m <- selected$model[selected$h == 1]
    d <- fcasts[fcasts$split == "holdout" & fcasts$h == 1 & fcasts$model == m, ]
    d <- d[order(d$target), ]
    plot(d$target, d$actual, type = "n", ylim = range(d$lower95, d$upper95, d$actual), xlab = "Target month",
        ylab = "Broiler-feed price ratio", main = paste("One-month forecasts:", m))
    polygon(c(d$target, rev(d$target)), c(d$lower95, rev(d$upper95)), col = "#E0DEF1", border = NA)
    lines(d$target, d$actual, lwd = 2.5, col = navy)
    lines(d$target, d$pred, lwd = 2.5, col = blue, lty = 2)
    legend("topleft", c("Observed", "Forecast", "95% prediction interval"), col = c(navy, blue,
        lav), lty = c(1, 2, 1), lwd = c(2, 2, 7), bty = "n")
})
figure("06_selected_residual_diagnostics", function() {
    m <- selected$model[selected$h == 1]
    f <- fit_one(dev, m)
    r <- na.omit(as.numeric(residuals(f)))
    par(mfrow = c(1, 2), mar = c(5, 4, 4, 1))
    acf(r, main = paste(m, "residual ACF"), col = blue)
    qqnorm(r, col = blue, pch = 16, main = "Residual normal Q-Q")
    qqline(r, col = coral, lwd = 2)
})
for (endpoint in c("FCRD11D35", "ADGD11D35")) local({
    e <- endpoint
    figure(if (e == "FCRD11D35")
        "07_causal_FCR" else "08_causal_ADG", function() {
        d <- effects[effects$endpoint == e & effects$specification == "baseline_adjusted" & effects$SE_type ==
            "HC3", ]
        d <- d[match(trt_levels[-1], d$treatment), ]
        par(mar = c(5, 10, 4, 2))
        yy <- rev(seq_len(nrow(d)))
        plot(d$estimate, yy, xlim = range(d$lower95, d$upper95, 0), ylim = c(0.5, 6.5), yaxt = "n",
            ylab = "", xlab = if (e == "FCRD11D35")
                "Treatment minus control (g feed / g gain)" else "Treatment minus control (g / bird / day)", pch = 19, col = blue, cex = 1.3, main = if (e ==
                "FCRD11D35")
                "Diet effects on feed conversion, days 11-35" else "Diet effects on daily gain, days 11-35")
        axis(2, at = yy, labels = d$treatment, las = 1, cex.axis = 0.9)
        segments(d$lower95, yy, d$upper95, yy, col = blue, lwd = 3)
        abline(v = 0, lty = 2, col = gray)
        mtext("63 pens. Baseline-adjusted HC3 estimates; pointwise 95% confidence intervals.", side = 1,
            line = 3.7, cex = 0.82)
    })
})
figure("09_phase_performance", function() {
    mat <- sapply(levels(long$phase), function(p) vapply(trt_levels, function(t) mean(long$FCR[long$phase ==
        p & long$TREATMENT == t]), numeric(1)))
    plot(1:2, range(mat), type = "n", xaxt = "n", xlab = "Feeding phase", ylab = "Mean feed conversion ratio",
        main = "Pen-linked performance across feeding phases", xlim = c(0.9, 3.15))
    axis(1, at = 1:2, labels = levels(long$phase))
    cols <- c(navy, blue, lav, coral, "#8497AC", "#C3A271", "#8E789C")
    for (i in 1:7) {
        lines(1:2, mat[i, ], col = cols[i], lwd = 2, pch = 16, type = "b")
    }
    legend(2.2, max(mat), legend = trt_levels, col = cols, lwd = 2, pch = 16, bty = "n", cex = 0.75)
})
figure("10_sensitivity_FCR", function() {
    d <- effects[effects$endpoint == "FCRD11D35" & effects$SE_type == "HC3", ]
    par(mar = c(5, 10, 4, 2))
    plot(0, 0, type = "n", xlim = range(d$lower95, d$upper95), ylim = c(0.5, 6.5), yaxt = "n", xlab = "Treatment minus control (g feed / g gain)",
        ylab = "", main = "FCR estimates with and without baseline adjustment")
    axis(2, at = 6:1, labels = trt_levels[-1])
    for (j in 1:2) {
        s <- c("unadjusted", "baseline_adjusted")[j]
        a <- d[d$specification == s, ]
        a <- a[match(trt_levels[-1], a$treatment), ]
        yy <- 6:1 + c(-0.12, 0.12)[j]
        segments(a$lower95, yy, a$upper95, yy, col = c(lav, blue)[j], lwd = 2)
        points(a$estimate, yy, col = c(lav, blue)[j], pch = c(17, 19)[j])
    }
    abline(v = 0, lty = 2, col = gray)
    legend("bottomright", c("Unadjusted", "Baseline adjusted"), col = c(lav, blue), pch = c(17,
        19), bty = "n", cex = 0.85)
})
figure("11_trial_DAG", function() {
    par(mar = c(1, 1, 4, 1))
    plot(0, 0, type = "n", xlim = c(0, 10), ylim = c(0, 7), axes = FALSE, xlab = "", ylab = "",
        main = "Causal assumptions for the feeding trial")
    nodes <- data.frame(x = c(1.6, 1.6, 5, 8.5), y = c(5.5, 1.5, 5.5, 3.5), label = c("Randomized\ndiet assignment",
        "Pretreatment\nbody weight", "Feed intake\n(mediator)", "Growth / FCR\n(outcome)"))
    for (i in 1:4) {
        rect(nodes$x[i] - 1.2, nodes$y[i] - 0.65, nodes$x[i] + 1.2, nodes$y[i] + 0.65, col = "#E8EDF6",
            border = blue)
        text(nodes$x[i], nodes$y[i], nodes$label[i], cex = 1)
    }
    arrows(2.8, 5.5, 3.7, 5.5, length = 0.12, col = navy, lwd = 2)
    arrows(6.2, 5.2, 7.3, 4, length = 0.12, col = navy, lwd = 2)
    arrows(2.8, 5.1, 7.3, 3.7, length = 0.12, col = navy, lwd = 2)
    arrows(2.8, 1.7, 7.3, 3.2, length = 0.12, col = navy, lwd = 2)
    arrows(2.6, 2.1, 4.1, 4.8, length = 0.12, col = navy, lwd = 2)
    text(5, 0.3, "Adjust for pretreatment weight. Do not condition on post-treatment feed intake.",
        cex = 0.9)
})

# 10. GOVERNANCE CONTROL TESTS: prove that known bad inputs are rejected.  Functions:
# tryCatch(), digest(); each test calls the production validator.  Passing these tests is
# internal validation, not independent audit certification.
controls <- list()
control <- function(id, description, expr, expect_error = TRUE) {
    err <- tryCatch({
        force(expr)
        NULL
    }, error = function(e) conditionMessage(e))
    passed <- if (expect_error)
        !is.null(err) else is.null(err)
    controls[[length(controls) + 1L]] <<- data.frame(control_id = id, test = description, expected = if (expect_error)
        "reject" else "accept", observed = if (is.null(err))
        "accept" else "reject", passed = passed, evidence = if (is.null(err))
        "Validation succeeded" else err)
}
control("DQ01", "Valid monthly snapshot", validate_months(monthly), FALSE)
z <- monthly
z$date[2] <- z$date[1]
control("DQ02", "Injected duplicate month", validate_months(z))
z <- monthly
z$ratio[20] <- NA
control("DQ03", "Injected missing ratio", validate_months(z))
control("DQ04", "Deleted calendar month", validate_months(monthly[-20, ]))
z <- trial
z$PEN[2] <- z$PEN[1]
control("DQ05", "Injected duplicate pen", validate_trial(z))
z <- trial
z$TREATMENT <- as.character(z$TREATMENT)
z$TREATMENT[1] <- "UNKNOWN"
control("DQ06", "Injected unknown treatment", validate_trial(z))
z <- trial
z$FCRD11D35[1] <- 99
control("DQ07", "Injected broken FCR identity", validate_trial(z))
control("ML01", "Injected future training row", validate_origin(as.Date(c("2020-01-01", "2020-03-01")),
    as.Date("2020-02-01"), as.Date("2020-03-01")))
bad_manifest <- manifest
bad_manifest$sha256[1] <- paste(rep("0", 64), collapse = "")
control("INT01", "Injected changed source checksum", validate_hashes(bad_manifest))
validate_artifact <- function(path, expected_hash, artifact_run) {
    assert(identical(artifact_run, run_id), "Stale run identifier")
    assert(identical(digest::digest(file = path, algo = "sha256"), expected_hash), "Artifact bytes changed")
    TRUE
}
image_path <- "outputs/figures/07_causal_FCR.png"
image_hash <- digest::digest(file = image_path, algo = "sha256")
control("REP01", "Valid chart identity", validate_artifact(image_path, image_hash, run_id), FALSE)
control("REP02", "Injected stale chart run", validate_artifact(image_path, image_hash, "obsolete_run"))
control("REP03", "Injected altered chart hash", validate_artifact(image_path, paste(rep("0", 64),
    collapse = ""), run_id))
control("CA01", "Valid trial snapshot", validate_trial(trial), FALSE)
ct <- do.call(rbind, controls)
write_table(ct, "control_test_results")
assert(all(ct$passed), "Control test failure: stop publication")
figure("12_control_tests", function() {
    par(mar = c(5, 15, 4, 2))
    barplot(rep(1, nrow(ct)), horiz = TRUE, names.arg = ct$test, las = 1, col = blue, border = NA,
        xlim = c(0, 1.2), axes = FALSE, cex.names = 0.8, main = "Internal controls: injected faults were detected")
    text(rep(1.05, nrow(ct)), seq(0.7, by = 1.2, length.out = nrow(ct)), "PASS", col = navy, cex = 0.8)
    mtext("Checks cover these scenarios only; deployment security and legal compliance are not certified.",
        side = 1, line = 2, cex = 0.8)
})
# Record versions and object hashes after all statistical and control outputs exist.
graphics.off()
writeLines(capture.output(sessionInfo()), "outputs/logs/sessionInfo.txt")
write.csv(as.data.frame(installed.packages()[, c("Package", "Version")]), "outputs/logs/package_versions.csv",
    row.names = FALSE)
files <- list.files("outputs", recursive = TRUE, full.names = TRUE)
files <- files[!grepl("execution.log$", files)]  # Active console log is still being written.
output_manifest <- data.frame(file = files, sha256 = vapply(files, function(f) digest::digest(file = f,
    algo = "sha256"), character(1)), run_id = run_id)
write.csv(output_manifest, "governance/output_manifest.csv", row.names = FALSE)
cat("\nANALYSIS COMPLETE. Run:", run_id, "\n")
print(selected)
print(metrics_all[metrics_all$split == "holdout" & metrics_all$selected, ])
print(effects[effects$endpoint == "FCRD11D35" & effects$specification == "baseline_adjusted" & effects$SE_type ==
    "HC3", ])
cat("Control tests passed:", sum(ct$passed), "of", nrow(ct), "\n")
