function gnss_ml_plot(data, results, component, varargin)
% GNSS_ML_PLOT  Publication-ready visualisation for all GNSS ML denoising methods.
% Pass 'Dates', datetime_vector to show dd-mm-yyyy on the x-axis.
%
% IMPROVEMENTS over v1.0
%   - Extended 6-panel layout: original panels + normality QQ-plot + new
%     extended metrics panel (AIC, RMSE, normality flag, CV-RMSE).
%   - Taylor diagram support when called with multiple results structs.
%   - Seasonal model overlay (annual + semi-annual) from det_model field.
%   - Outlier epoch markers from outlier_idx field.
%   - Publication-quality export via gnss_ml_utils('save_publication_figure').
%   - Consistent colour scheme across all methods.
%   - Auto-title includes velocity estimate from deterministic model.
%
% Syntax:
%   gnss_ml_plot(data, results, component)
%   gnss_ml_plot(data, results, component, 'SaveFig', true, 'OutputDir', './figs')
%   gnss_ml_plot(data, results_cell, component)   % Taylor diagram mode
%
% Inputs:
%   data        - Original coordinate vector (m)
%   results     - Single results struct OR cell array of structs (Taylor mode)
%   component   - Component index for figure title (default: 1)
%   Optional:
%     'SaveFig'    - Save to file (default: false)
%     'OutputDir'  - Output directory (default: current folder)
%     'ColWidth'   - 86 (single) or 178 mm (double column, default)
%     'Format'     - 'png' (default) | 'eps' | 'pdf'
%
% Author:  Dr. Ahmed Mohammed
%          Department of Surveying and Geoinformatics,
%          Modibbo Adama University, Yola
% Date:    2026

%% -- Input parsing ----------------------------------------------------------
if nargin < 3, component = 1; end

p = inputParser;
addRequired(p, 'data');
addRequired(p, 'results');
addRequired(p, 'component');
addParameter(p, 'SaveFig',    false, @islogical);
addParameter(p, 'OutputDir',  '.',   @ischar);
addParameter(p, 'ColWidth',   178,   @(x) ismember(x,[86,178]));
addParameter(p, 'Format',     'png', @ischar);
addParameter(p, 'Dates',      [],    @(x) isempty(x)||isa(x,'datetime'));
addParameter(p, 'StationName','',    @ischar);
parse(p, data, results, component, varargin{:});

save_fig     = p.Results.SaveFig;
output_dir   = p.Results.OutputDir;
col_width    = p.Results.ColWidth;
fmt          = p.Results.Format;
dates        = p.Results.Dates;
station_name = strtrim(p.Results.StationName);
use_dates    = ~isempty(dates) && isa(dates, 'datetime') && length(dates) == length(data);

data = data(:);

%% -- Taylor diagram mode (cell array of results) ----------------------------
if iscell(results)
    plot_taylor_diagram(data, results, component, save_fig, output_dir, col_width, fmt, station_name);
    return;
end

%% -- Single-method 6-panel figure ------------------------------------------
method_name = results.method;
n_data  = length(data);
t_num   = (1:n_data)';      % always numeric -- used for all plot() calls
t_axis  = t_num;            % datetime overrides tick LABELS only (not x-data)
if use_dates, t_axis = dates(:); end

% Build station prefix for all titles
if ~isempty(station_name)
    sta_prefix = sprintf('[%s]  ', station_name);
else
    sta_prefix = '';
end

% Method colour map for consistency across all plots
cmap = containers.Map( ...
    {'GPR','SVR','Random Forest','Gradient Boosting','KNN'}, ...
    {[0.12 0.47 0.71], [0.89 0.10 0.11], [0.20 0.63 0.17], ...
     [1.00 0.50 0.00], [0.42 0.24 0.60]});
if isKey(cmap, method_name)
    method_color = cmap(method_name);
else
    method_color = [0.5 0.5 0.5];
end

if ~isempty(station_name)
    fig_name = sprintf('%s -- %s  Component %d', station_name, method_name, component);
else
    fig_name = sprintf('%s Analysis -- Component %d', method_name, component);
end
fig = figure('Color', 'w', ...
    'Position', [60 60 1600 900], ...
    'Name', fig_name);

