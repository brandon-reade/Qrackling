% Author: Brandon Reade
% Date: 26/01/2026
% Compare two different MODTRAN folders for the same zen/azi

clear; clc;

repo_root = utilities.addUserPath('~\Documents\GitHub\Qrackling');
modtran_dir = fullfile(repo_root, 'Examples', 'Data', ...
    'atmospheric transmittance', 'raw modtran data', ...
    'HOGS_WinterClouds_Lunar_angles', 'HOGS_WinterClouds-10kVis', ...
    'sun_jan3rd_2026_1pm','100 to 10000nm Zen0 Azi0'); 

% Get all items in the directory
items = dir(modtran_dir);

% set which zenith and azimuth to plot
zen = 0;
azi = 0;

% Filter to only get CSV files
csv_files = dir(fullfile(modtran_dir, '*.csv'));
file_names = {csv_files.name};

% Print available files
fprintf('Available files in %s:\n', modtran_dir);
for i = 1:length(file_names)
    fprintf('  %d: %s\n', i, file_names{i});
end

% Define cloud condition keywords and their labels
cloud_keywords = {
    'none',            'Clear (None)';
    'cirrus_thin',     'Cirrus (Thin)';
    'cirrus',          'Cirrus';
    'cumulus',         'Cumulus';
    'stratocumulus',   'Stratocumulus';
    'stratus',         'Stratus';
    'altostratus',     'Altostratus';
    'nimbostratus',    'Nimbostratus';
};

% Build cases structure by finding matching files
cases = struct('file', {}, 'zen_deg', {}, 'azi_deg', {}, 'label', {});
for i = 1:size(cloud_keywords, 1)
    keyword = cloud_keywords{i};
    label = cloud_keywords{i, 2};
    
    % Find files containing this keyword (case-insensitive)
    matching_files = file_names(contains(lower(file_names), lower(keyword)));
    
    if ~isempty(matching_files)
        % Use the first matching file
        full_path = fullfile(modtran_dir, matching_files{1});
        cases(end+1) = struct('file', full_path, 'zen_deg', zen, 'azi_deg', azi, 'label', label);
    else
        warning('No file found containing keyword: %s', keyword);
    end
end

% Set the plot options
opts.useTwoPanels = true;
opts.titlePrefix = sprintf('Cloud Comparison (zen=%d, azi=%d): ', zen, azi);

% plot the graphs
plots.TransmittanceRadiance(cases, opts);