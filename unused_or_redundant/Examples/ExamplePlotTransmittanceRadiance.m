% Author: Brandon Reade
% Date: 26/01/2026
% Plots radiance and transmittance vs wavelength for specified
% MODTRAN scan file (e.g. specific zenith/azimuth output file).
% - The file contains columns for wavelength, radiance, transmittance
% - Wavelength is in nm, radiance converted to W m-2 sr-1 nm -1, transmittance is [0..1]

clear; clc;

%% User inputs
repo_root = utilities.addUserPath('~\Documents\GitHub\Qrackling');
modtran_dir = fullfile(repo_root, 'Examples', 'Data', ...
    'atmospheric transmittance', 'raw modtran data', ...
    'HOGS_WinterClear_Lunar_angles', 'HOGS_WinterClear-10kVis', ...
    'sun_jan3rd_2026_1pm_100to10000nm');
if ~isfolder(modtran_dir)
    error('MODTRAN folder not found: %s', modtran_dir);
end

if ~isfolder(modtran_dir)
    error('MODTRAN folder not found: %s', modtran_dir);
end

% set figure name
figure_name = "Solar radiance and thermal tmission, HOGS 03/01/2026 1pm, Zen: 0 Azi: 0";

% Choose which zen/azi file to plot
zen_deg = 0;
azi_deg = 0;

% Plot options
useTwoPanels = false;                                                        % true: 2 stacked plots, false: dual-y plot
print_parsing_info = true;                                                 % print meta data from readModtranFile.m

%% Check if file exists
% Check for transmission files
csvFiles = dir(fullfile(modtran_dir, '*Transm*.csv'));
if isempty(csvFiles)
    csvFiles = dir(fullfile(modtran_dir, '*.csv'));
end
if isempty(csvFiles)
    error('No MODTRAN CSVs found in %s', modtran_dir);
end

% Check for specific zen/azi file
modtran_file = "";
for k = 1:numel(csvFiles)
    name = csvFiles(k).name;

    tokZen = regexp(name, 'zen[_-]?(\d+)', 'tokens', 'once', 'ignorecase');
    if isempty(tokZen)
        tokZen = regexp(name, 'zen(\d+)', 'tokens', 'once', 'ignorecase');
    end
    if isempty(tokZen), continue; end
    zen = str2double(tokZen{1});

    tokAzi = regexp(name, 'azi[_-]?(\d+)', 'tokens', 'once', 'ignorecase');
    if isempty(tokAzi)
        azi = NaN; % legacy
    else
        azi = str2double(tokAzi{1});
    end

    % Match requested
    if zen == zen_deg && ( (isnan(azi) && isnan(azi_deg)) || (~isnan(azi) && azi == azi_deg) )
        modtran_file = fullfile(csvFiles(k).folder, csvFiles(k).name);
        break;
    end
end

fprintf('Plotting MODTRAN file: %s\n', modtran_file);

%% Read MODTRAN file
[wav, tr, rad, meta] = utilities.readModtranFile(modtran_file);

if isempty(wav) || isempty(tr)
    error("No numeric data parsed from file: %s", modtran_file);
end

% Ensure column vectors
wav = wav(:);
tr     = tr(:);
if ~isempty(rad), rad = rad(:) / 100; end                                   % unit conversion to W m-2 sr-1 nm -1 from uW cm-2 sr-1 nm-1 (which MODTRAN outputs)

% Remove NaN rows (keep rows where wavelength and transmittance exist; radiance optional)
mask = ~isnan(wav) & ~isnan(tr);
if ~isempty(rad)
    mask = mask & ~isnan(rad);
end

wav = wav(mask);
tr     = tr(mask);
if ~isempty(rad), rad = rad(mask); end

% Sort by wavelength (MODTRAN usually is sorted already, but be safe)
[wav, idx] = sort(wav);
tr = tr(idx);
if ~isempty(rad), rad = rad(idx); end

%% ---- Plot ----
fig = figure("Name", figure_name, "Color", "w");
if useTwoPanels
    tiledlayout(fig, 2,1, "Padding","compact", "TileSpacing","compact");

    % Radiance panel (if present)
    nexttile;
    if isempty(rad)
        text(0.5, 0.5, "Radiance not present in this file", ...
            "HorizontalAlignment","center");
        axis off;
        title("Radiance vs Wavelength (nm)");
    else
        plot(wav, rad, "LineWidth", 1.5);
        grid on;
        xlabel("Wavelength (nm)");
        ylabel("Radiance");
        title("Radiance vs Wavelength (nm)");
    end

    % Transmittance panel
    nexttile;
    plot(wav, tr, "LineWidth", 1.5);
    grid on;
    xlabel("Wavelength (nm)");
    ylabel("Transmittance");
    title("Transmittance vs Wavelength (nm)");

else
    % Dual-y axis version;
    if isempty(rad)
        plot(wav, tr, "LineWidth", 1.5);
        grid on;
        xlabel("Wavelength (nm)");
        ylabel("Transmittance");
        title("Transmittance vs Wavelength (nm) (radiance not present)");
        if forceTransmittance01
            mn = min(tr, [], "omitnan");
            mx = max(tr, [], "omitnan");
            if mn >= 0 && mx <= 1.05
                ylim([0 1]);
            end
        end
    else
        yyaxis left
        plot(wav, rad, "LineWidth", 1.5);
        ylabel("Radiance");

        yyaxis right
        plot(wav, tr, "LineWidth", 1.5);
        ylabel("Transmittance");

        grid on;
        xlabel("Wavelength (nm)");
        title("Radiance and Transmittance vs Wavelength (nm)");
    end
end

%% Optional: print parsing info 
if (print_parsing_info)
    fprintf("File: %s\n", modtran_dir);
    if isfield(meta, "chosen_column")
        fprintf("Transmittance column chosen: %d\n", meta.chosen_column);
    end
    if isfield(meta, "rad_column") && ~isempty(meta.rad_column)
        fprintf("Radiance column chosen: %d\n", meta.rad_column);
    end
    if isfield(meta, "has_rad")
        fprintf("Has radiance: %d\n", meta.has_rad);
    end
    if isfield(meta, "is_dark")
        fprintf("Is dark: %d\n", meta.is_dark);
    end
end