% Station + method supertitle
sgtitle(fig, sprintf('%s%s  |  Component %d', sta_prefix, method_name, component), ...
    'FontSize', 13, 'FontWeight', 'bold');

%% Panel 1 -- Original vs fit (+seasonal overlay +anomalies) -----------------
ax1 = subplot(2,4,1);
hold on;
plot(t_num, data, 'Color', [0.6 0.6 0.6], 'LineWidth', 0.8, 'DisplayName', 'Original');

% Seasonal overlay (if deterministic model stored)
if isfield(results, 'det_model') && ~isempty(results.det_model)
    dm = results.det_model;
    seasonal_only = dm.annual + dm.semi_annual;
    detrended_orig = data - dm.fit + seasonal_only;
    % Show as a faint dashed background
    plot(t_num, dm.fit, 'k--', 'LineWidth', 1.0, 'DisplayName', 'Deterministic model');
end

plot(t_num, results.denoised_signal, '-', 'Color', method_color, ...
    'LineWidth', 2.0, 'DisplayName', [method_name ' fit']);

% GPR confidence bounds
if isfield(results,'confidence_95') && ~isempty(results.confidence_95)
    ci = results.confidence_95;
    fill([t_num; flipud(t_num)], [ci(:,1); flipud(ci(:,2))], method_color, ...
        'FaceAlpha', 0.15, 'EdgeColor', 'none', 'DisplayName', '95% CI');
end

% Anomalies
if isfield(results,'anomalies') && ~isempty(results.anomalies)
    plot(t_num(results.anomalies), data(results.anomalies), 'o', ...
        'MarkerSize', 6, 'MarkerFaceColor', [0.85 0.33 0.10], ...
        'MarkerEdgeColor', 'none', 'DisplayName', 'Anomalies');
end

% Outliers (from pre-processing)
if isfield(results,'outlier_idx') && any(results.outlier_idx)
    out_t = find(results.outlier_idx);
    plot(t_num(out_t), data(out_t), 'x', 'Color', [0.5 0 0.5], ...
        'MarkerSize', 6, 'LineWidth', 1.5, 'DisplayName', 'Pre-proc outliers');
end

grid on; box on;
legend('Location', 'best', 'FontSize', 8);
apply_date_axis_ml(ax1, t_axis, use_dates);
ylabel('Coordinate (m)', 'FontSize', 10);

% Build velocity ± uncertainty string
if isfield(results,'det_model') && ~isempty(results.det_model)
    vel_mmy = results.det_model.velocity;
    vel_unc = NaN;
    if isfield(results.det_model,'vel_uncertainty')
        vel_unc = results.det_model.vel_uncertainty;
    end
    if ~isnan(vel_unc)
        vel_str = sprintf('vel = %+.3f \x00B1 %.3f mm/yr', vel_mmy, vel_unc);
    else
        vel_str = sprintf('vel = %+.3f mm/yr', vel_mmy);
    end
    title(sprintf('%sComponent %d -- %s\n%s', ...
        sta_prefix, component, method_name, vel_str), ...
        'FontSize', 10, 'FontWeight', 'bold');
    % Velocity annotation text box (lower-left corner)
    text(ax1, 0.02, 0.04, vel_str, ...
        'Units', 'normalized', 'FontSize', 9, ...
        'VerticalAlignment', 'bottom', 'HorizontalAlignment', 'left', ...
        'BackgroundColor', 'w', 'EdgeColor', [0.65 0.65 0.65], ...
        'FontName', 'Courier New', 'Margin', 3);
else
    title(sprintf('%sComponent %d -- %s', sta_prefix, component, method_name), ...
        'FontSize', 11, 'FontWeight', 'bold');
end

