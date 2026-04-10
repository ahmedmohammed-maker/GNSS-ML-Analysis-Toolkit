function varargout = gnss_file_io(action, varargin)
% GNSS_FILE_IO  Standardised file I/O and multi-station batch engine for the
%               GNSS ML Denoising Toolkit.
%
% =========================================================================
%  FILE-NAMING CONVENTION
% =========================================================================
%   Every input CSV must follow the pattern:
%
%       <SSSS>_<TYPE>_txyz.csv
%
%   where
%     <SSSS>  = exactly 4-character GNSS station code (uppercase, e.g. YOLA)
%     <TYPE>  = one of
%                 dlts  -> Daily          time series
%                 hrts  -> High-Rate      time series
%                 wlts  -> Weekly         time series
%     txyz    = literal token indicating the file contains time + XYZ columns
%
%   Examples:
%     YOLA_dlts_txyz.csv     % YOLA station, daily
%     ABUZ_hrts_txyz.csv     % ABUZ station, high-rate
%     MAID_wlts_txyz.csv     % MAID station, weekly
%
% =========================================================================
%  CSV FORMAT
% =========================================================================
%   Row 1  : header  ->  date (or epoch), X, Y, Z
%   Col 1  : date/time  -- datetime string 'yyyy-MM-dd', MJD (numeric),
%             GPS week+second, or plain epoch integer (1,2,3,…)
%   Col 2+ : coordinate components in metres
%
%   Missing values : NaN or empty cell (auto-interpolated before processing)
%
% =========================================================================
%  ACTIONS / API
% =========================================================================
%   [info]       = gnss_file_io('parse_filename',  filename)
%   [T, info]    = gnss_file_io('load_file',       filepath)
%   [T, info]    = gnss_file_io('load_file',       filepath, 'Verbose', true)
%   files        = gnss_file_io('scan_folder',     folder_path)
%   files        = gnss_file_io('scan_folder',     folder_path, 'Types',{'dlts'})
%   gnss_file_io('validate_file',  filepath)             % throws on error
%   gnss_file_io('batch',          folder_path, methods, params)
%   gnss_file_io('batch',          folder_path, methods, params, Name,Value)
%   gnss_file_io('write_template', folder_path, station, type, n_epochs)
%
% =========================================================================
%  BATCH NAME-VALUE OPTIONS  (passed after params struct)
% =========================================================================
%   'OutputFolder'   - where to write results (default: <input>/results)
%   'Types'          - cell of type codes to include, e.g. {'dlts','wlts'}
%                      (default: all three)
%   'Stations'       - cell of 4-char station codes to include
%                      (default: all found)
%   'Components'     - which coordinate columns to process, e.g. [1 2 3]
%                      (default: all)
%   'Parallel'       - true to use parfor when Parallel Toolbox present
%                      (default: false)
%   'SaveMAT'        - save per-station .mat file  (default: true)
%   'SaveCSV'        - save per-station denoised CSV (default: true)
%   'Verbose'        - print progress (default: true)
%   'SignalConfig'   - gnss_ml_utils signal config struct (default: auto
%                      from series type)
%
% =========================================================================
%  RETURN VALUE  (batch action)
% =========================================================================
%   summary = gnss_file_io('batch', ...)
%   Returns a table with columns:
%     Station | Type | Component | Method | sigma_mm | SNR_dB |
%     NR_pct  | RMSE_mm | MAE_mm | AIC | BIC | Normal | CV_RMSE_mm
%
% Author:  Dr. Ahmed Mohammed
%          Department of Surveying and Geoinformatics,
%          Modibbo Adama University, Yola
% Date:    2026
% =========================================================================

    switch lower(action)
        case 'parse_filename'
            varargout{1} = parse_filename(varargin{:});

        case 'load_file'
            [varargout{1}, varargout{2}] = load_file(varargin{:});

        case 'scan_folder'
            varargout{1} = scan_folder(varargin{:});

        case 'validate_file'
            validate_file(varargin{:});

        case 'batch'
            varargout{1} = run_batch(varargin{:});

        case 'write_template'
            write_template(varargin{:});

        otherwise
            error('gnss_file_io:unknownAction', ...
                'Unknown action "%s". Valid: parse_filename, load_file, scan_folder, validate_file, batch, write_template.', action);
    end
end


