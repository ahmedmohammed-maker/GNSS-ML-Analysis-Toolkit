classdef GNSS_ML_Comparison_App < matlab.apps.AppBase
% GNSS_ML_COMPARISON_APP  Comprehensive GNSS coordinate time-series analysis toolkit.
%
% IMPROVEMENTS over v1.0
%   Architecture
%     - METHOD_NAMES / METHOD_IDX constants eliminate copy-pasted mapping.
%     - Session save/load (Tab 6) -- all results survive app close/reopen.
%     - Batch processing mode (Tab 6) -- folder of CSV files, one loop.
%     - Private run_single_method() isolates all per-method dispatch.
%     - Private extract_component() handles NaN gaps with interpolation.
%
%   Performance
%     - parfor parallel execution when Parallel Computing Toolbox present.
%     - Per-method status badges (colour-coded) replace single progress gauge.
%
%   Analysis
%     - RunCV checkbox triggers 5-fold walk-forward CV on each method.
%     - Preset dropdown ('Daily GNSS', 'Sub-daily', 'Weekly') fills params.
%     - Taylor diagram button in Tab 5 for multi-method comparison.
%
%   Metrics & Reporting
%     - Comparison table includes RMSE, MAE, AIC, BIC, normality flag.
%     - Export to CSV in addition to .mat.
%     - LaTeX table export.
%     - Publication-quality figure save (300 dpi, journal column width).
%
% Author:  Dr. Ahmed Mohammed
%          Department of Surveying and Geoinformatics,
%          Modibbo Adama University, Yola
% Date:    2026

    %% -- UI component declarations -----------------------------------------
    properties (Access = public)
        UIFigure                     matlab.ui.Figure
        TabGroup                     matlab.ui.container.TabGroup

        % Tab 1 -- Load data
        LoadTab                      matlab.ui.container.Tab
        LoadFileButton               matlab.ui.control.Button
        FileNameLabel                matlab.ui.control.Label
        DataInfoLabel                matlab.ui.control.Label
        DataPreviewTable             matlab.ui.control.Table

        % Tab 2 -- Classical analysis
        ClassicalTab                 matlab.ui.container.Tab
        RunClassicalButton           matlab.ui.control.Button
        ClassicalStatusLabel         matlab.ui.control.Label
        ClassicalComponentDropDown   matlab.ui.control.DropDown
        PlotClassicalButton          matlab.ui.control.Button
        ClassicalResultsTable        matlab.ui.control.Table
        % Tab 2 signal config checkboxes (Group 1: Seasonal)
        ClsAnnualCB                  matlab.ui.control.CheckBox
        ClsSemiAnnualCB              matlab.ui.control.CheckBox
        ClsTerAnnualCB               matlab.ui.control.CheckBox
        ClsQuarterlyCB               matlab.ui.control.CheckBox
        % Tab 2 signal config checkboxes (Group 2: Draconitic)
        ClsDrac1CB                   matlab.ui.control.CheckBox
        ClsDrac2CB                   matlab.ui.control.CheckBox
        ClsDrac3CB                   matlab.ui.control.CheckBox
        ClsDrac4CB                   matlab.ui.control.CheckBox
        ClsDrac5CB                   matlab.ui.control.CheckBox
        ClsDrac6CB                   matlab.ui.control.CheckBox
        ClsDrac7CB                   matlab.ui.control.CheckBox
        ClsDrac8CB                   matlab.ui.control.CheckBox
        % Tab 2 signal config checkboxes (Group 3: Tidal/OTL)
        ClsMfCB                      matlab.ui.control.CheckBox
        ClsMsfCB                     matlab.ui.control.CheckBox
        ClsMmCB                      matlab.ui.control.CheckBox
        ClsMsmCB                     matlab.ui.control.CheckBox
        ClsChandlerCB                matlab.ui.control.CheckBox
        % Tab 2 signal config checkboxes (Group 4: Atmospheric)
        ClsS1AtmCB                   matlab.ui.control.CheckBox
        ClsS2AtmCB                   matlab.ui.control.CheckBox
        ClsMjoCB                     matlab.ui.control.CheckBox
        % Tab 2 signal config checkboxes (Group 5: Inter-annual)
        ClsEnsoCB                    matlab.ui.control.CheckBox
        ClsNodal18CB                 matlab.ui.control.CheckBox
        % Tab 2 signal config checkboxes (Group 6: Sub-daily OTL -- hrts only)
        ClsSubDailyPanel             matlab.ui.container.Panel
        ClsM2OtlCB                   matlab.ui.control.CheckBox
        ClsS2OtlCB                   matlab.ui.control.CheckBox
        ClsK2OtlCB                   matlab.ui.control.CheckBox
        ClsN2OtlCB                   matlab.ui.control.CheckBox
        ClsK1OtlCB                   matlab.ui.control.CheckBox
        ClsO1OtlCB                   matlab.ui.control.CheckBox
        ClsP1OtlCB                   matlab.ui.control.CheckBox
        ClsQ1OtlCB                   matlab.ui.control.CheckBox
        ClsS3AtmCB                   matlab.ui.control.CheckBox
        ClsS4AtmCB                   matlab.ui.control.CheckBox
        % Tab 2 preset signal dropdown
        ClsSignalPresetDropDown      matlab.ui.control.DropDown
        % Tab 2 period search controls
        ClsPeriodSearchCheckBox      matlab.ui.control.CheckBox
        ClsPeriodSearchPresetDropDown matlab.ui.control.DropDown

        % Tab 3 -- ML setup
        MLSetupTab                   matlab.ui.container.Tab
        GPRCheckBox                  matlab.ui.control.CheckBox
        SVRCheckBox                  matlab.ui.control.CheckBox
        RFCheckBox                   matlab.ui.control.CheckBox
        GBCheckBox                   matlab.ui.control.CheckBox
        KNNCheckBox                  matlab.ui.control.CheckBox
        SelectAllButton              matlab.ui.control.Button
        DeselectAllButton            matlab.ui.control.Button
        PresetDropDown               matlab.ui.control.DropDown
        WindowSizeSpinner            matlab.ui.control.Spinner
        NumTreesSpinner              matlab.ui.control.Spinner
        OptimizeCheckBox             matlab.ui.control.CheckBox
        RunCVCheckBox                matlab.ui.control.CheckBox
        MLComponentDropDown          matlab.ui.control.DropDown
        RunMLButton                  matlab.ui.control.Button
        MLProgressGauge              matlab.ui.control.LinearGauge
        MLStatusLabel                matlab.ui.control.Label
        % Tab 3 signal config checkboxes (mirrors Tab 2 but independent)
        MlAnnualCB                   matlab.ui.control.CheckBox
        MlSemiAnnualCB               matlab.ui.control.CheckBox
        MlTerAnnualCB                matlab.ui.control.CheckBox
        MlQuarterlyCB                matlab.ui.control.CheckBox
        MlDrac1CB                    matlab.ui.control.CheckBox
        MlDrac2CB                    matlab.ui.control.CheckBox
        MlDrac3CB                    matlab.ui.control.CheckBox
        MlDrac4CB                    matlab.ui.control.CheckBox
        MlDrac5CB                    matlab.ui.control.CheckBox
        MlDrac6CB                    matlab.ui.control.CheckBox
        MlDrac7CB                    matlab.ui.control.CheckBox
        MlDrac8CB                    matlab.ui.control.CheckBox
        MlMfCB                       matlab.ui.control.CheckBox
        MlMsfCB                      matlab.ui.control.CheckBox
        MlMmCB                       matlab.ui.control.CheckBox
        MlMsmCB                      matlab.ui.control.CheckBox
        MlChandlerCB                 matlab.ui.control.CheckBox
        MlS1AtmCB                    matlab.ui.control.CheckBox
        MlS2AtmCB                    matlab.ui.control.CheckBox
        MlMjoCB                      matlab.ui.control.CheckBox
        MlEnsoCB                     matlab.ui.control.CheckBox
        MlNodal18CB                  matlab.ui.control.CheckBox
        MlSignalPresetDropDown       matlab.ui.control.DropDown
        MlSyncFromClsButton          matlab.ui.control.Button
        % Tab 3 signal config checkboxes (Group 6: Sub-daily OTL -- hrts only)
        MlSubDailyPanel              matlab.ui.container.Panel
        MlM2OtlCB                    matlab.ui.control.CheckBox
        MlS2OtlCB                    matlab.ui.control.CheckBox
        MlK2OtlCB                    matlab.ui.control.CheckBox
        MlN2OtlCB                    matlab.ui.control.CheckBox
        MlK1OtlCB                    matlab.ui.control.CheckBox
        MlO1OtlCB                    matlab.ui.control.CheckBox
        MlP1OtlCB                    matlab.ui.control.CheckBox
        MlQ1OtlCB                    matlab.ui.control.CheckBox
        MlS3AtmCB                    matlab.ui.control.CheckBox
        MlS4AtmCB                    matlab.ui.control.CheckBox
        % Tab 3 period search controls
        MlPeriodSearchCheckBox       matlab.ui.control.CheckBox
        MlPeriodSearchPresetDropDown matlab.ui.control.DropDown
        % Per-method status lamps (colour = status)
        GPRLamp                      matlab.ui.control.Lamp
        SVRLamp                      matlab.ui.control.Lamp
        RFLamp                       matlab.ui.control.Lamp
        GBLamp                       matlab.ui.control.Lamp
        KNNLamp                      matlab.ui.control.Lamp

        % Tab 4 -- ML results
        MLResultsTab                 matlab.ui.container.Tab
        MLResultsTable               matlab.ui.control.Table
        PlotMLButton                 matlab.ui.control.Button
        TaylorDiagramButton          matlab.ui.control.Button
        MethodDropDown               matlab.ui.control.DropDown
        ResultsComponentDropDown     matlab.ui.control.DropDown
        SaveFigCheckBox              matlab.ui.control.CheckBox

        % Tab 5 -- Comparison & export
        ComparisonTab                matlab.ui.container.Tab
        ComparisonTable              matlab.ui.control.Table
        GenerateComparisonButton     matlab.ui.control.Button
        GenerateReportButton         matlab.ui.control.Button
        ExportMATButton              matlab.ui.control.Button
        ExportCSVButton              matlab.ui.control.Button
        ExportLaTeXButton            matlab.ui.control.Button
        ComparisonStatusLabel        matlab.ui.control.Label

        % Tab 6 -- Session / Batch
        SessionTab                   matlab.ui.container.Tab
        SaveSessionButton            matlab.ui.control.Button
        LoadSessionButton            matlab.ui.control.Button
        % Legacy classical-only batch (kept for backwards compatibility)
        BatchFolderButton            matlab.ui.control.Button
        BatchStatusLabel             matlab.ui.control.Label
        % New standardised ML batch controls
        BatchMLFolderButton          matlab.ui.control.Button
        BatchMLOutputButton          matlab.ui.control.Button
        BatchMLRunButton             matlab.ui.control.Button
        BatchMLTypesListBox          matlab.ui.control.ListBox
        BatchMLSaveCSVCheckBox       matlab.ui.control.CheckBox
        BatchMLSaveMATCheckBox       matlab.ui.control.CheckBox
        BatchMLParallelCheckBox      matlab.ui.control.CheckBox
        BatchMLInputLabel            matlab.ui.control.Label
        BatchMLOutputLabel           matlab.ui.control.Label
        BatchMLProgressLabel         matlab.ui.control.Label
        BatchMLSummaryTable          matlab.ui.control.Table
        StationNameLabel             matlab.ui.control.Label
    end

    %% -- App state ----------------------------------------------------------
    properties (Access = private)
        filename             % Current file path
        data_table           % Loaded data (table)
        results_classical    % Classical analysis results (struct array)
        results_ml           % ML results {n_comp x 5} cell
        num_components       % Number of coordinate components
        ml_methods_used      % Which methods have been run (cell of strings)
        signal_config_cls       % Signal config struct for Tab 2 (classical)
        signal_config_ml        % Signal config struct for Tab 3 (ML methods)
        period_search_config_cls % Period search config for Tab 2
        period_search_config_ml  % Period search config for Tab 3
        station_name         % 4-char station code (parsed from filename or entered)
        batch_output_folder  % Last used batch output folder
        is_hrts              % true when the loaded file is a high-rate (hrts) series
    end

    %% -- Constants ----------------------------------------------------------
    properties (Constant, Access = private)
        % Single source of truth for method names and column indices
        METHOD_NAMES = {'GPR', 'SVR', 'Random Forest', 'Gradient Boosting', 'KNN'}
        METHOD_IDX   = struct('GPR',1,'SVR',2,'RF',3,'GB',4,'KNN',5)
        DISPLAY_NAMES = {'GPR','SVR','Random Forest','Gradient Boosting','KNN'}
    end

    %% ========================================================================
    %  CALLBACKS
    %% ========================================================================
    methods (Access = private)

        function startupFcn(app)
            app.FileNameLabel.Text     = 'No file loaded';
            app.ClassicalStatusLabel.Text = 'Ready';
            app.MLStatusLabel.Text     = 'Select methods and component, then run.';
            app.ComparisonStatusLabel.Text = 'Run analyses first.';
            app.BatchStatusLabel.Text  = 'No batch job running.';
            app.station_name           = '';
            app.batch_output_folder    = '';
            % Initialise signal configs from gnss_ml_utils defaults
            app.signal_config_cls        = gnss_ml_utils('default_signal_config');
            app.signal_config_ml         = gnss_ml_utils('default_signal_config');
            app.period_search_config_cls = gnss_ml_utils('default_period_search_config');
            app.period_search_config_ml  = gnss_ml_utils('default_period_search_config');
            app.results_ml             = cell(0, 5);
            app.ml_methods_used        = {};
            app.is_hrts                = false;
            reset_lamps(app);
            % Sub-daily OTL panels are hidden until an hrts file is loaded
            app.ClsSubDailyPanel.Visible = 'off';
            app.MlSubDailyPanel.Visible  = 'off';
        end

        %% -- Tab 1: Load data ----------------------------------------------
        function LoadFileButtonPushed(app, ~)
            [file, path] = uigetfile( ...
                {'*.xlsx;*.xls;*.csv', 'Data Files (*.xlsx,*.xls,*.csv)'}, ...
                'Select GNSS coordinate file');
            if isequal(file, 0), return; end

            app.filename = fullfile(path, file);
            try
                app.data_table = readtable(app.filename, 'VariableNamingRule', 'preserve');

                % -- Preview (convert any datetime column to string) --------
                prev = app.data_table(1:min(10,height(app.data_table)), :);
                pc   = table2cell(prev);
                for ii = 1:numel(pc)
                    if isdatetime(pc{ii}), pc{ii} = char(pc{ii}); end
                    if isnumeric(pc{ii}),  pc{ii} = num2str(pc{ii},'%.6f'); end
                end
                app.DataPreviewTable.Data       = pc;
                app.DataPreviewTable.ColumnName = app.data_table.Properties.VariableNames;

                % -- Update state -------------------------------------------
                app.num_components = width(app.data_table) - 1;
                app.results_ml     = cell(app.num_components, 5);

                % -- Detect epoch type for user info -----------------------
                col1 = app.data_table{:,1};
                [~, epoch_type] = gnss_parse_epoch(col1);

                app.DataInfoLabel.Text = sprintf( ...
                    'Loaded: %d epochs  |  %d coordinate component(s)  |  Epoch type: %s', ...
                    height(app.data_table), app.num_components, epoch_type);
                app.FileNameLabel.Text      = ['File: ' file];
                app.FileNameLabel.FontColor = [0 0.55 0];

                % -- Parse station name from standardised filename ----------
                finfo = gnss_file_io('parse_filename', file);
                if finfo.valid
                    app.station_name = finfo.station;
                    sta_str = sprintf('Station: %s  |  Series type: %s', ...
                        finfo.station, finfo.type_str);
                    app.is_hrts = strcmpi(finfo.type, 'hrts');
                else
                    % Fallback: use first part before underscore or first 4 chars
                    [~, nm] = fileparts(file);
                    parts   = strsplit(nm, '_');
                    app.station_name = upper(parts{1}(1:min(4,end)));
                    sta_str = sprintf('Station: %s  (non-standard filename)', app.station_name);
                    % Heuristic fallback: flag hrts by 'hrts' in filename or
                    % by sub-daily epoch spacing (median step < 0.09 d ~ 2.2 h)
                    app.is_hrts = contains(lower(nm), 'hrts');
                    if ~app.is_hrts && height(app.data_table) > 1
                        col1_raw = app.data_table{:,1};
                        if isnumeric(col1_raw)
                            med_step = median(abs(diff(col1_raw)), 'omitnan');
                            app.is_hrts = (med_step > 0) && (med_step < 0.09);
                        end
                    end
                end
                app.StationNameLabel.Text      = sta_str;
                app.StationNameLabel.FontColor = [0 0.45 0.74];

                % -- Show / highlight Sub-daily OTL panel based on file type --
                update_subdaily_panel_visibility(app);

                comp_items = cellstr(string(1:app.num_components));
                for dd = {app.ClassicalComponentDropDown, app.MLComponentDropDown, ...
                           app.ResultsComponentDropDown}
                    dd{1}.Items = comp_items;
                    dd{1}.Value = comp_items{1};
                end

                uialert(app.UIFigure, sprintf('%d epochs loaded.', height(app.data_table)), ...
                    'Success', 'Icon', 'success');
            catch ME
                app.FileNameLabel.Text      = 'Error loading file.';
                app.FileNameLabel.FontColor = [0.85 0 0];
                uialert(app.UIFigure, ME.message, 'Load Error');
            end
        end

        %% -- Tab 2: Classical analysis -------------------------------------
        function RunClassicalButtonPushed(app, ~)
            if isempty(app.filename)
                uialert(app.UIFigure, 'Load a data file first.', 'No Data'); return;
            end
            app.ClassicalStatusLabel.Text      = 'Running classical analysis...';
            app.ClassicalStatusLabel.FontColor = [0 0 0.8];
            drawnow;
            try
                cfg = read_signal_config_from_ui(app, 'classical');
                app.signal_config_cls = cfg;
                % Embed period search config inside signal_config struct
                if app.ClsPeriodSearchCheckBox.Value
                    cfg.period_search = app.period_search_config_cls;
                end
                app.results_classical = embedded_gnss_engine(app.filename, cfg);
                update_classical_table(app);
                app.ClassicalStatusLabel.Text = sprintf( ...
                    'Complete -- %d components analysed.', length(app.results_classical));
                app.ClassicalStatusLabel.FontColor = [0 0.55 0];
            catch ME
                uialert(app.UIFigure, ME.message, 'Analysis Error');
                app.ClassicalStatusLabel.Text      = 'Failed.';
                app.ClassicalStatusLabel.FontColor = [0.85 0 0];
            end
        end

        function PlotClassicalButtonPushed(app, ~)
            if isempty(app.results_classical)
                uialert(app.UIFigure, 'Run classical analysis first.', 'No Results'); return;
            end
            c = str2double(app.ClassicalComponentDropDown.Value);
            embedded_gnss_plot(app.results_classical, c);
        end

        %% -- Tab 3: ML setup -----------------------------------------------
        function SelectAllButtonPushed(app, ~)
            for cb = {app.GPRCheckBox, app.SVRCheckBox, app.RFCheckBox, ...
                       app.GBCheckBox, app.KNNCheckBox}
                cb{1}.Value = true;
            end
        end

        function DeselectAllButtonPushed(app, ~)
            for cb = {app.GPRCheckBox, app.SVRCheckBox, app.RFCheckBox, ...
                       app.GBCheckBox, app.KNNCheckBox}
                cb{1}.Value = false;
            end
        end

        % -- Signal config helpers ------------------------------------------
        function cfg = read_signal_config_from_ui(app, tab)
        % READ_SIGNAL_CONFIG_FROM_UI  Read checkbox states into a signal_config struct.
        %   tab = 'classical' reads Tab 2 checkboxes; 'ml' reads Tab 3 checkboxes.
            cfg = gnss_ml_utils('default_signal_config');
            if strcmp(tab, 'classical')
                cfg.annual       = app.ClsAnnualCB.Value;
                cfg.semi_annual  = app.ClsSemiAnnualCB.Value;
                cfg.ter_annual   = app.ClsTerAnnualCB.Value;
                cfg.quarterly    = app.ClsQuarterlyCB.Value;
                cfg.draconitic_1 = app.ClsDrac1CB.Value;
                cfg.draconitic_2 = app.ClsDrac2CB.Value;
                cfg.draconitic_3 = app.ClsDrac3CB.Value;
                cfg.draconitic_4 = app.ClsDrac4CB.Value;
                cfg.draconitic_5 = app.ClsDrac5CB.Value;
                cfg.draconitic_6 = app.ClsDrac6CB.Value;
                cfg.draconitic_7 = app.ClsDrac7CB.Value;
                cfg.draconitic_8 = app.ClsDrac8CB.Value;
                cfg.mf_tidal     = app.ClsMfCB.Value;
                cfg.msf_tidal    = app.ClsMsfCB.Value;
                cfg.mm_tidal     = app.ClsMmCB.Value;
                cfg.msm_tidal    = app.ClsMsmCB.Value;
                cfg.chandler     = app.ClsChandlerCB.Value;
                cfg.s1_atm       = app.ClsS1AtmCB.Value;
                cfg.s2_atm       = app.ClsS2AtmCB.Value;
                cfg.mjo          = app.ClsMjoCB.Value;
                cfg.enso         = app.ClsEnsoCB.Value;
                cfg.nodal_18yr   = app.ClsNodal18CB.Value;
                % Group 6: Sub-daily OTL (hrts only)
                cfg.m2_otl       = app.ClsM2OtlCB.Value;
                cfg.s2_otl       = app.ClsS2OtlCB.Value;
                cfg.k2_otl       = app.ClsK2OtlCB.Value;
                cfg.n2_otl       = app.ClsN2OtlCB.Value;
                cfg.k1_otl       = app.ClsK1OtlCB.Value;
                cfg.o1_otl       = app.ClsO1OtlCB.Value;
                cfg.p1_otl       = app.ClsP1OtlCB.Value;
                cfg.q1_otl       = app.ClsQ1OtlCB.Value;
                cfg.s3_atm       = app.ClsS3AtmCB.Value;
                cfg.s4_atm       = app.ClsS4AtmCB.Value;
            else
                cfg.annual       = app.MlAnnualCB.Value;
                cfg.semi_annual  = app.MlSemiAnnualCB.Value;
                cfg.ter_annual   = app.MlTerAnnualCB.Value;
                cfg.quarterly    = app.MlQuarterlyCB.Value;
                cfg.draconitic_1 = app.MlDrac1CB.Value;
                cfg.draconitic_2 = app.MlDrac2CB.Value;
                cfg.draconitic_3 = app.MlDrac3CB.Value;
                cfg.draconitic_4 = app.MlDrac4CB.Value;
                cfg.draconitic_5 = app.MlDrac5CB.Value;
                cfg.draconitic_6 = app.MlDrac6CB.Value;
                cfg.draconitic_7 = app.MlDrac7CB.Value;
                cfg.draconitic_8 = app.MlDrac8CB.Value;
                cfg.mf_tidal     = app.MlMfCB.Value;
                cfg.msf_tidal    = app.MlMsfCB.Value;
                cfg.mm_tidal     = app.MlMmCB.Value;
                cfg.msm_tidal    = app.MlMsmCB.Value;
                cfg.chandler     = app.MlChandlerCB.Value;
                cfg.s1_atm       = app.MlS1AtmCB.Value;
                cfg.s2_atm       = app.MlS2AtmCB.Value;
                cfg.mjo          = app.MlMjoCB.Value;
                cfg.enso         = app.MlEnsoCB.Value;
                cfg.nodal_18yr   = app.MlNodal18CB.Value;
                % Group 6: Sub-daily OTL (hrts only)
                cfg.m2_otl       = app.MlM2OtlCB.Value;
                cfg.s2_otl       = app.MlS2OtlCB.Value;
                cfg.k2_otl       = app.MlK2OtlCB.Value;
                cfg.n2_otl       = app.MlN2OtlCB.Value;
                cfg.k1_otl       = app.MlK1OtlCB.Value;
                cfg.o1_otl       = app.MlO1OtlCB.Value;
                cfg.p1_otl       = app.MlP1OtlCB.Value;
                cfg.q1_otl       = app.MlQ1OtlCB.Value;
                cfg.s3_atm       = app.MlS3AtmCB.Value;
                cfg.s4_atm       = app.MlS4AtmCB.Value;
            end
        end

        function write_signal_config_to_ui(app, cfg, tab)
        % WRITE_SIGNAL_CONFIG_TO_UI  Push a signal_config struct into checkboxes.
            if strcmp(tab, 'classical')
                app.ClsAnnualCB.Value      = cfg.annual;
                app.ClsSemiAnnualCB.Value  = cfg.semi_annual;
                app.ClsTerAnnualCB.Value   = cfg.ter_annual;
                app.ClsQuarterlyCB.Value   = cfg.quarterly;
                app.ClsDrac1CB.Value       = cfg.draconitic_1;
                app.ClsDrac2CB.Value       = cfg.draconitic_2;
                app.ClsDrac3CB.Value       = cfg.draconitic_3;
                app.ClsDrac4CB.Value       = cfg.draconitic_4;
                app.ClsDrac5CB.Value       = cfg.draconitic_5;
                app.ClsDrac6CB.Value       = cfg.draconitic_6;
                app.ClsDrac7CB.Value       = cfg.draconitic_7;
                app.ClsDrac8CB.Value       = cfg.draconitic_8;
                app.ClsMfCB.Value          = cfg.mf_tidal;
                app.ClsMsfCB.Value         = cfg.msf_tidal;
                app.ClsMmCB.Value          = cfg.mm_tidal;
                app.ClsMsmCB.Value         = cfg.msm_tidal;
                app.ClsChandlerCB.Value    = cfg.chandler;
                app.ClsS1AtmCB.Value       = cfg.s1_atm;
                app.ClsS2AtmCB.Value       = cfg.s2_atm;
                app.ClsMjoCB.Value         = cfg.mjo;
                app.ClsEnsoCB.Value        = cfg.enso;
                app.ClsNodal18CB.Value     = cfg.nodal_18yr;
                % Group 6: Sub-daily OTL (hrts only)
                if isfield(cfg,'m2_otl'),  app.ClsM2OtlCB.Value = cfg.m2_otl;  end
                if isfield(cfg,'s2_otl'),  app.ClsS2OtlCB.Value = cfg.s2_otl;  end
                if isfield(cfg,'k2_otl'),  app.ClsK2OtlCB.Value = cfg.k2_otl;  end
                if isfield(cfg,'n2_otl'),  app.ClsN2OtlCB.Value = cfg.n2_otl;  end
                if isfield(cfg,'k1_otl'),  app.ClsK1OtlCB.Value = cfg.k1_otl;  end
                if isfield(cfg,'o1_otl'),  app.ClsO1OtlCB.Value = cfg.o1_otl;  end
                if isfield(cfg,'p1_otl'),  app.ClsP1OtlCB.Value = cfg.p1_otl;  end
                if isfield(cfg,'q1_otl'),  app.ClsQ1OtlCB.Value = cfg.q1_otl;  end
                if isfield(cfg,'s3_atm'),  app.ClsS3AtmCB.Value = cfg.s3_atm;  end
                if isfield(cfg,'s4_atm'),  app.ClsS4AtmCB.Value = cfg.s4_atm;  end
            else
                app.MlAnnualCB.Value       = cfg.annual;
                app.MlSemiAnnualCB.Value   = cfg.semi_annual;
                app.MlTerAnnualCB.Value    = cfg.ter_annual;
                app.MlQuarterlyCB.Value    = cfg.quarterly;
                app.MlDrac1CB.Value        = cfg.draconitic_1;
                app.MlDrac2CB.Value        = cfg.draconitic_2;
                app.MlDrac3CB.Value        = cfg.draconitic_3;
                app.MlDrac4CB.Value        = cfg.draconitic_4;
                app.MlDrac5CB.Value        = cfg.draconitic_5;
                app.MlDrac6CB.Value        = cfg.draconitic_6;
                app.MlDrac7CB.Value        = cfg.draconitic_7;
                app.MlDrac8CB.Value        = cfg.draconitic_8;
                app.MlMfCB.Value           = cfg.mf_tidal;
                app.MlMsfCB.Value          = cfg.msf_tidal;
                app.MlMmCB.Value           = cfg.mm_tidal;
                app.MlMsmCB.Value          = cfg.msm_tidal;
                app.MlChandlerCB.Value     = cfg.chandler;
                app.MlS1AtmCB.Value        = cfg.s1_atm;
                app.MlS2AtmCB.Value        = cfg.s2_atm;
                app.MlMjoCB.Value          = cfg.mjo;
                app.MlEnsoCB.Value         = cfg.enso;
                app.MlNodal18CB.Value      = cfg.nodal_18yr;
                % Group 6: Sub-daily OTL (hrts only)
                if isfield(cfg,'m2_otl'),  app.MlM2OtlCB.Value = cfg.m2_otl;  end
                if isfield(cfg,'s2_otl'),  app.MlS2OtlCB.Value = cfg.s2_otl;  end
                if isfield(cfg,'k2_otl'),  app.MlK2OtlCB.Value = cfg.k2_otl;  end
                if isfield(cfg,'n2_otl'),  app.MlN2OtlCB.Value = cfg.n2_otl;  end
                if isfield(cfg,'k1_otl'),  app.MlK1OtlCB.Value = cfg.k1_otl;  end
                if isfield(cfg,'o1_otl'),  app.MlO1OtlCB.Value = cfg.o1_otl;  end
                if isfield(cfg,'p1_otl'),  app.MlP1OtlCB.Value = cfg.p1_otl;  end
                if isfield(cfg,'q1_otl'),  app.MlQ1OtlCB.Value = cfg.q1_otl;  end
                if isfield(cfg,'s3_atm'),  app.MlS3AtmCB.Value = cfg.s3_atm;  end
                if isfield(cfg,'s4_atm'),  app.MlS4AtmCB.Value = cfg.s4_atm;  end
            end
        end

        function ClsSignalPresetDropDownChanged(app, ~)
            cfg = apply_signal_preset(app.ClsSignalPresetDropDown.Value);
            write_signal_config_to_ui(app, cfg, 'classical');
        end

        function MlSignalPresetDropDownChanged(app, ~)
            cfg = apply_signal_preset(app.MlSignalPresetDropDown.Value);
            write_signal_config_to_ui(app, cfg, 'ml');
        end

        function MlSyncFromClsButtonPushed(app, ~)
        % Copy Tab 2 signal config AND period search settings into Tab 3
            cfg = read_signal_config_from_ui(app, 'classical');
            write_signal_config_to_ui(app, cfg, 'ml');
            app.MlSignalPresetDropDown.Value       = app.ClsSignalPresetDropDown.Value;
            app.MlPeriodSearchCheckBox.Value       = app.ClsPeriodSearchCheckBox.Value;
            app.MlPeriodSearchPresetDropDown.Value = app.ClsPeriodSearchPresetDropDown.Value;
            app.period_search_config_ml            = app.period_search_config_cls;
        end

        function ClsPeriodSearchPresetChanged(app, ~)
            app.period_search_config_cls = apply_period_search_preset( ...
                app.ClsPeriodSearchPresetDropDown.Value);
        end

        function MlPeriodSearchPresetChanged(app, ~)
            app.period_search_config_ml  = apply_period_search_preset( ...
                app.MlPeriodSearchPresetDropDown.Value);
        end

        function PresetDropDownValueChanged(app, ~)
            switch app.PresetDropDown.Value
                case 'Daily GNSS (default)'
                    app.WindowSizeSpinner.Value  = 30;
                    app.NumTreesSpinner.Value    = 200;
                case 'Sub-daily (high rate)'
                    app.WindowSizeSpinner.Value  = 120;
                    app.NumTreesSpinner.Value    = 300;
                case 'Weekly data'
                    app.WindowSizeSpinner.Value  = 12;
                    app.NumTreesSpinner.Value    = 150;
            end
        end

        function RunMLButtonPushed(app, ~)
            if isempty(app.data_table)
                uialert(app.UIFigure, 'Load a data file first.', 'No Data'); return;
            end

            % -- Collect selected methods -----------------------------------
            method_flags = [app.GPRCheckBox.Value, app.SVRCheckBox.Value, ...
                            app.RFCheckBox.Value,  app.GBCheckBox.Value, ...
                            app.KNNCheckBox.Value];
            method_keys  = {'GPR','SVR','RF','GB','KNN'};
            methods_sel  = method_keys(logical(method_flags));

            if isempty(methods_sel)
                uialert(app.UIFigure, 'Select at least one method.', 'No Methods'); return;
            end

            % -- Parameters ------------------------------------------------
            c           = str2double(app.MLComponentDropDown.Value);
            window_size = app.WindowSizeSpinner.Value;
            num_trees   = app.NumTreesSpinner.Value;
            optimize    = app.OptimizeCheckBox.Value;
            run_cv      = app.RunCVCheckBox.Value;
            ml_sig_cfg  = read_signal_config_from_ui(app, 'ml');
            app.signal_config_ml = ml_sig_cfg;
            if app.MlPeriodSearchCheckBox.Value
                ml_sig_cfg.period_search = app.period_search_config_ml;
            end

            % -- Extract component data (NaN-safe) --------------------------
            data_raw = app.data_table{:, c + 1};
            data_in  = extract_component(app, data_raw);

            if length(data_in) < 2 * window_size
                uialert(app.UIFigure, ...
                    sprintf('Too few data points (%d) for window size %d.', ...
                    length(data_in), window_size), 'Insufficient Data');
                return;
            end

            % -- Pass classical det_model for correct velocity anchor --------
            % The classical engine fitted the deterministic model using the
            % physical time axis (J2000 days / MJD).  ML denoisers internally
            % use t = (1:n)' -- a plain epoch index -- which gives a different
            % rate coefficient when the epoch spacing is not exactly 1 day
            % (gaps, high-rate, weekly data).  To ensure ML velocity matches
            % the geodetically correct classical value, we pass the classical
            % det_model so gnss_run_single_method can substitute it after
            % the ML denoiser runs.
            cls_det_model_c = [];
            if ~isempty(app.results_classical) && ...
               length(app.results_classical) >= c && ...
               isfield(app.results_classical(c), 'det_model')
                cls_det_model_c = app.results_classical(c).det_model;
            end

            % -- Ensure results cell is large enough -----------------------
            if size(app.results_ml,1) < app.num_components || size(app.results_ml,2) < 5
                old = app.results_ml;
                app.results_ml = cell(app.num_components, 5);
                app.results_ml(1:size(old,1), 1:size(old,2)) = old;
            end

            % -- Reset lamps for selected methods --------------------------
            set_lamp(app, methods_sel, 'idle');
            n_sel = length(methods_sel);
            app.MLProgressGauge.Value = 0;

            % -- Detect Parallel Computing Toolbox -------------------------
            use_parallel = license('test', 'Distrib_Computing_Toolbox') && n_sel > 1;

            % -- Run methods (parallel if available) -----------------------
            temp_results = cell(1, n_sel);

            if use_parallel
                app.MLStatusLabel.Text = sprintf( ...
                    'Running %d methods in parallel...', n_sel);
                app.MLStatusLabel.FontColor = [0 0 0.8];
                drawnow;

                parfor mi = 1:n_sel
                    try
                        temp_results{mi} = gnss_run_single_method( ...
                            methods_sel{mi}, data_in, window_size, num_trees, ...
                            optimize, run_cv, ml_sig_cfg, cls_det_model_c);
                    catch ME
                        temp_results{mi} = struct('error', ME.message, ...
                            'method', methods_sel{mi});
                    end
                end

                % Store and report
                for mi = 1:n_sel
                    col_idx = app.METHOD_IDX.(methods_sel{mi});
                    if isfield(temp_results{mi}, 'error')
                        uialert(app.UIFigure, ...
                            sprintf('%s failed: %s', methods_sel{mi}, temp_results{mi}.error), ...
                            'Method Error');
                        set_lamp(app, methods_sel(mi), 'error');
                    else
                        app.results_ml{c, col_idx} = temp_results{mi};
                        app.ml_methods_used = union(app.ml_methods_used, methods_sel{mi});
                        set_lamp(app, methods_sel(mi), 'done');
                    end
                end
                app.MLProgressGauge.Value = 100;

            else
                % Sequential
                for mi = 1:n_sel
                    meth = methods_sel{mi};
                    app.MLStatusLabel.Text = sprintf('Running %s (%d/%d)...', meth, mi, n_sel);
                    app.MLStatusLabel.FontColor = [0 0 0.8];
                    set_lamp(app, {meth}, 'running');
                    drawnow;

                    col_idx = app.METHOD_IDX.(meth);
                    try
                        app.results_ml{c, col_idx} = gnss_run_single_method( ...
                            meth, data_in, window_size, num_trees, optimize, run_cv, ...
                            ml_sig_cfg, cls_det_model_c);
                        app.ml_methods_used = union(app.ml_methods_used, meth);
                        set_lamp(app, {meth}, 'done');
                    catch ME
                        uialert(app.UIFigure, sprintf('%s failed: %s', meth, ME.message), 'Error');
                        set_lamp(app, {meth}, 'error');
                    end
                    app.MLProgressGauge.Value = (mi/n_sel)*100;
                    drawnow;
                end
            end

            update_ml_results_table(app, c);
            app.MLStatusLabel.Text = sprintf( ...
                'Done -- Component %d | %d method(s).', c, n_sel);
            app.MLStatusLabel.FontColor = [0 0.55 0];
        end

        %% -- Tab 4: ML results ---------------------------------------------
        function PlotMLButtonPushed(app, ~)
            c        = str2double(app.ResultsComponentDropDown.Value);
            meth_disp = app.MethodDropDown.Value;
            meth_key  = display_to_key(meth_disp);
            col_idx   = app.METHOD_IDX.(meth_key);

            if isempty(app.results_ml) || size(app.results_ml,1) < c || ...
               isempty(app.results_ml{c, col_idx})
                uialert(app.UIFigure, ...
                    sprintf('Run %s for component %d first.', meth_disp, c), 'No Results');
                return;
            end

            data_in = extract_component(app, app.data_table{:, c+1});
            % Pass datetime vector if available for dd-mm-yyyy x-axis
            dates_ml = [];
            if isfield(app.results_classical(c), 'dates') && ...
               ~isempty(app.results_classical(c).dates)
                dates_ml = app.results_classical(c).dates;
            end
            gnss_ml_plot(data_in, app.results_ml{c, col_idx}, c, ...
                'SaveFig', app.SaveFigCheckBox.Value, ...
                'OutputDir', './gnss_figures', ...
                'Dates', dates_ml, ...
                'StationName', app.station_name);
        end

        function TaylorDiagramButtonPushed(app, ~)
            c = str2double(app.ResultsComponentDropDown.Value);
            if isempty(app.results_ml) || size(app.results_ml,1) < c
                uialert(app.UIFigure,'Run ML methods first.','No Results'); return;
            end

            % Collect all non-empty results for this component
            rc = {};
            for mi = 1:5
                if ~isempty(app.results_ml{c, mi})
                    rc{end+1} = app.results_ml{c, mi}; %#ok<AGROW>
                end
            end
            if numel(rc) < 2
                uialert(app.UIFigure,'Run at least 2 methods for Taylor diagram.','Insufficient'); return;
            end

            data_in = extract_component(app, app.data_table{:, c+1});
            dates_ml = [];
            if isfield(app.results_classical(c), 'dates') && ...
               ~isempty(app.results_classical(c).dates)
                dates_ml = app.results_classical(c).dates;
            end
            gnss_ml_plot(data_in, rc, c, ...
                'SaveFig', app.SaveFigCheckBox.Value, ...
                'OutputDir', './gnss_figures', ...
                'Dates', dates_ml, ...
                'StationName', app.station_name);
        end

        %% -- Tab 5: Comparison & export ------------------------------------
        function GenerateComparisonButtonPushed(app, ~)
            if isempty(app.results_classical) || isempty(app.results_ml)
                uialert(app.UIFigure,'Run both classical and ML analyses first.','Incomplete'); return;
            end
            generate_comparison_plots(app);
            app.ComparisonStatusLabel.Text      = 'Comparison plots generated.';
            app.ComparisonStatusLabel.FontColor = [0 0.55 0];
        end

        function GenerateReportButtonPushed(app, ~)
            if isempty(app.results_classical)
                uialert(app.UIFigure,'Run analyses first.','No Results'); return;
            end
            generate_text_report(app);
        end

        function ExportMATButtonPushed(app, ~)
            [file, path] = uiputfile('*.mat','Save Results (.mat)');
            if isequal(file,0), return; end
            results_classical = app.results_classical; %#ok<PROP>
            results_ml        = app.results_ml;        %#ok<PROP>
            ml_methods_used   = app.ml_methods_used;   %#ok<PROP>
            save(fullfile(path,file), 'results_classical','results_ml','ml_methods_used');
            app.ComparisonStatusLabel.Text = ['Saved: ' file];
            app.ComparisonStatusLabel.FontColor = [0 0.55 0];
        end

        function ExportCSVButtonPushed(app, ~)
            [file, path] = uiputfile('*.csv','Export comparison table (.csv)');
            if isequal(file,0), return; end
            tbl = build_comparison_table_data(app);
            if isempty(tbl), return; end
            writetable(tbl, fullfile(path,file));
            app.ComparisonStatusLabel.Text = ['CSV saved: ' file];
        end

        function ExportLaTeXButtonPushed(app, ~)
            [file, path] = uiputfile('*.tex','Export LaTeX table (.tex)');
            if isequal(file,0), return; end
            export_latex_table(app, fullfile(path,file));
            app.ComparisonStatusLabel.Text = ['LaTeX saved: ' file];
        end

        %% -- Tab 6: Session / Batch ----------------------------------------
        function SaveSessionButtonPushed(app, ~)
            [file, path] = uiputfile('*.mat','Save Session');
            if isequal(file,0), return; end
            session.filename          = app.filename;
            session.data_table        = app.data_table;
            session.results_classical = app.results_classical;
            session.results_ml        = app.results_ml;
            session.num_components    = app.num_components;
            session.ml_methods_used   = app.ml_methods_used;
            session.station_name      = app.station_name;
            save(fullfile(path,file),'session');
            app.BatchStatusLabel.Text = ['Session saved: ' file];
        end

        function LoadSessionButtonPushed(app, ~)
            [file, path] = uigetfile('*.mat','Load Session');
            if isequal(file,0), return; end
            S = load(fullfile(path,file),'session');
            s = S.session;
            app.filename          = s.filename;
            app.data_table        = s.data_table;
            app.results_classical = s.results_classical;
            app.results_ml        = s.results_ml;
            app.num_components    = s.num_components;
            app.ml_methods_used   = s.ml_methods_used;
            if isfield(s,'station_name'), app.station_name = s.station_name; end

            app.FileNameLabel.Text      = ['Loaded: ' app.filename];
            app.FileNameLabel.FontColor = [0 0.55 0];
            if ~isempty(app.station_name)
                app.StationNameLabel.Text = ['Station: ' app.station_name];
            end
            comp_items = cellstr(string(1:app.num_components));
            for dd = {app.ClassicalComponentDropDown, app.MLComponentDropDown, ...
                       app.ResultsComponentDropDown}
                dd{1}.Items = comp_items;
                dd{1}.Value = comp_items{1};
            end
            if ~isempty(app.results_classical), update_classical_table(app); end
            app.BatchStatusLabel.Text = ['Session loaded: ' file];
        end

        % -- Legacy classical-only batch (single folder, no naming check) --
        function BatchFolderButtonPushed(app, ~)
            folder = uigetdir(pwd,'Select folder containing CSV/XLSX station files');
            if isequal(folder,0), return; end

            files = [dir(fullfile(folder,'*.csv')); dir(fullfile(folder,'*.xlsx'))];
            if isempty(files)
                uialert(app.UIFigure,'No CSV/XLSX files found in selected folder.','No Files');
                return;
            end

            out_dir = fullfile(folder,'batch_results');
            params = struct( ...
                'window_size', app.WindowSizeSpinner.Value, ...
                'num_trees',   app.NumTreesSpinner.Value, ...
                'optimize',    app.OptimizeCheckBox.Value, ...
                'run_cv',      false);

            method_flags = [app.GPRCheckBox.Value, app.SVRCheckBox.Value, ...
                            app.RFCheckBox.Value,  app.GBCheckBox.Value, ...
                            app.KNNCheckBox.Value];
            method_keys  = {'GPR','SVR','RF','GB','KNN'};
            methods_sel  = method_keys(logical(method_flags));
            if isempty(methods_sel)
                uialert(app.UIFigure,'Select at least one method first.','No Methods');
                return;
            end

            app.BatchStatusLabel.Text = sprintf( ...
                'Classical batch: %d files x %d methods ...', ...
                length(files), length(methods_sel));
            drawnow;

            try
                gnss_batch_analyse(folder, out_dir, methods_sel, params);
                app.BatchStatusLabel.Text = sprintf( ...
                    'Classical batch complete -- %d files. Results: %s', ...
                    length(files), out_dir);
            catch ME
                app.BatchStatusLabel.Text = ['Batch failed: ' ME.message];
                uialert(app.UIFigure, ME.message, 'Batch Error');
            end
        end

        % -- New standardised ML batch: select input folder -----------------
        function BatchMLFolderButtonPushed(app, ~)
            folder = uigetdir(pwd, ...
                'Select folder with standardised CSV files (SSSS_dlts/hrts/wlts_txyz.csv)');
            if isequal(folder,0), return; end
            app.BatchMLInputLabel.Text = ['Input: ' folder];

            % Scan and show found files
            try
                types_sel = app.BatchMLTypesListBox.Value;
                if isempty(types_sel), types_sel = {'dlts','hrts','wlts'}; end
                files = gnss_file_io('scan_folder', folder, 'Types', types_sel, ...
                                     'Verbose', false);
                if isempty(files)
                    app.BatchMLProgressLabel.Text = ...
                        'No conforming files found. Files must be named: SSSS_dlts/hrts/wlts_txyz.csv';
                    app.BatchMLProgressLabel.FontColor = [0.8 0.3 0];
                else
                    stations = unique({files.station});
                    app.BatchMLProgressLabel.Text = sprintf( ...
                        'Found %d file(s) | %d station(s): %s', ...
                        numel(files), numel(stations), strjoin(stations, ', '));
                    app.BatchMLProgressLabel.FontColor = [0 0.55 0];
                    % Enable run button
                    app.BatchMLRunButton.Enable = 'on';
                    % Store folder in tag for later use
                    app.BatchMLFolderButton.Tag = folder;
                end
            catch ME
                app.BatchMLProgressLabel.Text = ['Scan error: ' ME.message];
                app.BatchMLProgressLabel.FontColor = [0.85 0 0];
            end
        end

        % -- Select batch output folder ------------------------------------
        function BatchMLOutputButtonPushed(app, ~)
            folder = uigetdir(pwd, 'Select output folder for batch results');
            if isequal(folder,0), return; end
            app.batch_output_folder    = folder;
            app.BatchMLOutputLabel.Text = ['Output: ' folder];
        end

        % -- Run standardised ML batch -------------------------------------
        function BatchMLRunButtonPushed(app, ~)
            input_folder = app.BatchMLFolderButton.Tag;
            if isempty(input_folder) || ~isfolder(input_folder)
                uialert(app.UIFigure,'Select an input folder first.','No Folder');
                return;
            end

            % Output folder
            if isempty(app.batch_output_folder)
                out_folder = fullfile(input_folder, 'batch_results');
            else
                out_folder = app.batch_output_folder;
            end

            % Methods
            method_flags = [app.GPRCheckBox.Value, app.SVRCheckBox.Value, ...
                            app.RFCheckBox.Value,  app.GBCheckBox.Value, ...
                            app.KNNCheckBox.Value];
            method_keys  = {'GPR','SVR','RF','GB','KNN'};
            methods_sel  = method_keys(logical(method_flags));
            if isempty(methods_sel)
                uialert(app.UIFigure,'Select at least one ML method (Tab 3).','No Methods');
                return;
            end

            % Types filter
            types_sel = app.BatchMLTypesListBox.Value;
            if isempty(types_sel), types_sel = {'dlts','hrts','wlts'}; end

            % Build params from current App settings
            params = struct( ...
                'window_size',   0, ...   % 0 = auto by type
                'num_trees',     app.NumTreesSpinner.Value, ...
                'optimize',      app.OptimizeCheckBox.Value, ...
                'run_cv',        app.RunCVCheckBox.Value, ...
                'learn_rate',    0.1, ...
                'max_depth',     3, ...
                'num_neighbors', 5, ...
                'max_evals',     10);

            app.BatchMLRunButton.Enable    = 'off';
            app.BatchMLProgressLabel.Text  = 'Batch running -- see Command Window for progress...';
            app.BatchMLProgressLabel.FontColor = [0 0 0.8];
            app.BatchStatusLabel.Text      = 'ML Batch in progress...';
            drawnow;

            try
                summary = gnss_file_io('batch', input_folder, methods_sel, params, ...
                    'OutputFolder',  out_folder, ...
                    'Types',         types_sel, ...
                    'SaveMAT',       app.BatchMLSaveMATCheckBox.Value, ...
                    'SaveCSV',       app.BatchMLSaveCSVCheckBox.Value, ...
                    'Parallel',      app.BatchMLParallelCheckBox.Value, ...
                    'Verbose',       true);

                % Show summary in table
                if ~isempty(summary)
                    app.BatchMLSummaryTable.Data       = table2cell(summary);
                    app.BatchMLSummaryTable.ColumnName = summary.Properties.VariableNames;
                end

                n_sta = numel(unique(summary.Station));
                app.BatchMLProgressLabel.Text = sprintf( ...
                    'Batch complete -- %d station(s) | Results: %s', n_sta, out_folder);
                app.BatchMLProgressLabel.FontColor = [0 0.55 0];
                app.BatchStatusLabel.Text = sprintf( ...
                    'ML Batch done: %d station(s) x %d method(s). Output: %s', ...
                    n_sta, numel(methods_sel), out_folder);
                uialert(app.UIFigure, ...
                    sprintf('Batch complete!\n%d station(s) processed.\nResults saved to:\n%s', ...
                    n_sta, out_folder), 'Batch Complete', 'Icon','success');

            catch ME
                app.BatchMLProgressLabel.Text  = ['Batch FAILED: ' ME.message];
                app.BatchMLProgressLabel.FontColor = [0.85 0 0];
                app.BatchStatusLabel.Text      = ['Batch failed: ' ME.message];
                uialert(app.UIFigure, ME.message, 'Batch Error');
            end
            app.BatchMLRunButton.Enable = 'on';
        end

    end % callbacks


    %% ========================================================================
    %  PRIVATE HELPERS
    %% ========================================================================
    methods (Access = private)

        % -- Show/hide and highlight Sub-daily OTL panel --------------------
        function update_subdaily_panel_visibility(app)
        % UPDATE_SUBDAILY_PANEL_VISIBILITY
        %   Shows the Group 6 (Sub-daily / OTL) panel on both Tabs 2 and 3
        %   when an hrts file is loaded, and hides it for dlts / wlts files.
        %   When visible the panel border turns amber to draw attention.
            if app.is_hrts
                vis = 'on';
                border_col = [0.85 0.55 0.0];   % amber highlight
                title_sfx  = '  [hrts -- active]';
            else
                vis = 'off';
                border_col = [0.5 0.5 0.5];
                title_sfx  = '';
            end
            app.ClsSubDailyPanel.Visible         = vis;
            app.MlSubDailyPanel.Visible          = vis;
            app.ClsSubDailyPanel.ForegroundColor = border_col;
            app.MlSubDailyPanel.ForegroundColor  = border_col;
            app.ClsSubDailyPanel.Title = ...
                ['SUB-DAILY / OTL  (high-rate data)' title_sfx];
            app.MlSubDailyPanel.Title  = ...
                ['SUB-DAILY / OTL  (high-rate data)' title_sfx];
        end

        % -- Safe component extraction (handles NaN gaps) ------------------
        function data_out = extract_component(app, data_raw) %#ok<INUSL>
            data_raw = data_raw(:);
            valid    = ~isnan(data_raw);
            x_good   = data_raw(valid);
            idx_good = find(valid);
            if isempty(x_good)
                error('GNSS_App:noData','Component contains only NaN values.');
            end
            if any(~valid)
                % Linear interpolation across gaps
                data_out = interp1(idx_good, x_good, (1:length(data_raw))', ...
                                   'linear', 'extrap');
            else
                data_out = x_good;
            end
        end

        % -- Update classical results table --------------------------------
        function update_classical_table(app)
            n   = length(app.results_classical);
            dat = cell(n, 15);
            for ii = 1:n
                r = app.results_classical(ii);
                vel     = r.velocity;
                vel_unc = NaN;
                if isfield(r,'vel_uncertainty'), vel_unc = r.vel_uncertainty; end
                dat(ii,:) = {ii, r.sigma, r.sigma*1000, r.k, ...
                             r.white, r.flicker, r.rw, length(r.steps), ...
                             get_detected_T(r,'annual'), ...
                             get_detected_T(r,'semi_annual'), ...
                             get_detected_T(r,'draconitic_1'), ...
                             r.A_annual, r.A_semi, ...
                             vel, vel_unc};
            end
            app.ClassicalResultsTable.Data = dat;
            app.ClassicalResultsTable.ColumnName = ...
                {'Comp','sigma (m)','sigma (mm)','k','White','Flicker','RW','Steps', ...
                 'Ann.T (d)','Semi.T (d)','Drac1.T (d)','Ann.amp (mm)','Semi.amp (mm)', ...
                 'Vel (mm/yr)','Vel unc (mm/yr)'};
            update_comparison_table(app);
        end

        % -- Update ML results table (Tab 4) -------------------------------
        function update_ml_results_table(app, comp)
            dat = {};
            for mi = 1:5
                if ~isempty(app.results_ml) && size(app.results_ml,1) >= comp && ...
                   ~isempty(app.results_ml{comp, mi})
                    r   = app.results_ml{comp, mi};
                    % Method-specific velocity and uncertainty from post-denoising re-fit
                    vel     = NaN;  vel_unc = NaN;
                    if isfield(r,'det_model') && ~isempty(r.det_model)
                        if isfield(r.det_model,'velocity'),        vel     = r.det_model.velocity;        end
                        if isfield(r.det_model,'vel_uncertainty'), vel_unc = r.det_model.vel_uncertainty; end
                    end
                    % Method-specific spectral index from denoised residuals
                    ml_k = NaN;
                    if isfield(r,'k_denoised'), ml_k = r.k_denoised; end
                    row = {app.METHOD_NAMES{mi}, ...
                           r.residual_std, r.residual_std*1000, ...
                           r.snr_improvement, r.noise_reduction, ...
                           r.rmse*1000, r.mae*1000, ml_k, vel, vel_unc};
                    if isfield(r,'aic')
                        row{end+1} = r.aic; %#ok<AGROW>
                        row{end+1} = r.bic; %#ok<AGROW>
                    end
                    if isfield(r,'residual_gaussian')
                        row{end+1} = r.residual_gaussian; %#ok<AGROW>
                    end
                    if isfield(r,'cv_rmse') && ~isnan(r.cv_rmse)
                        row{end+1} = r.cv_rmse; %#ok<AGROW>
                    end
                    dat(end+1,:) = row; %#ok<AGROW>
                end
            end
            app.MLResultsTable.Data = dat;
            app.MLResultsTable.ColumnName = ...
                {'Method','sigma(m)','sigma(mm)','SNR(dB)','NoiseRed%','RMSE(mm)','MAE(mm)', ...
                 'k(denoised)','Vel(mm/yr)','Vel unc(mm/yr)','AIC','BIC','Gaussian','CV-RMSE'};
            update_comparison_table(app);
        end

        % -- Master comparison table (Tab 5) -------------------------------
        function update_comparison_table(app)
            tbl = build_comparison_table_data(app);
            if isempty(tbl), return; end
            app.ComparisonTable.Data       = table2cell(tbl);
            app.ComparisonTable.ColumnName = tbl.Properties.VariableNames;
        end

        function tbl = build_comparison_table_data(app)
            tbl = [];
            if isempty(app.results_classical), return; end
            rows = {};
            for c = 1:length(app.results_classical)
                cls_r     = app.results_classical(c);
                cls_sigma = cls_r.sigma;
                cls_k     = cls_r.k;          % classical spectral index
                cls_vel   = cls_r.velocity;
                cls_vunc  = NaN;
                if isfield(cls_r,'vel_uncertainty'), cls_vunc = cls_r.vel_uncertainty; end
                for mi = 1:5
                    if ~isempty(app.results_ml) && ...
                       size(app.results_ml,1) >= c && ...
                       ~isempty(app.results_ml{c,mi})
                        r  = app.results_ml{c,mi};
                        impr = (cls_sigma - r.residual_std) / cls_sigma * 100;

                        % Method-specific spectral index from denoised residuals
                        ml_k = NaN;
                        if isfield(r,'k_denoised') && ~isnan(r.k_denoised)
                            ml_k = r.k_denoised;
                        end

                        % Method-specific velocity and uncertainty
                        ml_vel  = NaN;  ml_vunc = NaN;
                        if isfield(r,'det_model') && ~isempty(r.det_model)
                            if isfield(r.det_model,'velocity'),        ml_vel  = r.det_model.velocity;        end
                            if isfield(r.det_model,'vel_uncertainty'), ml_vunc = r.det_model.vel_uncertainty; end
                        end
                        row = {c, app.METHOD_NAMES{mi}, cls_sigma*1000, ...
                               r.residual_std*1000, r.snr_improvement, ...
                               r.noise_reduction, r.rmse*1000, impr, ...
                               cls_k, ml_k, ...
                               cls_vel, cls_vunc, ml_vel, ml_vunc};
                        if isfield(r,'aic')
                            row{end+1} = r.aic; %#ok<AGROW>
                        end
                        rows(end+1,:) = row; %#ok<AGROW>
                    end
                end
            end
            if isempty(rows), return; end
            tbl = cell2table(rows, 'VariableNames', ...
                {'Comp','Method','Classical_mm','ML_mm','SNR_dB', ...
                 'NoiseRed_pct','RMSE_mm','Improvement_pct', ...
                 'k_Classical','k_ML', ...
                 'Cls_Vel_mmyr','Cls_VelUnc_mmyr', ...
                 'ML_Vel_mmyr','ML_VelUnc_mmyr','AIC'});
        end

        % -- Comparison plots (Tab 5) ---------------------------------------
        function generate_comparison_plots(app)
            [n_comp, ~] = size(app.results_ml);
            colors      = lines(5);

            for c = 1:n_comp
                any_result = any(~cellfun(@isempty, app.results_ml(c,:)));
                if ~any_result, continue; end

                % Use the signal stored by classical engine -- guaranteed same
                % length as trend/seasonal/resid, avoiding NaN-length mismatches.
                data_in   = app.results_classical(c).signal(:);
                cls_resid = app.results_classical(c).resid(:);
                n_pts     = length(data_in);
                % Date vector for x-axis labels (dd-mm-yyyy)
                if isfield(app.results_classical(c), 'dates') && ...
                   ~isempty(app.results_classical(c).dates)
                    date_vec = app.results_classical(c).dates;
                    use_dates = true;
                else
                    date_vec = (1:n_pts)';
                    use_dates = false;
                end

                fig = figure('Name', sprintf('Comparison -- Component %d', c), ...
                    'Position', [40 40 1400 1100], 'Color', 'w');

                % Figure supertitle: station + component
                if ~isempty(app.station_name)
                    sgtitle(fig, sprintf('Station: %s  |  Component %d  |  Method Comparison', ...
                        app.station_name, c), ...
                        'FontSize', 14, 'FontWeight', 'bold');
                end

                % Compute mask first -- only index non-empty cells in cellfun
                % to avoid "dot indexing not supported" on empty [] entries.
                mask      = ~cellfun(@isempty, app.results_ml(c,:));
                mask_idx  = find(mask);
                avail_res = app.results_ml(c, mask);   % only non-empty results

                % Subplot 1: SNR bar chart
                subplot(3,3,1);
                snr_v = cellfun(@(r) r.snr_improvement, avail_res);
                bar(snr_v, 'FaceColor', 'flat', 'CData', colors(mask_idx,:));
                set(gca,'XTickLabel', app.METHOD_NAMES(mask), 'XTickLabelRotation',30);
                ylabel('SNR improvement (dB)'); grid on; box on;
                title(sprintf('Component %d -- SNR Comparison', c), 'FontWeight','bold');

                % Subplot 2: Sigma comparison
                subplot(3,3,2);
                cls_s   = app.results_classical(c).sigma * 1000;
                ml_s_v  = cellfun(@(r) r.residual_std*1000, avail_res);
                sigma_v = [cls_s, ml_s_v];
                lab_v   = [{'Classical'}, app.METHOD_NAMES(mask)];
                b = bar(sigma_v); b.FaceColor = 'flat';
                b.CData = [[0.5 0.5 0.5]; colors(mask_idx,:)];
                set(gca,'XTickLabel',lab_v,'XTickLabelRotation',30);
                ylabel('Residual sigma (mm)'); grid on; box on;
                title('Residual sigma Comparison', 'FontWeight','bold');

                % Subplot 3: Noise reduction
                subplot(3,3,3);
                nr_v = cellfun(@(r) r.noise_reduction, avail_res);
                bar(nr_v, 'FaceColor','flat','CData',colors(mask_idx,:));
                set(gca,'XTickLabel',app.METHOD_NAMES(mask),'XTickLabelRotation',30);
                ylabel('Noise reduction (%)'); grid on; box on;
                yline(0,'k--'); title('Noise Reduction', 'FontWeight','bold');

                % Subplot 4: Signal overlay (best 3 by SNR)
                % Use safe_trim() to align any length-mismatched ML signals
                % (can differ by +-window_size epochs due to sliding window).
                subplot(3,3,4);
                [~, best] = sort(snr_v, 'descend');
                plot(1:n_pts, data_in, 'Color',[0.7 0.7 0.7], 'LineWidth',0.8, ...
                    'DisplayName','Original'); hold on;
                for bi = 1:min(3, numel(best))
                    mi = mask_idx(best(bi));
                    r  = app.results_ml{c,mi};
                    sig = safe_trim(r.denoised_signal, n_pts);
                    plot(1:length(sig), sig, 'Color', colors(mi,:), ...
                        'LineWidth', 1.8, 'DisplayName', app.METHOD_NAMES{mi});
                end
                legend('Location','best','FontSize',8);
                ylabel('Coordinate (m)');
                apply_date_axis(gca, date_vec, use_dates);
                grid on; box on;
                title('Signal Overlay (top 3 SNR)', 'FontWeight','bold');

                % Subplot 5: Residual overlay
                % Use pre-computed classical residuals (same length as data_in).
                subplot(3,3,5);
                plot(1:n_pts, cls_resid*1000, 'k-', ...
                    'DisplayName','Classical', 'LineWidth',0.8); hold on;
                for bi = 1:min(3, numel(best))
                    mi = mask_idx(best(bi));
                    r  = app.results_ml{c,mi};
                    res_sig = safe_trim(r.residuals, n_pts);
                    plot(1:length(res_sig), res_sig*1000, 'Color', colors(mi,:), ...
                        'LineWidth', 1.0, 'DisplayName', app.METHOD_NAMES{mi});
                end
                yline(0,'k--','LineWidth',0.7);
                legend('Location','best','FontSize',8);
                ylabel('Residual (mm)');
                apply_date_axis(gca, date_vec, use_dates);
                grid on; box on;
                title('Residual Overlay (top 3 SNR)', 'FontWeight','bold');

                %% Subplot 6: Amplitude periodogram -- original vs all ML residuals ----
                ax_amp6 = subplot(3,3,6);
                hold on;

                % Common period grid (log-spaced, 2 days to data span)
                n_amp    = length(data_in);
                span_amp = n_amp;
                T_amp    = exp(linspace(log(2), log(span_amp*0.9), 2000));
                f_cpy_amp = (1./T_amp) * 365.25;
                t_yrs_amp = (1:n_amp)' / 365.25;

                % Classical residuals amplitude spectrum
                cls_r_amp = app.results_classical(c).resid(:);
                sig_cls   = std(cls_r_amp*1000);
                [pxx_cls6, ~] = plomb(cls_r_amp*1000, t_yrs_amp, f_cpy_amp, 'normalized');
                amp_cls6  = sig_cls * sqrt(2*pxx_cls6 / n_amp);
                plot(T_amp, amp_cls6, 'k-', 'LineWidth', 1.5, 'DisplayName', 'Classical');

                % ML residuals amplitude spectra
                for mi = 1:5
                    if ~isempty(app.results_ml{c,mi})
                        r6   = app.results_ml{c,mi};
                        res6 = safe_trim(r6.residuals, n_amp) * 1000;
                        sig6 = std(res6);
                        [pxx6, ~] = plomb(res6, t_yrs_amp, f_cpy_amp, 'normalized');
                        amp6 = sig6 * sqrt(2*pxx6 / n_amp);
                        plot(T_amp, amp6, '-', 'Color', colors(mi,:), ...
                            'LineWidth', 1.2, 'DisplayName', app.METHOD_NAMES{mi});
                    end
                end

                % Known geodetic period markers
                prd_lbl6 = {365.25,'Ann'; 182.63,'S-ann'; 351.4,'Drac1'; ...
                             175.7,'Drac2'; 13.661,'Mf'; 14.765,'MSf'; ...
                             27.555,'Mm'; 432.2,'Chand'};
                prd_col6 = {'b','b','g','g','r','r','r','m'};
                ax_amp6_ylim = get(ax_amp6,'YLim');
                ymax6 = ax_amp6_ylim(2);
                for pk = 1:size(prd_lbl6,1)
                    Tp = prd_lbl6{pk,1};
                    if Tp >= 2 && Tp <= span_amp*0.9
                        xline(Tp,'--','Color',prd_col6{pk},'LineWidth',0.7,'Alpha',0.55);
                        text(Tp, ymax6*0.92, prd_lbl6{pk,2}, 'FontSize',7, ...
                            'Color',prd_col6{pk},'Rotation',90, ...
                            'VerticalAlignment','top','HorizontalAlignment','right');
                    end
                end

                set(ax_amp6,'XScale','log');
                grid on; box on;
                legend('Location','northeast','FontSize',7);
                xlabel('Period (days)', 'FontSize', 10);
                ylabel('Amplitude (mm)', 'FontSize', 10);
                xtk6 = [2,5,10,14,28,60,91,122,182,365,730];
                xtk6 = xtk6(xtk6 <= span_amp);
                set(ax_amp6,'XTick',xtk6,'XTickLabel',arrayfun(@num2str,xtk6,'UniformOutput',false));
                ax_amp6.XTickLabelRotation = 30;
                title(sprintf('Comp %d -- Amplitude Spectrum: Classical vs ML Residuals', c), ...
                    'FontWeight','bold');

                %% Subplot 7: PSD overlay (classical + all ML residuals) ------
                ax_psd7 = subplot(3,3,7);
                cls_resid_psd = app.results_classical(c).resid(:);
                n_seg = min(256, floor(length(cls_resid_psd)/4));
                first_plot7 = true;
                if n_seg >= 4
                    [pxx_c, f_c] = pwelch(cls_resid_psd, hann(n_seg), [], [], 1);
                    f_pos = f_c(f_c > 0);
                    % First loglog call sets log scale; hold on after
                    loglog(f_pos, pxx_c(f_c>0)*1e6, 'k-', 'LineWidth', 1.5, ...
                        'DisplayName', sprintf('Classical (k=%.2f)', ...
                        app.results_classical(c).k));
                    hold on; first_plot7 = false;
                    for mi = 1:5
                        if ~isempty(app.results_ml{c,mi})
                            r = app.results_ml{c,mi};
                            res_psd = safe_trim(r.residuals, length(cls_resid_psd));
                            [pxx_ml, f_ml] = pwelch(res_psd, hann(n_seg), [], [], 1);
                            fp = f_ml(f_ml > 0);
                            loglog(fp, pxx_ml(f_ml>0)*1e6, '-', ...
                                'Color', colors(mi,:), 'LineWidth', 1.2, ...
                                'DisplayName', app.METHOD_NAMES{mi});
                        end
                    end
                end
                set(ax_psd7, 'XScale','log', 'YScale','log');
                grid on; box on;
                legend('Location','southwest','FontSize',7);
                xlabel('Frequency (cycles/epoch)', 'FontSize', 10);
                ylabel('PSD (mm^2/Hz)', 'FontSize', 10);
                title('PSD Comparison: Classical vs ML Residuals (log-log)', 'FontWeight','bold');

                %% Subplot 8: Spectral index bar chart -------------------------
                subplot(3,3,8);
                k_methods = {};
                k_vals    = [];
                k_cols    = [];
                % Classical
                k_methods{end+1} = 'Classical';
                k_vals(end+1)    = app.results_classical(c).k;
                k_cols(end+1,:)  = [0.4 0.4 0.4];
                % ML methods
                for mi = 1:5
                    if ~isempty(app.results_ml{c,mi})
                        r = app.results_ml{c,mi};
                        res_k = safe_trim(r.residuals, length(cls_resid_psd));
                        n_k = min(256, floor(length(res_k)/4));
                        if n_k >= 4
                            [pxx_k, f_k] = pwelch(res_k, hann(n_k), [], [], 1);
                            fp_k = f_k(f_k > 0);
                            kv = polyfit(log10(fp_k), log10(pxx_k(f_k>0)+eps), 1);
                            k_methods{end+1} = app.METHOD_NAMES{mi};
                            k_vals(end+1)    = kv(1);
                            k_cols(end+1,:)  = colors(mi,:);
                        end
                    end
                end
                bk = bar(k_vals, 'FaceColor','flat');
                bk.CData = k_cols;
                set(gca,'XTickLabel',k_methods,'XTickLabelRotation',30);
                yline(0,  'k--','LineWidth',0.8);
                yline(-1, 'r--','LineWidth',0.8,'DisplayName','Flicker k=-1');
                yline(-2, 'b--','LineWidth',0.8,'DisplayName','RW k=-2');
                grid on; box on;
                ylabel('Spectral Index k', 'FontSize', 10);
                title('Spectral Index per Method', 'FontWeight','bold');
                legend('Location','best','FontSize',7);

                %% Subplot 9: Velocity ± Uncertainty comparison (Classical vs all ML) ---
                subplot(3,3,9);
                hold on;

                % Collect velocities and uncertainties for all methods
                vel_labels = {'Classical'};
                vel_vals   = zeros(1, 1 + sum(mask));
                vel_uncs   = zeros(1, 1 + sum(mask));
                vel_cols   = zeros(1 + sum(mask), 3);

                % Classical
                vel_vals(1) = app.results_classical(c).velocity;
                if isfield(app.results_classical(c),'vel_uncertainty')
                    vel_uncs(1) = app.results_classical(c).vel_uncertainty;
                end
                vel_cols(1,:) = [0.4 0.4 0.4];

                % ML methods
                vi = 2;
                for mi = 1:5
                    if ~isempty(app.results_ml{c,mi})
                        r9 = app.results_ml{c,mi};
                        vel_labels{vi} = app.METHOD_NAMES{mi};
                        vel_cols(vi,:) = colors(mi,:);
                        if isfield(r9,'det_model') && ~isempty(r9.det_model)
                            if isfield(r9.det_model,'velocity')
                                vel_vals(vi) = r9.det_model.velocity;
                            end
                            if isfield(r9.det_model,'vel_uncertainty')
                                vel_uncs(vi) = r9.det_model.vel_uncertainty;
                            end
                        end
                        vi = vi + 1;
                    end
                end
                n_bars = vi - 1;

                % Bar chart with individual colours
                bv = bar(1:n_bars, vel_vals(1:n_bars), 'FaceColor','flat');
                bv.CData = vel_cols(1:n_bars,:);

                % Overlay ± 1-sigma error bars
                errorbar(1:n_bars, vel_vals(1:n_bars), vel_uncs(1:n_bars), ...
                    'k.', 'LineWidth', 1.5, 'CapSize', 8);

                % Reference line at classical velocity
                yline(vel_vals(1), 'k--', 'LineWidth', 0.8, ...
                    'Alpha', 0.6, 'DisplayName', 'Classical ref.');

                set(gca, 'XTick', 1:n_bars, 'XTickLabel', vel_labels(1:n_bars), ...
                    'XTickLabelRotation', 30);
                ylabel('Velocity (mm/yr)', 'FontSize', 10);
                grid on; box on;
                title('Velocity \pm 1\sigma Uncertainty: Classical vs ML', ...
                    'FontWeight', 'bold');

                % Annotate each bar with its value
                for vi2 = 1:n_bars
                    text(vi2, vel_vals(vi2) + sign(vel_vals(vi2))*vel_uncs(vi2) + ...
                         0.05*range(vel_vals(1:n_bars)), ...
                         sprintf('%.3f\n\x00B1%.3f', vel_vals(vi2), vel_uncs(vi2)), ...
                         'HorizontalAlignment','center','FontSize',7, ...
                         'VerticalAlignment','bottom');
                end
                hold off;

                % No author stamp -- station identified in sgtitle above
            end
        end

        % -- Text report ---------------------------------------------------
        function generate_text_report(app)
            [f, p] = uiputfile('*.txt','Save Report');
            if isequal(f,0), return; end
            fpath = fullfile(p,f);
            fid   = fopen(fpath,'w');
            fprintf(fid,'%s\n', repmat('=',1,70));
            fprintf(fid,'GNSS ML ANALYSIS REPORT (v3.0)\n');
            fprintf(fid,'%s\n', repmat('=',1,70));
            if ~isempty(app.station_name)
                fprintf(fid,'Station : %s\n', app.station_name);
            end
            fprintf(fid,'File    : %s\n', app.filename);
            fprintf(fid,'Date    : %s\n\n', datestr(now));

            fprintf(fid,'CLASSICAL ANALYSIS\n%s\n', repmat('-',1,70));
            fprintf(fid,'%-6s %-12s %-8s %-8s %-14s %-14s\n', ...
                'Comp','sigma(mm)','k','Steps','Vel(mm/yr)','VelUnc(mm/yr)');
            for ii = 1:length(app.results_classical)
                r   = app.results_classical(ii);
                vel = r.velocity;
                vun = NaN;
                if isfield(r,'vel_uncertainty'), vun = r.vel_uncertainty; end
                if isnan(vun)
                    vun_str = '   N/A';
                else
                    vun_str = sprintf('%+.4f', vun);
                end
                fprintf(fid,'%-6d %-12.4f %-8.3f %-8d %+.4f        %s\n', ...
                    ii, r.sigma*1000, r.k, length(r.steps), vel, vun_str);
            end

            if ~isempty(app.results_ml)
                fprintf(fid,'\nML METHODS COMPARISON\n%s\n', repmat('-',1,70));
                fprintf(fid,'%-5s %-20s %-10s %-10s %-10s %-14s %-14s %-10s\n', ...
                    'Comp','Method','sigma(mm)','SNR(dB)','NR(%)', ...
                    'Vel(mm/yr)','VelUnc(mm/yr)','Gaussian');
                [n_comp,~] = size(app.results_ml);
                for c = 1:n_comp
                    for mi = 1:5
                        if ~isempty(app.results_ml{c,mi})
                            r  = app.results_ml{c,mi};
                            gn = 'N/A';
                            if isfield(r,'residual_gaussian') && ~isnan(r.residual_gaussian)
                                if r.residual_gaussian, gn = 'Yes'; else, gn = 'No'; end
                            end
                            ml_vel = NaN; ml_vun = NaN;
                            if isfield(r,'det_model') && ~isempty(r.det_model)
                                if isfield(r.det_model,'velocity'),        ml_vel = r.det_model.velocity;        end
                                if isfield(r.det_model,'vel_uncertainty'), ml_vun = r.det_model.vel_uncertainty; end
                            end
                            if isnan(ml_vel), vel_str = '  N/A  ';
                            else,             vel_str = sprintf('%+.4f', ml_vel); end
                            if isnan(ml_vun), vun_str = '  N/A  ';
                            else,             vun_str = sprintf('%.4f',  ml_vun); end
                            fprintf(fid,'%-5d %-20s %-10.4f %-10.2f %-10.1f %-14s %-14s %-10s\n', ...
                                c, app.METHOD_NAMES{mi}, ...
                                r.residual_std*1000, r.snr_improvement, ...
                                r.noise_reduction, vel_str, vun_str, gn);
                        end
                    end
                end
            end
            fclose(fid);
            open(fpath);
            app.ComparisonStatusLabel.Text = ['Report: ' f];
        end

        % -- LaTeX table export --------------------------------------------
        function export_latex_table(app, fpath)
            fid = fopen(fpath,'w');
            fprintf(fid,'%% Auto-generated by GNSS_ML_Comparison_App v3.0\n');
            fprintf(fid,'\\begin{table}[ht]\n\\centering\n');
            fprintf(fid,'\\caption{GNSS ML Denoising Results: Noise and Velocity Estimates}\n');
            fprintf(fid,'\\label{tab:gnss_ml_results}\n');
            fprintf(fid,'\\begin{tabular}{llrrrrrl}\n\\toprule\n');
            fprintf(fid, ...
                'Comp & Method & $\\sigma_r$ (mm) & SNR (dB) & NR (\\%%) & Vel (mm/yr) & $\\sigma_v$ (mm/yr) & Normal \\\\\n');
            fprintf(fid,'\\midrule\n');
            if ~isempty(app.results_ml)
                for c = 1:size(app.results_ml,1)
                    % Classical row first
                    if ~isempty(app.results_classical) && ...
                            length(app.results_classical) >= c
                        rc   = app.results_classical(c);
                        cvel = rc.velocity;
                        cvun = NaN;
                        if isfield(rc,'vel_uncertainty'), cvun = rc.vel_uncertainty; end
                        if isnan(cvun), cvun_str = '--';
                        else,           cvun_str = sprintf('%.3f', cvun); end
                        fprintf(fid,'%d & Classical & %.4f & -- & -- & %+.3f & %s & -- \\\\\n', ...
                            c, rc.sigma*1000, cvel, cvun_str);
                    end
                    for mi = 1:5
                        if ~isempty(app.results_ml{c,mi})
                            r  = app.results_ml{c,mi};
                            gn = '--';
                            if isfield(r,'residual_gaussian') && ~isnan(r.residual_gaussian)
                                if r.residual_gaussian, gn = 'Yes'; else, gn = 'No'; end
                            end
                            ml_vel = NaN; ml_vun = NaN;
                            if isfield(r,'det_model') && ~isempty(r.det_model)
                                if isfield(r.det_model,'velocity'),        ml_vel = r.det_model.velocity;        end
                                if isfield(r.det_model,'vel_uncertainty'), ml_vun = r.det_model.vel_uncertainty; end
                            end
                            if isnan(ml_vel), vel_str = '--';
                            else,             vel_str = sprintf('%+.3f', ml_vel); end
                            if isnan(ml_vun), vun_str = '--';
                            else,             vun_str = sprintf('%.3f',  ml_vun); end
                            fprintf(fid,'%d & %s & %.4f & %.2f & %.1f & %s & %s & %s \\\\\n', ...
                                c, app.METHOD_NAMES{mi}, ...
                                r.residual_std*1000, r.snr_improvement, ...
                                r.noise_reduction, vel_str, vun_str, gn);
                        end
                    end
                    if c < size(app.results_ml,1)
                        fprintf(fid,'\\midrule\n');
                    end
                end
            end
            fprintf(fid,'\\bottomrule\n\\end{tabular}\n\\end{table}\n');
            fclose(fid);
        end

        % -- Lamp helpers --------------------------------------------------
        function reset_lamps(app)
            for lp = {app.GPRLamp, app.SVRLamp, app.RFLamp, app.GBLamp, app.KNNLamp}
                lp{1}.Color = [0.6 0.6 0.6];  % grey = idle
            end
        end

        function set_lamp(app, method_keys, state)
            lamp_map = struct('GPR', app.GPRLamp, 'SVR', app.SVRLamp, ...
                              'RF', app.RFLamp,   'GB',  app.GBLamp, ...
                              'KNN', app.KNNLamp);
            color_map = struct('idle',   [0.60 0.60 0.60], ...
                               'running',[0.00 0.45 0.85], ...
                               'done',   [0.10 0.70 0.25], ...
                               'error',  [0.85 0.15 0.10]);
            clr = color_map.(state);
            for mi = 1:length(method_keys)
                lmp = lamp_map.(method_keys{mi});
                lmp.Color = clr;
            end
        end

    end % private helpers


    %% ========================================================================
    %  UI CONSTRUCTION
    %% ========================================================================
    methods (Access = private)

        function createComponents(app)
            app.UIFigure = uifigure('Visible','off');
            app.UIFigure.Position = [80 60 1240 780];
            app.UIFigure.Name     = 'GNSS ML Analysis Toolkit v3.0';
            app.UIFigure.Color    = [0.96 0.97 0.98];

            app.TabGroup          = uitabgroup(app.UIFigure);
            app.TabGroup.Position = [1 1 1240 780];

            %% --- Tab 1: Load ---------------------------------------------
            app.LoadTab       = uitab(app.TabGroup, 'Title', '1. Load Data');
            lp = uipanel(app.LoadTab,'Title','Data Loading', ...
                'Position',[12 430 1216 300], ...
                'BackgroundColor',[0.98 0.99 1.00], ...
                'BorderType','line','HighlightColor',[0.75 0.82 0.90]);

            app.LoadFileButton = uibutton(lp,'push','Text','⬆  Load GNSS Data', ...
                'Position',[20 225 210 42],'FontSize',13,'FontWeight','bold', ...
                'BackgroundColor',[0.13 0.45 0.72],'FontColor',[1 1 1], ...
                'ButtonPushedFcn', createCallbackFcn(app,@LoadFileButtonPushed,true));

            app.FileNameLabel  = uilabel(lp,'Position',[245 236 950 22],'FontSize',12, ...
                'FontColor',[0.2 0.2 0.2]);
            app.DataInfoLabel  = uilabel(lp,'Position',[20 195 1170 22],'FontSize',11, ...
                'FontColor',[0.25 0.25 0.25]);
            app.StationNameLabel = uilabel(lp,'Position',[20 168 1170 22],'FontSize',11, ...
                'FontWeight','bold','FontColor',[0.12 0.47 0.71]);

            app.DataPreviewTable = uitable(app.LoadTab,'Position',[12 20 1216 395]);

            %% --- Tab 2: Classical ----------------------------------------
            app.ClassicalTab  = uitab(app.TabGroup,'Title','2. Classical');

            % Top toolbar
            app.RunClassicalButton = uibutton(app.ClassicalTab,'push', ...
                'Text','▶  Run Classical Analysis','Position',[12 712 230 38], ...
                'FontSize',12,'FontWeight','bold', ...
                'BackgroundColor',[0.13 0.45 0.72],'FontColor',[1 1 1], ...
                'ButtonPushedFcn', createCallbackFcn(app,@RunClassicalButtonPushed,true));

            uilabel(app.ClassicalTab,'Text','Component:', ...
                'Position',[258 722 85 22],'FontColor',[0.25 0.25 0.25]);
            app.ClassicalComponentDropDown = uidropdown(app.ClassicalTab, ...
                'Items',{'1'},'Position',[348 722 75 22]);

            app.PlotClassicalButton = uibutton(app.ClassicalTab,'push', ...
                'Text','📈 Plot','Position',[438 718 110 30], ...
                'BackgroundColor',[0.23 0.55 0.30],'FontColor',[1 1 1],'FontWeight','bold', ...
                'ButtonPushedFcn', createCallbackFcn(app,@PlotClassicalButtonPushed,true));

            app.ClassicalStatusLabel = uilabel(app.ClassicalTab, ...
                'Position',[12 680 1200 28],'FontSize',11,'FontColor',[0.25 0.25 0.25]);

            % ---- Signal Configuration Panel (Tab 2) ----------------------
            sp2 = uipanel(app.ClassicalTab,'Title','Deterministic Model — Signal Selection', ...
                'Position',[12 390 1216 280],'FontWeight','bold', ...
                'BackgroundColor',[0.97 0.98 1.00], ...
                'BorderType','line','HighlightColor',[0.75 0.82 0.90]);

            % Preset dropdown
            uilabel(sp2,'Text','Preset:','Position',[10 235 55 22],'FontWeight','bold');
            app.ClsSignalPresetDropDown = uidropdown(sp2, ...
                'Items',{'Minimal (trend only)','Standard (annual + semi-annual)', ...
                         'Extended (+ ter-annual + quarterly)', ...
                         'Geodetic (+ draconitic 1-3)', ...
                         'Full geodetic (+ tidal aliases)', ...
                         'Custom'}, ...
                'Value','Standard (annual + semi-annual)', ...
                'Position',[70 235 340 22], ...
                'ValueChangedFcn', createCallbackFcn(app,@ClsSignalPresetDropDownChanged,true));

            % --- Group 1: Seasonal ---
            uilabel(sp2,'Text','SEASONAL HARMONICS','Position',[10 205 200 18], ...
                'FontWeight','bold','FontColor',[0.12 0.47 0.71]);
            app.ClsAnnualCB     = uicheckbox(sp2,'Text','Annual (365.25 d)', ...
                'Value',true,'Position',[10 185 185 20]);
            app.ClsSemiAnnualCB = uicheckbox(sp2,'Text','Semi-annual (182.6 d)', ...
                'Value',true,'Position',[10 163 185 20]);
            app.ClsTerAnnualCB  = uicheckbox(sp2,'Text','Ter-annual (121.8 d)', ...
                'Value',false,'Position',[10 141 185 20]);
            app.ClsQuarterlyCB  = uicheckbox(sp2,'Text','Quarterly (91.3 d)', ...
                'Value',false,'Position',[10 119 185 20]);

            % --- Group 2: Draconitic ---
            uilabel(sp2,'Text','GPS DRACONITIC','Position',[210 205 170 18], ...
                'FontWeight','bold','FontColor',[0.17 0.63 0.17]);
            app.ClsDrac1CB = uicheckbox(sp2,'Text','Drac-1 (351.4 d)', ...
                'Value',false,'Position',[210 185 175 20]);
            app.ClsDrac2CB = uicheckbox(sp2,'Text','Drac-2 (175.7 d)', ...
                'Value',false,'Position',[210 163 175 20]);
            app.ClsDrac3CB = uicheckbox(sp2,'Text','Drac-3 (117.1 d)', ...
                'Value',false,'Position',[210 141 175 20]);
            app.ClsDrac4CB = uicheckbox(sp2,'Text','Drac-4 (87.9 d)', ...
                'Value',false,'Position',[210 119 175 20]);
            app.ClsDrac5CB = uicheckbox(sp2,'Text','Drac-5 (70.3 d)', ...
                'Value',false,'Position',[210 97 175 20]);
            app.ClsDrac6CB = uicheckbox(sp2,'Text','Drac-6 (58.6 d)', ...
                'Value',false,'Position',[210 75 175 20]);
            app.ClsDrac7CB = uicheckbox(sp2,'Text','Drac-7 (50.2 d)', ...
                'Value',false,'Position',[210 53 175 20]);
            app.ClsDrac8CB = uicheckbox(sp2,'Text','Drac-8 (43.9 d)', ...
                'Value',false,'Position',[210 31 175 20]);

            % --- Group 3: Tidal / OTL aliases ---
            uilabel(sp2,'Text','TIDAL / OTL ALIASES','Position',[400 205 200 18], ...
                'FontWeight','bold','FontColor',[0.84 0.15 0.16]);
            app.ClsMfCB      = uicheckbox(sp2,'Text','Mf fortnightly (13.66 d)', ...
                'Value',false,'Position',[400 185 230 20]);
            app.ClsMsfCB     = uicheckbox(sp2,'Text','MSf fortnightly (14.77 d)', ...
                'Value',false,'Position',[400 163 230 20]);
            app.ClsMmCB      = uicheckbox(sp2,'Text','Mm monthly (27.56 d)', ...
                'Value',false,'Position',[400 141 230 20]);
            app.ClsMsmCB     = uicheckbox(sp2,'Text','MSm monthly (31.81 d)', ...
                'Value',false,'Position',[400 119 230 20]);
            app.ClsChandlerCB= uicheckbox(sp2,'Text','Chandler wobble (432.2 d)', ...
                'Value',false,'Position',[400 97 230 20]);

            % --- Group 4: Atmospheric ---
            uilabel(sp2,'Text','ATMOSPHERIC LOADING','Position',[645 205 210 18], ...
                'FontWeight','bold','FontColor',[0.58 0.40 0.74]);
            app.ClsS1AtmCB   = uicheckbox(sp2,'Text','S1 atm. tide (1.003 d)', ...
                'Value',false,'Position',[645 185 220 20]);
            app.ClsS2AtmCB   = uicheckbox(sp2,'Text','S2 atm. tide (0.501 d)', ...
                'Value',false,'Position',[645 163 220 20]);
            app.ClsMjoCB     = uicheckbox(sp2,'Text','MJO proxy (45.0 d)', ...
                'Value',false,'Position',[645 141 220 20]);

            % --- Group 5: Inter-annual ---
            uilabel(sp2,'Text','INTER-ANNUAL','Position',[880 205 160 18], ...
                'FontWeight','bold','FontColor',[0.55 0.34 0.29]);
            app.ClsEnsoCB    = uicheckbox(sp2,'Text','ENSO proxy (1461 d)', ...
                'Value',false,'Position',[880 185 210 20]);
            app.ClsNodal18CB = uicheckbox(sp2,'Text','18.6-yr nodal (6798 d)', ...
                'Value',false,'Position',[880 163 210 20]);

            % Period search row
            app.ClsPeriodSearchCheckBox = uicheckbox(sp2, ...
                'Text','Enable adaptive period search (Lomb-Scargle peak detection per signal)', ...
                'Value', true, 'Position',[10 33 450 20], ...
                'Tooltip', ...
                'When ON: for each enabled signal the toolkit searches a tolerance window around the nominal period and uses the detected spectral peak. Astronomical tides always use fixed periods.');
            uilabel(sp2,'Text','Search preset:','Position',[475 33 110 20]);
            app.ClsPeriodSearchPresetDropDown = uidropdown(sp2, ...
                'Items',{'Default tolerances','Tight (stable signals)','Wide (unstable/noisy)', ...
                         'Astronomical only (tides fixed)','All fixed (no search)'}, ...
                'Value','Default tolerances','Position',[590 31 250 22], ...
                'ValueChangedFcn', createCallbackFcn(app,@ClsPeriodSearchPresetChanged,true));

            % Hint label
            uilabel(sp2,'Text', ...
                'Enable signals present in your data. Span must be >= 2 x period. Period search finds the exact peak within a tolerance window around each nominal period.', ...
                'Position',[10 8 1180 20],'FontColor',[0.5 0.5 0.5],'FontSize',10);

            % --- Group 6: Sub-daily / OTL (hrts files only) ---
            % Hidden by default; shown and highlighted when an hrts file is loaded.
            app.ClsSubDailyPanel = uipanel(app.ClassicalTab, ...
                'Title','SUB-DAILY / OTL  (high-rate data)', ...
                'Position',[12 382 1216 100], ...
                'FontWeight','bold','ForegroundColor',[0.5 0.5 0.5], ...
                'Visible','off');

            % Semi-diurnal OTL constituents (col 1)
            uilabel(app.ClsSubDailyPanel,'Text','SEMI-DIURNAL OTL', ...
                'Position',[10 62 190 16],'FontWeight','bold', ...
                'FontColor',[0.84 0.15 0.16]);
            app.ClsM2OtlCB = uicheckbox(app.ClsSubDailyPanel, ...
                'Text','M2 OTL (0.5175 d)','Value',false,'Position',[10 44 175 18]);
            app.ClsS2OtlCB = uicheckbox(app.ClsSubDailyPanel, ...
                'Text','S2 OTL (0.5000 d)','Value',false,'Position',[10 24 175 18]);
            app.ClsN2OtlCB = uicheckbox(app.ClsSubDailyPanel, ...
                'Text','N2 OTL (0.5274 d)','Value',false,'Position',[10 4 175 18]);
            app.ClsK2OtlCB = uicheckbox(app.ClsSubDailyPanel, ...
                'Text','K2 OTL (0.4986 d)','Value',false,'Position',[195 44 175 18]);

            % Diurnal OTL constituents (col 2)
            uilabel(app.ClsSubDailyPanel,'Text','DIURNAL OTL', ...
                'Position',[390 62 160 16],'FontWeight','bold', ...
                'FontColor',[0.84 0.15 0.16]);
            app.ClsK1OtlCB = uicheckbox(app.ClsSubDailyPanel, ...
                'Text','K1 OTL (0.9972 d)','Value',false,'Position',[390 44 175 18]);
            app.ClsO1OtlCB = uicheckbox(app.ClsSubDailyPanel, ...
                'Text','O1 OTL (1.0758 d)','Value',false,'Position',[390 24 175 18]);
            app.ClsP1OtlCB = uicheckbox(app.ClsSubDailyPanel, ...
                'Text','P1 OTL (1.0028 d)','Value',false,'Position',[390 4 175 18]);
            app.ClsQ1OtlCB = uicheckbox(app.ClsSubDailyPanel, ...
                'Text','Q1 OTL (1.1195 d)','Value',false,'Position',[575 44 175 18]);

            % Sub-daily atmospheric (col 3)
            uilabel(app.ClsSubDailyPanel,'Text','ATM (SUB-DAILY)', ...
                'Position',[770 62 175 16],'FontWeight','bold', ...
                'FontColor',[0.58 0.40 0.74]);
            app.ClsS3AtmCB = uicheckbox(app.ClsSubDailyPanel, ...
                'Text','S3 atm. (0.3333 d)','Value',false,'Position',[770 44 185 18]);
            app.ClsS4AtmCB = uicheckbox(app.ClsSubDailyPanel, ...
                'Text','S4 atm. (0.2500 d)','Value',false,'Position',[770 24 185 18]);

            % Info note
            uilabel(app.ClsSubDailyPanel, ...
                'Text', ...
                ['True OTL periods (not aliases). Activate only for high-rate (hrts) data. ' ...
                 'For daily data use Mf/MSf alias entries in Group 3 above.'], ...
                'Position',[975 10 345 55],'FontSize',9,'FontColor',[0.45 0.45 0.45], ...
                'WordWrap','on');

            % Results table
            app.ClassicalResultsTable = uitable(app.ClassicalTab, ...
                'Position',[12 20 1216 357]);

            %% --- Tab 3: ML Setup -----------------------------------------
            app.MLSetupTab = uitab(app.TabGroup,'Title','3. ML Methods');

            % Method selection panel - publication quality
            mp = uipanel(app.MLSetupTab,'Title','Select Methods', ...
                'Position',[12 490 430 260], ...
                'BackgroundColor',[0.97 0.98 1.00], ...
                'BorderType','line','HighlightColor',[0.75 0.82 0.90]);

            row_y = {205,165,125,85,45};
            lamps = {'GPR','SVR','Random Forest','Gradient Boosting','KNN'};
            cbs   = {'GPRCheckBox','SVRCheckBox','RFCheckBox','GBCheckBox','KNNCheckBox'};
            lmp_f = {'GPRLamp','SVRLamp','RFLamp','GBLamp','KNNLamp'};
            for ci = 1:5
                app.(cbs{ci}) = uicheckbox(mp,'Text',lamps{ci}, ...
                    'Value',true,'Position',[40 row_y{ci} 220 22]);
                app.(lmp_f{ci}) = uilamp(mp,'Position',[270 row_y{ci} 20 20], ...
                    'Color',[0.6 0.6 0.6]);
            end

            app.SelectAllButton = uibutton(mp,'push','Text','All', ...
                'Position',[305 148 80 30], ...
                'BackgroundColor',[0.13 0.45 0.72],'FontColor',[1 1 1],'FontWeight','bold', ...
                'ButtonPushedFcn', createCallbackFcn(app,@SelectAllButtonPushed,true));
            app.DeselectAllButton = uibutton(mp,'push','Text','None', ...
                'Position',[305 108 80 30], ...
                'BackgroundColor',[0.55 0.55 0.60],'FontColor',[1 1 1],'FontWeight','bold', ...
                'ButtonPushedFcn', createCallbackFcn(app,@DeselectAllButtonPushed,true));

            % Parameters panel - publication quality
            pp = uipanel(app.MLSetupTab,'Title','Parameters', ...
                'Position',[460 490 768 260], ...
                'BackgroundColor',[0.97 0.98 1.00], ...
                'BorderType','line','HighlightColor',[0.75 0.82 0.90]);

            uilabel(pp,'Text','Preset:','Position',[15 210 60 22], ...
                'FontColor',[0.25 0.25 0.25]);
            app.PresetDropDown = uidropdown(pp, ...
                'Items',{'Daily GNSS (default)','Sub-daily (high rate)','Weekly data'}, ...
                'Position',[85 210 200 22], ...
                'ValueChangedFcn', createCallbackFcn(app,@PresetDropDownValueChanged,true));

            uilabel(pp,'Text','Window size:','Position',[15 170 100 22], ...
                'FontColor',[0.25 0.25 0.25]);
            app.WindowSizeSpinner = uispinner(pp,'Value',30,'Limits',[5 300], ...
                'Position',[125 170 80 22]);

            uilabel(pp,'Text','Num trees:','Position',[225 170 90 22], ...
                'FontColor',[0.25 0.25 0.25]);
            app.NumTreesSpinner = uispinner(pp,'Value',200,'Limits',[50 2000], ...
                'Position',[325 170 80 22]);

            app.OptimizeCheckBox = uicheckbox(pp,'Text','Optimise hyperparameters (slower)', ...
                'Value',false,'Position',[15 130 270 22]);
            app.RunCVCheckBox    = uicheckbox(pp,'Text','Run cross-validation (CV)', ...
                'Value',false,'Position',[15 95 230 22]);

            uilabel(pp,'Text','Component:','Position',[15 55 90 22], ...
                'FontColor',[0.25 0.25 0.25]);
            app.MLComponentDropDown = uidropdown(pp,'Items',{'1'}, ...
                'Position',[110 55 80 22]);

            app.RunMLButton = uibutton(pp,'push','Text','▶  Run Selected Methods', ...
                'Position',[15 10 260 42],'FontSize',12,'FontWeight','bold', ...
                'BackgroundColor',[0.13 0.45 0.72],'FontColor',[1 1 1], ...
                'ButtonPushedFcn', createCallbackFcn(app,@RunMLButtonPushed,true));

            % Status label replaces the LinearGauge (removed per request)
            app.MLProgressGauge = uigauge(app.MLSetupTab,'linear', ...
                'Position',[12 462 1216 20], ...
                'Visible','off');   % Hidden - kept for code compatibility only
            app.MLStatusLabel   = uilabel(app.MLSetupTab, ...
                'Position',[12 462 1216 24],'FontSize',11, ...
                'FontColor',[0.15 0.35 0.65],'FontWeight','bold');

            % ---- Signal Configuration Panel (Tab 3) ----------------------
            sp3 = uipanel(app.MLSetupTab,'Title','Deterministic Model — Signal Selection (ML Pre-processing)', ...
                'Position',[12 130 1216 320],'FontWeight','bold', ...
                'BackgroundColor',[0.97 0.98 1.00], ...
                'BorderType','line','HighlightColor',[0.75 0.82 0.90]);

            % Preset + sync row
            uilabel(sp3,'Text','Preset:','Position',[10 280 55 22],'FontWeight','bold');
            app.MlSignalPresetDropDown = uidropdown(sp3, ...
                'Items',{'Minimal (trend only)','Standard (annual + semi-annual)', ...
                         'Extended (+ ter-annual + quarterly)', ...
                         'Geodetic (+ draconitic 1-3)', ...
                         'Full geodetic (+ tidal aliases)', ...
                         'Custom'}, ...
                'Value','Standard (annual + semi-annual)', ...
                'Position',[70 280 340 22], ...
                'ValueChangedFcn', createCallbackFcn(app,@MlSignalPresetDropDownChanged,true));

            app.MlSyncFromClsButton = uibutton(sp3,'push', ...
                'Text','↩  Sync from Tab 2','Position',[430 278 180 26], ...
                'BackgroundColor',[0.55 0.55 0.60],'FontColor',[1 1 1],'FontWeight','bold', ...
                'Tooltip','Copy signal selection from Classical tab', ...
                'ButtonPushedFcn', createCallbackFcn(app,@MlSyncFromClsButtonPushed,true));

            % Group 1: Seasonal
            uilabel(sp3,'Text','SEASONAL HARMONICS','Position',[10 248 200 18], ...
                'FontWeight','bold','FontColor',[0.12 0.47 0.71]);
            app.MlAnnualCB     = uicheckbox(sp3,'Text','Annual (365.25 d)', ...
                'Value',true,'Position',[10 228 185 20]);
            app.MlSemiAnnualCB = uicheckbox(sp3,'Text','Semi-annual (182.6 d)', ...
                'Value',true,'Position',[10 206 185 20]);
            app.MlTerAnnualCB  = uicheckbox(sp3,'Text','Ter-annual (121.8 d)', ...
                'Value',false,'Position',[10 184 185 20]);
            app.MlQuarterlyCB  = uicheckbox(sp3,'Text','Quarterly (91.3 d)', ...
                'Value',false,'Position',[10 162 185 20]);

            % Group 2: Draconitic
            uilabel(sp3,'Text','GPS DRACONITIC','Position',[210 248 170 18], ...
                'FontWeight','bold','FontColor',[0.17 0.63 0.17]);
            app.MlDrac1CB = uicheckbox(sp3,'Text','Drac-1 (351.4 d)', ...
                'Value',false,'Position',[210 228 175 20]);
            app.MlDrac2CB = uicheckbox(sp3,'Text','Drac-2 (175.7 d)', ...
                'Value',false,'Position',[210 206 175 20]);
            app.MlDrac3CB = uicheckbox(sp3,'Text','Drac-3 (117.1 d)', ...
                'Value',false,'Position',[210 184 175 20]);
            app.MlDrac4CB = uicheckbox(sp3,'Text','Drac-4 (87.9 d)', ...
                'Value',false,'Position',[210 162 175 20]);
            app.MlDrac5CB = uicheckbox(sp3,'Text','Drac-5 (70.3 d)', ...
                'Value',false,'Position',[210 140 175 20]);
            app.MlDrac6CB = uicheckbox(sp3,'Text','Drac-6 (58.6 d)', ...
                'Value',false,'Position',[210 118 175 20]);
            app.MlDrac7CB = uicheckbox(sp3,'Text','Drac-7 (50.2 d)', ...
                'Value',false,'Position',[210 96 175 20]);
            app.MlDrac8CB = uicheckbox(sp3,'Text','Drac-8 (43.9 d)', ...
                'Value',false,'Position',[210 74 175 20]);

            % Group 3: Tidal / OTL aliases
            uilabel(sp3,'Text','TIDAL / OTL ALIASES','Position',[400 248 200 18], ...
                'FontWeight','bold','FontColor',[0.84 0.15 0.16]);
            app.MlMfCB       = uicheckbox(sp3,'Text','Mf fortnightly (13.66 d)', ...
                'Value',false,'Position',[400 228 230 20]);
            app.MlMsfCB      = uicheckbox(sp3,'Text','MSf fortnightly (14.77 d)', ...
                'Value',false,'Position',[400 206 230 20]);
            app.MlMmCB       = uicheckbox(sp3,'Text','Mm monthly (27.56 d)', ...
                'Value',false,'Position',[400 184 230 20]);
            app.MlMsmCB      = uicheckbox(sp3,'Text','MSm monthly (31.81 d)', ...
                'Value',false,'Position',[400 162 230 20]);
            app.MlChandlerCB = uicheckbox(sp3,'Text','Chandler wobble (432.2 d)', ...
                'Value',false,'Position',[400 140 230 20]);

            % Group 4: Atmospheric
            uilabel(sp3,'Text','ATMOSPHERIC LOADING','Position',[645 248 210 18], ...
                'FontWeight','bold','FontColor',[0.58 0.40 0.74]);
            app.MlS1AtmCB    = uicheckbox(sp3,'Text','S1 atm. tide (1.003 d)', ...
                'Value',false,'Position',[645 228 220 20]);
            app.MlS2AtmCB    = uicheckbox(sp3,'Text','S2 atm. tide (0.501 d)', ...
                'Value',false,'Position',[645 206 220 20]);
            app.MlMjoCB      = uicheckbox(sp3,'Text','MJO proxy (45.0 d)', ...
                'Value',false,'Position',[645 184 220 20]);

            % Group 5: Inter-annual
            uilabel(sp3,'Text','INTER-ANNUAL','Position',[880 248 160 18], ...
                'FontWeight','bold','FontColor',[0.55 0.34 0.29]);
            app.MlEnsoCB     = uicheckbox(sp3,'Text','ENSO proxy (1461 d)', ...
                'Value',false,'Position',[880 228 210 20]);
            app.MlNodal18CB  = uicheckbox(sp3,'Text','18.6-yr nodal (6798 d)', ...
                'Value',false,'Position',[880 206 210 20]);

            % Period search row
            app.MlPeriodSearchCheckBox = uicheckbox(sp3, ...
                'Text','Enable adaptive period search (Lomb-Scargle peak detection per signal)', ...
                'Value', true, 'Position',[10 52 450 20], ...
                'Tooltip', ...
                'When ON: uses LS peak detection per signal before ML training. Should match Tab 2 setting for consistent classical vs ML comparison.');
            uilabel(sp3,'Text','Search preset:','Position',[475 52 110 20]);
            app.MlPeriodSearchPresetDropDown = uidropdown(sp3, ...
                'Items',{'Default tolerances','Tight (stable signals)','Wide (unstable/noisy)', ...
                         'Astronomical only (tides fixed)','All fixed (no search)'}, ...
                'Value','Default tolerances','Position',[590 50 260 22], ...
                'ValueChangedFcn', createCallbackFcn(app,@MlPeriodSearchPresetChanged,true));

            uilabel(sp3,'Text', ...
                'These signals are removed BEFORE ML training. Use same settings as Tab 2. Click "Sync from Tab 2" to copy both signal and period search settings.', ...
                'Position',[10 8 1180 20],'FontColor',[0.5 0.5 0.5],'FontSize',10);

            % --- Group 6: Sub-daily / OTL (hrts files only) ---
            app.MlSubDailyPanel = uipanel(app.MLSetupTab, ...
                'Title','SUB-DAILY / OTL  (high-rate data)', ...
                'Position',[12 126 1216 98], ...
                'FontWeight','bold','ForegroundColor',[0.5 0.5 0.5], ...
                'Visible','off');

            % Semi-diurnal OTL constituents
            uilabel(app.MlSubDailyPanel,'Text','SEMI-DIURNAL OTL', ...
                'Position',[10 62 190 16],'FontWeight','bold', ...
                'FontColor',[0.84 0.15 0.16]);
            app.MlM2OtlCB = uicheckbox(app.MlSubDailyPanel, ...
                'Text','M2 OTL (0.5175 d)','Value',false,'Position',[10 44 175 18]);
            app.MlS2OtlCB = uicheckbox(app.MlSubDailyPanel, ...
                'Text','S2 OTL (0.5000 d)','Value',false,'Position',[10 24 175 18]);
            app.MlN2OtlCB = uicheckbox(app.MlSubDailyPanel, ...
                'Text','N2 OTL (0.5274 d)','Value',false,'Position',[10 4 175 18]);
            app.MlK2OtlCB = uicheckbox(app.MlSubDailyPanel, ...
                'Text','K2 OTL (0.4986 d)','Value',false,'Position',[195 44 175 18]);

            % Diurnal OTL constituents
            uilabel(app.MlSubDailyPanel,'Text','DIURNAL OTL', ...
                'Position',[390 62 160 16],'FontWeight','bold', ...
                'FontColor',[0.84 0.15 0.16]);
            app.MlK1OtlCB = uicheckbox(app.MlSubDailyPanel, ...
                'Text','K1 OTL (0.9972 d)','Value',false,'Position',[390 44 175 18]);
            app.MlO1OtlCB = uicheckbox(app.MlSubDailyPanel, ...
                'Text','O1 OTL (1.0758 d)','Value',false,'Position',[390 24 175 18]);
            app.MlP1OtlCB = uicheckbox(app.MlSubDailyPanel, ...
                'Text','P1 OTL (1.0028 d)','Value',false,'Position',[390 4 175 18]);
            app.MlQ1OtlCB = uicheckbox(app.MlSubDailyPanel, ...
                'Text','Q1 OTL (1.1195 d)','Value',false,'Position',[575 44 175 18]);

            % Sub-daily atmospheric
            uilabel(app.MlSubDailyPanel,'Text','ATM (SUB-DAILY)', ...
                'Position',[770 62 175 16],'FontWeight','bold', ...
                'FontColor',[0.58 0.40 0.74]);
            app.MlS3AtmCB = uicheckbox(app.MlSubDailyPanel, ...
                'Text','S3 atm. (0.3333 d)','Value',false,'Position',[770 44 185 18]);
            app.MlS4AtmCB = uicheckbox(app.MlSubDailyPanel, ...
                'Text','S4 atm. (0.2500 d)','Value',false,'Position',[770 24 185 18]);

            % Info note
            uilabel(app.MlSubDailyPanel, ...
                'Text', ...
                ['True OTL periods (not aliases). Activate only for high-rate (hrts) data. ' ...
                 'For daily data use Mf/MSf alias entries in Group 3 above.'], ...
                'Position',[975 10 220 55],'FontSize',9,'FontColor',[0.45 0.45 0.45], ...
                'WordWrap','on');

            % Info panel - publication quality
            ip = uipanel(app.MLSetupTab,'Title','Method Reference', ...
                'Position',[12 20 1216 105], ...
                'BackgroundColor',[0.97 0.98 1.00], ...
                'BorderType','line','HighlightColor',[0.75 0.82 0.90]);
            info = sprintf([...
                'GPR  — Gaussian Process Regression: probabilistic, provides 95%% confidence bounds. Best for geodetic applications needing uncertainty.\n'...
                'SVR  — Support Vector Regression: robust to outliers, excellent on non-stationary series. RBF kernel with Bayesian hyperparameter tuning.\n'...
                'RF   — Random Forest: ensemble of 200 trees, OOB error monitoring, permutation feature importance. Fastest ensemble method.\n'...
                'GB   — Gradient Boosting (LSBoost): sequential residual fitting, eta=0.05 shrinkage, depth-4 trees. Often highest point accuracy.\n'...
                'KNN  — K-Nearest Neighbours: non-parametric, auto-selects k from {3,5,7,10,15} by resubstitution error. Excellent baseline.\n\n'...
                'All methods: IQR outlier removal → deterministic model (trend + harmonics) → z-score normalisation → sliding window features.']);
            uilabel(ip,'Text',info,'Position',[15 5 1180 90],'WordWrap','on', ...
                'VerticalAlignment','top','FontSize',10,'FontColor',[0.2 0.2 0.2]);

            %% --- Tab 4: ML Results ---------------------------------------
            app.MLResultsTab = uitab(app.TabGroup,'Title','4. ML Results');

            uilabel(app.MLResultsTab,'Text','Method:', ...
                'Position',[12 710 65 22],'FontColor',[0.25 0.25 0.25]);
            app.MethodDropDown = uidropdown(app.MLResultsTab, ...
                'Items',app.DISPLAY_NAMES,'Position',[85 710 180 22]);

            uilabel(app.MLResultsTab,'Text','Component:', ...
                'Position',[278 710 88 22],'FontColor',[0.25 0.25 0.25]);
            app.ResultsComponentDropDown = uidropdown(app.MLResultsTab, ...
                'Items',{'1'},'Position',[372 710 75 22]);

            app.PlotMLButton = uibutton(app.MLResultsTab,'push', ...
                'Text','📈 Plot Results', ...
                'Position',[462 706 150 30],'FontSize',12,'FontWeight','bold', ...
                'BackgroundColor',[0.23 0.55 0.30],'FontColor',[1 1 1], ...
                'ButtonPushedFcn', createCallbackFcn(app,@PlotMLButtonPushed,true));

            app.TaylorDiagramButton = uibutton(app.MLResultsTab,'push', ...
                'Text','◎ Taylor Diagram', ...
                'Position',[625 706 165 30],'FontSize',12,'FontWeight','bold', ...
                'BackgroundColor',[0.13 0.45 0.72],'FontColor',[1 1 1], ...
                'ButtonPushedFcn', createCallbackFcn(app,@TaylorDiagramButtonPushed,true));

            app.SaveFigCheckBox = uicheckbox(app.MLResultsTab, ...
                'Text','Save figure (300 dpi)','Value',false, ...
                'Position',[805 710 200 22]);

            app.MLResultsTable = uitable(app.MLResultsTab, ...
                'Position',[12 20 1216 670]);

            %% --- Tab 5: Comparison ---------------------------------------
            app.ComparisonTab = uitab(app.TabGroup,'Title','5. Compare & Export');

            btn_y = 700; btn_h = 40;
            btn_defs = { ...
                'GenerateComparisonButton', '📊 Comparison Plots', [12  btn_y 210 btn_h], @GenerateComparisonButtonPushed, [0.13 0.45 0.72]; ...
                'GenerateReportButton',     '📄 Text Report',      [235 btn_y 160 btn_h], @GenerateReportButtonPushed,    [0.23 0.55 0.30]; ...
                'ExportMATButton',          '💾 Export .mat',      [408 btn_y 140 btn_h], @ExportMATButtonPushed,         [0.45 0.35 0.65]; ...
                'ExportCSVButton',          '📋 Export .csv',      [561 btn_y 140 btn_h], @ExportCSVButtonPushed,         [0.45 0.35 0.65]; ...
                'ExportLaTeXButton',        '📝 Export LaTeX',     [714 btn_y 140 btn_h], @ExportLaTeXButtonPushed,       [0.60 0.35 0.15]; ...
            };
            for bi = 1:size(btn_defs,1)
                app.(btn_defs{bi,1}) = uibutton(app.ComparisonTab,'push', ...
                    'Text',btn_defs{bi,2},'Position',btn_defs{bi,3},'FontSize',11, ...
                    'FontWeight','bold','FontColor',[1 1 1], ...
                    'BackgroundColor',btn_defs{bi,5}, ...
                    'ButtonPushedFcn', createCallbackFcn(app,btn_defs{bi,4},true));
            end

            app.ComparisonStatusLabel = uilabel(app.ComparisonTab, ...
                'Position',[12 650 1200 30],'FontSize',11,'FontColor',[0.25 0.25 0.25]);
            app.ComparisonTable = uitable(app.ComparisonTab, ...
                'Position',[12 20 1216 610]);

            %% --- Tab 6: Session / Batch ----------------------------------
            app.SessionTab = uitab(app.TabGroup,'Title','6. Session & Batch');

            % ---- Session Management panel --------------------------------
            sp = uipanel(app.SessionTab,'Title','Session Management', ...
                'Position',[12 610 620 140], ...
                'BackgroundColor',[0.97 0.98 1.00], ...
                'BorderType','line','HighlightColor',[0.75 0.82 0.90]);
            app.SaveSessionButton = uibutton(sp,'push','Text','💾  Save Session', ...
                'Position',[20 70 220 40],'FontSize',12,'FontWeight','bold', ...
                'BackgroundColor',[0.13 0.45 0.72],'FontColor',[1 1 1], ...
                'ButtonPushedFcn', createCallbackFcn(app,@SaveSessionButtonPushed,true));
            app.LoadSessionButton = uibutton(sp,'push','Text','📂  Load Session', ...
                'Position',[260 70 220 40],'FontSize',12,'FontWeight','bold', ...
                'BackgroundColor',[0.23 0.55 0.30],'FontColor',[1 1 1], ...
                'ButtonPushedFcn', createCallbackFcn(app,@LoadSessionButtonPushed,true));
            uilabel(sp,'Text', ...
                'Save/load all results, data and settings between MATLAB sessions.', ...
                'Position',[20 35 580 22],'FontSize',10,'FontColor',[0.35 0.35 0.35]);

            % ---- Legacy Classical Batch panel ----------------------------
            bp_cls = uipanel(app.SessionTab,'Title', ...
                'Classical Batch (legacy — any CSV, no naming convention required)', ...
                'Position',[12 500 620 100], ...
                'BackgroundColor',[0.97 0.98 1.00], ...
                'BorderType','line','HighlightColor',[0.75 0.82 0.90]);
            app.BatchFolderButton = uibutton(bp_cls,'push', ...
                'Text','📁  Select folder & run classical batch', ...
                'Position',[15 35 340 42],'FontSize',11,'FontWeight','bold', ...
                'BackgroundColor',[0.55 0.40 0.20],'FontColor',[1 1 1], ...
                'ButtonPushedFcn', createCallbackFcn(app,@BatchFolderButtonPushed,true));
            uilabel(bp_cls,'Text', ...
                'Analyses all CSV files using the classical noise engine. No file-naming check.', ...
                'Position',[370 40 230 40],'WordWrap','on','FontSize',9, ...
                'FontColor',[0.4 0.4 0.4]);

            % Shared status bar
            app.BatchStatusLabel = uilabel(app.SessionTab, ...
                'Position',[12 468 1216 28],'FontSize',10, ...
                'FontColor',[0.3 0.3 0.3]);

            % ================================================================
            % ML Batch Engine panel (standardised naming convention)
            % ================================================================
            bp = uipanel(app.SessionTab,'Title', ...
                'ML Batch Engine  —  Standardised files: <SSSS>_<dlts|hrts|wlts>_txyz.csv', ...
                'Position',[12 20 1216 440],'FontWeight','bold', ...
                'ForegroundColor',[0.12 0.47 0.71], ...
                'BackgroundColor',[0.97 0.98 1.00], ...
                'BorderType','line','HighlightColor',[0.75 0.82 0.90]);

            % -- Row 1: Input folder ---------------------------------------
            uilabel(bp,'Text','Input Folder:','Position',[10 390 100 22], ...
                'FontWeight','bold','FontColor',[0.2 0.2 0.2]);
            app.BatchMLFolderButton = uibutton(bp,'push', ...
                'Text','Browse Input Folder...','Position',[115 388 200 26], ...
                'FontSize',11,'Tag','','FontWeight','bold', ...
                'BackgroundColor',[0.13 0.45 0.72],'FontColor',[1 1 1], ...
                'ButtonPushedFcn', createCallbackFcn(app,@BatchMLFolderButtonPushed,true));
            app.BatchMLInputLabel = uilabel(bp, ...
                'Text','No folder selected', ...
                'Position',[330 390 600 22],'FontColor',[0.5 0.5 0.5]);

            % -- Row 2: Output folder --------------------------------------
            uilabel(bp,'Text','Output Folder:','Position',[10 358 105 22], ...
                'FontWeight','bold','FontColor',[0.2 0.2 0.2]);
            app.BatchMLOutputButton = uibutton(bp,'push', ...
                'Text','Browse Output Folder...','Position',[115 356 200 26], ...
                'FontSize',11,'FontWeight','bold', ...
                'BackgroundColor',[0.13 0.45 0.72],'FontColor',[1 1 1], ...
                'ButtonPushedFcn', createCallbackFcn(app,@BatchMLOutputButtonPushed,true));
            app.BatchMLOutputLabel = uilabel(bp, ...
                'Text','Default: <input>/batch_results/', ...
                'Position',[330 358 600 22],'FontColor',[0.5 0.5 0.5]);

            % -- Row 3: Series type filter ---------------------------------
            uilabel(bp,'Text','Series Types:','Position',[10 310 105 22], ...
                'FontWeight','bold','FontColor',[0.2 0.2 0.2]);
            app.BatchMLTypesListBox = uilistbox(bp, ...
                'Items',{'dlts','hrts','wlts'}, ...
                'Value',{'dlts','hrts','wlts'}, ...
                'Multiselect','on', ...
                'Position',[115 280 200 60]);
            uilabel(bp,'Text','Hold Ctrl to multi-select', ...
                'Position',[115 262 200 18],'FontSize',9,'FontColor',[0.5 0.5 0.5]);

            % -- Options column --------------------------------------------
            uilabel(bp,'Text','Options:','Position',[340 325 80 22], ...
                'FontWeight','bold','FontColor',[0.2 0.2 0.2]);
            app.BatchMLSaveCSVCheckBox = uicheckbox(bp, ...
                'Text','Save denoised CSV per station', ...
                'Value',true,'Position',[340 300 260 22]);
            app.BatchMLSaveMATCheckBox = uicheckbox(bp, ...
                'Text','Save .mat results per station', ...
                'Value',true,'Position',[340 278 260 22]);
            app.BatchMLParallelCheckBox = uicheckbox(bp, ...
                'Text','Use parallel processing (if PCT available)', ...
                'Value',false,'Position',[340 256 300 22]);

            % -- Info box --------------------------------------------------
            info_bp = uipanel(bp,'Title','File convention & outputs', ...
                'Position',[620 248 580 145], ...
                'BackgroundColor',[0.94 0.96 0.99]);
            info_txt = sprintf([ ...
                'INPUT FILES must be named:  <SSSS>_<TYPE>_txyz.csv\n' ...
                '  SSSS = 4-char station code (e.g. YOLA, ABUZ, MAID)\n' ...
                '  TYPE = dlts (daily) | hrts (high-rate) | wlts (weekly)\n\n' ...
                'OUTPUTS written to Output Folder:\n' ...
                '  batch_summary.csv          all stations x methods x components\n' ...
                '  <SSSS>_summary.csv         per-station method ranking\n' ...
                '  <SSSS>_<type>_denoised.csv original + all denoised columns\n' ...
                '  <SSSS>_<type>_results.mat  full result structs']);
            uilabel(info_bp,'Text',info_txt,'Position',[8 5 560 130], ...
                'FontSize',9,'VerticalAlignment','top','WordWrap','on', ...
                'FontName','Courier New');

            % -- Progress label --------------------------------------------
            app.BatchMLProgressLabel = uilabel(bp, ...
                'Text','Select a folder to begin.', ...
                'Position',[10 230 1180 22],'FontSize',10,'FontColor',[0.3 0.3 0.3]);

            % -- Run button ------------------------------------------------
            app.BatchMLRunButton = uibutton(bp,'push', ...
                'Text','▶▶  Run ML Batch','Position',[10 180 230 46], ...
                'FontSize',14,'FontWeight','bold', ...
                'BackgroundColor',[0.12 0.47 0.71], ...
                'FontColor','white', ...
                'Enable','off', ...
                'ButtonPushedFcn', createCallbackFcn(app,@BatchMLRunButtonPushed,true));

            uilabel(bp,'Text', ...
                sprintf(['Uses methods and parameters from Tab 3 (ML Setup).\n' ...
                 'Window size is auto-set per series type when left at 0.\n' ...
                 'Hyperparameter optimisation uses current Optimize/Evaluations settings.']), ...
                'Position',[255 178 600 62],'WordWrap','on','FontSize',10, ...
                'FontColor',[0.3 0.3 0.3]);

            % -- Summary results table -------------------------------------
            uilabel(bp,'Text','Batch Summary (populated after run):', ...
                'Position',[10 152 400 22],'FontWeight','bold','FontColor',[0.2 0.2 0.2]);
            app.BatchMLSummaryTable = uitable(bp, ...
                'Position',[10 10 1185 138]);

            app.UIFigure.Visible = 'on';
        end

    end % createComponents

    %% ========================================================================
    %  LIFECYCLE
    %% ========================================================================
    methods (Access = public)
        function app = GNSS_ML_Comparison_App
            createComponents(app);
            registerApp(app, app.UIFigure);
            runStartupFcn(app, @startupFcn);
            if nargout == 0, clear app; end
        end

        function delete(app)
            delete(app.UIFigure);
        end
    end

