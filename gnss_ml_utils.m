function varargout = gnss_ml_utils(action, varargin)
% GNSS_ML_UTILS  Shared utility library for all GNSS ML denoising methods.
%
%   Version 3.0 -- Extended deterministic model with configurable periodic signals.
%
%   New in v3.0:
%     fit_deterministic now accepts an optional signal_config struct that
%     activates/deactivates individual geodetic periodic signals organised
%     into five groups:
%       1. Seasonal harmonics (annual, semi-annual, ter-annual, quarterly)
%       2. GPS/GNSS draconitic harmonics (up to 8 terms)
%       3. Tidal / OTL aliases (fortnightly, monthly, Chandler wobble)
%       4. Atmospheric loading (S1, S2, MJO)
%       5. Inter-annual signals (ENSO proxy)
%
%   Usage:
%     [X, Y, meta] = gnss_ml_utils('build_features', data, window_size)
%     [X, Y, meta] = gnss_ml_utils('build_features', data, window_size, signal_config)
%     metrics      = gnss_ml_utils('compute_metrics', data, denoised, method_name)
%     [x_clean, outlier_idx] = gnss_ml_utils('remove_outliers', x, k_iqr)
%     [residuals, det_model] = gnss_ml_utils('fit_deterministic', t, x)
%     [residuals, det_model] = gnss_ml_utils('fit_deterministic', t, x, signal_config)
%     cfg          = gnss_ml_utils('default_signal_config')
%     gnss_ml_utils('log', level, fmt, varargin)
%     cv_rmse      = gnss_ml_utils('timeseries_cv', X, Y, model_fn, k_folds)
%
%   signal_config fields (all logical, default shown):
%     Seasonal:
%       .annual          = true   365.25 days
%       .semi_annual     = true   182.63 days
%       .ter_annual      = false  121.75 days
%       .quarterly       = false   91.31 days
%     Draconitic:
%       .draconitic_1    = false  351.4 days (GPS 1st harmonic)
%       .draconitic_2    = false  175.7 days
%       .draconitic_3    = false  117.1 days
%       .draconitic_4    = false   87.9 days
%       .draconitic_5    = false   70.3 days
%       .draconitic_6    = false   58.6 days
%       .draconitic_7    = false   50.2 days
%       .draconitic_8    = false   43.9 days
%     Tidal / OTL aliases:
%       .mf_tidal        = false   13.661 days (M2/O1 OTL alias)
%       .msf_tidal       = false   14.765 days (M2 OTL alias)
%       .mm_tidal        = false   27.555 days (Mm / monthly)
%       .msm_tidal       = false   31.812 days
%       .chandler        = false  432.2  days (Chandler wobble)
%     Atmospheric loading:
%       .s1_atm          = false    1.003 days (S1 atm tide alias)
%       .s2_atm          = false    0.501 days (S2 atm tide alias)
%       .mjo             = false   45.0   days (MJO proxy, mid-period)
%     Inter-annual:
%       .enso            = false 1461.0   days (ENSO ~4-year proxy)
%       .nodal_18yr      = false 6798.4   days (18.6-year nodal tide)
%
% Author:  Dr. Ahmed Mohammed
%          Department of Surveying and Geoinformatics,
%          Modibbo Adama University, Yola
% Date:    2026

    switch lower(action)
        case 'build_features'
            [varargout{1}, varargout{2}, varargout{3}] = build_features(varargin{:});
        case 'compute_metrics'
            varargout{1} = compute_metrics(varargin{:});
        case 'remove_outliers'
            [varargout{1}, varargout{2}] = remove_outliers(varargin{:});
        case 'fit_deterministic'
            [varargout{1}, varargout{2}] = fit_deterministic(varargin{:});
        case 'fit_denoised'
            varargout{1} = fit_denoised(varargin{:});
        case 'default_signal_config'
            varargout{1} = default_signal_config();
        case 'default_period_search_config'
            varargout{1} = default_period_search_config();
        case 'detect_periods'
            varargout{1} = detect_periods(varargin{:});
        case 'log'
            gnss_log(varargin{:});
        case 'timeseries_cv'
            varargout{1} = timeseries_cv(varargin{:});
        case 'save_publication_figure'
            save_publication_figure(varargin{:});
        otherwise
            error('gnss_ml_utils:unknownAction', 'Unknown action: %s', action);
    end
end


