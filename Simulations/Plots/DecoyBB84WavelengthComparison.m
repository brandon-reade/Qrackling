% Author: Brandon Reade
% Date: 22/04/2026
% Best-wavelength study at fixed candidate wavelengths (no continuous wavelength sweep)

% To do:
%   - Include satellite pass comparisons
%   - QBER comparisons
%   - Frequency comparisons
%   - Perfect vs standardised vs current real detectors
%   - Include saving QKD run tables and summary settings
%   - Include satellite pass comparison

%% Configure MODTRAN Data
repo_root = utilities.addUserPath('~\Documents\GitHub\Qrackling');

% 1k vis
modtran_dir = fullfile(repo_root, 'Examples', 'Data', ...                              
    'atmospheric transmittance', 'raw modtran data',...
    'HOGS_WinterClear_Lunar_angles', 'HOGS_Winter-1kVis',...
    'moon_jan3rd_2026_1am_800to3000nm_full');   % sun_jan3rd_2026_1pm_800to3000nm_full
                                               % moon_jan3rd_2026_1am_800to3000nm_full

% 10k vis
modtran_dir1 = fullfile(repo_root, 'Examples', 'Data', ...                              
    'atmospheric transmittance', 'raw modtran data',...
    'HOGS_WinterClear_Lunar_angles', 'HOGS_WinterClear-10kVis',...
    'moon_jan3rd_2026_800to3000_1am_full');   % sun_jan3rd_2026_1pm_800to3000nm_full
                                               % moon_jan3rd_2026_800to3000_1am_full 

% dawn
modtran_dir1 = fullfile(repo_root,...
    '+modtran\Data\HOGS\HOGS_sun_Jan3_8am_1kmvis_300to10000_zenstep10_azistep30');  % dawn 8am

if ~isfolder(modtran_dir)
    error('MODTRAN folder not found: %s', modtran_dir);
end
addpath(fullfile(repo_root));

%% 1. Choose parameters
plot_best_vs_rxdiam      = true;
plot_heatmap             = true;                                            % optional: heatmap of metric over (rxDiam x wavelength)
plot_each_pass           = false;  

% system configuration
perfect_detectors       = false;
small_sat               = false;

if small_sat
    defaultTxDiam = 0.3;
else
    defaultTxDiam = 0.08;
end

OrbitDataFileLocation = "500kmSSOrbitLLAT.txt";
Receiver_Jitter       = 1e-6;
Rep_Rate              = 1e9;
Spectral_Filter_Width = 1;      % nm

% decoy state parameters
MPNs = [0.8, 0.3, 0];
SPs  = [0.7, 0.2, 0.1];
state_prep_error = 0.0025;

%  Candidate wavelengths you want to consider (NO sweep)
candidateWavelengthsNm = [
    850;  1290; 1400; 
    1550; 1556; 1589; 
    1700; %1800; 1900;
    2132; 2193; 2210; 2230; 2310
    ];

% ignore a subset even in candidate list
%%{ 
ignoreRangesNm = [
    890, 980;
    1110, 1170;
    1330, 1520;
    1770, 1999; 
    2040, 2080;
    2510, 2895];
%}

% Sweep variable: receiver diameter
rxSweep_m = [0.2 : 0.2 : 2, 3 : 1 : 5]';                                   % 0.2 steps from 0.2 to 2, then 1 steps from 2 to 10


% Compare two TX diameters
txDiameters_m = [0.08; 0.3];

% Ground station location
LLA  = [55.909723,-3.319995,10];
Name = "Heriot-Watt";

% Mask used to summarize metrics
% - "Communication" is usually best for "total keys generated"
metricMask = "Communication";

%% 2. Choose detector presets for each candidate wavelength
% For fixed candidate wavelengths, it's best to define presets explicitly.
% Adjust to match your repo's available presets.
detPresetFcn = @(w) localPresetForWavelength(w, perfect_detectors);
timeGateFcn = @(w) localGateForWavelength(w, perfect_detectors);

% Create a QKDsystems template
if perfect_detectors
    QKDsystems = struct( ...
    'Wavelength', {850, 1550, 2210, 2310}, ...
    'DetectorPreset', {'Perfect', 'Perfect', 'Perfect', 'Perfect' }, ...
    'txDiam', {defaultTxDiam, defaultTxDiam, defaultTxDiam, defaultTxDiam}, ...
    'rxDiam', {1, 1, 1, 1}, ...
    'rxFOV', {37E-6, 37E-6, 37E-6, 37E-6}, ...
    'TimeGateWidth', {500E-12, 500E-12, 100E-12, 100E-12} );
else
    QKDsystems = struct( ...
        'Wavelength', {850, 1550, 2210, 2310}, ...
        'DetectorPreset', {'PerkinElmer', 'QuantumOpus1550_RoomTempAmplifier', 'SNSPD_NbTiN_2um', 'SNSPD_NbTiN_2um' }, ...
        'txDiam', {defaultTxDiam, defaultTxDiam, defaultTxDiam, defaultTxDiam}, ...
        'rxDiam', {1, 1, 1, 1}, ...
        'rxFOV', {37E-6, 37E-6, 37E-6, 37E-6}, ...
        'TimeGateWidth', {352E-12, 352E-12, 28.6E-12, 28.6E-12} );
end

%% 3. Create the Environment
Env = buildEnvironment(modtran_dir);

%% 4. Run sweep
% run a sweep over rxDiam and evaluate systems at the candidate wavelengths