%% Panel 2 -- Uncertainty / Feature importance / Info ----------------------
ax2 = subplot(2,4,2);
if isfield(results,'uncertainty') && ~isempty(results.uncertainty)
    plot(t_num, results.uncertainty * 1000, 'Color', method_color, 'LineWidth', 1.5);
    grid on; box on;
    apply_date_axis_ml(ax2, t_axis, use_dates);
    ylabel('Uncertainty (mm)', 'FontSize', 10);
    title('Posterior Uncertainty (1sigma)', 'FontSize', 11, 'FontWeight', 'bold');
    unc_mean = mean(results.uncertainty) * 1000;
    unc_max  = max(results.uncertainty)  * 1000;
    text(0.97, 0.95, sprintf('Mean: %.3f mm\nMax: %.3f mm', unc_mean, unc_max), ...
        'Units', 'normalized', 'FontSize', 9, 'HorizontalAlignment', 'right', ...
        'VerticalAlignment', 'top', 'BackgroundColor', 'w', 'EdgeColor', [0.7 0.7 0.7]);
elseif isfield(results,'importance') && ~isempty(results.importance)
    imp = results.importance;
    bar(imp, 'FaceColor', method_color, 'EdgeColor', 'none');
    grid on; box on;
    xlabel('Lag feature index', 'FontSize', 10);
    ylabel('OOB importance', 'FontSize', 10);
    title('Feature Importance (OOB Permutation)', 'FontSize', 11, 'FontWeight', 'bold');
else
    axis off;
    fields = {'residual_std','snr_improvement','noise_reduction', ...
              'smoothness_improvement','rmse','mae'};
    labels = {'sigma_r (m)','SNR (dB)','Noise red. (%)','Smoothness (%)','RMSE','MAE'};
    info_str = sprintf('%s Results\n\n', method_name);
    for fi = 1:length(fields)
        if isfield(results, fields{fi})
            info_str = [info_str sprintf('%-18s %10.4g\n', [labels{fi} ':'], results.(fields{fi}))]; %#ok<AGROW>
        end
    end
    text(0.05, 0.95, info_str, 'Units', 'normalized', 'FontSize', 9, ...
        'VerticalAlignment', 'top', 'FontName', 'Courier');
end

%% Panel 3 -- Residuals time series ------------------------------------------
ax3 = subplot(2,4,3);
sig2  = results.residual_std;
hold on;
plot(t_num, results.residuals * 1000, 'Color', [0.2 0.6 0.2], 'LineWidth', 0.8);
yline(0,            'k--', 'LineWidth', 1.0);
yline( 2*sig2*1000, 'r--', 'LineWidth', 0.8, 'Alpha', 0.6);
yline(-2*sig2*1000, 'r--', 'LineWidth', 0.8, 'Alpha', 0.6);
grid on; box on;
apply_date_axis_ml(ax3, t_axis, use_dates);
ylabel('Residual (mm)', 'FontSize', 10);
title(sprintf('Residuals  (sigma = %.4f mm)', sig2*1000), 'FontSize', 11, 'FontWeight', 'bold');

%% Panel 4 -- PSD: original residuals vs ML residuals ----------------------
ax4 = subplot(2,4,4);
% Compute PSD of original residuals (after deterministic model removal)
if isfield(results,'det_model') && ~isempty(results.det_model)
    orig_resid = data - results.det_model.fit;
else
    orig_resid = data - mean(data);
end
ml_resid = results.residuals;
n_seg = min(256, floor(length(orig_resid)/4));
if n_seg >= 4
    [pxx_orig, f_orig] = pwelch(orig_resid,   hann(n_seg), [], [], 1);
    [pxx_ml,   f_ml  ] = pwelch(ml_resid,     hann(n_seg), [], [], 1);
    f_pos = f_orig(f_orig > 0);
    % Use loglog BEFORE hold on so log scale is set by the first plot call
    loglog(f_pos, pxx_orig(f_orig>0)*1e6, 'Color',[0.6 0.6 0.6], ...
        'LineWidth',1.2, 'DisplayName','Original');
    hold on;
    loglog(f_pos, pxx_ml(f_ml>0)*1e6, 'Color', method_color, ...
        'LineWidth',1.8, 'DisplayName',[method_name ' residuals']);
    % Spectral index fit lines
    logf = log10(f_pos);
    k_orig = polyfit(logf, log10(pxx_orig(f_orig>0)+eps), 1);
    k_ml   = polyfit(logf, log10(pxx_ml(f_ml>0)+eps),   1);
    p_fit_orig = 10.^(polyval(k_orig, logf)) * 1e6;
    p_fit_ml   = 10.^(polyval(k_ml,   logf)) * 1e6;
    loglog(f_pos, p_fit_orig, '--', 'Color',[0.5 0.5 0.5], 'LineWidth',0.8, ...
        'DisplayName', sprintf('k_{orig}=%.2f', k_orig(1)));
    loglog(f_pos, p_fit_ml,   '--', 'Color', method_color*0.7, 'LineWidth',0.8, ...
        'DisplayName', sprintf('k_{ML}=%.2f',   k_ml(1)));
