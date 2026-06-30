% Author: Brandon Reade
% Date: 11/03/2026
% Comparison of a standard BB84 2000nm pass: day vs night


%% Configure MODTRAN Data
repo_root = utilities.addUserPath('~\Documents\GitHub\Qrackling');          % returns e.g. 'C:\Users\you' , change '~\Documents\GitHub\Qrackling' to wherever Qrackling is installed

% Day-time data directory
daytime_dir = fullfile(repo_root, 'Examples', 'Data', ...                              
    'atmospheric transmittance', 'raw modtran data',...
    'HOGS_WinterClear_Lunar_angles', 'HOGS_WinterClear-10kVis',...
    'sun_jan3rd_2026_1pm_800to3000nm_full');                                % note the extraterrestrial source, date, and time - this is relevant for the radiance modelling

% Night-time data directory
night_dir = fullfile(repo_root, 'Examples', 'Data', ...                              
    'atmospheric transmittance', 'raw modtran data',...
    'HOGS_WinterClear_Lunar_angles', 'HOGS_WinterClear-10kVis',...
    'moon_jan3rd_2026_800to3000_1am_full');

if ~isfolder(daytime_dir) || ~isfolder(night_dir)
    error('One of the MODTRAN directories have not been found');
end

addpath(fullfile(repo_root));                                                % adds the folder containing +environment


%% 1. Choose parameters
Transmitter_Telescope_Diameter=0.1;                                        % diameters are measured in m
OrbitDataFileLocation='100kmSSOrbitLLAT.txt';                              % orbits are described by files containing latitude, longitude, altitude and time stamps. These are in the 'orbit modelling resources' folder
Receiver_Telescope_Diameter=1;                                           
Time_Gate_Width=2E-9;                                                      % times are measured in s
Spectral_Filter_Width=10;                                                  % consistent with wavelength, spectral width is measured in nm
RC700_FOV = 4.756E-3;
RC700_Jitter = 10E-6;

% Choosing which wavelengths and detector presets to use
QKDsystems = struct( ...
    'Wavelength', {2000, 2000}, ...
    'DetectorPreset', {'SNSPD_NbTiN_2um', 'SNSPD_NbTiN_2um'}, ...
    'EnvDir', {daytime_dir, night_dir}...
);

% Preallocate results and objects
nQKDSystems = numel(QKDsystems);
Sat     = cell(1, nQKDSystems);
Det     = cell(1, nQKDSystems);
GS      = cell(1, nQKDSystems);
Results = cell(1, nQKDSystems);
Envs    = cell(1, nQKDSystems);


%% Create different QKD objects 
for i = 1:nQKDSystems
    % Create Environments
    Env = buildEnvironment(QKDsystems(i).EnvDir);
    Envs{i} = Env;

    % Create satellite
    Sat{i} = createSatellite(QKDsystems(i).Wavelength, OrbitDataFileLocation,...
        1E8, 0.1, Transmitter_Telescope_Diameter);
    
    % Create detector
    Det{i} = createPresetDetector(QKDsystems(i).Wavelength, 1E8,...
        Time_Gate_Width, Spectral_Filter_Width, QKDsystems(i).DetectorPreset);
    
    % Create ground station
    GS{i} = createGroundStation(Det{i}, Receiver_Telescope_Diameter,...
        QKDsystems(i).Wavelength, RC700_FOV, RC700_Jitter, ...
        Env, [55.909723,-3.319995,10], 'Heriot-Watt');
    
    % Run simulation
    Results{i} = nodes.QkdPassSimulation(GS{i}, Sat{i}, protocol.bb84);

    fprintf("FOV=%g: sifted max=%g, secret max=%g, qber median=%g\n", ...
    GS{1}.Telescope.FOV, max(Results{1}.sifted_key_rate), max(Results{1}.secret_key_rate), median(Results{1}.qber(Results{1}.elevation_mask)));

        % Plot + rename the figure that the library creates
    wl = QKDsystems(i).Wavelength;
    fig = Results{i}.plot();                                                % capture returned figure handle
    fig.Name = sprintf('BB84 Pass - %dnm', wl);
    fig.NumberTitle = 'off';
    fig.Tag = sprintf('BB84_%dnm', wl);  
end

%% Plot results for QKD systems
labels = ["Day","Night"];
colours = [ ...
    0.8500 0.3250 0.0980;  % Day
    0.0000 0.4470 0.7410   % Night
];

plots.compare.QKDComparison(Results, ...
    'Labels', labels, ...
    'Colors', colours, ...
    'MaskMode', "elevation", ...
    'FigureName', "BB84 QKD - Day vs Night");

%% Plot Background Counts Comparison
plots.compare.BackgroundCountsComparison(Results, ...
    'Labels', labels, ...
    'MaskMode', "elevation", ...
    'FigureName', "Background Counts - Day vs Night");

%% Plot Radiance and Transmission graphs at Zen0 Azi 0
zen = 0;
azi = 0;

cases(1) = struct('dir', night_dir, 'zen_deg', zen, 'azi_deg', azi, 'label', '1am (Lunar)');
cases(2) = struct('dir', daytime_dir, 'zen_deg', zen, 'azi_deg', azi, 'label', '1pm (Solar)');

opts.useTwoPanels = true;
opts.titlePrefix = sprintf('Solar/Lunar comparison (zen=%d, azi=%d): ', zen, azi);

% plot the graphs
plots.TransmittanceRadiance(cases, opts);

% Get the current figure and set its name
fig = gcf; 
set(fig, 'Name', 'MODTRAN Data - Day vs Night', 'NumberTitle', 'off');

%% Plot Radiance + Transmittance vs Zenith (10 deg steps) at fixed azimuth
Env_day   = Envs{1};
Env_night = Envs{2};

plots.compare.RadTranVsZenith({Env_day, Env_night}, ...
    'Labels', labels, ...
    'Colors', colours, ...
    'ShowMarkers', true, ...
    'AzimuthDeg', 0, ...
    'ZenithDeg', 0:10:90, ...
    'Wavelength', 2000);

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
    RxTelescope = components.Telescope(RxDiameter,...
        'FOV', FOV,...                                               
        'Pointing_Jitter', Jitter, ...
        'Wavelength', Wavelength);

    SimGS = nodes.Ground_Station(RxTelescope, 'Detector', Detector,...      % ground station
        'LLA', LLA, 'Name', Name);
    SimGS.Environment = Env;                                                % environment
end
