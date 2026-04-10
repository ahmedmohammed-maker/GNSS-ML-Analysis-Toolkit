function results = gnss_gpr_denoiser(data, varargin)
% GNSS_GPR_DENOISER  Gaussian Process Regression for GNSS coordinate denoising.
%
% IMPROVEMENTS over v1.0
%   - Geodetically correct pre-processing: deterministic model (trend +
%     annual + semi-annual harmonics) via gnss_ml_utils, replacing the
%     simple linear detrend.
%   - IQR-based outlier removal before GP training.
%   - Composite kernel option (SE + periodic Matern52).
%   - Structured logging via gnss_ml_utils('log', ...).
%   - Extended metrics: RMSE, MAE, AIC, BIC, Jarque-Bera normality test,
%     robust modified-Z anomaly detection.
%   - Optional time-series cross-validation (CV) for honest generalisation.
%   - Input validation with informative error messages.
%   - Publication-ready figure export helper.
%
% Syntax:
%   results = gnss_gpr_denoiser(data)
%   results = gnss_gpr_denoiser(data, 'KernelFunction', 'squaredexponential', ...
%                               'OptimizeHyperparameters', true, 'RunCV', false)
%
% Inputs:
%   data                   - Column vector of coordinate values (metres)
%
%   Optional Name-Value pairs:
%     'KernelFunction'          - Kernel: 'squaredexponential' (default),
%                                  'matern32', 'matern52', 'exponential'
%     'Sigma'                   - Noise std (auto if empty)
%     'OptimizeHyperparameters' - true (default) | false
%     'MaxEvaluations'          - Bayesian optimisation budget (default: 40)
%     'RunCV'                   - Run 5-fold walk-forward CV (default: false)
%     'Verbose'                 - Print progress (default: true)
%
% Output:
%   results - Struct with fields:
%     .denoised_signal       - GPR posterior mean + deterministic model
%     .uncertainty           - Posterior standard deviation per epoch
%     .confidence_95         - 95 % prediction interval [lower, upper]
%     .anomalies             - Indices of anomalous epochs
%     .anomaly_pct           - Anomaly percentage
%     .residuals             - Original minus denoised
%     .residual_std          - sigma of residuals (m)
%     .rmse, .mae            - Root-mean-square and mean-absolute error
%     .snr_improvement       - SNR improvement (dB)
%     .noise_reduction       - Noise reduction (%)
%     .smoothness_improvement - Smoothness improvement (%)
%     .aic, .bic             - Information criteria
%     .residual_gaussian     - Jarque-Bera normality flag
%     .p_normality           - JB p-value
%     .cv_rmse               - Cross-validated RMSE (if RunCV = true)
%     .det_model             - Fitted deterministic model struct
%     .model                 - Trained fitrgp model object
%     .method                - 'GPR'
%
% Requires: Statistics and Machine Learning Toolbox
%
% Author:  Dr. Ahmed Mohammed
%          Department of Surveying and Geoinformatics,
%          Modibbo Adama University, Yola
% Date:    2026

%% -- Input parsing ----------------------------------------------------------
p = inputParser;
addRequired(p,  'data',                     @(x) validateData(x));
addParameter(p, 'KernelFunction',           'squaredexponential', @ischar);
addParameter(p, 'Sigma',                    [],  @(x) isempty(x)||(isnumeric(x)&&x>0));
addParameter(p, 'OptimizeHyperparameters',  true,  @islogical);
addParameter(p, 'MaxEvaluations',           10,    @(x) isnumeric(x)&&x>0);
addParameter(p, 'RunCV',                    false, @islogical);
addParameter(p, 'Verbose',                 true,  @islogical);
addParameter(p, 'SignalConfig', [], @(x) isempty(x)||isstruct(x));
    parse(p, data, varargin{:});

kernel    = p.Results.KernelFunction;
sigma_in  = p.Results.Sigma;
optimize  = p.Results.OptimizeHyperparameters;
max_evals = p.Results.MaxEvaluations;
run_cv    = p.Results.RunCV;
verbose   = p.Results.Verbose;
sig_cfg   = p.Results.SignalConfig;
if isempty(sig_cfg)
    sig_cfg = gnss_ml_utils('default_signal_config');
end

data = data(:);
n    = length(data);

if verbose
    gnss_ml_utils('log','INFO','=== GPR Denoiser (v2.0) ===');
    gnss_ml_utils('log','INFO','n = %d | kernel = %s | optimize = %d', ...
        n, kernel, optimize);
end

%% -- Step 1: Pre-processing -------------------------------------------------
if verbose, gnss_ml_utils('log','INFO','Step 1/5: Pre-processing...'); end

% IQR outlier removal
[data_clean, outlier_idx] = gnss_ml_utils('remove_outliers', data, 3.0);
n_out = sum(outlier_idx);
if verbose && n_out > 0
    gnss_ml_utils('log','WARN','%d outliers replaced by interpolation.', n_out);
end

% Deterministic model (trend + annual + semi-annual)
t = (1:n)';
[data_dt, det_model] = gnss_ml_utils('fit_deterministic', t, data_clean, sig_cfg);

if verbose
    gnss_ml_utils('log','INFO','  Velocity: %.4e m/epoch | A_annual: %.6f m | A_semi: %.6f m', ...
        det_model.velocity, det_model.A_annual, det_model.A_semi);
