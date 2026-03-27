% Author: Brandon Reade
% Date: 19/02/2026
% Comparison of a standard BB84 pass day vs night


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
Receiver_Telescope_Diameter=0.7;                                           
Time_Gate_Width=2E-9;                                                      % times are measured in s
Spectral_Filter_Width=10;                                                  % consistent with wavelength, spectral width is measured in nm

% Choosing which wavelengths and detector presets to use
QKDsystems = struct( ...
    'Wavelength', {850, 850}, ...
    'DetectorPreset', {'PerkinElmer', 'PerkinElmer'}, ...
    'EnvDir', {daytime_dir, night_dir}...
);

%{
QKDsystems = struct( ...
    'Wavelength', {2000, 2000}, ...
    'DetectorPreset', {'SNSPD_NbTiN_2um', 'SNSPD_NbTiN_2um'}, ...
    'EnvDir', {daytime_dir, night_dir}...
);
%}

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
        QKDsystems(i).Wavelength, Env, [55.909723,-3.319995,10], 'Heriot-Watt');
    
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

%% Plot results for multiple QKD systems
% Consistent color scheme
DAY_COLOR   = [0.8500 0.3250 0.0980];
NIGHT_COLOR = [0.0000 0.4470 0.7410]; 

getCaseColor = @(i) (DAY_COLOR   * contains(QKDsystems(i).EnvDir,'sun') + ...
                     NIGHT_COLOR * ~contains(QKDsystems(i).EnvDir,'sun'));

getCaseLabel = @(i) caseLabel(QKDsystems(i).EnvDir);

figure('Name','BB84 QKD Comparison','NumberTitle','off');
lineWidth = 1.5;

% Sifted Key Rate
ax1 = subplot(3,1,1); hold on; grid on;
for i = 1:nQKDSystems
    mask = Results{i}.elevation_mask;
    plot(Results{i}.time(mask), Results{i}.sifted_key_rate(mask), ...
        'Color', getCaseColor(i), 'LineWidth', lineWidth, ...
        'DisplayName', getCaseLabel(i));
end
ylabel('Sifted Key Rate (bits/s)','FontWeight','bold');
title('BB84 QKD Comparison','FontWeight','bold');
legend('Location','northwest');

% Secret Key Rate
ax2 = subplot(3,1,2); hold on; grid on;
for i = 1:nQKDSystems
    mask = Results{i}.elevation_mask;
    plot(Results{i}.time(mask), Results{i}.secret_key_rate(mask), ...
        'Color', getCaseColor(i), 'LineWidth', lineWidth, ...
        'DisplayName', getCaseLabel(i));
end
ylabel('Secret Key Rate (bits/s)','FontWeight','bold');
legend('Location','northwest');

% QBER
ax3 = subplot(3,1,3); hold on; grid on;
for i = 1:nQKDSystems
    mask = Results{i}.elevation_mask;
    plot(Results{i}.time(mask), Results{i}.qber(mask)*100, ...
        'Color', getCaseColor(i), 'LineWidth', lineWidth, ...
        'DisplayName', getCaseLabel(i));
end
ylabel('QBER (%)','FontWeight','bold');
xlabel('Time','FontWeight','bold');
legend('Location','northeast');

linkaxes([ax1, ax2, ax3],'x');

%% Plot Loss Comparison
figure('Name', 'Loss Components - Day vs Night Side-by-Side', 'NumberTitle', 'off');

% Get loss component names
loss_names = Results{1}.loss.Names;
n_loss_types = length(loss_names);

% Add total loss to the list
all_loss_types = ['TotalLoss', loss_names];
n_plots = length(all_loss_types);

% Create grid layout
n_rows = ceil(n_plots / 2);
tiledlayout(n_rows, 2, 'TileSpacing', 'compact');

for j = 1:n_plots
    nexttile;
    hold on; grid on;
    
    if j == 1
        % Total Loss
        plot_title = 'Total Loss';
        for i = 1:nQKDSystems
            mask = Results{i}.elevation_mask;
            x_axis = Results{i}.time;
            loss_data = Results{i}.loss.TotalLoss.dB;
            
            if contains(QKDsystems(i).EnvDir, 'sun')
                label_str = 'Day';
            else
                label_str = 'Night';
            end
            
            plot(x_axis(mask), loss_data(mask), ...
                'Color', getCaseColor(i), 'LineWidth', lineWidth, 'DisplayName', label_str);
        end
    else
        % Individual loss components
        loss_name = all_loss_types{j};
        plot_title = strrep(loss_name, '_', ' ');
        plot_title(1) = upper(plot_title(1));
        
        for i = 1:nQKDSystems
            mask = Results{i}.elevation_mask;
            x_axis = Results{i}.time;
            loss_data = Results{i}.loss.(loss_name).dB;
            
            if contains(QKDsystems(i).EnvDir, 'sun')
                label_str = 'Day';
            else
                label_str = 'Night';
            end
            
            plot(x_axis(mask), loss_data(mask), ...
                'Color', getCaseColor(i), 'LineWidth', lineWidth, 'DisplayName', label_str);
        end
    end
    
    ylabel('Loss (dB)', 'FontWeight', 'bold');
    title(plot_title, 'FontWeight', 'bold', 'FontSize', 11);
    legend('Location', 'best');
    grid on;
    
    xlim([min(Results{1}.time(Results{1}.elevation_mask)), ...
          max(Results{1}.time(Results{1}.elevation_mask))]);
    
    % Only add x-label to bottom row
    if j > n_plots - 2
        xlabel('Time', 'FontWeight', 'bold');
    end
    
    hold off;