end
% Force log-log scale explicitly in case hold on was set earlier
set(ax4, 'XScale', 'log', 'YScale', 'log');
grid on; box on;
legend('Location','southwest','FontSize',7);
xlabel('Frequency (cycles/epoch)', 'FontSize', 10);
ylabel('PSD (mm^2/Hz)', 'FontSize', 10);
title('PSD: Original vs ML Residuals (log-log)', 'FontSize', 11, 'FontWeight', 'bold');

%% Panel 5 -- Residual histogram + Gaussian fit ------------------------------
ax5 = subplot(2,4,5);
res_mm = results.residuals * 1000;
histogram(res_mm, 50, 'Normalization', 'pdf', ...
    'FaceColor', method_color, 'FaceAlpha', 0.55, 'EdgeColor', 'none');
hold on;
xr = linspace(min(res_mm), max(res_mm), 200);
plot(xr, normpdf(xr, 0, sig2*1000), 'r-', 'LineWidth', 2.0, 'DisplayName', 'Normal(0,sigma)');
grid on; box on;
xlabel('Residual (mm)', 'FontSize', 10);
ylabel('PDF', 'FontSize', 10);
norm_flag = '';
if isfield(results,'residual_gaussian')
    norm_flag = sprintf('  Gaussian: %s', yn(results.residual_gaussian));
end
title(['Residual Distribution' norm_flag], 'FontSize', 11, 'FontWeight', 'bold');
legend('Residuals', 'Normal(0,sigma)', 'Location', 'best', 'FontSize', 8);

%% Panel 5 -- Normal probability plot (QQ) ----------------------------------
ax6 = subplot(2,4,6);
qqplot(res_mm);
title('Normal Q-Q Plot of Residuals', 'FontSize', 11, 'FontWeight', 'bold');
xlabel('Theoretical quantiles', 'FontSize', 10);
ylabel('Sample quantiles (mm)', 'FontSize', 10);
grid on; box on;
ax6.Children(end).Color   = method_color;    % Q-Q data points
ax6.Children(end).MarkerSize = 4;

%% Panel 7 -- Amplitude spectrum: full data (signal + noise) vs ML denoised --
ax7 = subplot(2,4,7);
hold on;

% Full signal amplitude spectrum (before any denoising)
n_7   = length(data);
t_7   = (1:n_7)' / 365.25;   % years
span_7 = n_7;
T_grid_7 = exp(linspace(log(2), log(span_7*0.9), 2000));
f_cpy_7  = (1./T_grid_7) * 365.25;

[pxx_raw7, ~]  = plomb(data*1000,                  t_7, f_cpy_7, 'normalized');
[pxx_den7, ~]  = plomb(results.denoised_signal*1000, t_7, f_cpy_7, 'normalized');

sigma_raw7 = std(data*1000);
sigma_den7 = std(results.denoised_signal*1000);
amp_raw7   = sigma_raw7 * sqrt(2*pxx_raw7 / n_7);
amp_den7   = sigma_den7 * sqrt(2*pxx_den7 / n_7);

semilogx(T_grid_7, amp_raw7, '-', 'Color',[0.65 0.65 0.65], ...
    'LineWidth',1.2, 'DisplayName','Original signal');
semilogx(T_grid_7, amp_den7, '-', 'Color', method_color, ...
    'LineWidth',1.8, 'DisplayName',[method_name ' denoised']);

