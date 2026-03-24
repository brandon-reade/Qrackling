% Author: Brandon Reade
% Date: 06/01/2026
%

repo_root = utilities.addUserPath('~\Documents\GitHub\Qrackling');
modtran_dir = fullfile(repo_root, 'Examples', 'Data', ...
    'atmospheric transmittance', 'raw modtran data', ...
    'HOGS_WinterClear_Lunar_angles', 'HOGS_WinterClear-10kVis', ...
    'moon_jan3rd_2024_1am');

if ~isfolder(modtran_dir)
    error('MODTRAN folder not found: %s', modtran_dir);
end

addpath(fullfile(repo_root));

csvFiles = dir(fullfile(modtran_dir, '*Transm*zen*deg*.csv'));
if isempty(csvFiles)
    csvFiles = dir(fullfile(modtran_dir, '*.csv'));
end
if isempty(csvFiles)
    fprintf('No CSVs found in %s\n', modtran_dir);
    return;
end

for k = 1:numel(csvFiles)
    fname = fullfile(csvFiles(k).folder, csvFiles(k).name);
    try
        [wav, tr, rad, meta] = utilities.readModtranFile(fname);

        if isempty(wav)
            fprintf('%s: no wavelength data\n', csvFiles(k).name);
            continue;
        end
        if isempty(tr)
            fprintf('%s: no transmittance data\n', csvFiles(k).name);
            continue;
        end

        fprintf('\n%s:\n', csvFiles(k).name);
        fprintf('  Transmittance: min=%g max=%g\n', nanmin(tr), nanmax(tr));
        fprintf('  Wavelength:    min=%g nm max=%g nm\n', nanmin(wav), nanmax(wav));

        if meta.has_rad
            fprintf('  Radiance column detected: col=%d\n', meta.rad_column);
            fprintf('  Radiance: min=%g max=%g (units as in file)\n', ...
                nanmin(rad), nanmax(rad));
        else
            fprintf('  No radiance column detected (treated as dark)\n');
        end

    catch ME
        fprintf('ERROR reading %s:\n  %s\n\n', csvFiles(k).name, ME.message);
    end
end
