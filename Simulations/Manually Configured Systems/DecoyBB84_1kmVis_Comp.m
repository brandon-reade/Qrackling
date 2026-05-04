% Author: Brandon Reade
% Date: 11/03/2026
% Last update: 19/04/2026
% Comparison of a simulation of a Decoy BB84 pass at 1km visibility

%% Configure MODTRAN Data
repo_root = utilities.addUserPath('~\Documents\GitHub\Qrackling');         

% 1k vis
modtran_dir1 = fullfile(repo_root, 'Examples', 'Data', ...                              
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
                                                
modtran_dir = fullfile(repo_root,...
    '+modtran\Data\HOGS\HOGS_sun_Jun21_4am_5kmvis_300to10000_zenstep10_azistep30');  % dawn 4am summer

if ~isfolder(modtran_dir)
    error('MODTRAN folder not found: %s', modtran_dir);
end
addpath(fullfile(repo_root));                                               

%% 1. Choose parameters
% plotting options
plot_each_pass              = true;
plot_compare                = true;
plot_loss_comparison        = true;
plot_link_loss_comparison   = false;
plot_background_counts      = true;
plot_orbit_summary          = true;
plot_detectors              = false;
plot_trans_rad              = true;
plot_2D_spectral_map        = true;
plot_3D_spectral_map        = false;
plot_spectral_comparison    = false;
LOS_at_time                 = false;

% system configuration
small_sat                   = true;                                        % false for cubesat settings
ideal_pass                  = true;                                         % satellite pass

% as per: https://digital-library.theiet.org/doi/10.1049/icp.2025.2223
if small_sat
    Transmitter_Telescope_Diameter=0.35;                                        % diameters in m
else
    Transmitter_Telescope_Diameter=0.1;
end
OrbitDataFileLocation='500kmSSOrbitLLAT.txt';                              
Receiver_Telescope_Diameter = 0.7;
Receiver_Jitter             = 1E-6;
Rep_Rate                    = 1E9;
%Time_Gate_Width             = 100E-12;                                      % times in s (@1GHz: ~200ps best for 1550, ~35 best for 2140)
Spectral_Filter_Width       = 0.5;                                          % spectral width in nm (0.1nm possible but difficult, 1nm possible, 10-12nm standard)

% decoy state parameters
% as per: https://opg.optica.org/oe/fulltext.cfm?uri=oe-32-15-26776
MPNs = [0.8,0.3,0];                                                         % mean photon numbers: signal, decoy, vacuum
SPs = [0.7,0.2,0.1];                                                        % state probabilities
state_prep_error = 0.0025;

% Choosing which wavelengths and detector presets to use
QKDsystems = struct( ...
    'Wavelength', {1550, 2210, 3700}, ...                                   % in nanmometers such as: 850, 1550, 2140, 2210, 3400
    'DetectorPreset', { 'QuantumOpus1550_RoomTempAmplifier', ...
                        'SNSPD_NbTiN_2um', ...
                        'mod_SNSPD_NbTiN_2um'}, ... %mod_SNSPD_NbTiN_2um
    'txDiam', {Transmitter_Telescope_Diameter, Transmitter_Telescope_Diameter, Transmitter_Telescope_Diameter},...     % transmitter telescope diameter (0.08m for SPOQC)
    'rxDiam', {0.7, 0.7, 0.7},...                                         % receiever telescope diameter (0.7m for HOGS)
    'rxFOV', {37E-6, 37E-6, 37E-6},...                                         % acceptance angle "FOV" (not diffraction limit or geometric FOV) - this is 37u for HOGS. We can use diffraction limit by setting this arbitrarily small
    'TimeGateWidth', {352E-12, 28.6E-12, 28.6E-12}...
                        );

% Preallocate results and objects
nQKDSystems = numel(QKDsystems);
Sat = cell(1, nQKDSystems);
Det = cell(1, nQKDSystems);
GS  = cell(1, nQKDSystems);
Results = cell(1, nQKDSystems);

%% Create the Environment
Env = buildEnvironment(modtran_dir);

%% Create different QKD objects 
for i = 1:nQKDSystems
    % Create satellite
    Sat{i} = createSatellite(QKDsystems(i).Wavelength, OrbitDataFileLocation,...
        Rep_Rate, QKDsystems(i).txDiam, MPNs, SPs, state_prep_error, ideal_pass);
    
    % Create detector
    Det{i} = createPresetDetector(QKDsystems(i).Wavelength, Rep_Rate,...
        QKDsystems(i).TimeGateWidth, Spectral_Filter_Width, QKDsystems(i).DetectorPreset);
    
    % Create ground station
    GS{i} = createGroundStation(Det{i}, QKDsystems(i).rxDiam,...
        QKDsystems(i).Wavelength, QKDsystems(i).rxFOV, Receiver_Jitter, ...
        Env, [55.909723,-3.319995,10], 'Heriot-Watt');

    tel = GS{i}.Telescope;
    fprintf("(%dnm) Acceptance FOV = %.3g urad, Receiver jitter = %.3g urad\n", ...         % diffraction-limited is automatically calculated
        QKDsystems(i).Wavelength, tel.FOV*1e6, tel.Pointing_Jitter*1e6);                    % otherwise when it is fixed it is an acceptance angle
    
    % Run simulation
    Results{i} = nodes.QkdPassSimulation(GS{i}, Sat{i}, protocol.decoyBB84);

    if plot_each_pass
        % Plot + rename the figure that the library creates
        wl = QKDsystems(i).Wavelength;
        fig = Results{i}.plot();                                                % capture returned figure handle
        fig.Name = sprintf('Decoy-state BB84 Pass - %dnm', wl);
        fig.NumberTitle = 'off';
        fig.Tag = sprintf('Decoy-state BB84_%dnm', wl); 
    end

    if plot_detectors
        Det{i}.Plot;
        fwhm = detectorJitterFWHM(Det{i});
        Trep = 1 / Det{i}.Repetition_Rate;
        fprintf("(%dnm) Detector jitter FWHM: %.2f ps\n", QKDsystems(i).Wavelength, fwhm*1e12);
        k = 2; % gate = 2×FWHM is a decent starting point
        gate = min(k * fwhm, 0.5 * Trep);

        fprintf("(%dnm) RepRate=%.2g Hz (T=%.2f ps), choose gate≈%.2f ps (k=%g)\n", ...
        QKDsystems(i).Wavelength, Det{i}.Repetition_Rate, Trep*1e12, gate*1e12, k);
    end

    if LOS_at_time
        printResultAtOffset(Results{i}, Env, QKDsystems(i).Wavelength, minutes(7)+seconds(30));
    end


    %% Plot Orbit Summary
    if plot_orbit_summary
        index=1;
        plots.plotOrbitSummary(Results{i}, Env, ...
            IncludeTimeSeries=false, ...
            PolarOverlay="sky_points", ...        
            PolarData="spectral_radiance", ...
            WavelengthNm=QKDsystems(i).Wavelength, ...
            SurfaceMetric="loss:atmospheric",...                                  % "skr", "loss:atmospheric"
            SurfacePlotType="scatter", ...
            Mask="Communication");
    end

end

%% Plot results for multiple QKD systems
if plot_compare
    plots.compare.QKDComparison(Results, ...
        'Wavelengths', [QKDsystems.Wavelength], ...
        'MaskMode', "active", ...                 
        'FigureName', "Decoy-state BB84 QKD Comparison (Vis 1km)");
end

if plot_loss_comparison
    plots.compare.LossComparison(Results, ...
        'Wavelengths', [QKDsystems.Wavelength], ...
        'MaskMode', "active", ...
        'FigureName', "Loss Components Comparison (Vis 1km)");
end

if plot_background_counts
    plots.compare.BackgroundCountsComparison(Results, ...
        'Wavelengths', [QKDsystems.Wavelength], ...
        'MaskMode', "active", ...
        'FigureName', "Background Counts Comparison (Vis 1km)");
end
%% Plot Radiance and Transmittance Profiles
% compare transmittance and radiance at different wavelengths and zeniths
% for a given azimuth
if plot_trans_rad
    labels  = arrayfun(@(x) sprintf('%dnm', x), [QKDsystems.Wavelength], 'UniformOutput', false);
    colours = lines(numel(QKDsystems));
    
    plots.compare.RadTranVsZenith(Env, ...
        'Labels', labels, 'Colors', colours, 'ShowMarkers', true, ...
        'AzimuthDeg', 180, 'ZenithDeg', 0:10:90, ...
        'Wavelength', [QKDsystems.Wavelength], ...
        'TwoPanel', false, 'UseYYAxis', true);
    
    % Plot Radiance and Transmission Profiles
    zen_angles = 0:30:60; 
    azi = 30;
    clear cases;
    for i = 1:length(zen_angles)
        cases(i).dir     = modtran_dir;
        cases(i).zen_deg = zen_angles(i);
        cases(i).azi_deg = azi;
        cases(i).label   = sprintf('%d° Zen', zen_angles(i));
    end
    % Set options and plot
    opts.useTwoPanels = true;
    opts.titlePrefix = sprintf('Atmospheric Profile (azi=%d): ', azi);
    plots.TransmittanceRadiance(cases, opts);
end

%% Plot Environment spectral radiance
if plot_2D_spectral_map
    plots.plotRadianceMap(Env, [QKDsystems(1).Wavelength, QKDsystems(2).Wavelength, QKDsystems(3).Wavelength], ...
    'View',"2D", ...
    'TwoDStyle',"tiles",...                                                 % "tiles" or "pcolour"
    'FigureMode', 'subplots',...
    'UseLogZ', false, ...
    'AzimuthDeg',(0:30:330)', ...
    'ZenithDeg',(0:10:90)', ...
    'Title',"MODTRAN spectral radiance maps");
end

if plot_3D_spectral_map
    plots.plotRadianceMap(Env, [QKDsystems(1).Wavelength, QKDsystems(2).Wavelength, QKDsystems(3).Wavelength], ...
    'View',"3D", ...
    'TwoDStyle',"tiles",...                                                 % "tiles" or "pcolour"
    'FigureMode', 'subplots',...
    'Mode', "bars",...
    'UseLogZ', false, ...
    'AzimuthDeg',(0:30:330)', ...
    'ZenithDeg',(0:10:90)', ...
    'Title',"MODTRAN spectral radiance maps");
end

if plot_spectral_comparison
    plots.plotRadianceMap(Env, [QKDsystems(2).Wavelength, QKDsystems(3).Wavelength], ...
    'View',"2D", ...
    'TwoDStyle',"tiles",...                                                 % "tiles" or "pcolour"
    'FigureMode', "subplots",...
    'CompareMode',"dB", ...                                              % "dB" or "ratio" or "diff"
    'ReferenceWavelength',1550, ...
    'AzimuthDeg',(0:30:330)', ...
    'ZenithDeg',(0:10:90)', ...
    'Title',"Radiance relative to 1550 nm");
end

%% Plot Link Loss Comparison

if plot_link_loss_comparison
    % Key rate vs loss (SKR right axis, QBER left)
    plots.compare.LinkLossComparison(Results, ...
        'Wavelengths', [QKDsystems.Wavelength], ...
        'Mode', "LossVsSKR", ...
        'Mask', "None", ...
        'PlotSifted', false, ...
        'PlotQBER', false, ...
        'SplitBranches', true);
    
    % PLOB vs loss in bits/s
    plots.compare.TheoreticalLimitComparison(Results, ...
        'Wavelengths', [QKDsystems.Wavelength], ...
        'RepRates', Rep_Rate, ...
        'X', "LossdB", ...
        'Mask', "Line of sight", ...
        'YUnit', "bits_per_second", ...
        'FigureName', "Achieved SKR vs PLOB (vs loss)");
end

%% Functions to build QKD Systems
% Environments
function Env = buildEnvironment(env_dir)
    envFile = dir(fullfile(env_dir, 'Radiant Environment*.mat'));
    % Check if an Environment has already been built
    if ~isempty(envFile)
        fprintf("Found environment...\n")
        try
            Env = environment.Environment.Load(fullfile(envFile(1).folder, envFile(1).name));
        catch ME
            warning('Failed to load Environment from %s: %s', fullfile(envFile(1).folder, envFile(1).name, ME.message));
        end
    else
        % build environment if one not found
        fprintf("Building environment...\n");
        try
            envPath = createMODTRANEnv(char(env_dir));
            if exist(envPath, 'file')
                Env = environment.Environment.Load(envPath);
            end
        catch ME
            warning('Failed to generate environment from CSVs in %s: %s', env_dir, ME.message);
        end
    end

    % optionally set a turbulence model
    Env.turbulence_model = environment.Turbulence_Model('Preset','HV10-10');   % or 'HV5-7': sea level, '2HV5-7': bad day at sea level,  'HV10-10': typical astronomical , 'HV15-12' excellent site
    
    %{
    Env.turbulence_model = environment.Turbulence_Model( ...
    'Preset','none', ...
    'Magnitudes',[17e-15, 27e-17, 3.59e-53], ...
    'Heights',   [100,   1500,   1000]);
    %}
end

% Satellite
function SimSat = createSatellite(Wavelength, OrbitDataFileLocation, RepetitionRate, TxDia, MPNs, SPs, state_prep_error, pass_type)
    Src = components.Source(Wavelength, ...                                 % tx source
        'Repetition_Rate', RepetitionRate, ...
        'MPN_Signal',      MPNs(1), ...
        'MPN_Decoy',       MPNs(2), ...
        'Probability_Signal', SPs(1), ...
        'Probability_Decoy',  SPs(2), ...
        'State_Prep_Error', state_prep_error);     
    TxTelescope = components.Telescope(TxDia);                              % transmitter telescope

    % using LLAT
    if pass_type
        SimSat = nodes.Satellite(TxTelescope, 'Source', Src,...                 % satellite
            'OrbitDataFileLocation', OrbitDataFileLocation);
    else
        % Using start/stop time
        StartTime = datetime(2025,12,25,6,40,0); %datetime(2026,1,31,4,0,0);
        StopTime = datetime(2025,12,25,7,20,0);   %datetime(2026,1,31,5,0,0);
        SimSat = nodes.Satellite(TxTelescope, 'Source', Src, ...
        'semiMajorAxis', 600e3 + earthRadius, ...
        'eccentricity', 0, ...
        'inclination', 97.065055549, ...
        'rightAscensionOfAscendingNode', -1.5, ...
        'argumentOfPeriapsis', 0, ...
        'trueAnomaly', 0, ...
        'StartTime', StartTime, ...
        'StopTime', StopTime, ...
        'sampleTime', seconds(1));
    end
end

% Detector
function Detector = createPresetDetector(Wavelength, RepetitionRate, TimeGateWidth, SpectralFilterWidth, Preset)
    Detector = components.Detector(Wavelength, RepetitionRate,...
        TimeGateWidth, SpectralFilterWidth, 'Preset', Preset);
end

% Ground Station
function SimGS = createGroundStation(Detector, RxDiameter, Wavelength, FOV, Jitter, Env, LLA, Name)
    RxTelescope = components.Telescope(RxDiameter, 'FOV', FOV,...          % receiver telescope
        'Pointing_Jitter', Jitter, ...
        'Wavelength', Wavelength);
    SimGS = nodes.Ground_Station(RxTelescope, 'Detector', Detector,...      % ground station
        'LLA', LLA, 'Name', Name);
    SimGS.Environment = Env;                                                % environment
end

%% Other helpers
function fwhm_s = detectorJitterFWHM(det)
    % Returns FWHM in seconds (NaN if unavailable)
    if ~isempty(det.PDF)
        y = det.PDF;
    elseif ~isempty(det.Jitter_Histogram)
        y = det.Jitter_Histogram;
    else
        fwhm_s = NaN;
        return;
    end

    [~, i0] = max(y);
    t = ((1:numel(y)) - i0) * det.Histogram_Bin_Width; % seconds
    y = y ./ max(y);

    mask = (y >= 0.5);
    if any(mask)
        fwhm_s = max(t(mask)) - min(t(mask));
    else
        fwhm_s = NaN;
    end
end

function printResultAtOffset(res, Env, wl_nm, offset, options)
% offset as duration or seconds from res.time(1)
    arguments
        res (1,1) nodes.PassSimulationResult
        Env
        wl_nm (1,1) double
        offset
        options.Reference (1,1) string {mustBeMember(options.Reference,["start","firstLOS"])} = "start"
    end

    t = res.time;
    if isempty(t) || all(ismissing(t))
        error("Result has no 'time' data.");
    end

    switch options.Reference
        case "start"
            t0 = t(1);
        case "firstLOS"
            vis = res.elevation > 0;
            i0 = find(vis, 1, "first");
            if isempty(i0), error("No LOS (el>0) points in result."); end
            t0 = t(i0);
    end

    if isa(offset, "duration")
        tq = t0 + offset;
    elseif isnumeric(offset)
        tq = t0 + seconds(offset);
    else
        error("offset must be duration or numeric seconds.");
    end

    % absolute-time query logic
    [~, idx] = min(abs(t - tq));

    az = res.heading(idx);
    el = res.elevation(idx);
    zen = 90 - el;

    rad = Env.Interp("spectral_radiance", az, el, wl_nm);

    bg = NaN; dk = NaN;
    for j = 1:numel(res.noise)
        if string(res.noise(j).label) == "Background Counts"
            bg = res.noise(j).values(idx);
        elseif string(res.noise(j).label) == "Detector Dark Counts"
            dk = res.noise(j).values(idx);
        end
    end

    tt = t(idx);
    tt.Format = 'dd-MMM-uuuu HH:mm:ss';
    fprintf("offset=%s | t=%s | az=%.2f | el=%.2f | rad=%.3g | bg=%.3g cps | dark=%.3g cps\n", ...
        string(t(idx) - t0), string(tt), az, el, rad, bg, dk);
end



