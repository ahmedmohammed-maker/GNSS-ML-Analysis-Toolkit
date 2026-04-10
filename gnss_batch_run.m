%% GNSS_BATCH_RUN  Multi-station batch denoising script.
%
%  HOW TO USE
%  ----------
%  1. Place this script (and all gnss_*.m files) in a folder on the MATLAB path.
%  2. Organise your input data files using the naming convention:
%
%         <SSSS>_<TYPE>_txyz.csv
%
%     where
%       <SSSS> = 4-character GNSS station code  e.g.  YOLA, ABUZ, MAID, KANO
%       <TYPE> = dlts  (daily)  |  hrts  (high-rate)  |  wlts  (weekly)
%
%     Example folder layout:
%       /data/gnss/
%           YOLA_dlts_txyz.csv
%           YOLA_wlts_txyz.csv
%           ABUZ_dlts_txyz.csv
%           MAID_hrts_txyz.csv
%
%  3. Edit the USER CONFIGURATION section below.
%  4. Run: >> gnss_batch_run
%
%  OUTPUTS (written to OutputFolder)
%  ---------
%   batch_summary.csv          — all stations × methods × components in one table
%   <SSSS>_summary.csv         — per-station method comparison
%   <SSSS>_<type>_denoised.csv — original + all denoised signals side-by-side
%   <SSSS>_<type>_results.mat  — full result structs for post-processing
%
% Author:  Dr. Ahmed Mohammed
%          Department of Surveying and Geoinformatics,
%          Modibbo Adama University, Yola
% Date:    2026

clear; clc;
fprintf('=======================================================\n');
fprintf('  GNSS ML Toolkit -- Standardised Batch Processor\n');
fprintf('=======================================================\n\n');

% =========================================================================
%  USER CONFIGURATION  (edit this section only)
% =========================================================================

%% Folder containing all input CSV files
INPUT_FOLDER  = 'C:\gnss_data\input';      % <-- change to your folder

%% Where results will be written (created automatically if missing)
OUTPUT_FOLDER = 'C:\gnss_data\results';    % <-- change or leave empty for auto

%% ML methods to run  (any subset of: 'GPR', 'SVR', 'RF', 'GB', 'KNN')
METHODS = {'GPR', 'SVR', 'RF', 'GB', 'KNN'};

%% Time-series types to include  (any subset of: 'dlts', 'hrts', 'wlts')
TYPES   = {'dlts', 'hrts', 'wlts'};

%% Station filter  -- empty = all stations found in folder
%  Example: STATIONS = {'YOLA', 'ABUZ'};
STATIONS = {};

%% Coordinate components to process  -- empty = all components
%  Example: COMPONENTS = [1 3] processes only the X and Z components.
COMPONENTS = [];   % [] = all

%% Algorithm hyperparameters
params.window_size   = 0;      % 0 = auto-select by series type
                               %   daily=30, high-rate=120, weekly=12
params.num_trees     = 200;    % RF and GB number of trees
params.optimize      = true;   % Bayesian hyperparameter optimisation (GPR, SVR)
params.max_evals     = 10;     % Optimisation budget (evaluations)
params.run_cv        = false;  % Walk-forward cross-validation
params.learn_rate    = 0.10;   % GB shrinkage rate
params.max_depth     = 3;      % GB tree depth
params.num_neighbors = 5;      % KNN: number of neighbours (0 = auto)

%% Signal configuration
%  Leave empty to auto-select based on series type (recommended).
%  Or supply a struct from gnss_ml_utils('default_signal_config') with
%  fields set to true/false.
SIGNAL_CONFIG = [];   % [] = auto

%% Parallelism  -- requires Parallel Computing Toolbox
USE_PARALLEL  = false;

%% Output options
SAVE_MAT = true;   % Save per-station .mat files
SAVE_CSV = true;   % Save per-station denoised CSV files

% =========================================================================
%  STEP 0: Validate input folder & scan files
% =========================================================================
fprintf('Input folder : %s\n', INPUT_FOLDER);

if ~isfolder(INPUT_FOLDER)
    error('gnss_batch_run:folderNotFound', ...
        'Input folder not found:\n  %s\nPlease update INPUT_FOLDER.', INPUT_FOLDER);
end

files = gnss_file_io('scan_folder', INPUT_FOLDER, ...
    'Types',    TYPES, ...
    'Stations', STATIONS, ...
    'Verbose',  true);

if isempty(files)
    fprintf('\n[WARNING] No conforming files found.\n');
    fprintf('Files must be named:  <SSSS>_<dlts|hrts|wlts>_txyz.csv\n');
    fprintf('Example:              YOLA_dlts_txyz.csv\n\n');
    return;
end

fprintf('\nFiles to process: %d\n', numel(files));

% =========================================================================
%  STEP 1: Pre-validate all files (fail fast before any long computation)
% =========================================================================
fprintf('\n--- Pre-validation ---\n');
bad_files = {};
for k = 1:numel(files)
    try
        gnss_file_io('validate_file', files(k).path);
    catch ME
        fprintf('  [FAIL] %s -- %s\n', files(k).name, ME.message);
        bad_files{end+1} = files(k).name; %#ok<SAGROW>
    end
end

if ~isempty(bad_files)
    fprintf('\n%d file(s) failed validation and will be skipped.\n', numel(bad_files));
end

% =========================================================================
%  STEP 2: Time estimate
% =========================================================================
t_est = estimate_batch_time(numel(files), METHODS, params);
fprintf('\nEstimated processing time: ~%.0f min (%.0f s)\n\n', ...
    t_est / 60, t_est);