% Known signal period markers
known_T7   = [365.25, 182.63, 351.4, 13.661, 14.765, 27.555];
known_lbl7 = {'Annual','S-ann','Drac1','Mf','MSf','Mm'};
known_col7 = {'b','b','g','r','r','r'};
y_max7 = max([amp_raw7; amp_den7]) * 1.05;
if y_max7 == 0 || isnan(y_max7), y_max7 = 1; end
for ki = 1:length(known_T7)
    if known_T7(ki) >= 2 && known_T7(ki) <= span_7*0.9
        xl = xline(known_T7(ki), '--', 'Color', known_col7{ki}, ...
            'LineWidth', 0.9, 'Alpha', 0.7);
        xl.HandleVisibility = 'off';   % keep out of legend
        text(known_T7(ki), y_max7*0.85, known_lbl7{ki}, ...
            'FontSize', 7, 'Color', known_col7{ki}, ...
            'Rotation', 90, 'VerticalAlignment', 'top', ...
            'HorizontalAlignment', 'right');
    end
end

set(ax7, 'XScale', 'log');
grid on; box on;
legend('Location','northeast','FontSize',7);
xlabel('Period (days)', 'FontSize', 10);
ylabel('Amplitude (mm)', 'FontSize', 10);
title(sprintf('Amplitude Spectrum: Signal vs %s Denoised', method_name), ...
    'FontSize', 11, 'FontWeight', 'bold');
xlim([2, span_7]);
xticks_7 = [2, 5, 14, 28, 91, 182, 365, 730];
xticks_7 = xticks_7(xticks_7 <= span_7);
set(ax7, 'XTick', xticks_7, 'XTickLabel', arrayfun(@num2str, xticks_7, 'UniformOutput', false));
ax7.XTickLabelRotation = 30;

%% Panel 8 -- Amplitude spectrum: deterministic residuals vs ML residuals -----
% PURPOSE: Show what periodic signal power REMAINS in the residuals after
%   (a) classical deterministic removal  and
%   (b) ML denoising + deterministic removal.
%
% Both spectra are computed on residuals AFTER the deterministic model is
% removed, so the y-axis represents unexplained (residual) periodic power.
% If ML denoising is working well, the ML residual spectrum should lie BELOW
% the classical residual spectrum at all geodetically significant periods.
%
% AMPLITUDE FORMULA (Lomb-Scargle, 'normalized' flag):
%   The normalised LS power P_norm is dimensionless (0..1).
%   Amplitude in physical units: A = sigma_resid * sqrt(2 * P_norm / n)
%   where sigma_resid is the RMS of the residual series and n is the number
%   of data points.  This converts normalised power back to mm.

ax8 = subplot(2,4,8);
hold on;

% -- Build residual series for both spectra ----------------------------------
% Original: data minus the deterministic model fit (classical pre-proc model)
if isfield(results,'det_model') && ~isempty(results.det_model)
    orig_resid_p = data - results.det_model.fit;
else
    orig_resid_p = data - mean(data);
end

% ML: denoised signal minus the same deterministic model fit.
% Using (denoised - det_model.fit) rather than (data - denoised) exposes
% what periodic power survives in the ML output AFTER the shared trend and
% seasonal model is removed -- this is what should be compared spectrally.
if isfield(results,'denoised_signal') && ~isempty(results.denoised_signal)
    den_sig = safe_trim(results.denoised_signal, length(data));
    if isfield(results,'det_model') && ~isempty(results.det_model)
        ml_resid_p = den_sig - results.det_model.fit;
    else
        ml_resid_p = den_sig - mean(den_sig);
    end
else
    ml_resid_p = results.residuals;
end

n_p      = length(orig_resid_p);
t_yrs_p  = (1:n_p)' / 365.25;   % non-negative, starting from epoch 1

% Dense log-spaced period grid: 2 days to 90% of data span
span_p   = n_p;
T_grid_p = exp(linspace(log(2), log(max(span_p * 0.9, 3)), 2000));
f_cpy_p  = (1 ./ T_grid_p) * 365.25;   % cycles per year for plomb

% Compute normalised Lomb-Scargle power for both residual series
[pxx_o_p, ~] = plomb(orig_resid_p * 1000, t_yrs_p, f_cpy_p, 'normalized');
[pxx_m_p, ~] = plomb(ml_resid_p   * 1000, t_yrs_p, f_cpy_p, 'normalized');