end % classdef


%% ==========================================================================
%  LOCAL HELPER (non-method)
%% ==========================================================================
function key = display_to_key(disp_name)
% Map display name ('Random Forest') to METHOD_IDX key ('RF')
    map = containers.Map( ...
        {'GPR','SVR','Random Forest','Gradient Boosting','KNN'}, ...
        {'GPR','SVR','RF','GB','KNN'});
    if isKey(map, disp_name)
        key = map(disp_name);
    else
        key = disp_name;
    end
end


function psc = apply_period_search_preset(preset_name)
% APPLY_PERIOD_SEARCH_PRESET  Return a period_search_config for a named preset.
%
%   Presets:
%     'Default tolerances'           -- from default_period_search_config()
%     'Tight (stable signals)'       -- halve all tolerances
%     'Wide (unstable/noisy)'        -- double all tolerances; relax FAP
%     'Astronomical only (tides fixed)' -- tidal signals fixed; rest search
%     'All fixed (no search)'        -- all signals use nominal period

    psc = gnss_ml_utils('default_period_search_config');
    fields = fieldnames(psc);

    switch preset_name
        case 'Default tolerances'
            % nothing to change

        case 'Tight (stable signals)'
            for fi = 1:length(fields)
                f = fields{fi};
                if isfield(psc.(f),'tol')
                    psc.(f).tol = psc.(f).tol * 0.5;
                end
                if isfield(psc.(f),'fap_thresh')
                    psc.(f).fap_thresh = min(psc.(f).fap_thresh, 0.05);
                end
            end

        case 'Wide (unstable/noisy)'
            for fi = 1:length(fields)
                f = fields{fi};
                if isfield(psc.(f),'tol') && strcmp(psc.(f).mode,'search')
                    psc.(f).tol = psc.(f).tol * 2.0;
                end
                if isfield(psc.(f),'fap_thresh')
                    psc.(f).fap_thresh = min(psc.(f).fap_thresh * 2, 0.30);
                end
            end

        case 'Astronomical only (tides fixed)'
            % Tidal group already fixed in default; make seasonal/draconitic
            % also search (no change from default) -- this preset is an alias
            % for the default but with a reminder that tides are fixed.

        case 'All fixed (no search)'
            for fi = 1:length(fields)
                f = fields{fi};
                if isfield(psc.(f),'mode')
                    psc.(f).mode = 'fixed';
                end
            end

        otherwise
            % unknown preset -- return defaults
    end