% =========================================================================
%  1.  FILENAME PARSER
% =========================================================================
function info = parse_filename(filename)
% PARSE_FILENAME  Decode station, type and validate the naming convention.
%
%   info = parse_filename('YOLA_dlts_txyz.csv')
%   info.station  = 'YOLA'
%   info.type     = 'dlts'
%   info.type_str = 'Daily'
%   info.valid    = true / false
%   info.error    = '' or error message

    [~, name, ext] = fileparts(filename);
    info.raw      = filename;
    info.name     = name;
    info.ext      = lower(ext);
    info.station  = '';
    info.type     = '';
    info.type_str = '';
    info.valid    = false;
    info.error    = '';

    % Must be .csv
    if ~strcmp(info.ext, '.csv')
        info.error = sprintf('Extension must be .csv, got "%s".', ext);
        return;
    end

    % Expected pattern:  SSSS_TYPE_txyz
    parts = strsplit(name, '_');
    if numel(parts) ~= 3
        info.error = sprintf( ...
            'Filename "%s" must have exactly 3 underscore-delimited tokens: <SSSS>_<TYPE>_txyz.', name);
        return;
    end

    station_code = upper(parts{1});
    type_code    = lower(parts{2});
    tail         = lower(parts{3});

    % Validate station code: exactly 4 alphanumeric characters
    if ~regexp(station_code, '^[A-Z0-9]{4}$')
        info.error = sprintf( ...
            'Station code "%s" must be exactly 4 alphanumeric characters.', station_code);
        return;
    end

    % Validate type code
    valid_types = struct('dlts','Daily', 'hrts','High-Rate', 'wlts','Weekly');
    if ~isfield(valid_types, type_code)
        info.error = sprintf( ...
            'Type code "%s" not recognised. Must be dlts, hrts, or wlts.', type_code);
        return;
    end

    % Validate tail token
    if ~strcmp(tail, 'txyz')
        info.error = sprintf('Tail token must be "txyz", got "%s".', tail);
        return;
    end

    info.station  = station_code;
    info.type     = type_code;
    info.type_str = valid_types.(type_code);
    info.valid    = true;
end


% =========================================================================
%  2.  FILE LOADER
% =========================================================================
function [T, info] = load_file(filepath, varargin)
% LOAD_FILE  Parse, validate and load a standardised GNSS CSV into a table.
%
%   [T, info] = gnss_file_io('load_file', '/data/YOLA_dlts_txyz.csv')
%
%   T    : MATLAB table with columns  [date | X | Y | Z]
%          (or fewer coordinate columns if file has fewer)
%   info : struct from parse_filename plus:
%            .n_epochs    - number of rows
%            .n_comps     - number of coordinate columns
%            .has_dates   - true if col 1 parsed as datetime
%            .date_vec    - datetime column vector (or [] if numeric epochs)
%            .components  - cell array of component column names

    p = inputParser;
    addRequired(p,  'filepath', @ischar);
    addParameter(p, 'Verbose',  true, @islogical);
    parse(p, filepath, varargin{:});
    verbose = p.Results.Verbose;

    [~, fname, ext] = fileparts(filepath);
    info = parse_filename([fname, ext]);

    if ~info.valid
        error('gnss_file_io:invalidName', ...
            'File naming error -- %s\nExpected: <SSSS>_<dlts|hrts|wlts>_txyz.csv', info.error);
    end

    if verbose
        gnss_log('INFO', 'Loading [%s | %s] from %s', ...
            info.station, info.type_str, filepath);
    end

    % ---- Read raw table --------------------------------------------------
    opts = detectImportOptions(filepath, 'VariableNamingRule', 'preserve');
    T_raw = readtable(filepath, opts);

    if width(T_raw) < 2
        error('gnss_file_io:formatError', ...
            'File must have at least 2 columns (epoch + 1 coordinate). Found %d.', width(T_raw));
    end

    % ---- Parse epoch / date column ---------------------------------------
    col1 = T_raw{:,1};
    info.has_dates = false;
    info.date_vec  = [];

    if isdatetime(col1)
        info.has_dates = true;
        info.date_vec  = col1;
    elseif iscell(col1) || isstring(col1)
        % Attempt datetime parse with multiple common formats
        date_fmts = {'yyyy-MM-dd', 'dd/MM/yyyy', 'MM/dd/yyyy', ...
                     'yyyy-MM-dd HH:mm:ss', 'yyyyMMdd'};
        for fi = 1:numel(date_fmts)
            try
                dv = datetime(col1, 'InputFormat', date_fmts{fi});
                info.has_dates = true;
                info.date_vec  = dv;
                break;
            catch
            end
        end
        if ~info.has_dates && verbose
            gnss_log('WARN', 'Column 1 not parsed as date -- treating as epoch index.');
        end
    elseif isnumeric(col1)
        % Could be MJD (> 50000), GPS week + fraction, or plain epoch index
        if max(col1) > 50000
            % Likely Modified Julian Date
            try
                info.date_vec  = datetime(col1, 'ConvertFrom', 'modifiedjuliandate');
                info.has_dates = true;
            catch
            end
        end
        % Otherwise keep as numeric epoch index
    end

    % ---- Extract coordinate columns -------------------------------------
    comp_cols = 2:width(T_raw);
    comp_names = T_raw.Properties.VariableNames(comp_cols);

    % Normalise component column names to X / Y / Z if unnamed / numeric
    expected_names = {'X','Y','Z'};
    for ci = 1:numel(comp_names)
        nm = strtrim(comp_names{ci});
        % If the header is empty or looks like 'Var2', replace with X/Y/Z
        if isempty(nm) || ~isempty(regexp(nm, '^Var\d+$', 'once'))
            if ci <= 3
                comp_names{ci} = expected_names{ci};
            else
                comp_names{ci} = sprintf('C%d', ci);
            end
        end
    end

    n_comps  = numel(comp_cols);
    coord_data = T_raw{:, comp_cols};

    % ---- Missing value handling ------------------------------------------
    for ci = 1:n_comps
        col_data = coord_data(:, ci);
        nan_mask = isnan(col_data);
        if any(nan_mask)
            good = find(~nan_mask);
            bad  = find(nan_mask);
            if length(good) > 1
                coord_data(bad, ci) = interp1(good, col_data(good), bad, 'linear', 'extrap');
            elseif length(good) == 1
                coord_data(nan_mask, ci) = col_data(good);
            end
            if verbose
                gnss_log('WARN', '  Component %s: %d NaN(s) interpolated.', ...
                    comp_names{ci}, sum(nan_mask));
            end
        end
    end

    % ---- Build output table ---------------------------------------------
    n_epochs = size(coord_data, 1);
    T = array2table(coord_data, 'VariableNames', comp_names);

    if info.has_dates
        T = addvars(T, info.date_vec, 'Before', comp_names{1}, ...
                    'NewVariableNames', {'date'});
    else
        T = addvars(T, (1:n_epochs)', 'Before', comp_names{1}, ...
                    'NewVariableNames', {'epoch'});
    end

    info.n_epochs   = n_epochs;
    info.n_comps    = n_comps;
    info.components = comp_names;

    if verbose
        gnss_log('INFO', '  Loaded: %d epochs | %d component(s) [%s]', ...
            n_epochs, n_comps, strjoin(comp_names, ', '));
    end