% Convert normalised LS power to physical amplitude (mm)
% A = sigma * sqrt(2 * P_norm / n)  (Scargle 1982 normalisation)
sigma_o  = std(orig_resid_p * 1000);
sigma_m  = std(ml_resid_p   * 1000);
n_pts_p  = n_p;
amp_o_p  = sigma_o * sqrt(max(2 * pxx_o_p / n_pts_p, 0));
amp_m_p  = sigma_m * sqrt(max(2 * pxx_m_p / n_pts_p, 0));

% Plot amplitude spectra
semilogx(T_grid_p, amp_o_p, '-', 'Color', [0.65 0.65 0.65], ...
    'LineWidth', 1.2, 'DisplayName', 'Classical resid.');
semilogx(T_grid_p, amp_m_p, '-', 'Color', method_color, ...
    'LineWidth', 1.8, 'DisplayName', [method_name ' resid.']);

% -- Mark active geodetic signal periods from det_model ---------------------
% Show only signals that were actually fitted in the deterministic model.
% This makes the markers meaningful -- they mark periods where signal power
% WAS removed (and should therefore be absent in both residual spectra).
y_max_p = max([amp_o_p; amp_m_p]) * 1.05;
if y_max_p == 0 || isnan(y_max_p), y_max_p = 1; end

% Build a list of (period, label, colour) from the active signals
period_marker_T   = [];
period_marker_lbl = {};
period_marker_col = {};

% Always show annual and semi-annual reference lines
base_periods  = [365.25, 182.63, 351.4, 175.7, 13.661, 14.765, 27.555, 432.2];
base_labels   = {'Ann','S-ann','Drac1','Drac2','Mf','MSf','Mm','Chand'};
base_colours  = {'b',  'b',    'g',   'g',    'r', 'r',  'r', 'm'};

% If det_model has active_periods use those, else fall back to base list
if isfield(results,'det_model') && ~isempty(results.det_model) && ...
   isfield(results.det_model,'active_periods') && ...
   ~isempty(results.det_model.active_periods)
    act_T   = results.det_model.active_periods(:)';
    act_lbl = results.det_model.active_labels;
    % Assign colours by matching to base list (approximate period match)
    for pi = 1:numel(act_T)
        [~, idx_b] = min(abs(base_periods - act_T(pi)));
        if abs(base_periods(idx_b) - act_T(pi)) < 5   % within 5 days
            col_p = base_colours{idx_b};
            lbl_p = base_labels{idx_b};
        else
            col_p = [0.5 0.5 0.5];
            lbl_p = sprintf('%.0fd', act_T(pi));
        end
        period_marker_T(end+1)   = act_T(pi);        %#ok<AGROW>
        period_marker_lbl{end+1} = lbl_p;            %#ok<AGROW>
        period_marker_col{end+1} = col_p;            %#ok<AGROW>
    end
else
    % Fallback: use full base list
    period_marker_T   = base_periods;
    period_marker_lbl = base_labels;
    period_marker_col = base_colours;
end

% Draw vertical period markers
for ki = 1:length(period_marker_T)
    T_ki = period_marker_T(ki);
    if T_ki >= 2 && T_ki <= span_p * 0.9
        xl = xline(T_ki, '--', 'Color', period_marker_col{ki}, ...
            'LineWidth', 0.9, 'Alpha', 0.75);
        xl.HandleVisibility = 'off';   % keep out of legend
        text(T_ki, y_max_p * 0.96, period_marker_lbl{ki}, ...
            'FontSize', 7, 'Color', period_marker_col{ki}, ...
            'Rotation', 90, 'VerticalAlignment', 'top', ...
            'HorizontalAlignment', 'right');
    end
end

% -- Axes formatting ---------------------------------------------------------
set(ax8, 'XScale', 'log');
grid on; box on;
legend(ax8, 'Location', 'northeast', 'FontSize', 7);
xlabel('Period (days)', 'FontSize', 10);
ylabel('Amplitude (mm)', 'FontSize', 10);
title(sprintf('Amplitude Spectrum: Classical vs %s Residuals', method_name), ...
    'FontSize', 11, 'FontWeight', 'bold');
