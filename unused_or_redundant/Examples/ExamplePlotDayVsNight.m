% Author: Brandon Reade
% Date: 27/01/2026
% Compare two different MODTRAN folders for Solar vs Lunar radiance

clear; clc;

repo_root = utilities.addUserPath('~\Documents\GitHub\Qrackling');

lunar_dir = fullfile(repo_root, 'Examples', 'Data', ...
    'atmospheric transmittance', 'raw modtran data', ...
    'HOGS_WinterClear_Lunar_angles', 'HOGS_WinterClear-10kVis', ...
    'moon_jan3rd_2026_1am_500to3000nm');

solar_dir = fullfile(repo_root, 'Examples', 'Data', ...
    'atmospheric transmittance', 'raw modtran data', ...
    'HOGS_WinterClear_Lunar_angles', 'HOGS_WinterClear-10kVis', ...
    'sun_jan3rd_2026_1pm_500to3000nm'); 

zen = 0;
azi = 0;

cases(1) = struct('dir', lunar_dir, 'zen_deg', zen, 'azi_deg', azi, 'label', '1am (Lunar)');
cases(2) = struct('dir', solar_dir, 'zen_deg', zen, 'azi_deg', azi, 'label', '1pm (Solar)');


opts.useTwoPanels = true;
opts.titlePrefix = sprintf('Solar/Lunar comparison (zen=%d, azi=%d): ', zen, azi);

% plot the graphs
plots.TransmittanceRadiance(cases);