end


function cfg = apply_signal_preset(preset_name)
% APPLY_SIGNAL_PRESET  Return a signal_config struct for a named preset.
%
%   Five presets are defined in increasing geodetic complexity:
%     'Minimal'         -- trend only (no periodic signals)
%     'Standard'        -- annual + semi-annual  [default]
%     'Extended'        -- Standard + ter-annual + quarterly
%     'Geodetic'        -- Extended + GPS draconitic harmonics 1-3
%     'Full geodetic'   -- Geodetic + tidal OTL aliases (Mf, MSf, Mm)
%     'Custom'          -- returns current default (no change to checkboxes)

    cfg = gnss_ml_utils('default_signal_config');

    switch preset_name
        case 'Minimal (trend only)'
            cfg.annual      = false;
            cfg.semi_annual = false;

        case 'Standard (annual + semi-annual)'
            % default is already annual + semi-annual; nothing more to do

        case 'Extended (+ ter-annual + quarterly)'
            cfg.ter_annual  = true;
            cfg.quarterly   = true;

        case 'Geodetic (+ draconitic 1-3)'
            cfg.ter_annual   = true;
            cfg.quarterly    = true;
            cfg.draconitic_1 = true;
            cfg.draconitic_2 = true;
            cfg.draconitic_3 = true;

        case 'Full geodetic (+ tidal aliases)'
            cfg.ter_annual   = true;
            cfg.quarterly    = true;
            cfg.draconitic_1 = true;
            cfg.draconitic_2 = true;
            cfg.draconitic_3 = true;
            cfg.draconitic_4 = true;
            cfg.draconitic_5 = true;
            cfg.mf_tidal     = true;
            cfg.msf_tidal    = true;
            cfg.mm_tidal     = true;
            cfg.chandler     = true;

        otherwise
            % 'Custom' -- return defaults unchanged, user controls checkboxes
    end
