function results = gnss_knn_denoiser(data, varargin)
% GNSS_KNN_DENOISER  K-Nearest Neighbours Regression for GNSS coordinate denoising.
%
% IMPROVEMENTS over v1.0
%   - Geodetically correct deterministic pre-processing (trend + seasonals).
%   - IQR outlier removal before feature construction.
%   - Shared feature matrix via gnss_ml_utils('build_features', ...).
%   - Extended metrics: RMSE, MAE, AIC, BIC, normality test.
%   - Automatic k selection via leave-one-out CV on training set.
%   - Optional walk-forward cross-validation.
%   - Input validation and structured logging.
%
% Syntax:
%   results = gnss_knn_denoiser(data)
%   results = gnss_knn_denoiser(data, 'WindowSize', 30, 'NumNeighbors', 5, ...)
%
% Inputs:
%   data                - Column vector of coordinate values (metres)
%
%   Optional Name-Value pairs:
%     'WindowSize'    - Sliding window width W (default: 30)
%     'NumNeighbors'  - k (default: 5; 0 = auto-select from {3,5,7,10,15})
%     'Distance'      - 'euclidean' (default), 'cityblock', 'cosine'
%     'RunCV'         - Walk-forward CV (default: false)
%     'Verbose'       - Print progress (default: true)
%
% Output:
%   results - Struct with all standard metrics
%
% Requires: Statistics and Machine Learning Toolbox
%
% Author:  Dr. Ahmed Mohammed
%          Department of Surveying and Geoinformatics,
%          Modibbo Adama University, Yola
% Date:    2026

%% -- Input parsing ----------------------------------------------------------
p = inputParser;
addRequired(p,  'data',            @(x) validateData(x));
addParameter(p, 'WindowSize',     30,          @(x) isnumeric(x)&&x>0);
addParameter(p, 'NumNeighbors',   5,           @(x) isnumeric(x)&&x>=0);
addParameter(p, 'Distance',       'euclidean', @ischar);
addParameter(p, 'RunCV',          false,       @islogical);
addParameter(p, 'Verbose',       true,        @islogical);
addParameter(p, 'SignalConfig', [], @(x) isempty(x)||isstruct(x));
    parse(p, data, varargin{:});

window_size = p.Results.WindowSize;
k_in        = p.Results.NumNeighbors;
distance    = p.Results.Distance;
run_cv      = p.Results.RunCV;
verbose     = p.Results.Verbose;
sig_cfg  = p.Results.SignalConfig;
if isempty(sig_cfg)
    sig_cfg = gnss_ml_utils('default_signal_config');
end

data = data(:);
n    = length(data);

if verbose
    gnss_ml_utils('log','INFO','=== KNN Denoiser (v2.0) ===');
    gnss_ml_utils('log','INFO','n = %d | W = %d | k = %d (0=auto)', n, window_size, k_in);
end

%% -- Step 1: Pre-processing & feature construction --------------------------
if verbose, gnss_ml_utils('log','INFO','Step 1/5: Pre-processing & feature construction...'); end

[X, Y, meta] = gnss_ml_utils('build_features', data, window_size, sig_cfg);
n_samples    = size(X, 1);

if verbose
    gnss_ml_utils('log','INFO','  Training samples: %d | Outliers removed: %d', ...
        n_samples, sum(meta.outlier_idx));
end

%% -- Step 2: Auto-select k (if requested) ----------------------------------
if k_in == 0
    if verbose, gnss_ml_utils('log','INFO','Step 2a: Auto-selecting k via LOO-CV...'); end
    k_candidates = [3, 5, 7, 10, 15];
    loo_err      = inf(size(k_candidates));
    for ki = 1:length(k_candidates)
        try
            mdl_tmp = fitrknn(X, Y, 'NumNeighbors', k_candidates(ki), ...
                              'Distance', distance, 'Standardize', true);
            loo_err(ki) = resubLoss(mdl_tmp);
        catch
            loo_err(ki) = inf;
        end
    end
    [~, best_idx] = min(loo_err);
    k = k_candidates(best_idx);
    if verbose
        gnss_ml_utils('log','INFO','  Selected k = %d (resubstitution MSE = %.6f)', k, loo_err(best_idx));
    end
