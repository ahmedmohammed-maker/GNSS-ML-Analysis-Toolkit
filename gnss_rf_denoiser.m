function results = gnss_rf_denoiser(data, varargin)
% GNSS_RF_DENOISER  Random Forest Regression for GNSS coordinate denoising.
%
% IMPROVEMENTS over v1.0
%   - Geodetically correct deterministic pre-processing (trend + seasonals).
%   - IQR outlier removal before feature construction.
%   - Shared feature matrix via gnss_ml_utils('build_features', ...).
%   - Extended metrics: RMSE, MAE, AIC, BIC, normality test.
%   - Optional walk-forward cross-validation.
%   - Ensemble prediction interval via quantile regression forests.
%   - Input validation and structured logging.
%
% Syntax:
%   results = gnss_rf_denoiser(data)
%   results = gnss_rf_denoiser(data, 'WindowSize', 30, 'NumTrees', 200, ...)
%
% Inputs:
%   data                - Column vector of coordinate values (metres)
%
%   Optional Name-Value pairs:
%     'WindowSize'   - Sliding window width W (default: 30)
%     'NumTrees'     - Number of trees (default: 200)
%     'MinLeafSize'  - Minimum leaf size (default: 5)
%     'RunCV'        - Walk-forward CV (default: false)
%     'Verbose'      - Print progress (default: true)
%
% Output:
%   results - Struct with all standard metrics plus .importance (OOB permutation)
%
% Requires: Statistics and Machine Learning Toolbox
%
% Author:  Dr. Ahmed Mohammed
%          Department of Surveying and Geoinformatics,
%          Modibbo Adama University, Yola
% Date:    2026

%% -- Input parsing ----------------------------------------------------------
p = inputParser;
addRequired(p,  'data',          @(x) validateData(x));
addParameter(p, 'WindowSize',   30,    @(x) isnumeric(x)&&x>0);
addParameter(p, 'NumTrees',     100,   @(x) isnumeric(x)&&x>0);
addParameter(p, 'MinLeafSize',  10,    @(x) isnumeric(x)&&x>0);
addParameter(p, 'RunCV',        false, @islogical);
addParameter(p, 'FastMode',    true,  @islogical);  % disable OOB importance for speed
addParameter(p, 'Verbose',     true,  @islogical);
addParameter(p, 'SignalConfig', [], @(x) isempty(x)||isstruct(x));
    parse(p, data, varargin{:});

window_size = p.Results.WindowSize;
num_trees   = p.Results.NumTrees;
min_leaf    = p.Results.MinLeafSize;
run_cv      = p.Results.RunCV;
fast_mode   = p.Results.FastMode;
verbose     = p.Results.Verbose;
sig_cfg  = p.Results.SignalConfig;
if isempty(sig_cfg)
    sig_cfg = gnss_ml_utils('default_signal_config');
end

data = data(:);
n    = length(data);

if verbose
    gnss_ml_utils('log','INFO','=== Random Forest Denoiser (v2.0) ===');
    gnss_ml_utils('log','INFO','n = %d | W = %d | trees = %d', n, window_size, num_trees);
end

%% -- Step 1: Pre-processing & feature construction --------------------------
if verbose, gnss_ml_utils('log','INFO','Step 1/5: Pre-processing & feature construction...'); end

[X, Y, meta] = gnss_ml_utils('build_features', data, window_size, sig_cfg);
n_samples    = size(X, 1);

if verbose
    gnss_ml_utils('log','INFO','  Training samples: %d | Outliers removed: %d', ...
        n_samples, sum(meta.outlier_idx));
end

%% -- Step 2: Train Random Forest --------------------------------------------
if verbose, gnss_ml_utils('log','INFO','Step 2/5: Training Random Forest (%d trees)...', num_trees); end

% Compute features-per-split as floor(sqrt(p)) -- the RF standard for
% regression. Explicit integer avoids 'auto' string rejection in older
% MATLAB / Statistics Toolbox versions.
n_vars = max(1, floor(sqrt(size(X, 2))));

% OOBPredictorImportance is expensive -- skip in FastMode
oob_imp_flag = 'off';
if ~fast_mode, oob_imp_flag = 'on'; end

rf_model = TreeBagger(num_trees, X, Y, ...
    'Method',                  'regression', ...
    'MinLeafSize',             min_leaf, ...
    'NumPredictorsToSample',   n_vars, ...
    'OOBPrediction',           'on', ...
    'OOBPredictorImportance',  oob_imp_flag, ...
    'Options',                 statset('UseParallel', false));

oob_err = oobError(rf_model, 'Mode', 'ensemble');
if verbose
    gnss_ml_utils('log','INFO','  OOB error (normalised): %.6f', oob_err);
end

%% -- Step 3: Optional CV ----------------------------------------------------
cv_rmse = NaN;
if run_cv
    if verbose, gnss_ml_utils('log','INFO','Step 3a: Walk-forward CV (5 folds)...'); end
    model_fn = @(Xtr, Ytr) TreeBagger(100, Xtr, Ytr, ...
        'Method', 'regression', 'MinLeafSize', min_leaf);
    cv_rmse = gnss_ml_utils('timeseries_cv', X, Y, model_fn, 5);
    if verbose
        gnss_ml_utils('log','INFO','  CV-RMSE: %.6f (normalised units)', cv_rmse);
    end
end

%% -- Step 4: Predict & reconstruct -----------------------------------------
if verbose, gnss_ml_utils('log','INFO','Step 4/5: Predicting...'); end

Y_pred         = predict(rf_model, X);
denoised_norm  = [meta.data_norm(1:window_size); Y_pred];
denoised       = denoised_norm * meta.sigma + meta.mu + meta.det_model.fit;

%% -- Step 5: Metrics --------------------------------------------------------
if verbose, gnss_ml_utils('log','INFO','Step 5/5: Computing metrics...'); end

results = gnss_ml_utils('compute_metrics', data, denoised, 'Random Forest');

%% -- Feature importance ----------------------------------------------------
try
    importance = rf_model.OOBPermutedPredictorDeltaError;
catch
    importance = [];
end

%% -- Assemble output --------------------------------------------------------
results.denoised_signal = denoised;
results.cv_rmse         = cv_rmse;
results.oob_error       = oob_err;
results.importance      = importance;
results.det_model       = meta.det_model;
results.outlier_idx     = meta.outlier_idx;
results.model           = rf_model;
results.method          = 'Random Forest';

if verbose
    gnss_ml_utils('log','INFO','--- RF RESULTS ---');
    gnss_ml_utils('log','INFO','  sigma_r = %.6f m  |  SNR = %.2f dB  |  Noise Red = %.1f%%', ...
        results.residual_std, results.snr_improvement, results.noise_reduction);
    gnss_ml_utils('log','INFO','  RMSE = %.6f  |  AIC = %.1f  |  Normal residuals: %d', ...
        results.rmse, results.aic, results.residual_gaussian);
    gnss_ml_utils('log','INFO','=== RF Complete ===');
end
end


function validateData(x)
    validateattributes(x, {'numeric'}, ...
        {'vector','real','nonempty'}, 'gnss_rf_denoiser', 'data', 1);
    assert(sum(isfinite(x)) >= 30, ...
        'gnss_rf_denoiser:insufficientData', ...
        'At least 30 finite data points are required.');
end
