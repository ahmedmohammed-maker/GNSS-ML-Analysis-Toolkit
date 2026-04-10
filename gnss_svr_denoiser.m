function results = gnss_svr_denoiser(data, varargin)
% GNSS_SVR_DENOISER  Support Vector Regression for GNSS coordinate denoising.
%
% IMPROVEMENTS over v1.0
%   - Geodetically correct deterministic pre-processing (trend + seasonals).
%   - IQR outlier removal before feature construction.
%   - Shared feature matrix via gnss_ml_utils('build_features', ...).
%   - Extended metrics: RMSE, MAE, AIC, BIC, normality test.
%   - Optional walk-forward cross-validation.
%   - Input validation and structured logging.
%
% Syntax:
%   results = gnss_svr_denoiser(data)
%   results = gnss_svr_denoiser(data, 'WindowSize', 30, 'KernelFunction', 'rbf', ...)
%
% Inputs:
%   data                   - Column vector of coordinate values (metres)
%
%   Optional Name-Value pairs:
%     'WindowSize'              - Sliding window width W (default: 30)
%     'KernelFunction'          - 'rbf' (default), 'polynomial', 'linear'
%     'OptimizeHyperparameters' - true (default) | false
%     'MaxEvaluations'          - Optimiser budget (default: 40)
%     'RunCV'                   - Walk-forward CV (default: false)
%     'Verbose'                 - Print progress (default: true)
%
% Output:
%   results - Struct (see gnss_gpr_denoiser for full field list)
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
addParameter(p, 'WindowSize',               30,    @(x) isnumeric(x)&&x>0);
addParameter(p, 'KernelFunction',           'rbf', @ischar);
addParameter(p, 'OptimizeHyperparameters',  true,  @islogical);
addParameter(p, 'MaxEvaluations',           10,    @(x) isnumeric(x)&&x>0);
addParameter(p, 'RunCV',                    false, @islogical);
addParameter(p, 'Verbose',                 true,  @islogical);
addParameter(p, 'SignalConfig', [], @(x) isempty(x)||isstruct(x));
    parse(p, data, varargin{:});

window_size = p.Results.WindowSize;
kernel      = p.Results.KernelFunction;
optimize    = p.Results.OptimizeHyperparameters;
max_evals   = p.Results.MaxEvaluations;
run_cv      = p.Results.RunCV;
verbose     = p.Results.Verbose;
sig_cfg  = p.Results.SignalConfig;
if isempty(sig_cfg)
    sig_cfg = gnss_ml_utils('default_signal_config');
end

data = data(:);
n    = length(data);

if verbose
    gnss_ml_utils('log','INFO','=== SVR Denoiser (v2.0) ===');
    gnss_ml_utils('log','INFO','n = %d | W = %d | kernel = %s | optimize = %d', ...
        n, window_size, kernel, optimize);
end

%% -- Step 1: Pre-processing & feature construction --------------------------
if verbose, gnss_ml_utils('log','INFO','Step 1/5: Pre-processing & feature construction...'); end

[X, Y, meta] = gnss_ml_utils('build_features', data, window_size, sig_cfg);
n_samples    = size(X, 1);

if verbose
    gnss_ml_utils('log','INFO','  Training samples: %d | Outliers removed: %d', ...
        n_samples, sum(meta.outlier_idx));
end

%% -- Step 2: Train SVR ------------------------------------------------------
if verbose, gnss_ml_utils('log','INFO','Step 2/5: Training SVR...'); end

% -- Speed optimisation ----------------------------------------------------
% Bayesian opt on 3 params x 10 evals is fast (~30s).
% 'expected-improvement' converges faster than 'expected-improvement-plus'.
% Subsample training data when n_samples is large to cap fit time.
MAX_TRAIN = 800;
if size(X,1) > MAX_TRAIN
    sub_idx = round(linspace(1, size(X,1), MAX_TRAIN));
    X_fit = X(sub_idx,:);  Y_fit = Y(sub_idx);
else
    X_fit = X;  Y_fit = Y;
end

hp_opts = struct('Verbose', 0, 'ShowPlots', false, ...
                 'MaxObjectiveEvaluations', max_evals, ...
                 'AcquisitionFunctionName', 'expected-improvement');

if optimize
    svr_model = fitrsvm(X_fit, Y_fit, ...
        'KernelFunction',          kernel, ...
        'Standardize',             true, ...
        'OptimizeHyperparameters', {'BoxConstraint','KernelScale','Epsilon'}, ...
        'HyperparameterOptimizationOptions', hp_opts);
else
    svr_model = fitrsvm(X_fit, Y_fit, ...
        'KernelFunction', kernel, ...
        'Standardize',    true);
end

if verbose
    gnss_ml_utils('log','INFO','  BoxConstraint: %.4f | KernelScale: %.4f | ?: %.4f', ...
        svr_model.BoxConstraints(1), svr_model.KernelParameters.Scale, svr_model.Epsilon);
end

%% -- Step 3: Optional CV ----------------------------------------------------
cv_rmse = NaN;
if run_cv
    if verbose, gnss_ml_utils('log','INFO','Step 3a: Walk-forward CV (5 folds)...'); end
    model_fn = @(Xtr, Ytr) fitrsvm(Xtr, Ytr, 'KernelFunction', kernel, 'Standardize', true);
    cv_rmse  = gnss_ml_utils('timeseries_cv', X, Y, model_fn, 5);
    if verbose
        gnss_ml_utils('log','INFO','  CV-RMSE: %.6f (normalised units)', cv_rmse);
    end
end

%% -- Step 4: Predict & reconstruct -----------------------------------------
if verbose, gnss_ml_utils('log','INFO','Step 4/5: Predicting...'); end

Y_pred         = predict(svr_model, X);
denoised_norm  = [meta.data_norm(1:window_size); Y_pred];
denoised       = denoised_norm * meta.sigma + meta.mu + meta.det_model.fit;

%% -- Step 5: Metrics --------------------------------------------------------
if verbose, gnss_ml_utils('log','INFO','Step 5/5: Computing metrics...'); end

results = gnss_ml_utils('compute_metrics', data, denoised, 'SVR');

%% -- Assemble output --------------------------------------------------------
results.denoised_signal = denoised;
results.cv_rmse         = cv_rmse;
results.det_model       = meta.det_model;
results.outlier_idx     = meta.outlier_idx;
results.model           = svr_model;
results.kernel          = kernel;
results.method          = 'SVR';

if verbose
    gnss_ml_utils('log','INFO','--- SVR RESULTS ---');
    gnss_ml_utils('log','INFO','  sigma_r = %.6f m  |  SNR = %.2f dB  |  Noise Red = %.1f%%', ...
        results.residual_std, results.snr_improvement, results.noise_reduction);
    gnss_ml_utils('log','INFO','  RMSE = %.6f  |  AIC = %.1f  |  Normal residuals: %d', ...
        results.rmse, results.aic, results.residual_gaussian);
    gnss_ml_utils('log','INFO','=== SVR Complete ===');
end
end


function validateData(x)
    validateattributes(x, {'numeric'}, ...
        {'vector','real','nonempty'}, 'gnss_svr_denoiser', 'data', 1);
    assert(sum(isfinite(x)) >= 30, ...
        'gnss_svr_denoiser:insufficientData', ...
        'At least 30 finite data points are required.');
end
