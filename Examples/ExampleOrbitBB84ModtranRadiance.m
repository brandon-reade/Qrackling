% Author: Brandon Reade
% Date: 19/01/2026
% Simulation of a standard BB84 pass at 2050nm. Uses MODTRAN 500nm-3um data
% and includes spectral radiance from lunar scattering and thermal emission
% for a direct north to south satellite overpass. Moon positioned at zenith
% 90 and azimuth 0 with respect to the Ground station.


%% Configure MODTRAN Data
repo_root = utilities.addUserPath('~\Documents\GitHub\Qrackling');          % returns e.g. 'C:\Users\you' , change '~\Documents\GitHub\Qrackling' to wherever Qrackling is installed
modtran_dir = fullfile(repo_root, 'Examples', 'Data', ...                   % finding MODTRAN data              
    'atmospheric transmittance', 'raw modtran data',...
    'HOGS_WinterClear_Lunar_angles', 'HOGS_WinterClear-10kVis',...
    'sun_jan3rd_2026_1pm_800to3000nm_full');
if ~isfolder(modtran_dir)
    error('MODTRAN folder not found: %s', modtran_dir);
end

addpath(fullfile(repo_root));                                                % adds the folder containing +environment

%% 1. Choose parameters
Transmitter_Telescope_Diameter=0.1;                                        % diameters are measured in m
OrbitDataFileLocation='100kmSSOrbitLLAT.txt';                           % orbits are described by files containing latitude, longitude, altitude and time stamps. These are in the 'orbit modelling resources' folder
Receiver_Telescope_Diameter=1;                                           
Time_Gate_Width=2E-9;                                                      % times are measured in s
Spectral_Filter_Width=10;                                                  % consistent with wavelength, spectral width is measured in nm

% Choosing which wavelengths and detector presets to use
QKDsystems = struct( ...
    'Wavelength', {850, 2000, 2050, 2140, 2990}, ...                        % we expect more geometric loss as approaching 3000nm as divergence increases with wavelength
    'DetectorPreset', {'PerkinElmer','SNSPD_NbTiN_2um', 'SNSPD_NbTiN_2um', ...
                       'SNSPD_NbTiN_2um', 'SNSPD_NbTiN_2um'} ...
);

% Preallocate results and objects
nQKDSystems = numel(QKDsystems);
Sat = cell(1, nQKDSystems);
Det = cell(1, nQKDSystems);
GS  = cell(1, nQKDSystems);
Results = cell(1, nQKDSystems);

%% Load or Create MODTRAN Environment
% check if Dark Environment is already prebuilt
envFiles = dir(fullfile(modtran_dir, 'Radiant Environment*.mat'));
if ~isempty(envFiles)
    fprintf("Found environment...\n");
    try
        Env = environment.Environment.Load(fullfile(envFiles(1).folder, envFiles(1).name));
    catch ME
        warning('Failed to load Radiant Environment from %s: %s', fullfile(envFiles(1).folder, envFiles(1).name), ME.message);
    end
else
    % attempt to built environment
    fprintf("Building environment...\n");
    try
        envPath = createMODTRANEnv(char(modtran_dir));                      % can place an atmosphere tag in here for the visibility 
        if exist(envPath, 'file')
            Env = environment.Environment.Load(envPath);
        end
    catch ME
        warning('Failed to generate environment from CSVs in %s: %s', modtran_dir, ME.message);
    end
end

%% Create different QKD objects and Run Simulation
for i = 1:nQKDSystems
    % Create satellite
    Sat{i} = createSatellite(QKDsystems(i).Wavelength, OrbitDataFileLocation,...
        1E8, 0.1, Transmitter_Telescope_Diameter);
    
    % Create detector
    Det{i} = createPresetDetector(QKDsystems(i).Wavelength, 1E8,...
        Time_Gate_Width, Spectral_Filter_Width, QKDsystems(i).DetectorPreset);
    
    % Create ground station
    GS{i} = createGroundStation(Det{i}, Receiver_Telescope_Diameter,...
        QKDsystems(i).Wavelength, Env, [55.909723,-3.319995,10], 'Heriot-Watt');
    
    % Run simulation
    Results{i} = nodes.QkdPassSimulation(GS{i}, Sat{i}, protocol.bb84);
    
    % Plot + rename the figure that the library creates
    wl = QKDsystems(i).Wavelength;
    fig = Results{i}.plot();                                                % capture returned figure handle
    fig.Name = sprintf('BB84 Pass - %dnm', wl);
    fig.NumberTitle = 'off';
    fig.Tag = sprintf('BB84_%dnm', wl);  
end


%% Functions to build QKD Systems
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
function SimGS = createGroundStation(Detector, RxDiameter, Wavelength, Env, LLA, Name)
    RxTelescope = components.Telescope(RxDiameter, 'FOV', 10E-6,...         % receiver telescope
        'Wavelength', Wavelength);
    SimGS = nodes.Ground_Station(RxTelescope, 'Detector', Detector,...      % ground station
        'LLA', LLA, 'Name', Name);
    SimGS.Environment = Env;                                                % environment
end