end

sgtitle(sprintf('%dnm QKD - Detailed Loss Component Comparison', QKDsystems(1).Wavelength), ...
    'FontWeight', 'bold', 'FontSize', 14);

%% Plot Background Counts Comparison
figure('Name', 'Background Counts Comparison - Day vs Night', 'NumberTitle', 'off');

tiledlayout(1, 2);

for i = 1:nQKDSystems
    nexttile;
    
    mask = Results{i}.elevation_mask;
    x_axis = Results{i}.time;
    
    % Extract background count data
    n_sources = numel(Results{i}.noise);
    n_points = numel(Results{i}.noise(1).values);
    bcr_data = reshape([Results{i}.noise.values], [n_points, n_sources]);
    
    % Create area plot
    area(x_axis(mask), bcr_data(mask, :));
    
    % Labels
    xlabel('Time', 'FontWeight', 'bold');
    ylabel('BCR (counts/s)', 'FontWeight', 'bold');
    
    if contains(QKDsystems(i).EnvDir, 'sun')
        title('Day (1pm Solar)', 'FontWeight', 'bold');
    else
        title('Night (1am Lunar)', 'FontWeight', 'bold');
    end
    
    lgd = legend({Results{i}.noise.label}, 'Location', 'best');
    lgd.NumColumns = 1;
    grid on;
    xlim([min(x_axis(mask)), max(x_axis(mask))]);
end

sgtitle('Background Count Rate Comparison', 'FontWeight', 'bold', 'FontSize', 14);

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
azi_deg = 0;
zen_deg = 0:10:90;
el_deg  = 90 - zen_deg;
w0 = QKDsystems(1).Wavelength;

% Assume system 1 = day, system 2 = night
Env_day   = Envs{1};
Env_night = Envs{2};

rad_day   = Env_day.Interp("spectral_radiance", azi_deg*ones(size(el_deg)), el_deg, w0);
rad_night = Env_night.Interp("spectral_radiance", azi_deg*ones(size(el_deg)), el_deg, w0);

att_day   = Env_day.Interp("attenuation", azi_deg*ones(size(el_deg)), el_deg, w0);
att_night = Env_night.Interp("attenuation", azi_deg*ones(size(el_deg)), el_deg, w0);

figure('Name', sprintf('Env slice at azi=%d deg, %dnm', azi_deg, w0), 'NumberTitle', 'off');
tiledlayout(1,2,'TileSpacing','compact');

% Radiance panel
nexttile; hold on; grid on;
semilogy(zen_deg, rad_day,   'Color', DAY_COLOR,   'LineWidth',1.5,'DisplayName','Day');
semilogy(zen_deg, rad_night, 'Color', NIGHT_COLOR, 'LineWidth',1.5,'DisplayName','Night');
xlabel('Zenith (deg)','FontWeight','bold');
ylabel('Spectral radiance (W/m^2/sr/nm)','FontWeight','bold');
title('Radiance vs Zenith','FontWeight','bold');
legend('Location','best');

% Transmittance panel
nexttile; hold on; grid on;
plot(zen_deg, att_day,   'Color', DAY_COLOR,   'LineWidth',1.5,'DisplayName','Day');
plot(zen_deg, att_night, 'Color', NIGHT_COLOR, 'LineWidth',1.5,'DisplayName','Night');
xlabel('Zenith (deg)','FontWeight','bold');
ylabel('Transmittance (probability)','FontWeight','bold');
title('Transmittance vs Zenith','FontWeight','bold');
legend('Location','best');

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
function SimGS = createGroundStation(Detector, RxDiameter, Wavelength, Env, LLA, Name)
    RC700_FOV = 4.756E-3;
    RC700_Jitter = 10E-6;

    RxTelescope = components.Telescope(RxDiameter,...
        'FOV', RC700_FOV,...                                               
        'Pointing_Jitter', RC700_Jitter, ...
        'Wavelength', Wavelength);

    SimGS = nodes.Ground_Station(RxTelescope, 'Detector', Detector,...      % ground station
        'LLA', LLA, 'Name', Name);
    SimGS.Environment = Env;                                                % environment
end

% Helper for labels
function label = caseLabel(envDir)
    if contains(envDir,'sun')
        label = "Day";
    else
        label = "Night";
    end
end