end


% =========================================================================
%  3.  FOLDER SCANNER
% =========================================================================
function files = scan_folder(folder_path, varargin)
% SCAN_FOLDER  Discover all conforming CSV files under folder_path.
%
%   files = gnss_file_io('scan_folder', '/data/gnss')
%   files = gnss_file_io('scan_folder', '/data/gnss', 'Types', {'dlts'})
%   files = gnss_file_io('scan_folder', '/data/gnss', 'Stations', {'YOLA','ABUZ'})
%
%   Returns a struct array with fields:
%     .path     - full file path
%     .name     - filename without extension
%     .station  - 4-char station code
%     .type     - 'dlts' | 'hrts' | 'wlts'
%     .type_str - human-readable type
%     .n_epochs - (populated lazily -- 0 until loaded)

    p = inputParser;
    addRequired(p,  'folder_path', @ischar);
    addParameter(p, 'Types',    {'dlts','hrts','wlts'}, @iscell);
    addParameter(p, 'Stations', {}, @iscell);
    addParameter(p, 'Verbose',  true, @islogical);
    parse(p, folder_path, varargin{:});

    types_filter    = cellfun(@lower, p.Results.Types,    'UniformOutput', false);
    stations_filter = cellfun(@upper, p.Results.Stations, 'UniformOutput', false);
    verbose         = p.Results.Verbose;

    if ~isfolder(folder_path)
        error('gnss_file_io:folderNotFound', 'Folder not found: %s', folder_path);
    end

    raw = dir(fullfile(folder_path, '*.csv'));
    files = struct('path',{}, 'name',{}, 'station',{}, 'type',{}, ...
                   'type_str',{}, 'n_epochs',{});

    n_skipped = 0;
    for k = 1:numel(raw)
        info = parse_filename(raw(k).name);
        if ~info.valid
            n_skipped = n_skipped + 1;
            continue;
        end

        % Apply type filter
        if ~isempty(types_filter) && ~ismember(info.type, types_filter)
            continue;
        end

        % Apply station filter
        if ~isempty(stations_filter) && ~ismember(info.station, stations_filter)
            continue;
        end

        entry.path     = fullfile(folder_path, raw(k).name);
        entry.name     = raw(k).name;
        entry.station  = info.station;
        entry.type     = info.type;
        entry.type_str = info.type_str;
        entry.n_epochs = 0;  % populated on load
        files(end+1)   = entry; %#ok<AGROW>
    end

    if verbose
        gnss_log('INFO', 'Folder scan: %d conforming file(s) found | %d skipped (bad name).', ...
            numel(files), n_skipped);
        if numel(files) > 0
            % Print station x type summary
            all_stations = unique({files.station});
            for si = 1:numel(all_stations)
                mask  = strcmp({files.station}, all_stations{si});
                types = {files(mask).type};
                gnss_log('INFO', '  Station %s: %s', all_stations{si}, strjoin(types, ', '));
            end
        end
    end