end


%% ==========================================================================
%  EMBEDDED CLASSICAL ENGINE  (improved)
%% ==========================================================================
function results = embedded_gnss_engine(filename, signal_config)
% Reads a GNSS coordinate file and performs classical noise analysis on
% each component.  Uses the extended gnss_ml_utils deterministic model
% with the full configurable signal set.
    if nargin < 2 || isempty(signal_config)
        signal_config = gnss_ml_utils('default_signal_config');
    end

    T      = readtable(filename, 'VariableNamingRule','preserve');
    col1   = T{:,1};
    data   = T{:, 2:end};

    % ---- Robust epoch parsing (MJD / J2000 / date string / index) ----------
    J2000_dt = datetime(2000, 1, 1, 12, 0, 0);
    [epoch, epoch_type] = gnss_parse_epoch(col1);   %#ok<ASGLU>

    % t_days = days since J2000.0 (numeric, used by fit_deterministic / plomb)
    if ~isempty(epoch)
        t_days = days(epoch - J2000_dt);
    else
        % Plain index fallback — treat 1-based integer as "days"
        t_days = (1:size(T,1))';
    end
    t_days = t_days(:);
    n_comp = size(data, 2);
    results(n_comp) = struct();

    for c = 1:n_comp
        x     = data(:, c);
        valid = ~isnan(x);
        x_v   = x(valid);
        t_v   = t_days(valid);
        n_v   = length(x_v);

        % -- Deterministic model with configurable signal set --------------
        % t_v may be negative (e.g. J2000 days for pre-2000 data).
        % gnss_ml_utils normalises internally (t_norm = t - t(1)), so the
        % call below is safe regardless of the t_v origin.
        [resid, det_model] = gnss_ml_utils('fit_deterministic', t_v, x_v, signal_config);

        % -- Zero-referenced time for spectral functions --------------------
        % pwelch and plomb both require non-negative, monotonically increasing
        % time.  Shift t_v so the first epoch = 0, preserving all spacings.
        t_norm_v = t_v - t_v(1);           % always >= 0
        t_years  = t_norm_v / 365.25;      % years from first epoch

        % -- Power spectral density (Welch) --------------------------------
        fs     = 1;   % 1 sample/day (assumed)
        [pxx, f] = pwelch(resid, hann(min(256, floor(n_v/4))), [], [], fs);
        f_pos  = f(f > 0);
        p_pos  = pxx(f > 0);

        % -- Spectral index fit (log-log) ----------------------------------
        logf = log10(f_pos);
        logp = log10(p_pos + eps);
        poly_k = polyfit(logf, logp, 1);
        k_val  = poly_k(1);

        % -- Lomb-Scargle periodogram (normalised time in years) -----------
        [pxx_ls, f_ls] = plomb(x_v, t_years);
        [~, locs]      = findpeaks(pxx_ls, f_ls, ...
            'MinPeakProminence', 0.1*max(pxx_ls));
        freqs = locs(1:min(5, length(locs)));

        % -- Noise component decomposition ---------------------------------
        freq_annual = 1.0;   % cpy
        freq_semi   = 2.0;
        white_power   = median(p_pos);
        flicker_power = mean(p_pos(f_pos < 0.01 & f_pos > 0.001) + eps);
        rw_power      = mean(p_pos(f_pos < 0.001) + eps);

        % -- Step detection (IQR on second differences) -------------------
        d2   = diff(diff(resid));
        thr  = 5 * iqr(d2);
        step_idx = find(abs(d2) > thr) + 2;

        % -- Store ---------------------------------------------------------
        results(c).signal    = x_v;
        results(c).t         = t_v;
        % Datetime axis for plots (only when epoch was successfully parsed)
        if ~isempty(epoch)
            results(c).dates = epoch(valid);
        else
            results(c).dates = [];
        end
        results(c).resid     = resid;
        results(c).det_model = det_model;
        results(c).trend     = det_model.trend;
        results(c).seasonal  = det_model.seasonal;  % sum of ALL active harmonic components
        results(c).sigma     = std(resid);
        results(c).k         = k_val;
        results(c).white     = white_power;
        results(c).flicker   = flicker_power;
        results(c).rw        = rw_power;
        results(c).f         = f_pos;
        results(c).pxx       = p_pos;
        results(c).f_ls      = f_ls;
        results(c).pxx_ls    = pxx_ls;
        results(c).freqs     = freqs;
        results(c).period    = 1 ./ f_pos;
        results(c).steps     = step_idx;
        results(c).velocity  = det_model.velocity;          % mm/yr
        results(c).vel_uncertainty = det_model.vel_uncertainty; % mm/yr 1-sigma
        results(c).A_annual  = det_model.A_annual;   % mm     (already converted in gnss_ml_utils)
        results(c).A_semi    = det_model.A_semi;     % mm     (already converted in gnss_ml_utils)
    end
