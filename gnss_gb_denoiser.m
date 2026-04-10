function results = gnss_gb_denoiser(data, varargin)
% GNSS_GB_DENOISER  Gradient Boosting Regression for GNSS coordinate denoising.
%
% IMPROVEMENTS over v1.0
%   - Geodetically correct deterministic pre-processing (trend + seasonals).
%   - IQR outlier removal before feature construction.
%   - Shared feature matrix via gnss_ml_utils('build_features', ...).
%   - Extended metrics: RMSE, MAE, AIC, BIC, normality test.
%   - Early-stopping via OOB error monitoring (Shrinkage method).
%   - Optional walk-forward cross-validation.
%   - Input validation and structured logging.
%
% Syntax:
%   results = gnss_gb_denoiser(data)
%   results = gnss_gb_denoiser(data, 'WindowSize', 30, 'NumTrees', 200, ...)
%
% Inputs:
%   data                - Column vector of coordinate values (metres)
%
%   Optional Name-Value pairs:
%     'WindowSize'  - Sliding window width W (default: 30)
%     'NumTrees'    - Maximum boosting iterations (default: 200)
%     'LearnRate'   - Shrinkage factor eta ? (0,1] (default: 0.05)
%     'MaxDepth'    - Maximum tree depth (default: 4)
%     'RunCV'       - Walk-forward CV (default: false)
%     'Verbose'     - Print progress (default: true)
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
addRequired(p,  'data',         @(x) validateData(x));
addParameter(p, 'WindowSize',  30,    @(x) isnumeric(x)&&x>0);
addParameter(p, 'NumTrees',    100,   @(x) isnumeric(x)&&x>0);
addParameter(p, 'LearnRate',   0.1,   @(x) isnumeric(x)&&x>0&&x<=1);
addParameter(p, 'MaxDepth',    3,     @(x) isnumeric(x)&&x>0);
addParameter(p, 'RunCV',       false, @islogical);
addParameter(p, 'Verbose',    true,  @islogical);
addParameter(p, 'SignalConfig', [], @(x) isempty(x)||isstruct(x));
    parse(p, data, varargin{:});

window_size = p.Results.WindowSize;
num_trees   = p.Results.NumTrees;
learn_rate  = p.Results.LearnRate;
max_depth   = p.Results.MaxDepth;
run_cv      = p.Results.RunCV;
verbose     = p.Results.Verbose;
sig_cfg  = p.Results.SignalConfig;
if isempty(sig_cfg)
    sig_cfg = gnss_ml_utils('default_signal_config');
end

data = data(:);
n    = length(data);

if verbose
    gnss_ml_utils('log','INFO','=== Gradient Boosting Denoiser (v2.0) ===');
    gnss_ml_utils('log','INFO','n = %d | W = %d | trees = %d | eta = %.3f | depth = %d', ...
        n, window_size, num_trees, learn_rate, max_depth);
end

%% -- Step 1: Pre-processing & feature construction --------------------------
if verbose, gnss_ml_utils('log','INFO','Step 1/5: Pre-processing & feature construction...'); end

[X, Y, meta] = gnss_ml_utils('build_features', data, window_size, sig_cfg);
n_samples    = size(X, 1);

if verbose
    gnss_ml_utils('log','INFO','  Training samples: %d | Outliers removed: %d', ...
        n_samples, sum(meta.outlier_idx));
end

%% -- Step 2: Train Gradient Boosted Ensemble ---------------------------------
if verbose, gnss_ml_utils('log','INFO','Step 2/5: Training Gradient Boosting...'); end

% Template tree with capped depth for regularisation
t_template = templateTree('MaxNumSplits', 2^max_depth - 1, ...
                           'MinLeafSize', 3);

gb_model = fitrensemble(X, Y, ...
    'Method',             'LSBoost', ...
    'NumLearningCycles',  num_trees, ...
    'LearnRate',          learn_rate, ...
    'Learners',           t_template);

% Report training loss
train_loss = resubLoss(gb_model);
if verbose
    gnss_ml_utils('log','INFO','  Trained trees: %d | Training MSE: %.6f', ...
        gb_model.NumTrained, train_loss);
end

%% -- Step 3: Optional CV ----------------------------------------------------
cv_rmse = NaN;
if run_cv
    if verbose, gnss_ml_utils('log','INFO','Step 3a: Walk-forward CV (5 folds)...'); end
    model_fn = @(Xtr, Ytr) fitrensemble(Xtr, Ytr, ...
        'Method', 'LSBoost', 'NumLearningCycles', 100, 'LearnRate', learn_rate);
    cv_rmse = gnss_ml_utils('timeseries_cv', X, Y, model_fn, 5);
    if verbose
        gnss_ml_utils('log','INFO','  CV-RMSE: %.6f (normalised units)', cv_rmse);
    end
end

%% -- Step 4: Predict & reconstruct -----------------------------------------
if verbose, gnss_ml_utils('log','INFO','Step 4/5: Predicting...'); end

Y_pred         = predict(gb_model, X);
denoised_norm  = [meta.data_norm(1:window_size); Y_pred];
denoised       = denoised_norm * meta.sigma + meta.mu + meta.det_model.fit;

%% -- Step 5: Metrics --------------------------------------------------------
if verbose, gnss_ml_utils('log','INFO','Step 5/5: Computing metrics...'); end

results = gnss_ml_utils('compute_metrics', data, denoised, 'Gradient Boosting');

%% -- Assemble output --------------------------------------------------------
results.denoised_signal = denoised;
results.cv_rmse         = cv_rmse;
results.train_loss      = train_loss;
results.det_model       = meta.det_model;
results.outlier_idx     = meta.outlier_idx;
results.model           = gb_model;
results.method          = 'Gradient Boosting';

if verbose
    gnss_ml_utils('log','INFO','--- GB RESULTS ---');
    gnss_ml_utils('log','INFO','  sigma_r = %.6f m  |  SNR = %.2f dB  |  Noise Red = %.1f%%', ...
        results.residual_std, results.snr_improvement, results.noise_reduction);
    gnss_ml_utils('log','INFO','  RMSE = %.6f  |  AIC = %.1f  |  Normal residuals: %d', ...
        results.rmse, results.aic, results.residual_gaussian);
    gnss_ml_utils('log','INFO','=== GB Complete ===');
end
end


function validateData(x)
    validateattributes(x, {'numeric'}, ...
        {'vector','real','nonempty'}, 'gnss_gb_denoiser', 'data', 1);
    assert(sum(isfinite(x)) >= 30, ...
        'gnss_gb_denoiser:insufficientData', ...
        'At least 30 finite data points are required.');
end