T = utilities.runQKDSweep(Env, QKDsystems, ...
    SweepVarName="rxDiam", ...
    SweepValues=rxSweep_m, ...
    WavelengthsNm=candidateWavelengthsNm, ...
    TxDiameters=txDiameters_m, ...
    DetectorPresetFcn=detPresetFcn, ...
    TimeGateWidthFcn=timeGateFcn,...
    UseParallel=true, ...
    NumWorkers=2,...
    Mask=metricMask,...
    SatMode="orbitFile");                                                    % "orbitFile" or "elements"
    
    % IgnoreRangesNm=ignoreRangesNm, ...


Tq = T(T.NCommSamples > 0, :);                                          % QBER is only meaningful when there's actual key exchange otherwise QBER may sit at 0.5 by default. So before plotting QBER filter
%% 5. Plot: best wavelength vs RX diameter with TX diameter lines
if plot_best_vs_rxdiam
    % Total secret keys
    plots.compare.plotBestWavelengthVsSweep(T, ...
        Metric="TotalSecretKeys", ...
        GroupBy=["TxDiam_m"], ...
        BestMode="max", ...
        ShowBestWavelengthLabels=true, ...
        FigureName="Best candidate wavelength (max total keys) vs Rx diameter", ...
        YScale="log");

    % minimum Mean QBER
    plots.compare.plotBestWavelengthVsSweep(T, ...
        Metric="MeanQBER", ...
        GroupBy=["TxDiam_m"], ...
        BestMode="min", ...                    
        ShowBestWavelengthLabels=true, ...
        FigureName="Best candidate wavelength (min mean QBER) vs Rx diameter", ...
        YScale="linear");

    % Minimum loss
    plots.compare.plotBestWavelengthVsSweep(T, ...
        Metric="MeanLoss_dB", ...
        GroupBy=["TxDiam_m"], ...
        BestMode="min", ...                    
        ShowBestWavelengthLabels=true, ...
        FigureName="Best candidate wavelength (min Loss) vs Rx diameter", ...
        YScale="linear");
end

%% 6. Heatmap (RxDiam x Wavelength) for each TxDiam
if plot_heatmap
    plots.compare.plotSweepHeatmap(T, ...
        Metric="TotalSecretKeys", ...
        XVar="WavelengthNm", ...
        YVar="RxDiam_m", ...
        GroupBy="TxDiam_m", ...
        FigureName="Heatmap: Total secret keys (candidate wavelengths)", ...
        ColorScale="log", ...
        InterpolateToGrid=true, ...
        InterpMethod="pchip", ...
        Interp="none");

    plots.compare.plotSweepHeatmap(T, ...
        Metric="MeanQBER", ...
        XVar="WavelengthNm", ...
        YVar="RxDiam_m", ...
        GroupBy="TxDiam_m", ...
        Combine="min", ...
        ColorScale="linear", ...
        Colormap="turbo", ...
        InterpolateToGrid=true, ...
        NX=600, NY=400, ...
        InterpMethod="pchip", ...
        ShowSamplePoints=true);

    plots.compare.plotSweepHeatmap(T, ...
        Metric="MeanLoss_dB", ...
        XVar="WavelengthNm", ...
        YVar="RxDiam_m", ...
        GroupBy="TxDiam_m", ...
        Combine="min", ...
        ColorScale="linear", ...
        Colormap="turbo", ...
        InterpolateToGrid=true, ...
        NX=600, NY=400, ...
        InterpMethod="pchip", ...
        ShowSamplePoints=true);
end

%%  Functions
% Detector preset
function preset = localPresetForWavelength(w, perfect)
    if perfect
        preset = "Perfect";
    else
        if w >= 825 && w < 1000
            preset = "PerkinElmer";
        elseif w >= 1000 && w <= 1700
            preset = "QuantumOpus1550_RoomTempAmplifier";
        elseif w >= 2000 && w <= 3000
            preset = "SNSPD_NbTiN_2um";
        else
            error("No detector preset found for wavelength: %d nm", w);
        end
    end
end

function g = localGateForWavelength(w, perfect)
    if perfect
        g = 50e-12;
    else
        if w >= 825 && w < 1000
            g = 500e-12;
        elseif w >= 1000 && w <= 1700
            g = 352e-12;
        elseif w >= 2000 && w <= 3000
            g = 28.6e-12;
        else
            error("No detector preset found for wavelength: %d nm", w);
        end
    end
end

% Environment builder
function Env = buildEnvironment(env_dir)
    envFile = dir(fullfile(env_dir, 'Radiant Environment*.mat'));
    if ~isempty(envFile)
        fprintf("Found environment...\n");
        Env = environment.Environment.Load(fullfile(envFile(1).folder, envFile(1).name));
    else
        fprintf("Building environment...\n");
        envPath = createMODTRANEnv(char(env_dir));
        Env = environment.Environment.Load(envPath);
    end
    Env.turbulence_model = environment.Turbulence_Model('Preset','HV10-10');
end

% Build pass cases
function passCases = buildPassCases(varargin)
    passCases = [varargin{:}];
end



%% DEBUGGING EXAMPLES IN CONSOLE
%{
tx = 0.3; rx = 1.0;
S = T(abs(T.TxDiam_m-tx)<1e-9 & abs(T.RxDiam_m-rx)<1e-9, ["WavelengthNm","MeanQBER"]);
S = sortrows(S, "WavelengthNm");
disp(S);
%}