end


% =========================================================================
%  4.  FILE VALIDATOR
% =========================================================================
function validate_file(filepath)
% VALIDATE_FILE  Strict validation -- throws detailed errors on failure.
%
%   gnss_file_io('validate_file', '/data/YOLA_dlts_txyz.csv')
%
%   Checks:
%     1. File exists
%     2. Filename conforms to convention
%     3. At least 2 columns
%     4. At least 30 finite data rows per component
%     5. No constant (zero-variance) components

    % Existence
    assert(isfile(filepath), 'gnss_file_io:fileNotFound', ...
        'File not found: %s', filepath);

    % Name
    [~, fname, ext] = fileparts(filepath);
    info = parse_filename([fname, ext]);
    assert(info.valid, 'gnss_file_io:invalidName', ...
        'Filename error: %s\nExpected format: <SSSS>_<dlts|hrts|wlts>_txyz.csv', info.error);

    % Content
    T = readtable(filepath, 'VariableNamingRule', 'preserve');
    assert(width(T) >= 2, 'gnss_file_io:tooFewColumns', ...
        'File has %d column(s). Minimum 2 (epoch + 1 coordinate).', width(T));

    n_comps = width(T) - 1;
    for ci = 1:n_comps
        col = T{:, ci+1};
        n_finite = sum(isfinite(col));
        assert(n_finite >= 30, 'gnss_file_io:insufficientData', ...
            'Component %d has only %d finite values (minimum 30).', ci, n_finite);
        assert(std(col(isfinite(col))) > 0, 'gnss_file_io:constantSignal', ...
            'Component %d has zero variance (constant signal).', ci);
    end

    gnss_log('INFO', 'Validation PASSED: %s (%d comps, %d rows)', ...
        [fname, ext], n_comps, height(T));
end