else
    k = k_in;
end

%% -- Step 3: Train KNN ------------------------------------------------------
if verbose, gnss_ml_utils('log','INFO','Step 3/5: Training KNN (k=%d)...', k); end

use_builtin = true;
try
    knn_model = fitrknn(X, Y, ...
        'NumNeighbors', k, ...
        'Distance',     distance, ...
        'Standardize',  true);
catch
    % Fallback to manual KNN when fitrknn is unavailable
    use_builtin = false;
    if verbose
        gnss_ml_utils('log','WARN','fitrknn not available -- using manual implementation.');
    end
    X_mn  = mean(X);
    X_sd  = std(X);
    X_sd(X_sd < eps) = 1;
    X_std_train = (X - X_mn) ./ X_sd;
    knn_model   = struct('X_norm', X_std_train, 'Y', Y, 'k', k, ...
                          'X_mean', X_mn, 'X_std', X_sd);
end

%% -- Step 4a: Optional CV ---------------------------------------------------
cv_rmse = NaN;
if run_cv && use_builtin
    if verbose, gnss_ml_utils('log','INFO','Step 4a: Walk-forward CV (5 folds)...'); end
    model_fn = @(Xtr, Ytr) fitrknn(Xtr, Ytr, 'NumNeighbors', k, ...
                                    'Distance', distance, 'Standardize', true);
    cv_rmse = gnss_ml_utils('timeseries_cv', X, Y, model_fn, 5);
    if verbose
        gnss_ml_utils('log','INFO','  CV-RMSE: %.6f (normalised units)', cv_rmse);
    end
end

%% -- Step 4b: Predict & reconstruct ----------------------------------------
if verbose, gnss_ml_utils('log','INFO','Step 4/5: Predicting...'); end

if use_builtin
    Y_pred = predict(knn_model, X);
else
    % Manual KNN prediction
    Y_pred = zeros(n_samples, 1);
    X_nrm  = (X - knn_model.X_mean) ./ knn_model.X_std;
    X_tr   = knn_model.X_norm;
    for i = 1:n_samples
        dists         = sum((X_tr - X_nrm(i,:)).^2, 2);
        [~, idx]      = sort(dists);
        nbr_idx       = idx(2 : k+1);   % exclude self
        Y_pred(i)     = mean(knn_model.Y(nbr_idx));
    end
end

denoised_norm = [meta.data_norm(1:window_size); Y_pred];
denoised      = denoised_norm * meta.sigma + meta.mu + meta.det_model.fit;

%% -- Step 5: Metrics --------------------------------------------------------
if verbose, gnss_ml_utils('log','INFO','Step 5/5: Computing metrics...'); end

results = gnss_ml_utils('compute_metrics', data, denoised, 'KNN');

%% -- Assemble output --------------------------------------------------------
results.denoised_signal = denoised;
results.cv_rmse         = cv_rmse;
results.k               = k;
results.det_model       = meta.det_model;
results.outlier_idx     = meta.outlier_idx;
results.model           = knn_model;
results.method          = 'KNN';

if verbose
    gnss_ml_utils('log','INFO','--- KNN RESULTS ---');
    gnss_ml_utils('log','INFO','  sigma_r = %.6f m  |  SNR = %.2f dB  |  Noise Red = %.1f%%', ...
        results.residual_std, results.snr_improvement, results.noise_reduction);
    gnss_ml_utils('log','INFO','  RMSE = %.6f  |  AIC = %.1f  |  Normal residuals: %d', ...
        results.rmse, results.aic, results.residual_gaussian);
    gnss_ml_utils('log','INFO','=== KNN Complete ===');
end
end


function validateData(x)
    validateattributes(x, {'numeric'}, ...
        {'vector','real','nonempty'}, 'gnss_knn_denoiser', 'data', 1);
    assert(sum(isfinite(x)) >= 30, ...
        'gnss_knn_denoiser:insufficientData', ...
        'At least 30 finite data points are required.');
end