end


function embedded_gnss_plot(results, component)
% 4-panel classical analysis plot with improved seasonal decomposition display.

    r   = results(component);
    n_r = length(r.signal);
    t_num = (1:n_r)';   % always numeric for plot() calls -- avoids DatetimeRuler

    % Date vector for tick labels only (not for plot x-data)
    if isfield(r, 'dates') && ~isempty(r.dates) && isa(r.dates,'datetime')
        t_axis    = r.dates;
        use_dates = true;
    else
        t_axis    = t_num;
        use_dates = false;
    end

    fig = figure('Color','w','Position',[80 80 1300 900], ...
        'Name', sprintf('Classical Analysis -- Component %d', component));

    % Station identifier in figure supertitle
    if isfield(results(component), 'station_name') && ...
       ~isempty(results(component).station_name)
        sgtitle(fig, sprintf('Station: %s  |  Component %d  |  Classical Analysis', ...
            results(component).station_name, component), ...
            'FontSize', 13, 'FontWeight', 'bold');
    end

    % Panel 1: Signal decomposition
    subplot(2,2,1);
    plot(t_num, r.signal,  'Color',[0.7 0.7 0.7],'LineWidth',0.8,'DisplayName','Original'); hold on;
    plot(t_num, r.trend + r.seasonal,'r-','LineWidth',2,'DisplayName','Det. model (T+S)');
    plot(t_num, r.trend,'k--','LineWidth',1.2,'DisplayName','Trend only');
    if ~isempty(r.steps)
        plot(t_num(r.steps), r.signal(r.steps),'mo','MarkerSize',8,'MarkerFaceColor','m','DisplayName','Steps');
    end
    grid on; box on; legend('Location','best','FontSize',8);
    apply_date_axis(gca, t_axis, use_dates); ylabel('Coordinate (m)');

    % Build velocity string with uncertainty if available
    vel_str = build_vel_string(r);
    title(sprintf('Component %d: Signal + Deterministic Model\n%s', ...
        component, vel_str), 'FontWeight','bold','FontSize',10);

    % Velocity info text box (lower-left of panel)
    text(0.02, 0.05, vel_str, 'Units','normalized','FontSize',9, ...
        'VerticalAlignment','bottom','HorizontalAlignment','left', ...
        'BackgroundColor','w','EdgeColor',[0.7 0.7 0.7], ...
        'FontName','Courier New');

    % Panel 2: Residuals
    subplot(2,2,2);
    plot(t_num, r.resid*1000,'b-','LineWidth',0.8); hold on;
    yline(0,'k--'); yline(2*r.sigma*1000,'r--'); yline(-2*r.sigma*1000,'r--');
    grid on; box on;
    apply_date_axis(gca, t_axis, use_dates); ylabel('Residual (mm)');
    title(sprintf('Residuals  (sigma=%.4f mm  k=%.3f)', r.sigma*1000, r.k), 'FontWeight','bold');

    % Panel 3: PSD
    subplot(2,2,3);
    loglog(r.f, r.pxx*1e6,'b-','LineWidth',1.5); hold on;
    % Overlay power-law fit line using stored k value
    f_fit  = r.f(r.f > 0);
    pf_coef = polyfit(log10(f_fit), log10(r.pxx(r.f>0)*1e6 + eps), 1);
    p_fit  = 10.^(polyval(pf_coef, log10(f_fit)));
    loglog(f_fit, p_fit,'r--','LineWidth',1.5,'DisplayName',sprintf('k=%.2f fit',pf_coef(1)));
    grid on; box on; legend('Location','best');
    xlabel('Frequency (cycles/day)', 'FontSize',10);
    ylabel('PSD (mm^2/Hz)', 'FontSize',10);
    title(sprintf('PSD (Welch, log-log) -- k=%.3f', r.k), 'FontWeight','bold');

    % Panel 4: Lomb-Scargle periodogram
    subplot(2,2,4);
    % Lomb-Scargle log-log: only plot f>0 to avoid log(0)
    f_ls_pos   = r.f_ls(r.f_ls > 0);
    pxx_ls_pos = r.pxx_ls(r.f_ls > 0);
    loglog(f_ls_pos, pxx_ls_pos,'m-','LineWidth',1.2); hold on;
    % Mark annual and semi-annual peaks
    xline(1.0,'b--','LineWidth',1,'DisplayName','1 cpy (annual)');
    xline(2.0,'g--','LineWidth',1,'DisplayName','2 cpy (semi-annual)');
    grid on; box on; legend('Location','best','FontSize',8);
    xlabel('Frequency (cycles/year)', 'FontSize',10);
    ylabel('LS Power (log scale)', 'FontSize',10);
    title(sprintf('Lomb-Scargle Periodogram (log-log)  A_{ann}=%.3f mm', r.A_annual), 'FontWeight','bold');

    % No author stamp -- station identified in sgtitle above