% =========================================================================
%  5.  BATCH PROCESSOR
% =========================================================================
function summary = run_batch(folder_path, methods, params, varargin)
% RUN_BATCH  Process every conforming CSV file in folder_path.
%
%   summary = gnss_file_io('batch', '/data/gnss', {'GPR','RF'}, params)
%   summary = gnss_file_io('batch', '/data/gnss', {'GPR','RF'}, params, ...
%               'OutputFolder', '/results', 'Types', {'dlts'}, 'Parallel', true)
%
%   params struct fields (all optional, defaults shown):
%     .window_size   = 30
%     .num_trees     = 200
%     .optimize      = true
%     .run_cv        = false
%     .learn_rate    = 0.1    (GB)
%     .max_depth     = 3      (GB)
%     .num_neighbors = 5      (KNN)

    %% -- Parse batch options -----------------------------------------------
    bp = inputParser;
    addRequired(bp, 'folder_path', @ischar);
    addRequired(bp, 'methods',     @iscell);
    addRequired(bp, 'params',      @isstruct);
    addParameter(bp, 'OutputFolder',  '',               @ischar);
    addParameter(bp, 'Types',         {'dlts','hrts','wlts'}, @iscell);
    addParameter(bp, 'Stations',      {},               @iscell);
    addParameter(bp, 'Components',    [],               @isnumeric);
    addParameter(bp, 'Parallel',      false,            @islogical);
    addParameter(bp, 'SaveMAT',       true,             @islogical);
    addParameter(bp, 'SaveCSV',       true,             @islogical);
    addParameter(bp, 'Verbose',       true,             @islogical);
    addParameter(bp, 'SignalConfig',  [],               @(x) isempty(x)||isstruct(x));
    parse(bp, folder_path, methods, params, varargin{:});

    out_folder   = bp.Results.OutputFolder;
    types_filter = bp.Results.Types;
    sta_filter   = bp.Results.Stations;
    comp_sel     = bp.Results.Components;
    use_parallel = bp.Results.Parallel;
    save_mat     = bp.Results.SaveMAT;
    save_csv     = bp.Results.SaveCSV;
    verbose      = bp.Results.Verbose;
    sig_cfg_in   = bp.Results.SignalConfig;

    %% -- Default params ---------------------------------------------------
    params = default_params(params);

    %% -- Output folder ----------------------------------------------------
    if isempty(out_folder)
        out_folder = fullfile(folder_path, 'results');
    end
    if ~isfolder(out_folder)
        mkdir(out_folder);
    end

    %% -- Discover files ---------------------------------------------------
    files = scan_folder(folder_path, 'Types', types_filter, ...
                        'Stations', sta_filter, 'Verbose', verbose);

    if isempty(files)
        warning('gnss_file_io:noFiles', ...
            'No conforming files found in %s (types: %s).', ...
            folder_path, strjoin(types_filter, ', '));
        summary = table();
        return;
    end

    n_files  = numel(files);
    n_meths  = numel(methods);

    gnss_log('INFO', '=== GNSS Batch Processing START ===');
    gnss_log('INFO', 'Files: %d | Methods: %s', n_files, strjoin(methods, ', '));
    gnss_log('INFO', 'Output: %s', out_folder);
    t_all = tic;

    %% -- Summary table accumulator ----------------------------------------
    col_names = {'Station','Type','Component','Method', ...
                 'sigma_mm','SNR_dB','NR_pct','RMSE_mm','MAE_mm', ...
                 'AIC','BIC','Normal_residuals','CV_RMSE_mm', ...
                 'Steps_detected','Max_offset_mm'};
    summary_rows = {};

    %% -- Per-station / per-type loop ---------------------------------------
    % Build per-file processing function to allow parfor later
    for fi = 1:n_files
        fpath   = files(fi).path;
        station = files(fi).station;
        ts_type = files(fi).type;

        if verbose
            gnss_log('INFO', '[%d/%d] Station: %s | Type: %s', ...
                fi, n_files, station, ts_type);
        end

        t_file = tic;

        try
            %% Load & validate -------------------------------------------
            [T, finfo] = load_file(fpath, 'Verbose', verbose);
            n_comps    = finfo.n_comps;

            % Resolve component selection
            if isempty(comp_sel)
                comps_todo = 1:n_comps;
            else
                comps_todo = comp_sel(comp_sel <= n_comps);
            end

            % Auto signal config from series type (unless overridden)
            if isempty(sig_cfg_in)
                sig_cfg = type_signal_config(ts_type);
            else
                sig_cfg = sig_cfg_in;
            end

            %% Per-component ML processing --------------------------------
            % Collect results in local cell to support parfor later
            n_c       = numel(comps_todo);
            comp_res  = cell(n_c, n_meths);  % {n_comps x n_methods}
            comp_sigs = cell(n_c, 1);         % denoised signals

            % Auto window size from series type if not user-set
            ws = params.window_size;
            if ws == 0   % sentinel: auto
                ws = type_window_size(ts_type);
            end

            for ci = 1:n_c
                comp_idx  = comps_todo(ci);
                comp_name = finfo.components{comp_idx};
                x_raw     = T{:, comp_name};
                x_raw     = x_raw(:);

                if verbose
                    gnss_log('INFO', '  Component %s (%d/%d) | n=%d', ...
                        comp_name, ci, n_c, length(x_raw));
                end

                % Prepare storage for this component's denoised outputs
                comp_sigs{ci} = table();

                % ---- Classical step detection for this component ----------
                % Run on raw signal so step_info is available for .mat export
                % and per-station summary. Uses the shared detect_steps action.
                step_epochs = [];
                step_info_c = struct('epoch',{},'t_val',{},'F_stat',{},...
                                     'p_val',{},'offset_m',{},'offset_mm',{});
                try
                    % Quick deterministic fit to get residuals for step detection
                    t_idx = (1:length(x_raw))';
                    [resid_for_step, ~] = gnss_ml_utils('fit_deterministic', ...
                        t_idx, x_raw, sig_cfg);
                    [step_epochs, step_info_c] = gnss_ml_utils('detect_steps', ...
                        resid_for_step, t_idx, ...
                        'Alpha', 0.01, 'MinSep', 10, 'MaxSteps', 30, ...
                        'WinSize', 5, 'Prescreen', true);
                    if verbose && ~isempty(step_epochs)
                        offsets = [step_info_c.offset_mm];
                        off_str = strjoin(arrayfun(@(o) sprintf('%+.2f', o), ...
                            offsets, 'UniformOutput', false), ', ');
                        gnss_log('INFO', '  Step detection: %d step(s) | offsets (mm): %s', ...
                            numel(step_epochs), off_str);
                    end
                catch ME_step
                    gnss_log('WARN', '  Step detection skipped: %s', ME_step.message);
                end

                for mi = 1:n_meths
                    mth = methods{mi};
                    if verbose
                        gnss_log('INFO', '    Running %s ...', mth);
                    end
                    t_m = tic;
                    try
                        r = dispatch_method(mth, x_raw, ws, params, sig_cfg);
                        comp_res{ci, mi} = r;

                        % Collect denoised signal column
                        den_col = safe_trim(r.denoised_signal, length(x_raw));
                        colname = strrep(mth, ' ', '_');
                        comp_sigs{ci}.(colname) = den_col;

                        if verbose
                            gnss_log('INFO', ...
                                '    %s done in %.1fs | RMSE=%.6f m | SNR=%.2f dB', ...
                                mth, toc(t_m), r.rmse, r.snr_improvement);
                        end
                    catch ME
                        comp_res{ci, mi} = struct('error', ME.message, 'method', mth);
                        gnss_log('WARN', '    %s FAILED: %s', mth, ME.message);
                    end
                end

                %% Append summary rows for this component ------------------
                for mi = 1:n_meths
                    r = comp_res{ci, mi};
                    % Step count and dominant offset magnitude for this component
                    n_steps_c  = numel(step_epochs);
                    max_off_mm = 0;
                    if ~isempty(step_info_c)
                        max_off_mm = max(abs([step_info_c.offset_mm]));
                    end
                    if isfield(r, 'error')
                        row = {station, ts_type, comp_name, methods{mi}, ...
                               NaN, NaN, NaN, NaN, NaN, NaN, NaN, NaN, NaN, ...
                               n_steps_c, max_off_mm};
                    else
                        cv_r = NaN;
                        if isfield(r, 'cv_rmse') && ~isnan(r.cv_rmse)
                            cv_r = r.cv_rmse * 1000;
                        end
                        row = {station, ts_type, comp_name, methods{mi}, ...
                               r.residual_std  * 1000, ...
                               r.snr_improvement, ...
                               r.noise_reduction, ...
                               r.rmse           * 1000, ...
                               r.mae            * 1000, ...
                               r.aic, ...
                               r.bic, ...
                               double(r.residual_gaussian), ...
                               cv_r, ...
                               n_steps_c, max_off_mm};
                    end
                    summary_rows{end+1} = row; %#ok<AGROW>
                end
                % Store step detection results in comp_res for MAT export
                comp_res{ci, n_meths+1} = struct( ...
                    'step_epochs', step_epochs, ...
                    'step_info',   step_info_c);
            end % component loop

            %% Save per-station .mat ---------------------------------------
            if save_mat
                mat_name = sprintf('%s_%s_results.mat', station, ts_type);
                mat_path = fullfile(out_folder, mat_name);
                save(mat_path, 'comp_res', 'finfo', 'T');
                if verbose
                    gnss_log('INFO', '  Saved MAT: %s', mat_name);
                end
            end

            %% Save per-station denoised CSV ------------------------------
            if save_csv
                write_denoised_csv(out_folder, station, ts_type, T, finfo, ...
                                   comps_todo, comp_sigs, verbose);
            end

            gnss_log('INFO', '[%d/%d] %s_%s complete in %.1fs.', ...
                fi, n_files, station, ts_type, toc(t_file));

        catch ME
            gnss_log('WARN', '[%d/%d] %s_%s FAILED: %s', ...
                fi, n_files, station, ts_type, ME.message);
            % Record failure row
            summary_rows{end+1} = {station, ts_type, 'ALL', 'ALL', ...
                NaN, NaN, NaN, NaN, NaN, NaN, NaN, NaN, NaN, 0, NaN}; %#ok<AGROW>
        end
    end % file loop

    %% -- Assemble & write summary table ------------------------------------
    if ~isempty(summary_rows)
        summary = cell2table(vertcat(summary_rows{:}), 'VariableNames', col_names);

        % Numeric conversion for columns that should be double
        num_cols = {'sigma_mm','SNR_dB','NR_pct','RMSE_mm','MAE_mm', ...
                    'AIC','BIC','Normal_residuals','CV_RMSE_mm', ...
                    'Steps_detected','Max_offset_mm'};
        for nc = 1:numel(num_cols)
            if iscell(summary.(num_cols{nc}))
                summary.(num_cols{nc}) = cell2mat(summary.(num_cols{nc}));
            end
        end

        csv_path = fullfile(out_folder, 'batch_summary.csv');
        writetable(summary, csv_path);
        gnss_log('INFO', 'Batch summary saved: %s', csv_path);

        % Also write per-station sub-summaries
        write_per_station_summaries(summary, out_folder, verbose);
    else
        summary = table();
    end

    total_min = toc(t_all) / 60;
    gnss_log('INFO', '=== Batch COMPLETE: %.1f min | %d file(s) | Output: %s ===', ...
        total_min, n_files, out_folder);
