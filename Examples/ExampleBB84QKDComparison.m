% Author: Brandon Reade
% Date: 12/01/2026
% Comparison from a simulation of a standard BB84 pass towards MWIR wavelengths


%% Configure MODTRAN Data
repo_root = utilities.addUserPath('~\Documents\GitHub\Qrackling');          % returns e.g. 'C:\Users\you' , change '~\Documents\GitHub\Qrackling' to wherever Qrackling is installed
modtran_dir = fullfile(repo_root, 'Examples', 'Data', ...                   % finding MODTRAN data              
    'atmospheric transmittance', 'raw modtran data',...
    'HOGS_WinterClear_Lunar_angles', 'HOGS_WinterClear-10kVis',...
    'moon_jan3rd_2026_800to3000_1am_full');                                 % note the extraterrestrial source, date, and time - this is relevant for the radiance modelling
if ~isfolder(modtran_dir)
    error('MODTRAN folder not found: %s', modtran_dir);
end

addpath(fullfile(repo_root));                                                % adds the folder containing +environment

%% 1. Choose parameters
Transmitter_Telescope_Diameter=0.1;                                        % diameters are measured in m
OrbitDataFileLocation='100kmSSOrbitLLAT.txt';                              % orbits are described by files containing latitude, longitude, altitude and time stamps. These are in the 'orbit modelling resources' folder
Receiver_Telescope_Diameter=1;
Receiver_Telescope_FOV = 10e-6;
Time_Gate_Width=2E-9;                                                      % times are measured in s
Spectral_Filter_Width=10;                                                  % consistent with wavelength, spectral width is measured in nm

% Choosing which wavelengths and detector presets to use
QKDsystems = struct( ...
    'Wavelength', {2000, 2050, 2140, 2990}, ...
    'DetectorPreset', {'SNSPD_NbTiN_2um', 'SNSPD_NbTiN_2um',...
                        'SNSPD_NbTiN_2um', 'SNSPD_NbTiN_2um'...
                        } ...
);

% Preallocate results and objects
nQKDSystems = numel(QKDsystems);
Sat = cell(1, nQKDSystems);
Det = cell(1, nQKDSystems);
GS  = cell(1, nQKDSystems);
Results = cell(1, nQKDSystems);


%% Create the Environment
    % Environment
    envFiles = dir(fullfile(modtran_dir, 'Dark Environment*.mat'));
    % check if Dark Environment already built
    if ~isempty(envFiles)
        fprintf("Found environment...\n");
        try
            Env = environment.Environment.Load(fullfile(envFiles(1).folder, envFiles(1).name));
        catch ME
            warning('Failed to load Dark Environment from %s: %s', fullfile(envFiles(1).folder, envFiles(1).name), ME.message);
        end
    else
        % otherwise attempt to built environment
        fprintf("Building environment...\n");
        try
            envPath = createMODTRANEnv(char(modtran_dir));          % can place an atmosphere tag in here for the visibility 
            if exist(envPath, 'file')
                Env = environment.Environment.Load(envPath);
            end
        catch ME
            warning('Failed to generate environment from CSVs in %s: %s', modtran_dir, ME.message);
        end
    end

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
        QKDsystems(i).Wavelength, Receiver_Telescope_FOV, ...
        Env, [55.909723,-3.319995,10], 'Heriot-Watt');
    
    % Run simulation
    Results{i} = nodes.QkdPassSimulation(GS{i}, Sat{i}, protocol.bb84);
end


%% Plot results for multiple QKD systems
plots.compare.QKDComparison(Results, ...
    'Wavelengths', [QKDsystems.Wavelength], ...
    'MaskMode', "active", ...                 
    'FigureName', "BB84 QKD Comparison (MWIR)");

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
function SimGS = createGroundStation(Detector, RxDiameter, Wavelength, FOV, Env, LLA, Name)
    RxTelescope = components.Telescope(RxDiameter, 'FOV', FOV,...          % receiver telescope
        'Wavelength', Wavelength);
    SimGS = nodes.Ground_Station(RxTelescope, 'Detector', Detector,...      % ground station
        'LLA', LLA, 'Name', Name);
    SimGS.Environment = Env;                                                % environment
end




