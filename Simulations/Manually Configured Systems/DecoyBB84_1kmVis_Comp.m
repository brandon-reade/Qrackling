% Author: Brandon Reade
% Date: 11/03/2026
% Last update: 27/03/2026
% Comparison of a simulation of a Decoy BB84 pass at 1km visibility
% To do:
% - look at time gate width and change for each detector

%% Configure MODTRAN Data
repo_root = utilities.addUserPath('~\Documents\GitHub\Qrackling');         
modtran_dir = fullfile(repo_root, 'Examples', 'Data', ...                              
    'atmospheric transmittance', 'raw modtran data',...
    'HOGS_WinterClear_Lunar_angles', 'HOGS_Winter-1kVis',...
    'moon_jan3rd_2026_1am_800to3000nm_full');   % sun_jan3rd_2026_1pm_800to3000nm_full
                                               % moon_jan3rd_2026_1am_800to3000nm_full 
                                                

if ~isfolder(modtran_dir)
    error('MODTRAN folder not found: %s', modtran_dir);
end
addpath(fullfile(repo_root));                                               

%% 1. Choose parameters
% as per: https://digital-library.theiet.org/doi/10.1049/icp.2025.2223
plot_each_pass = true;
Transmitter_Telescope_Diameter=0.1;                                        % diameters in m
OrbitDataFileLocation='500kmSSOrbitLLAT.txt';                              
Receiver_Telescope_Diameter = 0.7;
Receiver_Jitter             = 10E-6;
Rep_Rate                    = 2E9;
Time_Gate_Width             = 100E-12;                                      % times in s (@1GHz: 200ps best for 1550, ~35 best for 2140)
Spectral_Filter_Width       = 10;                                          % spectral width in nm

% decoy state parameters
% as per: https://opg.optica.org/oe/fulltext.cfm?uri=oe-32-15-26776
MPNs = [0.8,0.3,0];                                                         % mean photon numbers: signal, decoy, vacuum
SPs = [0.7,0.2,0.1];                                                        % state probabilities
state_prep_error = 0.0025;

% Choosing which wavelengths and detector presets to use
QKDsystems = struct( ...
    'Wavelength', {850, 1550, 2140}, ...
    'DetectorPreset', { 'PerkinElmer', ...
                        'QuantumOpus1550_RoomTempAmplifier', ...
                        'SNSPD_NbTiN_2um'}, ... %mod_SNSPD_NbTiN_2um
    'rxFOV', {37E-6, 37E-6, 37E-6}...                                       % diffraction-limited "FOV" (acceptance angle)
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
        Rep_Rate, Transmitter_Telescope_Diameter, MPNs, SPs, state_prep_error);
    
    % Create detector
    Det{i} = createPresetDetector(QKDsystems(i).Wavelength, 1E8,...
        Time_Gate_Width, Spectral_Filter_Width, QKDsystems(i).DetectorPreset);
    
    % Create ground station
    GS{i} = createGroundStation(Det{i}, Receiver_Telescope_Diameter,...
        QKDsystems(i).Wavelength, QKDsystems(i).rxFOV, Receiver_Jitter, ...
        Env, [55.909723,-3.319995,10], 'Heriot-Watt');

    tel = GS{i}.Telescope;
    fprintf("(%dnm) Diff-limited FOV = %.3g urad, Receiver jitter = %.3g urad\n", ...
        QKDsystems(i).Wavelength, tel.FOV*1e6, tel.Pointing_Jitter*1e6);
    
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
end


%% Plot results for multiple QKD systems
plots.compare.QKDComparison(Results, ...
    'Wavelengths', [QKDsystems.Wavelength], ...
    'MaskMode', "active", ...                 
    'FigureName', "Decoy-state BB84 QKD Comparison (Vis 1km)");

plots.compare.LossComparison(Results, ...
    'Wavelengths', [QKDsystems.Wavelength], ...
    'MaskMode', "active", ...
    'FigureName', "Loss Components Comparison (Vis 1km)");

plots.compare.BackgroundCountsComparison(Results, ...
    'Wavelengths', [QKDsystems.Wavelength], ...
    'MaskMode', "active", ...
    'FigureName', "Background Counts Comparison (Vis 1km)");

%% Plot Radiance and Transmittance vs Zenith (10 deg steps) at fixed azimuth
labels  = arrayfun(@(x) sprintf('%dnm', x), [QKDsystems.Wavelength], 'UniformOutput', false);
colours = lines(numel(QKDsystems));

plots.compare.RadTranVsZenith(Env, ...
    'Labels', labels, 'Colors', colours, 'ShowMarkers', true, ...
    'AzimuthDeg', 180, 'ZenithDeg', 0:10:90, ...
    'Wavelength', [QKDsystems.Wavelength], ...
    'TwoPanel', false, 'UseYYAxis', true);

%% Plot Radiance and Transmission Profiles
zen_angles = 0:30:90; 
azi = 180;

clear cases;

% create a unique case for each zenith
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

%% Plot Environment spectral radiance
%Plot(Env,"spectral radiance");

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

end

% Satellite
function SimSat = createSatellite(Wavelength, OrbitDataFileLocation, RepetitionRate, TxDia, MPNs, SPs, state_prep_error)
    Src = components.Source(Wavelength, ...                                 % tx source
        'Repetition_Rate', RepetitionRate, ...
        'MPN_Signal',      MPNs(1), ...
        'MPN_Decoy',       MPNs(2), ...
        'Probability_Signal', SPs(1), ...
        'Probability_Decoy',  SPs(2), ...
        'State_Prep_Error', state_prep_error);     
    TxTelescope = components.Telescope(TxDia);                              % transmitter telescope
    SimSat = nodes.Satellite(TxTelescope, 'Source', Src,...                 % satellite
        'OrbitDataFileLocation', OrbitDataFileLocation);
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