end


% =========================================================================
%  6.  TEMPLATE WRITER
% =========================================================================
function write_template(folder_path, station, type_code, n_epochs)
% WRITE_TEMPLATE  Create a blank, correctly-named template CSV.
%
%   gnss_file_io('write_template', '/data', 'YOLA', 'dlts', 365)
%
%   Writes:  /data/YOLA_dlts_txyz.csv
%            with header: date,X,Y,Z
%            and n_epochs rows of NaN

    valid_types = {'dlts','hrts','wlts'};
    type_code   = lower(type_code);
    station     = upper(station);

    assert(~isempty(regexp(station,'^[A-Z0-9]{4}$','once')), ...
        'gnss_file_io:badStation','Station must be 4 alphanumeric chars.');
    assert(ismember(type_code, valid_types), ...
        'gnss_file_io:badType','Type must be dlts, hrts, or wlts.');

    if nargin < 4 || isempty(n_epochs)
        n_epochs = 365;
    end

    fname = sprintf('%s_%s_txyz.csv', station, type_code);
    fpath = fullfile(folder_path, fname);

    % Build template table
    if strcmp(type_code, 'hrts')
        % High-rate: 30-second epochs starting today
        t0   = datetime('today');
        dv   = t0 + seconds(0:30:(n_epochs-1)*30)';
        dstr = cellstr(datestr(dv, 'yyyy-mm-dd HH:MM:SS'));
    elseif strcmp(type_code, 'wlts')
        t0   = datetime('today');
        dv   = t0 + days(7*(0:n_epochs-1))';
        dstr = cellstr(datestr(dv, 'yyyy-mm-dd'));
    else
        t0   = datetime('today');
        dv   = t0 + days(0:n_epochs-1)';
        dstr = cellstr(datestr(dv, 'yyyy-mm-dd'));
    end

    T_tmpl = table(dstr, nan(n_epochs,1), nan(n_epochs,1), nan(n_epochs,1), ...
                   'VariableNames', {'date','X','Y','Z'});
    writetable(T_tmpl, fpath);
    gnss_log('INFO', 'Template written: %s (%d epochs)', fpath, n_epochs);