end


function generate_batch_report(batch_summary, out_dir)
% Write a concise batch summary text file.

    fid = fopen(fullfile(out_dir, 'batch_report.txt'), 'w');
    fprintf(fid,'GNSS BATCH CLASSICAL ANALYSIS REPORT\n');
    fprintf(fid,'%s\n', repmat('=',1,60));
    fprintf(fid,'Generated: %s\n\n', datestr(now));
    for fi = 1:length(batch_summary)
        s = batch_summary{fi};
        if isfield(s,'error')
            fprintf(fid,'%-30s  ERROR: %s\n', s.file, s.error);
        else
            sig_str = sprintf('%.4f ', s.sigmas*1000);
            k_str   = sprintf('%.3f  ', s.ks);
            fprintf(fid,'%-30s  n_comp=%d  sigma(mm)=[%s]  k=[%s]\n', ...
                s.file, s.n_comp, strtrim(sig_str), strtrim(k_str));
        end
    end
    fclose(fid);
end


%% ==========================================================================
%  STANDALONE DISPATCHER  -- callable from both sequential loops and parfor
%  (class methods cannot be called inside parfor; standalone functions can)
%% ==========================================================================
function r = gnss_run_single_method(meth, data_in, window_size, ...
                                     num_trees, optimize, run_cv, signal_config, ...
                                     cls_det_model)