% =========================================================================
%  STEP 3: Run batch
% =========================================================================
fprintf('--- Batch processing START ---\n\n');

summary = gnss_file_io('batch', INPUT_FOLDER, METHODS, params, ...
    'OutputFolder',  OUTPUT_FOLDER, ...
    'Types',         TYPES, ...
    'Stations',      STATIONS, ...
    'Components',    COMPONENTS, ...
    'Parallel',      USE_PARALLEL, ...
    'SaveMAT',       SAVE_MAT, ...
    'SaveCSV',       SAVE_CSV, ...
    'Verbose',       true, ...
    'SignalConfig',  SIGNAL_CONFIG);

% =========================================================================
%  STEP 4: Print summary table
% =========================================================================
if ~isempty(summary)
    fprintf('\n=== BATCH SUMMARY ===\n');
    disp(summary);

    % Find best method per station × component based on RMSE
    fprintf('\n--- Best method (lowest RMSE) per station × component ---\n');
    stations  = unique(summary.Station);
    comps_all = unique(summary.Component);
    for si = 1:numel(stations)
        for ci = 1:numel(comps_all)
            mask = strcmp(summary.Station, stations{si}) & ...
                   strcmp(summary.Component, comps_all{ci});
            sub  = summary(mask, :);
            if isempty(sub), continue; end
            [~, best_idx] = min(sub.RMSE_mm);
            best = sub(best_idx, :);
            fprintf('  %s | %s | Best: %-20s | RMSE = %.4f mm | SNR = %.2f dB\n', ...
                best.Station{1}, best.Component{1}, best.Method{1}, ...
                best.RMSE_mm, best.SNR_dB);
        end
    end
    fprintf('\nSummary CSV: %s\n', fullfile(OUTPUT_FOLDER, 'batch_summary.csv'));
else
    fprintf('No results produced.\n');
end


% =========================================================================
%  STEP 5: Quick visualisation (optional -- comment out if unwanted)
% =========================================================================
if ~isempty(summary) && SAVE_CSV
    fprintf('\n--- Quick Plot (first station, component X) ---\n');
    try
        quick_plot_first_station(OUTPUT_FOLDER, summary);
    catch ME
        fprintf('Quick plot skipped: %s\n', ME.message);
    end
end

fprintf('\nDone.\n');


% =========================================================================
%  LOCAL HELPERS
% =========================================================================

function t_s = estimate_batch_time(n_files, methods, params)
% ESTIMATE_BATCH_TIME  Rough estimate in seconds.
    per_method = struct('GPR', 120, 'SVR', 60, 'RF', 20, 'GB', 25, 'KNN', 6);
    if ~params.optimize
        per_method.GPR = 18;
        per_method.SVR = 12;
    end
    t_method = 0;
    for mi = 1:numel(methods)
        key = upper(strtrim(methods{mi}));
        if strcmp(key,'RANDOM FOREST') || strcmp(key,'RF')
            key = 'RF';
        elseif strcmp(key,'GRADIENT BOOSTING') || strcmp(key,'GB')
            key = 'GB';
        end
        if isfield(per_method, key)
            t_method = t_method + per_method.(key);
        else
            t_method = t_method + 30;
        end
    end
    t_s = n_files * t_method * 3;   % x3 for 3 components
end


function quick_plot_first_station(out_folder, summary)
% QUICK_PLOT_FIRST_STATION  Plot original vs all denoised signals.
    % Find first denoised CSV
    csvs = dir(fullfile(out_folder, '*_denoised.csv'));
    if isempty(csvs), return; end

    fpath = fullfile(out_folder, csvs(1).name);
    T     = readtable(fpath, 'VariableNamingRule', 'preserve');
    cols  = T.Properties.VariableNames;

    % Find numeric columns
    num_cols = cols(2:end);   % skip date/epoch

    % Identify original vs denoised columns
    orig_cols = num_cols(cellfun(@(c) numel(strsplit(c,'_')) == 1, num_cols));
    if isempty(orig_cols), orig_cols = num_cols(1); end
    orig_col = orig_cols{1};

    den_cols  = num_cols(cellfun(@(c) numel(strsplit(c,'_')) > 1 && ...
                         startsWith(c, orig_col), num_cols));

    if isempty(den_cols), return; end

    n = height(T);
    ep = 1:n;

    fig = figure('Name', sprintf('Quick Plot: %s', csvs(1).name), ...
                 'Position', [50 50 1200 500]);
    hold on;
    plot(ep, T.(orig_col), 'Color', [0.7 0.7 0.7], 'LineWidth', 0.8, ...
         'DisplayName', [orig_col ' (original)']);

    colors = lines(numel(den_cols));
    for di = 1:numel(den_cols)
        plot(ep, T.(den_cols{di}), 'Color', colors(di,:), 'LineWidth', 1.5, ...
             'DisplayName', den_cols{di});
    end
    hold off;
    legend('Location','best','FontSize',8);
    xlabel('Epoch');  ylabel('Coordinate (m)');
    title(strrep(csvs(1).name, '_', ' '), 'Interpreter','none');
    grid on;

    % Save figure
    fig_path = fullfile(out_folder, [strrep(csvs(1).name,'.csv','') '_quickplot.png']);
    print(fig, fig_path, '-dpng', '-r150');
    fprintf('Quick plot saved: %s\n', fig_path);
end
