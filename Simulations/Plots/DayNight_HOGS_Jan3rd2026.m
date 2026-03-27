% Author: Brandon Reade
% Date: 27/03/2026
% Comparison of a standard BB84 pass day vs night


%% Configure MODTRAN Data
repo_root = utilities.addUserPath('~\Documents\GitHub\Qrackling');

% Day-time data directory
daytime_dir = fullfile(repo_root, 'Examples', 'Data', ...                              
    'atmospheric transmittance', 'raw modtran data',...
    'HOGS_WinterClear_Lunar_angles', 'HOGS_WinterClear-10kVis',...
    'sun_jan3rd_2026_1pm_800to3000nm_full'); 

% Night-time data directory
night_dir = fullfile(repo_root, 'Examples', 'Data', ...                              
    'atmospheric transmittance', 'raw modtran data',...
    'HOGS_WinterClear_Lunar_angles', 'HOGS_WinterClear-10kVis',...
    'moon_jan3rd_2026_800to3000_1am_full'); 

if ~isfolder(daytime_dir) || ~isfolder(night_dir)
    error('One of the MODTRAN directories have not been found');
end
addpath(fullfile(repo_root));                                              

%% 1. Choose parameters
QKDsystems = struct( ...
    'Wavelength', {850, 1550, 2140} ...
    );
Env = struct(...
    'EnvDir', {daytime_dir, night_dir}, ...
    'label', {'day', 'night'}...
    );

azi = 120;

%% Plot Radiance and Transmittance vs Zenith (10 deg steps) at fixed azimuth
% Build Environment objects from your day/night directories
Env_day   = buildEnvironment(daytime_dir);
Env_night = buildEnvironment(night_dir);

Envs = {Env_day, Env_night};                                                % actual Environment objects
envLabels = ["Day","Night"];
colours = lines(numel(Env));

for i = 1:numel(QKDsystems)
    plots.compare.RadTranVsZenith(Envs, ...
        'Labels', envLabels, ...
        'Colors', colours, ...
        'ShowMarkers', true, ...
        'AzimuthDeg', azi, ...
        'ZenithDeg', 0:10:90, ...
        'Wavelength', QKDsystems(i).Wavelength, ... 
        'TwoPanel', true);
end
%% Plot Radiance and Transmission Profiles
zen_angles = 0:30:90; 

% Create a case for each combination of Day/Night and Zenith
clear cases;
count = 1;

for j = 1:length(Env)
    for z = 1:length(zen_angles)
        cases(count).dir     = Env(j).EnvDir;
        cases(count).zen_deg = zen_angles(z);
        cases(count).azi_deg = azi;
        cases(count).label   = sprintf('%d° Zen - %s', zen_angles(z), Env(j).label);
        count = count + 1;
    end
    % Set options and plot
    opts.useTwoPanels = true;
    opts.titlePrefix = sprintf('Atmospheric Profile (azi=%d): ', azi);
    plots.TransmittanceRadiance(cases, opts);
end


%% Functions
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