xlim([2, span_p]);
xticks_p = [2, 5, 10, 14, 28, 60, 91, 122, 182, 365, 730];
xticks_p = xticks_p(xticks_p <= span_p);
set(ax8, 'XTick', xticks_p, ...
    'XTickLabel', arrayfun(@num2str, xticks_p, 'UniformOutput', false));
ax8.XTickLabelRotation = 30;
ylim([0, y_max_p * 1.1]);

%% -- Figure stamp removed -- station shown in sgtitle ----------------------

%% -- Save figure ------------------------------------------------------------
if save_fig
    if ~exist(output_dir, 'dir'), mkdir(output_dir); end
    if ~isempty(station_name)
        fname = fullfile(output_dir, sprintf('%s_%s_comp%d.%s', ...
            lower(station_name), lower(strrep(method_name,' ','_')), component, fmt));
    else
        fname = fullfile(output_dir, sprintf('gnss_%s_comp%d.%s', ...
            lower(strrep(method_name,' ','_')), component, fmt));
    end
    gnss_ml_utils('save_publication_figure', fig, fname, fmt, col_width);
end
end


%% ===========================================================================
%  Taylor Diagram
% ============================================================================
function plot_taylor_diagram(data, results_cell, component, save_fig, ...
                              output_dir, col_width, fmt, station_name)
% PLOT_TAYLOR_DIAGRAM  Compare multiple methods on a single polar plot.
    if nargin < 8, station_name = ''; end
%
%   The Taylor diagram encodes three metrics simultaneously:
%     radius    = normalised standard deviation  (sigma_method / sigma_data)
%     angle     = arccos(correlation coefficient)
%     distance  = centred RMSE  (distance from the reference point at radius=1, ?=0)

    data = data(:);
    sigma_ref = std(data);
    n_methods = numel(results_cell);

    method_colors = {[0.12 0.47 0.71],[0.89 0.10 0.11],[0.20 0.63 0.17], ...
                     [1.00 0.50 0.00],[0.42 0.24 0.60]};
    max_r = 1.5;

    if ~isempty(station_name)
        fig_title = sprintf('Taylor Diagram -- Station: %s  |  Component %d', ...
            station_name, component);
    else
        fig_title = sprintf('Taylor Diagram -- Component %d', component);
    end

    fig = figure('Color','w','Position',[100 100 700 680], ...
        'Name', fig_title);
    ax = axes('Position', [0.08 0.08 0.82 0.82]);
    hold on; axis equal; axis off;

    % -- Arc: normalised std circles -------------------------------------
    theta_full = linspace(0, pi/2, 300);
    for r_val = [0.5, 1.0, 1.5]
        plot(r_val*cos(theta_full), r_val*sin(theta_full), ...
            'Color', [0.8 0.8 0.8], 'LineWidth', 0.7);
        text(r_val, -0.04, sprintf('%.1f', r_val), 'FontSize', 8, ...
            'HorizontalAlignment', 'center', 'Color', [0.5 0.5 0.5]);
    end

    % -- Correlation lines ------------------------------------------------
    for rho_val = [0.6 0.7 0.8 0.9 0.95 0.99]
        theta_corr = acos(rho_val);
        r_vec = [0 max_r];
        plot(r_vec*cos(theta_corr), r_vec*sin(theta_corr), ...
            '--', 'Color', [0.75 0.75 0.75], 'LineWidth', 0.5);
        text(max_r*cos(theta_corr)*1.06, max_r*sin(theta_corr)*1.06, ...
            sprintf('%.2f', rho_val), 'FontSize', 7.5, 'Color', [0.4 0.4 0.4], ...
            'HorizontalAlignment','center');
    end

    % -- Centred-RMSE arcs (from reference point) -------------------------
    for crmse_r = [0.25 0.5 0.75 1.0]
        theta_c = linspace(0, pi, 400);
        x_c = 1 + crmse_r*cos(theta_c);
        y_c =     crmse_r*sin(theta_c);
        valid = x_c >= 0 & y_c >= 0 & sqrt(x_c.^2+y_c.^2) <= max_r*1.1;
        plot(x_c(valid), y_c(valid), ':', 'Color', [0.9 0.6 0.3], 'LineWidth', 0.6);
    end

    % -- Reference point (observed data) ----------------------------------
    plot(1, 0, 'k*', 'MarkerSize', 12, 'LineWidth', 1.5);
    text(1.04, 0.04, 'Reference', 'FontSize', 9, 'FontWeight', 'bold');

    % -- Plot each method --------------------------------------------------
    legend_handles = gobjects(n_methods, 1);
    for mi = 1:n_methods
        r_struct = results_cell{mi};
        if isempty(r_struct), continue; end

        denoised = r_struct.denoised_signal;
        sigma_m  = std(denoised);
        rho      = corr(data, denoised);
        norm_std = sigma_m / sigma_ref;
        theta    = acos(max(-1, min(1, rho)));

        px = norm_std * cos(theta);
        py = norm_std * sin(theta);
        ci = mod(mi-1, numel(method_colors)) + 1;
        h  = plot(px, py, 'o', 'MarkerSize', 11, ...
            'MarkerFaceColor', method_colors{ci}, ...
            'MarkerEdgeColor', 'w', 'LineWidth', 1.5);
        text(px+0.04, py+0.03, r_struct.method, 'FontSize', 9);
        legend_handles(mi) = h;
    end

    % -- Axes labels -------------------------------------------------------
    text(0, -0.12, 'Normalised std dev', 'FontSize', 10, 'HorizontalAlignment', 'center');
    text(-0.12, max_r/2, 'Correlation', 'FontSize', 10, 'Rotation', 90, ...
        'HorizontalAlignment', 'center');

    title(fig_title, 'FontSize', 13, 'FontWeight', 'bold');

    % No author stamp -- station shown in title above

    if save_fig
        if ~exist(output_dir, 'dir'), mkdir(output_dir); end
        if ~isempty(station_name)
            fname = fullfile(output_dir, sprintf('%s_taylor_comp%d.%s', ...
                lower(station_name), component, fmt));
        else
            fname = fullfile(output_dir, sprintf('gnss_taylor_comp%d.%s', component, fmt));
        end
        gnss_ml_utils('save_publication_figure', fig, fname, fmt, col_width);
    end
