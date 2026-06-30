% Author: Brandon Reade
% Date: 11/03/2026
% Comparison of a simulation of a standard BB84 pass at 1km visibility

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
Transmitter_Telescope_Diameter=0.1;                                        % diameters in m
OrbitDataFileLocation='100kmSSOrbitLLAT.txt';                              
Receiver_Telescope_Diameter = 1;
Receiver_FOV                = 37E-6; %4.756E-3;                            % diffraction-limited "FOV" (acceptance angle)
Receiver_Jitter             = 10E-6;
Repe_Rate                   = 1E8;
Time_Gate_Width             = 2E-9;                                         % times in s
Spectral_Filter_Width       = 10;                                           % spectral width in nm

% Choosing which wavelengths and detector presets to use
QKDsystems = struct( ...
    'Wavelength', {850, 1550, 2050, 2140, 2310, 2990}, ...
    'DetectorPreset', {'PerkinElmer', 'QuantumOpus1550_RoomTempAmplifier', ...
                        'SNSPD_NbTiN_2um', 'SNSPD_NbTiN_2um', ...
                        'SNSPD_NbTiN_2um', 'SNSPD_NbTiN_2um'} ...
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
        1E8, 0.1, Transmitter_Telescope_Diameter);
    
    % Create detector
    Det{i} = createPresetDetector(QKDsystems(i).Wavelength, 1E8,...
        Time_Gate_Width, Spectral_Filter_Width, QKDsystems(i).DetectorPreset);
    
    % Create ground station
    GS{i} = createGroundStation(Det{i}, Receiver_Telescope_Diameter,...
        QKDsystems(i).Wavelength, Receiver_FOV, Receiver_Jitter, ...
        Env, [55.909723,-3.319995,10], 'Heriot-Watt');
    tel = GS{i}.Telescope;
    fprintf("(%dnm) Diff-limited FOV = %.3g urad, Receiver jitter = %.3g urad\n", ...
        QKDsystems(i).Wavelength, tel.FOV*1e6, tel.Pointing_Jitter*1e6);
    
    % Run simulation
    Results{i} = nodes.QkdPassSimulation(GS{i}, Sat{i}, protocol.bb84);
end


%% Plot results for multiple QKD systems
plots.compare.QKDComparison(Results, ...
    'Wavelengths', [QKDsystems.Wavelength], ...
    'MaskMode', "active", ...                 
    'FigureName', "BB84 QKD Comparison (Vis 1km)");

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
zen_angles = 0; %0:30:90; 
azi = 180;

clear cases;

% create a unique case for each zenith
for i = 1:length(zen_angles)
    cases(i).dir     = modtran_dir;
    cases(i).zen_deg = zen_angles(i);
    cases(i).azi_deg = azi;
    cases(i).label   = sprintf('%d° Zen (Lunar)', zen_angles(i));
end
% Set options and plot
opts.useTwoPanels = false;
opts.titlePrefix = sprintf('Atmospheric Profile (azi=%d): ', azi);
plots.TransmittanceRadiance(cases, opts);

%% Plot Environment attenuation
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
function SimSat = createSatellite(Wavelength, OrbitDataFileLocation, RepetitionRate, MPN, TxDia)
    Src = components.Source(Wavelength, 'Repetition_Rate',...               % source
        RepetitionRate, 'MPN_Signal', MPN);        
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