% =========================================================================
%  DEFAULT SIGNAL CONFIGURATION
% =========================================================================
function cfg = default_signal_config()
% DEFAULT_SIGNAL_CONFIG  Returns default config with only standard signals on.
%
%   All signals default to OFF except annual and semi-annual, which are the
%   minimum geodetically correct pre-processing for any GNSS series.
%   The App Designer GUI reads and writes this struct directly.

    % --- Group 1: Seasonal harmonics ----------------------------------------
    cfg.annual          = true;    % 365.25 days  -- always recommended
    cfg.semi_annual     = true;    % 182.63 days  -- always recommended
    cfg.ter_annual      = false;   % 121.75 days
    cfg.quarterly       = false;   %  91.31 days

    % --- Group 2: GPS draconitic harmonics ----------------------------------
    cfg.draconitic_1    = false;   % 351.40 days  1st harmonic
    cfg.draconitic_2    = false;   % 175.70 days  2nd harmonic
    cfg.draconitic_3    = false;   % 117.13 days  3rd harmonic
    cfg.draconitic_4    = false;   %  87.85 days  4th harmonic
    cfg.draconitic_5    = false;   %  70.28 days  5th harmonic
    cfg.draconitic_6    = false;   %  58.57 days  6th harmonic
    cfg.draconitic_7    = false;   %  50.20 days  7th harmonic
    cfg.draconitic_8    = false;   %  43.93 days  8th harmonic

    % --- Group 3: Tidal / OTL alias signals ---------------------------------
    cfg.mf_tidal        = false;   %  13.661 days  M2/O1 OTL alias fortnightly
    cfg.msf_tidal       = false;   %  14.765 days  MSf / M2 OTL alias fortnightly
    cfg.mm_tidal        = false;   %  27.555 days  Mm monthly tidal
    cfg.msm_tidal       = false;   %  31.812 days  MSm monthly tidal
    cfg.chandler        = false;   % 432.200 days  Chandler wobble

    % --- Group 4: Atmospheric loading signals -------------------------------
    cfg.s1_atm          = false;   %   1.003 days  S1 atmospheric tide alias
    cfg.s2_atm          = false;   %   0.501 days  S2 atmospheric tide alias
    cfg.mjo             = false;   %  45.000 days  MJO proxy (mid-period)

    % --- Group 5: Inter-annual signals --------------------------------------
    cfg.enso            = false;   % 1461.0 days   ENSO ~4-year proxy
    cfg.nodal_18yr      = false;   % 6798.4 days   18.6-year lunar nodal tide

    % --- Group 6: Sub-daily OTL (for high-rate / hrts data only) -----------
    %   True tidal constituent periods expressed in fractional days.
    %   For daily solutions these appear as aliases handled by Groups 3/4 above.
    %   All default OFF; auto-enabled by gnss_file_io type_signal_config for hrts.
    cfg.m2_otl          = false;   % 0.5175 d  M2  principal lunar semi-diurnal OTL
    cfg.s2_otl          = false;   % 0.5000 d  S2  principal solar  semi-diurnal OTL
    cfg.k2_otl          = false;   % 0.4986 d  K2  lunisolar        semi-diurnal OTL
    cfg.n2_otl          = false;   % 0.5274 d  N2  larger elliptic  semi-diurnal OTL
    cfg.k1_otl          = false;   % 0.9972 d  K1  lunisolar        diurnal OTL
    cfg.o1_otl          = false;   % 1.0758 d  O1  principal lunar  diurnal OTL
    cfg.p1_otl          = false;   % 1.0028 d  P1  principal solar  diurnal OTL
    cfg.q1_otl          = false;   % 1.1195 d  Q1  larger elliptic  diurnal OTL
    cfg.s3_atm          = false;   % 0.3333 d  S3  atmospheric terdiurnal
    cfg.s4_atm          = false;   % 0.2500 d  S4  atmospheric quarterdiurnal
end


