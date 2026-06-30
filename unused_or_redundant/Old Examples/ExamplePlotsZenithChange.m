% Author: Brandon Reade
% Date: 26/01/2026
% Compare MODTRAN outputs for multiple zenith angles with the same azimuth
clear; clc;

% set CSV location
repo_root = utilities.addUserPath('~\Documents\GitHub\Qrackling');
modtran_dir = fullfile(repo_root, 'Examples', 'Data', ...
    'atmospheric transmittance', 'raw modtran data', ...
    'HOGS_WinterClear_Lunar_angles', 'HOGS_WinterClear-10kVis', ...
    'moon_jan3rd_2026_1am_full');
%addpath(fullfile(repo_root));                                               % adds the folder containing +plots

%% Zenith comparison
% set angles to plot
azi = 0;                                                                    % compare at this azimuth
zens = [0 30 60 80];                                                        % compare these zeniths

% create the cases to plot
cases = repmat(struct('dir', "", 'zen_deg', [], 'azi_deg', [], 'label', ""), 1, numel(zens));
for i = 1:numel(zens)
    cases(i).dir     = modtran_dir;
    cases(i).zen_deg = zens(i);
    cases(i).azi_deg = azi;
    cases(i).label   = sprintf('zen=%d, azi=%d (%s)', zens(i), azi, 'jan3 1am');
end
% set plot options
options.useTwoPanels = true;
options.titlePrefix = "Zenith comparison: ";

% plot the graphs
plots.TransmittanceRadiance(cases, options);

%% Azimuth Comparison
% set angles to plot
azis = [0 60 120 180 240 300];                                             % compare these azimuthals
zen = 30;                                                                  % compare at this zenith

% create the cases to plot
cases = repmat(struct('dir', "", 'zen_deg', [], 'azi_deg', [], 'label', ""), 1, numel(azis));
for i = 1:numel(azis)
    cases(i).dir     = modtran_dir;
    cases(i).zen_deg = zen;
    cases(i).azi_deg = azis(i);
    cases(i).label   = sprintf('zen=%d, azi=%d (%s)', zen, azis(i), 'jan3 1am');
end

% set plot options
options.useTwoPanels = true;
options.titlePrefix = "Azimuth comparison: ";

% plot the graphs
plots.TransmittanceRadiance(cases, options);