% GNSS_RUN_SINGLE_METHOD  Route to the correct denoiser function.
%
%   cls_det_model (optional): det_model from embedded_gnss_engine, fitted
%   on the physical time axis (J2000/MJD days).  When provided, its velocity
%   replaces the ML pre-processing velocity (which uses integer epoch index
%   and can differ for non-daily or gappy data).
%
%   Kept as a file-level function so it is visible inside parfor loops.

    if nargin < 7 || isempty(signal_config)
        signal_config = gnss_ml_utils('default_signal_config');
    end
    if nargin < 8, cls_det_model = []; end

    switch meth
        case 'GPR'
            r = gnss_gpr_denoiser(data_in, ...
                'OptimizeHyperparameters', optimize, ...
                'RunCV', run_cv, 'Verbose', false, ...
                'SignalConfig', signal_config);
        case 'SVR'
            r = gnss_svr_denoiser(data_in, ...
                'WindowSize', window_size, ...
                'OptimizeHyperparameters', optimize, ...
                'RunCV', run_cv, 'Verbose', false, ...
                'SignalConfig', signal_config);
        case 'RF'
            r = gnss_rf_denoiser(data_in, ...
                'WindowSize', window_size, ...
                'NumTrees', num_trees, ...
                'FastMode', true, ...
                'RunCV', run_cv, 'Verbose', false, ...
                'SignalConfig', signal_config);
        case 'GB'
            r = gnss_gb_denoiser(data_in, ...
                'WindowSize', window_size, ...
                'NumTrees', num_trees, ...
                'RunCV', run_cv, 'Verbose', false, ...
                'SignalConfig', signal_config);
        case 'KNN'
            r = gnss_knn_denoiser(data_in, ...
                'WindowSize', window_size, ...
                'RunCV', run_cv, 'Verbose', false, ...
                'SignalConfig', signal_config);
        otherwise
            error('gnss_run_single_method:unknownMethod', ...
                'Unknown method key: ''%s''. Valid: GPR, SVR, RF, GB, KNN.', meth);
    end

    % ------------------------------------------------------------------
    % Substitute classical det_model velocity (always physically correct).
    % The ML pre-processing uses t=(1:n)' which gives a wrong velocity
    % when epoch spacing != 1 day (weekly, high-rate, gappy daily data).
    % ------------------------------------------------------------------
    if ~isempty(cls_det_model) && isstruct(cls_det_model)
        if isfield(cls_det_model,'velocity')
            r.det_model.velocity = cls_det_model.velocity;
        end
        if isfield(cls_det_model,'A_annual')
            r.det_model.A_annual = cls_det_model.A_annual;
        end
        if isfield(cls_det_model,'A_semi')
            r.det_model.A_semi   = cls_det_model.A_semi;
        end
        anchor_dm = cls_det_model;
    else
        anchor_dm = r.det_model;
    end

    % ------------------------------------------------------------------
    % Per-method velocity uncertainty and spectral index k
    % ------------------------------------------------------------------
    try
        den_info = gnss_ml_utils('fit_denoised', ...
            r.denoised_signal, signal_config, [], anchor_dm);
        r.det_model.vel_uncertainty  = den_info.vel_uncertainty;
        r.det_model.vel_scale_factor = den_info.vel_scale_factor;
        r.k_denoised = den_info.k;
    catch ME
        warning('gnss_run_single_method:metricsFailed', ...
            '%s post-denoising metrics failed: %s', meth, ME.message);
        r.k_denoised = NaN;
    end