% =========================================================================
%  PERIOD SEARCH CONFIGURATION
% =========================================================================
function psc = default_period_search_config()
% DEFAULT_PERIOD_SEARCH_CONFIG  Per-signal period search tolerances and strategy.
%
%   For each signal the config defines:
%     .mode   - 'fixed'  : use nominal period exactly (no search)
%               'search' : search within [nominal - tol, nominal + tol] days
%               'skip'   : never fit this signal regardless of signal_config
%
%     .tol    - half-width of search window in DAYS (only used when mode='search')
%
%     .fap_thresh - false alarm probability threshold for peak acceptance (0-1).
%                   If the best peak in the window has FAP > fap_thresh the
%                   signal falls back to the nominal period rather than being
%                   skipped.  Default 0.10 (10%%).
%
%   Design rationale (from geodetic literature):
%     - Astronomical tides (Mf, MSf, Mm, MSm) are gravitationally forced:
%       their frequencies are known to < 1e-6 cycles/day.  mode='fixed'.
%     - Annual/semi-annual are geophysically forced and show station-dependent
%       shifts of +-2..5 days due to regional loading phase.  mode='search'.
%     - GPS draconitic year varies +-0.5..2 d depending on GPS week and
%       station latitude.  mode='search' with tight tolerance.
%     - Chandler wobble period drifts between 430-435 d.  mode='search'.
%     - MJO and ENSO are quasi-periodic; a +-20%% search window is used.
%       The detected period is station- and epoch-specific.
%
%   GUI NOTE: The period search mode and tolerance for each signal can be
%   overridden in Tabs 2 and 3 via the Advanced Period Search panel.

    % --- Group 1: Seasonal harmonics ----------------------------------------
    psc.annual.mode        = 'search';   psc.annual.tol        =  5.0;
    psc.annual.fap_thresh  = 0.10;

    psc.semi_annual.mode   = 'search';   psc.semi_annual.tol   =  3.0;
    psc.semi_annual.fap_thresh = 0.10;

    psc.ter_annual.mode    = 'search';   psc.ter_annual.tol    =  2.0;
    psc.ter_annual.fap_thresh = 0.10;

    psc.quarterly.mode     = 'search';   psc.quarterly.tol     =  1.5;
    psc.quarterly.fap_thresh = 0.10;

    % --- Group 2: GPS draconitic harmonics ----------------------------------
    % Tolerance scales with harmonic number (higher harmonics are less stable)
    psc.draconitic_1.mode  = 'search';   psc.draconitic_1.tol  =  2.0;
    psc.draconitic_1.fap_thresh = 0.10;

    psc.draconitic_2.mode  = 'search';   psc.draconitic_2.tol  =  1.5;
    psc.draconitic_2.fap_thresh = 0.10;

    psc.draconitic_3.mode  = 'search';   psc.draconitic_3.tol  =  1.2;
    psc.draconitic_3.fap_thresh = 0.10;

    psc.draconitic_4.mode  = 'search';   psc.draconitic_4.tol  =  1.0;
    psc.draconitic_4.fap_thresh = 0.15;

    psc.draconitic_5.mode  = 'search';   psc.draconitic_5.tol  =  0.8;
    psc.draconitic_5.fap_thresh = 0.15;

    psc.draconitic_6.mode  = 'search';   psc.draconitic_6.tol  =  0.7;
    psc.draconitic_6.fap_thresh = 0.20;

    psc.draconitic_7.mode  = 'search';   psc.draconitic_7.tol  =  0.6;
    psc.draconitic_7.fap_thresh = 0.20;

    psc.draconitic_8.mode  = 'search';   psc.draconitic_8.tol  =  0.5;
    psc.draconitic_8.fap_thresh = 0.20;

    % --- Group 3: Tidal / OTL aliases (astronomically determined) ----------
    % These are known to < 0.05 days -- use fixed periods
    psc.mf_tidal.mode      = 'fixed';    psc.mf_tidal.tol      =  0.05;
    psc.mf_tidal.fap_thresh = 0.10;

    psc.msf_tidal.mode     = 'fixed';    psc.msf_tidal.tol     =  0.05;
    psc.msf_tidal.fap_thresh = 0.10;

    psc.mm_tidal.mode      = 'fixed';    psc.mm_tidal.tol      =  0.05;
    psc.mm_tidal.fap_thresh = 0.10;

    psc.msm_tidal.mode     = 'fixed';    psc.msm_tidal.tol     =  0.05;
    psc.msm_tidal.fap_thresh = 0.10;

    % Chandler wobble: known to drift between 430-435 days
    psc.chandler.mode      = 'search';   psc.chandler.tol      =  6.0;
    psc.chandler.fap_thresh = 0.15;

    % --- Group 4: Atmospheric loading ---------------------------------------
    % S1/S2 atmospheric tides: alias periods are stable
    psc.s1_atm.mode        = 'fixed';    psc.s1_atm.tol        =  0.01;
    psc.s1_atm.fap_thresh  = 0.10;

    psc.s2_atm.mode        = 'fixed';    psc.s2_atm.tol        =  0.01;
    psc.s2_atm.fap_thresh  = 0.10;

    % MJO: broad quasi-periodic signal, 30-90 day range
    psc.mjo.mode           = 'search';   psc.mjo.tol           = 20.0;
    psc.mjo.fap_thresh     = 0.20;

    % --- Group 5: Inter-annual ----------------------------------------------
    % ENSO: quasi-periodic ~2-7 year (730-2555 days); use wide 20%% window
    psc.enso.mode          = 'search';   psc.enso.tol          = 200.0;
    psc.enso.fap_thresh    = 0.20;

    % 18.6-yr nodal: astronomically forced, very stable
    psc.nodal_18yr.mode    = 'fixed';    psc.nodal_18yr.tol    =   5.0;
    psc.nodal_18yr.fap_thresh = 0.10;

    % --- Group 6: Sub-daily OTL (astronomically determined) ----------------
    % All tidal constituents use fixed periods -- frequencies known to < 1e-7 cpd.
    psc.m2_otl.mode    = 'fixed';  psc.m2_otl.tol    = 0.001;  psc.m2_otl.fap_thresh  = 0.10;
    psc.s2_otl.mode    = 'fixed';  psc.s2_otl.tol    = 0.001;  psc.s2_otl.fap_thresh  = 0.10;
    psc.k2_otl.mode    = 'fixed';  psc.k2_otl.tol    = 0.001;  psc.k2_otl.fap_thresh  = 0.10;
    psc.n2_otl.mode    = 'fixed';  psc.n2_otl.tol    = 0.001;  psc.n2_otl.fap_thresh  = 0.10;
    psc.k1_otl.mode    = 'fixed';  psc.k1_otl.tol    = 0.001;  psc.k1_otl.fap_thresh  = 0.10;
    psc.o1_otl.mode    = 'fixed';  psc.o1_otl.tol    = 0.001;  psc.o1_otl.fap_thresh  = 0.10;
    psc.p1_otl.mode    = 'fixed';  psc.p1_otl.tol    = 0.001;  psc.p1_otl.fap_thresh  = 0.10;
    psc.q1_otl.mode    = 'fixed';  psc.q1_otl.tol    = 0.001;  psc.q1_otl.fap_thresh  = 0.10;
    % Atmospheric sub-daily: solar-forced, fixed
    psc.s3_atm.mode    = 'fixed';  psc.s3_atm.tol    = 0.001;  psc.s3_atm.fap_thresh  = 0.10;
    psc.s4_atm.mode    = 'fixed';  psc.s4_atm.tol    = 0.001;  psc.s4_atm.fap_thresh  = 0.10;
end