end


% =========================================================================
%  PRIVATE HELPERS
% =========================================================================

function params = default_params(params)
% DEFAULT_PARAMS  Fill missing fields with sensible defaults.
    if ~isfield(params, 'window_size'),   params.window_size   = 30;   end
    if ~isfield(params, 'num_trees'),     params.num_trees     = 200;  end
    if ~isfield(params, 'optimize'),      params.optimize      = true; end
    if ~isfield(params, 'run_cv'),        params.run_cv        = false;end
    if ~isfield(params, 'learn_rate'),    params.learn_rate    = 0.1;  end
    if ~isfield(params, 'max_depth'),     params.max_depth     = 3;    end
    if ~isfield(params, 'num_neighbors'), params.num_neighbors = 5;    end
    if ~isfield(params, 'max_evals'),     params.max_evals     = 10;   end
end


function ws = type_window_size(type_code)
% TYPE_WINDOW_SIZE  Recommended sliding-window width for each series type.
    switch lower(type_code)
        case 'dlts', ws = 30;   % 30 daily samples ~ 1 month
        case 'hrts', ws = 120;  % 120 x 30 s = 60 min
        case 'wlts', ws = 12;   % 12 weekly samples ~ 3 months
        otherwise,   ws = 30;
    end
end


function cfg = type_signal_config(type_code)
% TYPE_SIGNAL_CONFIG  Auto-select appropriate signal configuration.
%   Daily data: full seasonal model recommended.
%   High-rate:  only intra-day signals matter (S1, S2 atm tides).
%   Weekly:     annual + semi-annual; disable short-period signals.
    cfg = gnss_ml_utils('default_signal_config');
    switch lower(type_code)
        case 'hrts'
            % High-rate: sub-daily, switch off multi-day seasonals
            cfg.annual       = false;
            cfg.semi_annual  = false;
            cfg.s1_atm       = true;
            cfg.s2_atm       = true;
        case 'wlts'
            % Weekly: fewer samples, keep only robust signals
            cfg.annual      = true;
            cfg.semi_annual = true;
            cfg.ter_annual  = false;
            cfg.quarterly   = false;
        % 'dlts': use defaults (annual + semi-annual ON)
    end