end


%% ==========================================================================
%  BATCH PROCESSING  -- analyse a folder of stations, save summary CSV
%% ==========================================================================
function gnss_batch_analyse(input_folder, output_folder, methods, params)
% GNSS_BATCH_ANALYSE  Run the full ML pipeline on every CSV in a folder.
%
%   Usage:
%     params.window_size = 30;
%     params.num_trees   = 100;
%     params.optimize    = false;   % <-- set false for batch speed
%     params.run_cv      = false;
%     gnss_batch_analyse('./stations', './results', ...
%                         {'GPR','SVR','RF','GB','KNN'}, params);
%
%   Output: output_folder/batch_summary.csv  +  one .mat per station

    if nargin < 3, methods = {'GPR','SVR','RF','GB','KNN'}; end
    if nargin < 4
        params = struct('window_size',30,'num_trees',100,...
                        'optimize',false,'run_cv',false);
    end
    if ~exist(output_folder,'dir'), mkdir(output_folder); end

    files = [dir(fullfile(input_folder,'*.csv')); ...
             dir(fullfile(input_folder,'*.xlsx'))];
    n_files = length(files);
    if n_files == 0
        error('gnss_batch_analyse:noFiles','No CSV/XLSX files found in: %s', ...
            input_folder);
    end

    fprintf('Batch: %d stations | %d methods | optimize=%d\n', ...
        n_files, length(methods), params.optimize);
    fprintf('Estimated time: ~%.0f min\n\n', n_files * estimate_time(methods, params));

    summary_rows = {};
    t_start_all  = tic;

    for fi = 1:n_files
        fpath = fullfile(input_folder, files(fi).name);
        fprintf('[%d/%d] %s ... ', fi, n_files, files(fi).name);
        t_start = tic;

        try
            % Classical
            res_c = embedded_gnss_engine(fpath);
            n_comp = length(res_c);

            % ML -- one component at a time to keep memory flat
            res_ml = cell(n_comp, length(methods));
            for c = 1:n_comp
                T     = readtable(fpath, 'VariableNamingRule','preserve');
                x_raw = T{:, c+1};
                x_raw = x_raw(:);
                valid = ~isnan(x_raw);
                if sum(valid) < 60, continue; end
                good  = find(valid);
                x_in  = interp1(good, x_raw(valid), (1:length(x_raw))', ...
                                'linear','extrap');

                for mi = 1:length(methods)
                    try
                        res_ml{c,mi} = gnss_run_single_method( ...
                            methods{mi}, x_in, ...
                            params.window_size, params.num_trees, ...
                            params.optimize, params.run_cv);
                    catch ME
                        res_ml{c,mi} = struct('error', ME.message);
                    end
                end
            end

            % Save per-station .mat
            mat_path = fullfile(output_folder, ...
                [strrep(files(fi).name,'.','_') '.mat']);
            save(mat_path, 'res_c', 'res_ml');

            % Append to summary
            for c = 1:n_comp
                for mi = 1:length(methods)
                    r = res_ml{c,mi};
                    if isempty(r) || ~isstruct(r) || isfield(r,'error')
                        row = {files(fi).name, c, methods{mi}, NaN, NaN, NaN, NaN};
                    else
                        row = {files(fi).name, c, methods{mi}, ...
                               r.residual_std*1000, r.snr_improvement, ...
                               r.noise_reduction,   r.rmse*1000};
                    end
                    summary_rows(end+1,:) = row; %#ok<AGROW>
                end
            end

            elapsed = toc(t_start);
            fprintf('done (%.1fs)\n', elapsed);

        catch ME
            fprintf('FAILED: %s\n', ME.message);
            summary_rows(end+1,:) = {files(fi).name, NaN, 'ALL', NaN, NaN, NaN, NaN};
        end
    end

    % Write summary CSV
    if ~isempty(summary_rows)
        T_sum = cell2table(summary_rows, 'VariableNames', ...
            {'Station','Component','Method','sigma_mm','SNR_dB','NR_pct','RMSE_mm'});
        csv_path = fullfile(output_folder, 'batch_summary.csv');
        writetable(T_sum, csv_path);
        fprintf('\nBatch complete in %.1f min. Summary: %s\n', ...
            toc(t_start_all)/60, csv_path);
    end
end


function t_min = estimate_time(methods, params)
% Rough per-station time estimate in minutes
    times = struct('GPR', 2.0, 'SVR', 1.0, 'RF', 0.3, 'GB', 0.4, 'KNN', 0.1);
    if ~params.optimize
        times.GPR = 0.3;  times.SVR = 0.2;
    end
    t_min = 0;
    for mi = 1:length(methods)
        if isfield(times, methods{mi})
            t_min = t_min + times.(methods{mi});
        end
    end
end


function add_figure_stamp_app(~)
% ADD_FIGURE_STAMP_APP  Stub kept for backwards compatibility.
%   Author stamp has been removed from all figures.
%   Station name is shown in the figure supertitle (sgtitle) instead.
end


function apply_date_axis(ax, date_vec, use_dates)
% APPLY_DATE_AXIS  Apply dd-mm-yyyy date labels to an axis.
%
%   All plots in the app now use a numeric x-axis (1:n) so the ruler is
%   always a NumericRuler.  This function keeps numeric XTick positions
%   and replaces only the string labels with formatted dates.
%   A try/catch guards against any edge-case ruler mismatch.

    if nargin < 3, use_dates = isa(date_vec, 'datetime'); end
    if ~use_dates || ~isa(date_vec,'datetime') || length(date_vec) < 2
        xlabel(ax, 'Epoch', 'FontSize', 10);
        return;
    end

    n       = length(date_vec);
    n_ticks = min(8, n);
    idx     = unique(round(linspace(1, n, n_ticks)));
    idx     = idx(idx >= 1 & idx <= n);

    try
        ax.XTick      = idx;
        ax.XTickLabel = datestr(date_vec(idx), 'dd-mm-yyyy');
        ax.XTickLabelRotation = 30;
        xlabel(ax, 'Date', 'FontSize', 10);
    catch
        xlabel(ax, 'Epoch', 'FontSize', 10);
    end
end


function T = get_detected_T(r, field)
% GET_DETECTED_T  Extract detected period string for a signal from a result struct.
    try
        dp = r.det_model.detected_periods;
        if isfield(dp, field)
            T = sprintf('%.3f', dp.(field).T_used);
        else
            T = '--';
        end
    catch
        T = '--';
    end
end


function out = safe_trim(v, target_len)
% SAFE_TRIM  Force vector v to exactly target_len elements.
%
%   ML denoised signals can be shorter than the original by up to
%   window_size epochs (the initial epochs are filled from the normalised
%   series prefix).  This pads with the last value or truncates so that
%   subplot overlays never throw a size mismatch.

    v = v(:);
    n = length(v);
    if n == target_len
        out = v;
    elseif n > target_len
        out = v(1:target_len);          % truncate
    else
        out = [v; repmat(v(end), target_len - n, 1)];  % pad with last value
    end
end


%% ==========================================================================
%  EPOCH COLUMN PARSER  -- shared by LoadFileButtonPushed & embedded_gnss_engine
%% ==========================================================================
function [dv, epoch_type] = gnss_parse_epoch(col1)
% GNSS_PARSE_EPOCH  Convert a raw epoch column to a datetime vector.
%
%   Recognised formats (tested in strict priority order):
%
%   Priority  Format               Typical range / example
%   --------  ------               -----------------------
%   1  datetime object             MATLAB datetime pass-through
%   2  Julian Date (JD)            numeric > 2 400 000   e.g. 2459000.5
%   3  J2000 seconds               numeric > 1 000 000   e.g. 630 763 200
%                                  (seconds elapsed since J2000.0 = 1 Jan 2000 12:00)
%   4  MJD                         numeric 44 244..99 999 e.g. 58849
%                                  (GPS era: MJD 44244 = 6 Jan 1980)
%   5  Decimal year                numeric in [1980..2100] with fraction
%                                  e.g. 2020.5328
%   6  J2000 days                  numeric in (-10 000..50 000]
%                                  median step >= 0.09 d
%                                  e.g. 7305.5  (= 1 Jan 2020)
%   7  Epoch index                 numeric, remaining cases -> dv = []
%   8  ISO 8601 date+time strings  'yyyy-MM-ddTHH:mm:ss' and variants
%   9  ISO 8601 date-only strings  'yyyy-MM-dd', 'yyyyMMdd', 'yyyy/MM/dd'
%  10  DOY strings                 'yyyy DDD', 'yyyy-DDD', 'yyyyDDD'
%  11  Other date strings          dd/MM/yyyy, MM/dd/yyyy, dd-MMM-yyyy …
%  12  Numeric string              cell/string -> str2double -> recurse
%  13  Fallback                    dv = [], epoch_type = 'epoch index'
%
%   -----------------------------------------------------------------------
%   PRIORITY BOUNDARIES (numeric, no ambiguity):
%
%     JD         > 2 400 000        (JD 2000000 = 26 May 763 AD -> safe)
%     J2000 sec  > 1 000 000        GPS era: ~630 M s (Jan 1980) to
%                                            ~700 M s (year 2022)
%                                   Cannot overlap MJD (max GPS-era MJD ~80000)
%     MJD        in [44 244..99 999] GPS era; tested after J2000-sec guard
%     Dec yr     all in [1980..2100] with non-zero fractional part
%     J2000 days in (-10 000..50 000], median step >= 0.09 d
%   -----------------------------------------------------------------------
%
%   Outputs:
%     dv         - datetime column vector, or [] if plain epoch index
%     epoch_type - human-readable label shown in the app DataInfoLabel

    % J2000.0 reference epoch (no TimeZone to maximise version compatibility)
    J2000_dt   = datetime(2000, 1, 1, 12, 0, 0);
    dv         = [];
    epoch_type = 'epoch index';

    % ==================================================================
    % 1. Already a MATLAB datetime
    % ==================================================================
    if isdatetime(col1)
        dv         = col1(:);
        epoch_type = 'datetime';
        return;
    end

    % ==================================================================
    % 2–7. Numeric column
    % ==================================================================
    if isnumeric(col1)
        vals = double(col1(:));
        mx   = max(vals, [], 'omitnan');
        mn   = min(vals, [], 'omitnan');

        % ---- 2. Julian Date (JD) ----------------------------------------
        % JD 2451545.0 = J2000.0 noon;  JD 2440588.0 = Unix epoch 1 Jan 1970.
        % GPS-era JD values: JD 2 444 245 (6 Jan 1980) to JD ~2 488 070 (year 2100).
        % All GPS-era JD values lie in the window (2 400 000 .. 2 600 000].
        % Values above 2 600 000 cannot be valid JD for any GNSS data and are
        % treated as J2000 seconds in the next branch.
        if mx > 2400000 && mx <= 2600000
            try
                dv         = datetime(vals - 2400000.5, ...
                                 'ConvertFrom', 'modifiedjuliandate');
                epoch_type = 'Julian Date (JD)';
            catch
            end
            return;
        end

        % ---- 3. J2000 seconds -------------------------------------------
        % Seconds elapsed since J2000.0 (= 1 Jan 2000, 12:00 UTC).
        %
        %   GPS start 6 Jan 1980  =>  J2000s ~ -630 763 148  (large negative)
        %   1 Jan 2000 12:00      =>  J2000s =           0
        %   1 Jan 2026            =>  J2000s ~  820 108 800  (large positive)
        %
        % Non-overlapping separation from JD:
        %   JD GPS era max  ~  2 488 070  (<= 2 600 000, already handled above)
        %   J2000s min pos  ~    630 000  (GPS start, large positive)
        %   Gap between them:  2 600 000  to  630 000 000 -- nothing valid lives here.
        %
        % Detection: mx > 2 600 000 (positive post-J2000 seconds)
        %         OR mn < -86 400   (pre-J2000 data, e.g. year 1980 => -631 M)
        if mx > 2600000 || mn < -86400
            try
                dv         = J2000_dt + seconds(vals);
                epoch_type = 'J2000 seconds';
            catch
            end
            return;
        end

        % ---- 4. Modified Julian Date (MJD) ------------------------------
        % MJD 0 = 17 Nov 1858.  GPS era: MJD 44 244 (6 Jan 1980) onward.
        % After JD (>2.4M) and J2000s (>100k) are excluded, values > 44 000
        % are unambiguously GPS-era MJD.
        if mx > 44000
            try
                dv         = datetime(vals, 'ConvertFrom', 'modifiedjuliandate');
                epoch_type = 'MJD';
            catch
            end
            return;
        end

        % ---- 5. Decimal year (e.g. 2020.5328) ---------------------------
        % All values in [1980..2100] with a non-zero fractional part.
        if mn >= 1980 && mx <= 2100
            frac_parts = mod(vals, 1);
            has_frac   = any(frac_parts > 1e-6);
            if has_frac
                try
                    yr_int     = floor(vals);
                    frac       = vals - yr_int;
                    % Per-epoch days-in-year (handles leap years correctly)
                    days_in_yr = days(datetime(yr_int + 1, 1, 1) - ...
                                      datetime(yr_int,     1, 1));
                    dv         = datetime(yr_int, 1, 1) + ...
                                 days(frac .* days_in_yr);
                    epoch_type = 'decimal year';
                catch
                end
                return;
            end
            % Pure integer years without fraction -> epoch index
            epoch_type = 'epoch index';
            return;
        end

        % ---- 6. J2000 days ----------------------------------------------
        % Days elapsed since J2000.0 noon.
        %   GPS start  6 Jan 1980  =>  -7300.5 d
        %   1 Jan 2026             =>  +9497 d
        %   year 2050              =>  +18262 d
        % Upper bound 44 000 d aligns with MJD lower bound (no gap/overlap).
        % Lower bound -10 000 d covers back to ~1972.
        % Minimum span guard: if all values are small non-negative integers
        % (1,2,3…) they are plain epoch indices, not J2000 days.
        is_j2000_day_range = (mx <= 44000) && (mn >= -10000);
        looks_like_index   = (mn >= 0) && (mx < 5000) && ...
                             (numel(vals) > 1) && ...
                             (max(abs(diff(sort(vals)))) <= 1.5);
        if is_j2000_day_range && ~looks_like_index
            if numel(vals) > 1
                med_step = median(abs(diff(vals)), 'omitnan');
            else
                med_step = 1;   % single-epoch file -> assume daily
            end
            if med_step >= 0.09
                try
                    dv         = J2000_dt + days(vals);
                    epoch_type = 'J2000 days';
                catch
                end
            else
                % Sub-daily fractional-day J2000 series
                try
                    dv         = J2000_dt + days(vals);
                    epoch_type = 'J2000 days (sub-daily)';
                catch
                end
            end
            return;
        end

        % ---- 7. Plain epoch index (unrecognised numeric) ----------------
        epoch_type = 'epoch index';
        return;
    end

    % ==================================================================
    % 8–12. String / cell column
    % ==================================================================
    if iscell(col1) || isstring(col1)

        % Ordered from most specific to least specific.
        % Cell array: {InputFormat, friendly_label}
        date_fmts = {
            % ISO 8601 date+time (with T separator)
            'yyyy-MM-dd''T''HH:mm:ss.SSS', 'ISO 8601 datetime+ms';
            'yyyy-MM-dd''T''HH:mm:ss',     'ISO 8601 datetime';
            % ISO 8601 date+time (space separator)
            'yyyy-MM-dd HH:mm:ss.SSS',     'datetime+ms (space)';
            'yyyy-MM-dd HH:mm:ss',         'datetime (space)';
            % ISO 8601 date-only variants
            'yyyy-MM-dd',                  'ISO date (yyyy-MM-dd)';
            'yyyy/MM/dd',                  'ISO date (yyyy/MM/dd)';
            'yyyyMMdd',                    'ISO date compact';
            % Day-of-year (DOY) -- geodetically very common
            'yyyy DDD',                    'year + DOY (space)';
            'yyyy-DDD',                    'year + DOY (dash)';
            'yyyyDDD',                     'year + DOY (compact)';
            % Regional date formats
            'dd/MM/yyyy HH:mm:ss',         'datetime (dd/MM/yyyy)';
            'dd/MM/yyyy',                  'date (dd/MM/yyyy)';
            'MM/dd/yyyy HH:mm:ss',         'datetime (MM/dd/yyyy)';
            'MM/dd/yyyy',                  'date (MM/dd/yyyy)';
            'dd-MMM-yyyy HH:mm:ss',        'datetime (dd-MMM-yyyy)';
            'dd-MMM-yyyy',                 'date (dd-MMM-yyyy)';
            'dd MMM yyyy',                 'date (dd MMM yyyy)';
            'MMM dd yyyy',                 'date (MMM dd yyyy)';
        };

        for fi = 1:size(date_fmts, 1)
            try
                dv_try = datetime(col1, 'InputFormat', date_fmts{fi,1});
                if all(isnat(dv_try))
                    continue;   % format parsed but produced no valid dates
                end
                dv         = dv_try;
                epoch_type = sprintf('date string (%s)', date_fmts{fi,2});
                return;
            catch
                % format did not match -- try next
            end
        end

        % ---- 12. String encodes a number -> recurse through numeric path -
        try
            num_vals = str2double(col1);
            if all(isfinite(num_vals))
                [dv, epoch_type] = gnss_parse_epoch(num_vals);
                return;
            end
        catch
        end

        % ---- 13. Unrecognised string ------------------------------------
        epoch_type = 'epoch index (unrecognised string)';
    end
end


function s = build_vel_string(r)
% BUILD_VEL_STRING  Format velocity ± uncertainty string for figure annotations.
%   Works for both classical results structs and ML det_model structs.
%   Returns a string like:  "vel = +2.34 ± 0.12 mm/yr"
%   or "vel = +2.34 mm/yr" if uncertainty is unavailable.

    % Extract velocity
    if isfield(r,'velocity')
        vel = r.velocity;
    elseif isfield(r,'det_model') && isfield(r.det_model,'velocity')
        vel = r.det_model.velocity;
    else
        s = 'vel = N/A';
        return;
    end

    % Extract uncertainty
    vel_unc = NaN;
    if isfield(r,'vel_uncertainty')
        vel_unc = r.vel_uncertainty;
    elseif isfield(r,'det_model') && isfield(r.det_model,'vel_uncertainty')
        vel_unc = r.det_model.vel_uncertainty;
    end

    % Format string
    if ~isnan(vel_unc)
        s = sprintf('vel = %+.3f \x00B1 %.3f mm/yr', vel, vel_unc);
    else
        s = sprintf('vel = %+.3f mm/yr', vel);
    end
end