% =========================================================================
%  PERIOD DETECTION (Lomb-Scargle peak search within tolerance window)
% =========================================================================
function results = detect_periods(t, x, signal_config, period_search_config)
% DETECT_PERIODS  Auto-detect best-fit period for each enabled signal.
%
%   For signals with mode='search', fits a dense Lomb-Scargle periodogram
%   within the tolerance window [T_nom - tol, T_nom + tol] and returns the
%   period of the highest peak.  For mode='fixed' signals returns T_nom.
%
%   Inputs:
%     t                   - epoch vector (days)
%     x                   - pre-detrended series (remove trend first for clarity)
%     signal_config       - from default_signal_config()
%     period_search_config- from default_period_search_config()
%
%   Output:
%     results  - struct array, one entry per enabled signal:
%       .field        - signal field name (e.g. 'annual')
%       .T_nominal    - nominal period (days)
%       .T_detected   - detected best-fit period (days)
%       .T_used       - period actually used in fitting (= detected or nominal)
%       .peak_power   - Lomb-Scargle power at T_detected
%       .fap          - false alarm probability at T_detected
%       .mode         - 'fixed' | 'search' | 'fallback'
%       .search_range - [T_lo, T_hi] actually searched
%       .label        - human-readable label

    if nargin < 4
        period_search_config = default_period_search_config();
    end

    t = t(:);
    x = x(:);
    n = length(t);

    % Signal catalogue: same order as fit_deterministic
    CATALOGUE = {
        'annual',       365.250, 'Annual (365.25 d)';
        'semi_annual',  182.625, 'Semi-annual (182.63 d)';
        'ter_annual',   121.750, 'Ter-annual (121.75 d)';
        'quarterly',     91.313, 'Quarterly (91.31 d)';
        'draconitic_1', 351.400, 'Draconitic 1 (351.4 d)';
        'draconitic_2', 175.700, 'Draconitic 2 (175.7 d)';
        'draconitic_3', 117.133, 'Draconitic 3 (117.1 d)';
        'draconitic_4',  87.850, 'Draconitic 4 (87.9 d)';
        'draconitic_5',  70.280, 'Draconitic 5 (70.3 d)';
        'draconitic_6',  58.567, 'Draconitic 6 (58.6 d)';
        'draconitic_7',  50.200, 'Draconitic 7 (50.2 d)';
        'draconitic_8',  43.925, 'Draconitic 8 (43.9 d)';
        'mf_tidal',      13.661, 'Mf tidal alias (13.66 d)';
        'msf_tidal',     14.765, 'MSf tidal alias (14.77 d)';
        'mm_tidal',      27.555, 'Mm monthly tidal (27.56 d)';
        'msm_tidal',     31.812, 'MSm monthly tidal (31.81 d)';
        'chandler',     432.200, 'Chandler wobble (432.2 d)';
        's1_atm',         1.003, 'S1 atm tide alias (1.003 d)';
        's2_atm',         0.501, 'S2 atm tide alias (0.501 d)';
        'mjo',           45.000, 'MJO proxy (45.0 d)';
        'enso',        1461.000, 'ENSO proxy (1461 d)';
        'nodal_18yr',  6798.400, '18.6-yr nodal (6798 d)';
        % Group 6: Sub-daily OTL (true tidal periods in fractional days)
        'm2_otl',         0.5175, 'M2 OTL semi-diurnal (0.5175 d)';
        's2_otl',         0.5000, 'S2 OTL semi-diurnal (0.5000 d)';
        'k2_otl',         0.4986, 'K2 OTL semi-diurnal (0.4986 d)';
        'n2_otl',         0.5274, 'N2 OTL semi-diurnal (0.5274 d)';
        'k1_otl',         0.9972, 'K1 OTL diurnal (0.9972 d)';
        'o1_otl',         1.0758, 'O1 OTL diurnal (1.0758 d)';
        'p1_otl',         1.0028, 'P1 OTL diurnal (1.0028 d)';
        'q1_otl',         1.1195, 'Q1 OTL diurnal (1.1195 d)';
        's3_atm',         0.3333, 'S3 atm terdiurnal (0.3333 d)';
        's4_atm',         0.2500, 'S4 atm quarterdiurnal (0.2500 d)';
    };

    % Time span for minimum-cycle check
    t_norm    = t - t(1);
    span_days = t_norm(end);
    % Time in years for plomb (frequencies in cpy)
    t_yrs     = t_norm / 365.25;

    results = struct('field',{},'T_nominal',{},'T_detected',{},'T_used',{}, ...
                     'peak_power',{},'fap',{},'mode',{},'search_range',{}, ...
                     'amplitude_mm',{},'label',{});
    ri = 0;

    for k = 1:size(CATALOGUE, 1)
        field   = CATALOGUE{k,1};
        T_nom   = CATALOGUE{k,2};
        label   = CATALOGUE{k,3};

        % Only process enabled signals
        if ~isfield(signal_config, field) || ~signal_config.(field)
            continue;
        end
        % Span guard: need >= 2 full cycles
        if span_days < 2 * T_nom
            continue;
        end

        ri = ri + 1;
        results(ri).field     = field;
        results(ri).T_nominal = T_nom;
        results(ri).label     = label;

        % Get per-signal search config
        if isfield(period_search_config, field)
            psc_sig = period_search_config.(field);
        else
            psc_sig = struct('mode','fixed','tol',0,'fap_thresh',0.10);
        end

        if strcmp(psc_sig.mode, 'fixed')
            % ---- Fixed period: just return nominal -------------------------
            results(ri).T_detected   = T_nom;
            results(ri).T_used       = T_nom;
            results(ri).search_range = [T_nom, T_nom];
            results(ri).mode         = 'fixed';
            results(ri).peak_power   = NaN;
            results(ri).fap          = NaN;

            % Still estimate amplitude via OLS for reporting
            coef_s = [cos(2*pi/T_nom * t_norm), sin(2*pi/T_nom * t_norm)] \ x;
            results(ri).amplitude_mm = sqrt(coef_s(1)^2 + coef_s(2)^2) * 1000;

        else
            % ---- Search mode: scan period window with dense LS ------------
            tol    = psc_sig.tol;
            T_lo   = max(T_nom - tol, span_days / floor(span_days / (T_nom - tol) + 1) + 0.01);
            T_hi   = T_nom + tol;
            T_lo   = max(T_lo, 2.0);   % never go below 2 days
            results(ri).search_range = [T_lo, T_hi];

            % Convert to frequency range in cpy for plomb
            f_lo_cpy = 365.25 / T_hi;
            f_hi_cpy = 365.25 / T_lo;

            % Dense frequency grid: at least 500 points across the window
            n_grid   = max(500, round((f_hi_cpy - f_lo_cpy) * span_days * 4));
            f_grid   = linspace(f_lo_cpy, f_hi_cpy, n_grid);

            try
                [pxx_w, f_w] = plomb(x, t_yrs, f_grid);
                [peak_pow, idx_peak] = max(pxx_w);
                T_det = 365.25 / f_w(idx_peak);

                % FAP: chi-squared approximation (Scargle 1982)
                M_eff = n_grid;   % number of independent frequencies tested
                fap   = 1 - (1 - exp(-peak_pow))^M_eff;
                fap   = max(min(fap, 1), 0);

                results(ri).peak_power = peak_pow;
                results(ri).fap        = fap;

                if fap <= psc_sig.fap_thresh
                    % Peak is statistically significant -- use detected period
                    results(ri).T_detected = T_det;
                    results(ri).T_used     = T_det;
                    results(ri).mode       = 'search';
                else
                    % Peak not significant -- fall back to nominal period
                    T_det = T_nom;
                    results(ri).T_detected = T_det;
                    results(ri).T_used     = T_nom;
                    results(ri).mode       = 'fallback';
                end
            catch
                % plomb failed (e.g. too few points in window)
                results(ri).T_detected = T_nom;
                results(ri).T_used     = T_nom;
                results(ri).mode       = 'fallback';
                results(ri).peak_power = NaN;
                results(ri).fap        = NaN;
                T_det = T_nom;
            end

            % Amplitude estimate at used period
            T_use = results(ri).T_used;
            coef_s = [cos(2*pi/T_use * t_norm), sin(2*pi/T_use * t_norm)] \ x;
            results(ri).amplitude_mm = sqrt(coef_s(1)^2 + coef_s(2)^2) * 1000;
        end
    end