end


function r = dispatch_method(method, x, window_size, params, sig_cfg)
% DISPATCH_METHOD  Call the correct denoiser function.
    switch upper(strtrim(method))
        case 'GPR'
            r = gnss_gpr_denoiser(x, ...
                'OptimizeHyperparameters', params.optimize, ...
                'MaxEvaluations',          params.max_evals, ...
                'RunCV',                   params.run_cv, ...
                'SignalConfig',            sig_cfg, ...
                'Verbose',                 false);

        case 'SVR'
            r = gnss_svr_denoiser(x, ...
                'WindowSize',              window_size, ...
                'OptimizeHyperparameters', params.optimize, ...
                'MaxEvaluations',          params.max_evals, ...
                'RunCV',                   params.run_cv, ...
                'SignalConfig',            sig_cfg, ...
                'Verbose',                 false);

        case {'RF','RANDOM FOREST','RANDOMFOREST'}
            r = gnss_rf_denoiser(x, ...
                'WindowSize',  window_size, ...
                'NumTrees',    params.num_trees, ...
                'RunCV',       params.run_cv, ...
                'SignalConfig', sig_cfg, ...
                'Verbose',     false);

        case {'GB','GRADIENT BOOSTING','GRADIENTBOOSTING'}
            r = gnss_gb_denoiser(x, ...
                'WindowSize',  window_size, ...
                'NumTrees',    params.num_trees, ...
                'LearnRate',   params.learn_rate, ...
                'MaxDepth',    params.max_depth, ...
                'RunCV',       params.run_cv, ...
                'SignalConfig', sig_cfg, ...
                'Verbose',     false);

        case 'KNN'
            r = gnss_knn_denoiser(x, ...
                'WindowSize',   window_size, ...
                'NumNeighbors', params.num_neighbors, ...
                'RunCV',        params.run_cv, ...
                'SignalConfig',  sig_cfg, ...
                'Verbose',      false);

        otherwise
            error('gnss_file_io:unknownMethod', ...
                'Method "%s" not recognised. Valid: GPR, SVR, RF, GB, KNN.', method);
    end
end


function write_denoised_csv(out_folder, station, ts_type, T, finfo, ...
                             comps_todo, comp_sigs, verbose)
% WRITE_DENOISED_CSV  Save a per-station CSV with original + denoised columns.
%
%   Output filename: <STATION>_<type>_denoised.csv
%   Columns: date/epoch | X | Y | Z | X_GPR | X_SVR | ... | Y_GPR | ...

    out_name = sprintf('%s_%s_denoised.csv', station, ts_type);
    out_path = fullfile(out_folder, out_name);

    % Start with epoch / date column
    T_out = T(:, 1);  % date or epoch column

    n_c = numel(comps_todo);
    for ci = 1:n_c
        comp_name = finfo.components{comps_todo(ci)};
        % Original signal
        T_out.(comp_name) = T.(comp_name);
        % Denoised columns
        if ~isempty(comp_sigs{ci})
            den_fields = fieldnames(comp_sigs{ci});
            for df = 1:numel(den_fields)
                new_col = sprintf('%s_%s', comp_name, den_fields{df});
                T_out.(new_col) = comp_sigs{ci}.(den_fields{df});
            end
        end
    end

    writetable(T_out, out_path);
    if verbose
        gnss_log('INFO', '  Saved denoised CSV: %s', out_name);
    end
end


function write_per_station_summaries(summary, out_folder, verbose)
% WRITE_PER_STATION_SUMMARIES  One CSV per station showing method comparison.
    stations = unique(summary.Station);
    for si = 1:numel(stations)
        sta = stations{si};
        sub = summary(strcmp(summary.Station, sta), :);
        fname = sprintf('%s_summary.csv', sta);
        writetable(sub, fullfile(out_folder, fname));
        if verbose
            gnss_log('INFO', '  Station summary: %s', fname);
        end
    end
end


function v = safe_trim(v, target_len)
% SAFE_TRIM  Force signal to exactly target_len samples.
    v = v(:);
    n = length(v);
    if n == target_len
        return;
    elseif n > target_len
        v = v(1:target_len);
    else
        v = [v; repmat(v(end), target_len - n, 1)];
    end
end


function gnss_log(level, fmt, varargin)
% GNSS_LOG  Minimal logger (mirrors gnss_ml_utils log).
    msg  = sprintf(fmt, varargin{:});
    line = sprintf('[%s][%s] %s\n', datestr(now,'HH:MM:SS'), upper(level), msg);
    fprintf('%s', line);
end