end


%% -- Local helpers ---------------------------------------------------------
function s = yn(v)
    if isnan(v) || isempty(v)
        s = 'N/A';
    elseif v
        s = 'Yes';
    else
        s = 'No';
    end
end


function add_figure_stamp(~)
% ADD_FIGURE_STAMP  Stub kept for backwards compatibility.
%   Author stamp removed. Station name is shown in figure title/sgtitle.
end


function apply_date_axis_ml(ax, t_axis, use_dates)
% APPLY_DATE_AXIS_ML  Set x-axis tick labels to dd-mm-yyyy date strings.
%
%   All plots in gnss_ml_plot use a numeric x-axis (t_num = 1:n), so the
%   ruler is always a NumericRuler.  This function keeps the numeric XTick
%   positions and replaces only the labels with formatted date strings.
%   It never assigns datetime values to the ruler.

    if nargin < 3, use_dates = isa(t_axis, 'datetime'); end
    if ~use_dates || ~isa(t_axis, 'datetime') || length(t_axis) < 2
        xlabel(ax, 'Epoch', 'FontSize', 10);
        return;
    end

    n       = length(t_axis);
    n_ticks = min(8, n);
    idx     = unique(round(linspace(1, n, n_ticks)));
    idx     = idx(idx >= 1 & idx <= n);

    try
        % Numeric positions + string labels -- safe for NumericRuler
        ax.XTick      = idx;
        ax.XTickLabel = datestr(t_axis(idx), 'dd-mm-yyyy');
        ax.XTickLabelRotation = 30;
        xlabel(ax, 'Date', 'FontSize', 10);
    catch
        % Fallback: plain epoch numbers
        xlabel(ax, 'Epoch', 'FontSize', 10);
    end
end


function v = safe_trim(v, target_len)
% SAFE_TRIM  Force vector v to exactly target_len elements.
%   ML denoised signals can be shorter by up to window_size epochs.
%   Pads with the last value or truncates to avoid size mismatches.
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
