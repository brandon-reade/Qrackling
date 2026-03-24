% Author: Brandon Reade
% Date: 06/01/2026
% Simulation of a standard BB84 pass at 2050nm. Uses MODTRAN 2um-5um data.
% Note that this is currently as DARK ENVIRONMENT
%% Configure MODTRAN Data
repo_root = utilities.addUserPath('~\Documents\GitHub\Qrackling');          % returns e.g. 'C:\Users\you' , change '~\Documents\GitHub\Qrackling' to wherever Qrackling is installed
modtran_dir = fullfile(repo_root, 'Examples', 'Data', ...                   % finding MODTRAN data              
    'atmospheric transmittance', 'raw modtran data',...
    'SubArcticWinterUrbanClear', 'SubArcticWinterUrbanClear10km');
if ~isfolder(modtran_dir)
    error('MODTRAN folder not found: %s', modtran_dir);
end


% above replaces: modtran_dir = 'C:\Users\bsr4001\Documents\GitHub\Qrackling\Examples\Data\atmospheric transmittance\raw modtran data\SubArcticWinterUrbanClear\SubArcticWinterUrbanClear10km';

%% 1. Choose parameters
Wavelength=2050;                                                           % wavelength is measured in nm
Transmitter_Telescope_Diameter=0.1;                                        % diameters are measured in m
OrbitDataFileLocation='100kmSSOrbitLLAT.txt';                              % orbits are described by files containing latitude, longitude, altitude and time stamps. These are in the 'orbit modelling resources' folder
Receiver_Telescope_Diameter=1;                                           
Time_Gate_Width=2E-9;                                                      % times are measured in s
Spectral_Filter_Width=10;                                                  % consistent with wavelength, spectral width is measured in nm
%% 2. Construct components
%2.1 Satellite
%2.1.1 Source
Transmitter_Source=components.Source(Wavelength,...
                                    'Repetition_Rate',1E8,...
                                    'MPN_Signal',0.1);                     % we use default values to simplify this example

%2.1.2 Transmitter telescope
Transmitter_Telescope=components.Telescope(Transmitter_Telescope_Diameter);% do not need to specify wavelength as this will be set by satellite object

%2.1.3 Construct satellite
SimSatellite=nodes.Satellite(Transmitter_Telescope,'Source',Transmitter_Source,...
                        'OrbitDataFileLocation',OrbitDataFileLocation);

%2.2 Ground station
%2.2.1 Detector
Detector=components.Detector(Wavelength,...
                            Transmitter_Source.Repetition_Rate,...
                            Time_Gate_Width,...
                            Spectral_Filter_Width,...
                            'Preset','SNSPD_NbTiN_2um');
%need to provide repetition rate in order to compute QBER and loss due to
%time gating

%2.2.2 Receiver telescope
Receiver_Telescope=components.Telescope(Receiver_Telescope_Diameter, ...
                                        'FOV',10E-6,...
                                        'Wavelength',Wavelength);

%2.2.3 construct ground station, use Heriot-Watt as an example
SimGround_Station=nodes.Ground_Station(Receiver_Telescope,...
                                'Detector',Detector,...
                                'LLA',[55.909723, -3.319995,10],...
                                'Name','Heriot-Watt');

%% Load or Create MODTRAN Environment
% check if Dark Environment is already prebuilt
envFiles = dir(fullfile(modtran_dir, 'Dark Environment*.mat'));
if ~isempty(envFiles)
    fprintf("Found environment...\n");
    try
        Env = environment.Environment.Load(fullfile(envFiles(1).folder, envFiles(1).name));
    catch ME
        warning('Failed to load Dark Environment from %s: %s', fullfile(envFiles(1).folder, envFiles(1).name), ME.message);
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

SimGround_Station.Environment = Env;

%% 3 run and plot simulation
%3.1 run simulation
Result=nodes.QkdPassSimulation(SimGround_Station,SimSatellite,protocol.bb84);
%3.2 plot results
Result.plot()
%Plot(Env,'attenuation dB');