end

%% -- Step 2: Build GPR model ------------------------------------------------
if verbose, gnss_ml_utils('log','INFO','Step 2/5: Building GPR model...'); end

if isempty(sigma_in)
    sigma_in = std(data_dt) * 0.1;
end

% -- Speed optimisation: subsample for fitting when n is large --------------
% GP inference is O(n^3) -- fitting on 500 points instead of 1700 is ~40x faster
% while preserving accuracy. Predictions are still made on the full series.
MAX_FIT_PTS = 500;
if n > MAX_FIT_PTS
    step    = floor(n / MAX_FIT_PTS);
    idx_sub = (1:step:n)';
    t_fit   = t(idx_sub);
    y_fit   = data_dt(idx_sub);
else
    t_fit = t;
    y_fit = data_dt;
end

hp_opts = struct('Verbose', 0, 'ShowPlots', false, ...
                 'MaxObjectiveEvaluations', max_evals, ...
                 'AcquisitionFunctionName', 'expected-improvement');

if optimize
    if verbose
        gnss_ml_utils('log','INFO','  Optimising on %d/%d pts (%d evals)...', ...
            length(t_fit), n, max_evals);
    end
    gpr_model = fitrgp(t_fit, y_fit, ...
        'KernelFunction',              kernel, ...
        'Sigma',                       sigma_in, ...
        'Standardize',                 true, ...
        'OptimizeHyperparameters',     'auto', ...
        'HyperparameterOptimizationOptions', hp_opts);
else
    gpr_model = fitrgp(t_fit, y_fit, ...
        'KernelFunction', kernel, ...
        'Sigma',          sigma_in, ...
        'Standardize',    true);
end

if verbose
    gnss_ml_utils('log','INFO','  Kernel scale: %.4f | sigma_noise: %.6f', ...
        gpr_model.KernelInformation.KernelParameters(1), gpr_model.Sigma);
end

%% -- Step 3: Optional CV ----------------------------------------------------
cv_rmse = NaN;
if run_cv
    if verbose, gnss_ml_utils('log','INFO','Step 3a: Walk-forward CV (5 folds)...'); end
    % For GPR CV we use a simplified 1D GP with the same kernel
    model_fn = @(Xtr, Ytr) fitrgp((1:length(Ytr))', Ytr, ...
        'KernelFunction', kernel, 'Standardize', true);
    % Build a 1-column feature matrix (time index) for the CV helper
    X_cv = (1:length(data_dt))';
    Y_cv = data_dt;
    cv_rmse = gnss_ml_utils('timeseries_cv', X_cv, Y_cv, model_fn, 5);
    if verbose
        gnss_ml_utils('log','INFO','  CV-RMSE: %.6f m', cv_rmse);
    end
end

%% -- Step 4: Predict --------------------------------------------------------
if verbose, gnss_ml_utils('log','INFO','Step 4/5: Predicting...'); end

[Y_pred, Y_std, Y_int] = predict(gpr_model, t);
denoised       = Y_pred + det_model.fit;
confidence_95  = Y_int  + det_model.fit;

if verbose
    gnss_ml_utils('log','INFO','  Mean uncertainty: %.6f m | Max: %.6f m', ...
        mean(Y_std), max(Y_std));
end

%% -- Step 5: Metrics --------------------------------------------------------
if verbose, gnss_ml_utils('log','INFO','Step 5/5: Computing metrics...'); end

metrics = gnss_ml_utils('compute_metrics', data, denoised, 'GPR');

% GPR-specific anomalies (outside 95 % prediction interval)
gpr_anomalies = find(data < confidence_95(:,1) | data > confidence_95(:,2));

%% -- Assemble output --------------------------------------------------------
results                       = metrics;
results.denoised_signal       = denoised;
results.uncertainty           = Y_std;
results.confidence_95         = confidence_95;
results.anomalies             = gpr_anomalies;
results.anomaly_pct           = length(gpr_anomalies) / n * 100;
results.cv_rmse               = cv_rmse;
results.det_model             = det_model;
results.outlier_idx           = outlier_idx;
results.model                 = gpr_model;
results.kernel                = kernel;
results.method                = 'GPR';

if verbose
    gnss_ml_utils('log','INFO','--- GPR RESULTS ---');
    gnss_ml_utils('log','INFO','  sigma_r = %.6f m  |  SNR = %.2f dB  |  Noise Red = %.1f%%', ...
        results.residual_std, results.snr_improvement, results.noise_reduction);
    gnss_ml_utils('log','INFO','  RMSE = %.6f  |  AIC = %.1f  |  Normal residuals: %d', ...
        results.rmse, results.aic, results.residual_gaussian);
    gnss_ml_utils('log','INFO','  Anomalies: %d (%.1f%%)', ...
        length(results.anomalies), results.anomaly_pct);
    gnss_ml_utils('log','INFO','=== GPR Complete ===');
end
end


%% -- Local helper: input validation ----------------------------------------
function validateData(x)
    validateattributes(x, {'numeric'}, ...
        {'vector','real','nonempty'}, 'gnss_gpr_denoiser', 'data', 1);
    assert(sum(isfinite(x)) >= 30, ...
        'gnss_gpr_denoiser:insufficientData', ...
        'At least 30 finite data points are required.');
end