end


% =========================================================================
%  1.  EXTENDED DETERMINISTIC MODEL
% =========================================================================
function [residuals, det_model] = fit_deterministic(t, x, signal_config)
% FIT_DETERMINISTIC  Remove configurable set of geodetic periodic signals.
%
%   Constructs a least-squares design matrix containing exactly the signals
%   enabled in signal_config, solves for amplitudes and phases, removes the
%   fitted model, and returns the residual series and full model struct.
%
%   Inputs:
%     t             - epoch vector (days from any reference)
%     x             - coordinate column vector (metres)
%     signal_config - struct from default_signal_config() with true/false
%                     fields.  Uses default (annual + semi-annual only) if
%                     omitted.
%
%   Outputs:
%     residuals  - x minus the fitted deterministic model
%     det_model  - struct with all fitted components and metadata

    if nargin < 3
        signal_config = default_signal_config();
    end

    x      = x(:);
    t      = t(:);
    n      = length(x);
    t_ref  = t(1);
    t_norm = t - t_ref;   % normalise for numerical stability

    % --- Determine period_search_config ------------------------------------
    % Extract from signal_config if present, else use defaults
    if isfield(signal_config, 'period_search')
        psc = signal_config.period_search;
    else
        psc = default_period_search_config();
    end

    % --- Pre-detrend for period detection (linear only) --------------------
    % Using a rough linear detrend so detect_periods sees a cleaner spectrum.
    % The full OLS below uses the original x.
    trend_coef  = polyfit(t_norm, x, 1);
    x_detrended = x - polyval(trend_coef, t_norm);

    % --- Run period detection for each active signal -----------------------
    % detect_periods returns the T_used (nominal or LS-detected) per signal
    det_res = detect_periods(t, x_detrended, signal_config, psc);

    % --- Build design matrix using detected periods -------------------------
    A_cols = {ones(n,1), t_norm};   % always: offset + velocity
    active_signals  = {};
    active_periods  = [];
    active_labels   = {};
    detected_periods = struct();    % store for reporting

    for ki = 1:length(det_res)
        field  = det_res(ki).field;
        T_use  = det_res(ki).T_used;
        label  = det_res(ki).label;
        dmode  = det_res(ki).mode;

        A_cols{end+1} = cos(2*pi/T_use * t_norm); %#ok<AGROW>
        A_cols{end+1} = sin(2*pi/T_use * t_norm); %#ok<AGROW>
        active_signals{end+1} = field;             %#ok<AGROW>
        active_periods(end+1) = T_use;             %#ok<AGROW>
        if strcmp(dmode,'search')
            active_labels{end+1} = sprintf('%s [det=%.3fd]', label, T_use); %#ok<AGROW>
        elseif strcmp(dmode,'fallback')
            active_labels{end+1} = sprintf('%s [fallback]', label);         %#ok<AGROW>
        else
            active_labels{end+1} = label;                                    %#ok<AGROW>
        end
        detected_periods.(field) = det_res(ki);
    end

    % --- OLS solution -------------------------------------------------------
    A    = [A_cols{:}];
    coef = A \ x;
    fit  = A * coef;

    % --- Velocity uncertainty (formal OLS + noise-model scaling) -----------
    % Step 1: formal OLS variance-covariance matrix
    %   C = sigma_res^2 * (A'A)^{-1}
    % Step 2: extract formal sigma for the rate coefficient (column 2 of A)
    % Step 3: scale by a noise-model factor that accounts for temporal
    %   correlation in the residuals.  For a power-law noise process with
    %   spectral index k the effective number of independent observations is
    %   approximately n_eff = n * (1 - rho) / (1 + rho) where rho is the
    %   lag-1 autocorrelation of the residuals (Williams 2003 approximation).
    %   The scaling factor is sqrt(n / n_eff).
    resid_ols  = x - fit;
    sigma_res  = std(resid_ols);
    n_params   = size(A, 2);
    dof        = max(n - n_params, 1);
    sigma2_res = sum(resid_ols.^2) / dof;   % unbiased residual variance

    % Formal (white-noise) covariance of coefficients
    try
        AtA_inv = inv(A' * A);
        vel_var_formal = sigma2_res * AtA_inv(2, 2);   % variance of rate coef
    catch
        vel_var_formal = NaN;
    end

    % Noise-model scaling: lag-1 autocorrelation of residuals
    % Gives a realistic uncertainty that accounts for temporal correlation.
    % Scale factor amplifies formal sigma when residuals are correlated (rho>0).
    try
        rho_lag1 = corr(resid_ols(1:end-1), resid_ols(2:end));
        rho_lag1 = max(-0.99, min(0.99, rho_lag1));   % clamp to (-1,1)
        if rho_lag1 > 0
            n_eff       = max(2, n * (1 - rho_lag1) / (1 + rho_lag1));
            scale_factor = sqrt(n / n_eff);
        else
            scale_factor = 1;   % anti-correlated: formal sigma is conservative
        end
        vel_sigma_m_day  = sqrt(vel_var_formal) * scale_factor;
    catch
        vel_sigma_m_day  = sqrt(vel_var_formal);
        scale_factor     = 1;
    end

    % Convert from m/day to mm/yr (same unit as velocity)
    vel_uncertainty = vel_sigma_m_day * 365.25 * 1000;   % mm/yr (1-sigma)

    % --- Assemble det_model struct ------------------------------------------
    det_model.fit              = fit;
    det_model.trend            = coef(1) + coef(2)*t_norm;
    det_model.velocity         = coef(2) * 365.25 * 1000;   % mm/yr
    det_model.vel_uncertainty  = vel_uncertainty;            % mm/yr (1-sigma)
    det_model.vel_scale_factor = scale_factor;               % noise scaling
    det_model.coef             = coef;
    det_model.t_ref            = t_ref;
    det_model.active_signals   = active_signals;
    det_model.active_periods   = active_periods;
    det_model.active_labels    = active_labels;
    det_model.signal_config    = signal_config;
    det_model.n_params         = length(coef);
    det_model.detected_periods = detected_periods;   % struct with per-signal detection results

    % --- Reconstruct individual components ----------------------------------
    % Initialise all components to zero (even inactive ones, for compatibility)
    component_fields = {'annual','semi_annual','ter_annual','quarterly', ...
                        'draconitic_1','draconitic_2','draconitic_3','draconitic_4', ...
                        'draconitic_5','draconitic_6','draconitic_7','draconitic_8', ...
                        'mf_tidal','msf_tidal','mm_tidal','msm_tidal','chandler', ...
                        's1_atm','s2_atm','mjo','enso','nodal_18yr', ...
                        'm2_otl','s2_otl','k2_otl','n2_otl', ...
                        'k1_otl','o1_otl','p1_otl','q1_otl', ...
                        's3_atm','s4_atm'};
    for fi = 1:length(component_fields)
        det_model.(component_fields{fi}) = zeros(n,1);
    end

    % Seasonal group sum (for backward compatibility)
    det_model.seasonal = zeros(n,1);

    % Fill in active components from coef columns (cols 3,4 = first active pair, etc.)
    col = 3;
    for si = 1:length(active_signals)
        fld = active_signals{si};
        T_d = active_periods(si);
        component = coef(col)  * cos(2*pi/T_d * t_norm) + ...
                    coef(col+1)* sin(2*pi/T_d * t_norm);
        det_model.(fld) = component;

        % Accumulate seasonal sum (first 4 groups = seasonal + draconitic)
        seasonal_fields = {'annual','semi_annual','ter_annual','quarterly', ...
                           'draconitic_1','draconitic_2','draconitic_3','draconitic_4', ...
                           'draconitic_5','draconitic_6','draconitic_7','draconitic_8'};
        if ismember(fld, seasonal_fields)
            det_model.seasonal = det_model.seasonal + component;
        end
        col = col + 2;
    end

    % Convenience amplitude accessors for the most common signals
    if isfield(signal_config,'annual') && signal_config.annual
        idx = find(strcmp(active_signals,'annual'));
        if ~isempty(idx)
            base_col = 2 + 2*(idx-1) + 1;
            det_model.A_annual = sqrt(coef(base_col)^2 + coef(base_col+1)^2)*1000; % mm
        else
            det_model.A_annual = 0;
        end
    else
        det_model.A_annual = 0;
    end

    if isfield(signal_config,'semi_annual') && signal_config.semi_annual
        idx = find(strcmp(active_signals,'semi_annual'));
        if ~isempty(idx)
            base_col = 2 + 2*(idx-1) + 1;
            det_model.A_semi = sqrt(coef(base_col)^2 + coef(base_col+1)^2)*1000; % mm
        else
            det_model.A_semi = 0;
        end
    else
        det_model.A_semi = 0;
    end

    residuals = x - fit;
end


% =========================================================================
%  2.  FEATURE MATRIX CONSTRUCTION  (sliding window)
% =========================================================================
function [X, Y, meta] = build_features(data, window_size, signal_config)
% BUILD_FEATURES  Construct supervised regression dataset from a univariate series.

    if nargin < 3
        signal_config = default_signal_config();
    end

    data = data(:);
    n    = length(data);

    assert(n > 2*window_size, ...
        'gnss_ml_utils:insufficientData', ...
        'Data length (%d) must exceed 2 x WindowSize (%d).', n, 2*window_size);

    % Outlier removal
    [data_clean, outlier_idx] = remove_outliers(data, 3.0);

    % Deterministic model with configured signals
    t = (1:n)';
    [data_dt, det_model] = fit_deterministic(t, data_clean, signal_config);

    % Z-score normalisation
    mu    = mean(data_dt);
    sigma = std(data_dt);
    if sigma < eps, sigma = 1; end
    data_norm = (data_dt - mu) / sigma;

    % Sliding-window feature matrix
    n_samples = n - window_size;
    X = zeros(n_samples, window_size);
    Y = zeros(n_samples, 1);
    for i = 1:n_samples
        X(i, :) = data_norm(i : i+window_size-1)';
        Y(i)    = data_norm(i + window_size);
    end

    % Pack metadata
    meta.mu             = mu;
    meta.sigma          = sigma;
    meta.det_model      = det_model;
    meta.data_norm      = data_norm;
    meta.data_dt        = data_dt;
    meta.data_clean     = data_clean;
    meta.outlier_idx    = outlier_idx;
    meta.n              = n;
    meta.window_size    = window_size;
    meta.t              = t;
    meta.signal_config  = signal_config;
end


% =========================================================================
%  3.  INVERSE TRANSFORM
% =========================================================================
function denoised = reconstruct_signal(Y_pred, meta)
    window_size   = meta.window_size;
    denoised_norm = [meta.data_norm(1:window_size); Y_pred];
    denoised      = denoised_norm * meta.sigma + meta.mu + meta.det_model.fit;
end


% =========================================================================
%  4.  PERFORMANCE METRICS
% =========================================================================
function metrics = compute_metrics(data, denoised, method_name)
    data     = data(:);
    denoised = denoised(:);
    n        = length(data);

    residuals  = data - denoised;
    sigma_data = std(data);
    sigma_res  = std(residuals);

    metrics.method                 = method_name;
    metrics.residuals              = residuals;
    metrics.residual_std           = sigma_res;
    metrics.snr_improvement        = 10 * log10(var(data) / max(var(residuals), eps));
    metrics.noise_reduction        = (sigma_data - sigma_res) / sigma_data * 100;
    metrics.smoothness_improvement = ...
        (std(diff(data)) - std(diff(denoised))) / std(diff(data)) * 100;
    metrics.rmse = sqrt(mean(residuals.^2));
    metrics.mae  = mean(abs(residuals));

    k_params   = 3;
    sigma2_res = var(residuals);
    log_lik    = -n/2 * log(2*pi*sigma2_res) - sum(residuals.^2)/(2*sigma2_res);
    metrics.aic = -2*log_lik + 2*k_params;
    metrics.bic = -2*log_lik + k_params*log(n);

    try
        [h_jb, p_jb]          = jbtest(residuals);
        metrics.residual_gaussian = ~h_jb;
        metrics.p_normality       = p_jb;
    catch
        metrics.residual_gaussian = NaN;
        metrics.p_normality       = NaN;
    end

    med_res = median(residuals);
    mad_res = median(abs(residuals - med_res));
    mod_z   = 0.6745 * (residuals - med_res) / max(mad_res, eps);
    metrics.anomalies   = find(abs(mod_z) > 3.5);
    metrics.anomaly_pct = length(metrics.anomalies) / n * 100;
end


% =========================================================================
%  4b.  POST-DENOISING METRICS  (method-specific k and vel_uncertainty)
% =========================================================================
function info = fit_denoised(denoised, signal_config, t_phys, orig_det_model)
% FIT_DENOISED  Compute method-specific spectral index and velocity
%               uncertainty from ML denoised residuals.
%
%   DESIGN RATIONALE
%   ----------------
%   The velocity estimate itself comes from the SHARED pre-processing
%   deterministic model (fitted on the original signal with the physical
%   time axis).  Re-fitting on the denoised signal would corrupt the
%   velocity because:
%     (a) the denoised signal has det_model.fit already added back, so
%         it includes the full original trend;
%     (b) the first window_size epochs of the denoised signal are filled
%         from the normalised pre-processed residual prefix, not from
%         independent ML predictions -- re-fitting across this seam
%         produces a biased slope.
%
%   Therefore this function:
%     1. Computes the SPECTRAL INDEX k from the ML residuals
%        (data - denoised), which is unique per method.
%     2. Re-estimates VELOCITY UNCERTAINTY using the shared OLS design
%        matrix but scaling by the method-specific residual sigma.
%        This gives each method a different uncertainty (better-denoising
%        methods produce smaller residuals -> tighter uncertainty) while
%        keeping the velocity estimate itself unchanged.
%     3. Returns the original det_model velocity unchanged.
%
%   Inputs:
%     denoised       - ML denoised coordinate vector (m), length n
%     signal_config  - gnss_ml_utils signal config struct
%     t_phys         - physical time vector (days) used for OLS (optional)
%                      if empty, uses integer index (1:n)
%     orig_det_model - shared pre-processing det_model struct (optional)
%                      if provided, reuses its design matrix for vel_unc
%
%   Output struct fields:
%     .velocity         - velocity (mm/yr) -- from orig_det_model if provided,
%                         else from fresh linear fit on denoised
%     .vel_uncertainty  - 1-sigma velocity uncertainty (mm/yr), method-specific
%     .vel_scale_factor - noise-model inflation factor
%     .k                - spectral index of ML residuals (data - denoised)
%     .det_model        - orig_det_model (passed through unchanged)

    if nargin < 2 || isempty(signal_config)
        signal_config = default_signal_config();
    end
    if nargin < 3, t_phys = []; end
    if nargin < 4, orig_det_model = []; end

    denoised = denoised(:);
    n        = length(denoised);

    % ------------------------------------------------------------------
    % 1. Velocity: use shared det_model value if available
    %    (preserves the physically correct velocity from the original fit)
    % ------------------------------------------------------------------
    if ~isempty(orig_det_model) && isfield(orig_det_model,'velocity')
        info.velocity  = orig_det_model.velocity;
        info.det_model = orig_det_model;
    else
        % Fallback: linear fit on denoised signal with integer time axis
        % NOTE: this path is only reached when no orig_det_model is passed.
        %       For daily data t=(1:n) gives the same rate as t_phys because
        %       fit_deterministic normalises t_norm = t - t(1) internally.
        t_fit  = (1:n)';
        p      = polyfit(t_fit, denoised, 1);
        info.velocity  = p(1) * 365.25 * 1000;   % m/epoch -> mm/yr (daily)
        info.det_model = struct('velocity', info.velocity);
    end

    % ------------------------------------------------------------------
    % 2. Per-method velocity uncertainty
    %    Reuse the shared OLS design matrix (same columns as original fit)
    %    but replace sigma_res with the method-specific residual sigma.
    %    This means better-performing ML methods get tighter uncertainties.
    % ------------------------------------------------------------------
    info.vel_uncertainty  = NaN;
    info.vel_scale_factor = NaN;

    try
        % Build the same design matrix used in fit_deterministic
        if ~isempty(t_phys)
            t_vec  = t_phys(:);
        else
            t_vec  = (1:n)';
        end
        t_norm = t_vec - t_vec(1);

        % Minimum design matrix: intercept + rate + active periodic terms
        A_cols = {ones(n,1), t_norm};
        if ~isempty(orig_det_model) && ...
           isfield(orig_det_model,'active_periods') && ...
           ~isempty(orig_det_model.active_periods)
            for pi = 1:numel(orig_det_model.active_periods)
                T_p = orig_det_model.active_periods(pi);
                A_cols{end+1} = cos(2*pi/T_p * t_norm); %#ok<AGROW>
                A_cols{end+1} = sin(2*pi/T_p * t_norm); %#ok<AGROW>
            end
        end
        A = [A_cols{:}];

        % Method-specific sigma: from (denoised - original_fit) residuals
        if ~isempty(orig_det_model) && isfield(orig_det_model,'fit')
            ml_resid   = denoised - orig_det_model.fit;
        else
            coef_tmp   = A \ denoised;
            ml_resid   = denoised - A * coef_tmp;
        end

        n_params   = size(A, 2);
        dof        = max(n - n_params, 1);
        sigma2_ml  = sum(ml_resid.^2) / dof;

        % Formal velocity variance with method-specific sigma
        AtA_inv        = inv(A' * A);
        vel_var_formal = sigma2_ml * AtA_inv(2, 2);

        % Noise-model scaling via lag-1 autocorrelation of ML residuals
        rho_lag1 = corr(ml_resid(1:end-1), ml_resid(2:end));
        rho_lag1 = max(-0.99, min(0.99, rho_lag1));
        if rho_lag1 > 0
            n_eff        = max(2, n * (1 - rho_lag1) / (1 + rho_lag1));
            scale_factor = sqrt(n / n_eff);
        else
            scale_factor = 1;
        end

        vel_sigma_m_per_step = sqrt(vel_var_formal) * scale_factor;
        % Convert to mm/yr: if t is in days, 1 step = 1 day
        % If t is an integer index for daily data, this is still correct.
        info.vel_uncertainty  = vel_sigma_m_per_step * 365.25 * 1000;
        info.vel_scale_factor = scale_factor;
        info.det_model.vel_uncertainty  = info.vel_uncertainty;
        info.det_model.vel_scale_factor = scale_factor;
    catch
        % Non-fatal: leave vel_uncertainty as NaN
    end

    % ------------------------------------------------------------------
    % 3. Spectral index k from the ML residuals (data - denoised)
    %    These are small and represent the method-specific noise floor.
    %    Using denoised - orig_det_model.fit gives a more informative
    %    spectrum (residuals after BOTH ML denoising and det removal).
    % ------------------------------------------------------------------
    k_val = NaN;
    try
        if ~isempty(orig_det_model) && isfield(orig_det_model,'fit')
            resid_for_k = denoised - orig_det_model.fit;
        else
            resid_for_k = ml_resid;   % reuse from above if available
        end
        n_seg = min(256, floor(n / 4));
        if n_seg >= 4
            [pxx, f] = pwelch(resid_for_k, hann(n_seg), [], [], 1);
            f_pos    = f(f > 0);
            p_pos    = pxx(f > 0);
            if numel(f_pos) > 2
                poly_k = polyfit(log10(f_pos), log10(p_pos + eps), 1);
                k_val  = poly_k(1);
            end
        end
    catch
    end
    info.k = k_val;
end


% =========================================================================
%  5.  OUTLIER REMOVAL
% =========================================================================
function [x_clean, outlier_idx] = remove_outliers(x, k_iqr)
    if nargin < 2, k_iqr = 3.0; end
    x   = x(:);
    Q1  = prctile(x, 25);
    Q3  = prctile(x, 75);
    IQR_val     = Q3 - Q1;
    lower_fence = Q1 - k_iqr * IQR_val;
    upper_fence = Q3 + k_iqr * IQR_val;
    outlier_idx = x < lower_fence | x > upper_fence;
    x_clean     = x;
    good_idx    = find(~outlier_idx);
    bad_idx     = find(outlier_idx);
    if ~isempty(bad_idx) && length(good_idx) > 1
        x_clean(bad_idx) = interp1(good_idx, x(good_idx), bad_idx, 'linear', 'extrap');
    end
end


% =========================================================================
%  6.  TIME-SERIES CROSS-VALIDATION
% =========================================================================
function cv_rmse = timeseries_cv(X, Y, model_fn, k_folds)
    if nargin < 4, k_folds = 5; end
    n         = size(X, 1);
    fold_size = floor(n / (k_folds + 1));
    cv_rmse   = nan(k_folds, 1);
    for k = 1:k_folds
        train_end  = k * fold_size;
        test_start = train_end + 1;
        test_end   = min(train_end + fold_size, n);
        if test_start > n, break; end
        try
            mdl        = model_fn(X(1:train_end,:), Y(1:train_end));
            yhat       = predict(mdl, X(test_start:test_end,:));
            cv_rmse(k) = sqrt(mean((Y(test_start:test_end) - yhat).^2));
        catch ME
            warning('gnss_ml_utils:cvFoldFailed','CV fold %d failed: %s', k, ME.message);
        end
    end
    cv_rmse = nanmean(cv_rmse);
end


% =========================================================================
%  7.  STRUCTURED LOGGER
% =========================================================================
function gnss_log(level, fmt, varargin)
    levels    = struct('DEBUG',0,'INFO',1,'WARN',2,'ERROR',3);
    min_level = 1;
    if ~isfield(levels, upper(level)), level = 'INFO'; end
    if levels.(upper(level)) < min_level, return; end
    msg  = sprintf(fmt, varargin{:});
    line = sprintf('[%s][%s] %s\n', datestr(now,'HH:MM:SS'), upper(level), msg);
    fprintf('%s', line);
    log_path = getenv('GNSS_LOG_FILE');
    if ~isempty(log_path)
        try
            fid = fopen(log_path,'a');
            if fid ~= -1, fprintf(fid,'%s',line); fclose(fid); end
        catch, end
    end
end


% =========================================================================
%  8.  PUBLICATION-QUALITY FIGURE EXPORT
% =========================================================================
function save_publication_figure(fig_handle, filename, format, col_width_mm)
    if nargin < 4, col_width_mm = 178; end
    if nargin < 3, format = 'png'; end
    height_mm = col_width_mm * 0.75;
    set(fig_handle, 'Units','centimeters', ...
        'Position',[0,0,col_width_mm/10,height_mm/10]);
    set(fig_handle, 'PaperUnits','centimeters', ...
        'PaperSize',[col_width_mm/10,height_mm/10], ...
        'PaperPosition',[0,0,col_width_mm/10,height_mm/10]);
    for h = findall(fig_handle,'-property','FontSize')'
        if h.FontSize < 8, h.FontSize = 8; end
    end
    for h = findall(fig_handle,'-property','LineWidth')'
        if h.LineWidth < 0.75, h.LineWidth = 0.75; end
    end
    print(fig_handle, filename, ['-d' format], '-r300');
    fprintf('[INFO] Figure saved: %s (%dx%d mm, 300 dpi)\n', ...
        filename, col_width_mm, round(height_mm));
end
