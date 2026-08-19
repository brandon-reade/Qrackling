% Author: Brandon Reade
% Date: 06/01/2026 (updated)
function envPath = createMODTRANEnv(modtran_dir, atmosphere_tag)
% Build and save an environment .mat from a folder of MODTRAN CSVs
% envPath = createMODTRANEnv(modtran_dir, atmosphere_tag)
% - If any spectral radiance is present and non-zero a "Radiant Environment <folder>.mat"
%   is created. Otherwise "Dark Environment <folder>.mat".
%
% The function understands both filename styles:
%  - filenames containing both zen and azi tokens: 'zen_30deg_azi_0deg'
%  - filenames containing only zen token (legacy): 'zen_30deg' (those are replicated across headings)

if nargin < 1 || isempty(modtran_dir)
    modtran_dir = pwd;
end
if nargin < 2
    atmosphere_tag = '';
end

[~, folderName] = fileparts(modtran_dir);

% Find CSVs (prefer files whose name contains "Transm" but fall back to any CSV)
csvFiles = dir(fullfile(modtran_dir, '*Transm*.csv'));
if isempty(csvFiles)
    csvFiles = dir(fullfile(modtran_dir, '*.csv'));
end
if isempty(csvFiles)
    error('No MODTRAN CSVs found in %s', modtran_dir);
end

% Collect tokens and build file map keyed by (zen,azi)
% We store azi as NaN when missing (legacy file with no spectral rad data)
fileMap = containers.Map();                                                 % key -> fullfilename
zenList = [];                                                               % list of zen values (may repeat if multiple azis)
aziList = [];                                                               % list of azi values (may contain NaN)
for k = 1:numel(csvFiles)
    name = csvFiles(k).name;
    fname = fullfile(csvFiles(k).folder, name);
    tokZen = regexp(name, 'zen[_-]?(\d+)', 'tokens', 'once', 'ignorecase');
    if isempty(tokZen)
        % Try alternative 'zen<digits>' (no separator)
        tokZen = regexp(name, 'zen(\d+)', 'tokens', 'once', 'ignorecase');
    end
    if isempty(tokZen)
        warning('Skipping file without zenith token: %s', name);
        continue;
    end
    zen = str2double(tokZen{1});
    tokAzi = regexp(name, 'azi[_-]?(\d+)', 'tokens', 'once', 'ignorecase');
    if isempty(tokAzi)
        azi = NaN; % legacy
    else
        azi = str2double(tokAzi{1});
    end
    key = mapKey(zen, azi);
    fileMap(key) = fname;
    zenList(end+1) = zen;
    aziList(end+1) = azi;
end

if isempty(zenList)
    error('No MODTRAN CSVs with zenith token found in %s', modtran_dir);
end

% unique zeniths and azimuthals
uniqueZens = unique(zenList, 'stable');
uniqueAzis = unique(aziList(~isnan(aziList)), 'stable'); % exclude NaNs for headings

if isempty(uniqueAzis)
    % legacy files, replicate across default headings
    Headings = [0, 90, 180, 270];
    useLegacyAzi = true;
else
    % use azimuths from CSVs
    Headings = uniqueAzis(:)';  % use azimuths as headings
    %Headings = mod(uniqueAzis(:)', 360);                                    % wrap 360 -> 0
    Headings = unique(Headings, 'stable');                                  % remove duplicates
    Headings = sort(Headings, 'ascend');                                    % ensure strictly increasing
    useLegacyAzi = false;
end


% Convert zeniths to elevations and sort increasing (required by Environment)
elevations = 90 - uniqueZens(:);
[Elevation, idxElevOrder] = sort(elevations, 'ascend');
% Keep corresponding zen order (sorted by elevation)
zen_sorted = uniqueZens(idxElevOrder);

% Choose a sample file to obtain wavelength grid
% Prefer a file that actually exists for a given zen/azi combination
sample_found = false;
sample_fname = '';
for ia = 1:numel(Headings)
    for ie = 1:numel(zen_sorted)
        if useLegacyAzi
            key = mapKey(zen_sorted(ie), NaN);
        else
            key = mapKey(zen_sorted(ie), Headings(ia));
        end
        if isKey(fileMap, key)
            sample_found = true;
            sample_fname = fileMap(key);
            break;
        end
    end
    if sample_found, break; end
end
if ~sample_found
    % Try any file from the map
    keysAll = fileMap.keys;
    sample_fname = fileMap(keysAll{1});
end

% Read sample wavelength using utilities.readModtranFile
try
    [wav0, ~, rad0, ~] = utilities.readModtranFile(sample_fname);
catch ME
    error('Failed to read sample MODTRAN file %s: %s', sample_fname, ME.message);
end
if isempty(wav0)
    error('Sample MODTRAN file produced no wavelength data: %s', sample_fname);
end
Wavelength = wav0(:);  % column vector
nW = numel(Wavelength);
nH = numel(Headings);
nE = numel(Elevation);

% Prepare arrays: wl x headings x elevation
Trep = zeros(nW, nH, nE);
SR   = zeros(nW, nH, nE);

% Flag if any radiance is present
any_radiant = false;

% Fill arrays by looking up file for each zen/heading
for ie = 1:nE
    zen = zen_sorted(ie);
    for ih = 1:nH
        if useLegacyAzi
            % Use legacy zen-only files (replicated across headings)
            key = mapKey(zen, NaN);
            if ~isKey(fileMap, key)
                error('Missing legacy MODTRAN output for zen=%d (expected key %s)', zen, key);
            end
        else
            azi = Headings(ih);
            key = mapKey(zen, azi);
            if ~isKey(fileMap, key)
                % fallback: if a zen-only file exists use that
                keyLegacy = mapKey(zen, NaN);
                if isKey(fileMap, keyLegacy)
                    key = keyLegacy;
                else
                    error('Missing MODTRAN output for azi=%d zen=%d (expected key %s)', azi, zen, key);
                end
            end
        end

        fname = fileMap(key);
        try
            [wav_i, tr_i, rad_i, meta_i] = utilities.readModtranFile(fname);
        catch ME
            error('Failed to parse MODTRAN file "%s": %s', fname, ME.message);
        end

        if isempty(wav_i) || isempty(tr_i)
            error('Parsed empty wavelength/transmission from %s', fname);
        end

        % ensure radiance units are consistent
        rad_i = rad_i / 100;                                                % unit conversion to W m-2 sr-1 nm -1 from uW cm-2 sr-1 nm-1 (which MODTRAN outputs)
    
        % --- enforce unique wavelength grid ---
        [wav_i, uniqIdx] = unique(wav_i(:), 'stable');
        tr_i = tr_i(uniqIdx);
        if ~isempty(rad_i)
            rad_i = rad_i(uniqIdx);
        end


        % interpolate if wavelength grids differ
        if ~isequal(wav_i(:), Wavelength(:))
            tr_i = interp1(wav_i(:), tr_i(:), Wavelength(:), 'linear', 'extrap');
            if ~isempty(rad_i)
                rad_i = interp1(wav_i(:), rad_i(:), Wavelength(:), 'linear', 'extrap');
            end
        else
            tr_i = tr_i(:);
            if ~isempty(rad_i)
                rad_i = rad_i(:);
            end
        end

        Trep(:, ih, ie) = tr_i(:);
        if ~isempty(rad_i)
            SR(:, ih, ie) = rad_i(:);
            if any(abs(rad_i(:)) > 0)
                any_radiant = true;
            end
        else
            SR(:, ih, ie) = 0;
        end
    end
end

% Decide environment name based on whether any radiance exists
if any_radiant
    outEnvName = ['Radiant Environment ', folderName];
else
    outEnvName = ['Dark Environment ', folderName];
end

% Build Environment object: (Headings, Elevation, Wavelength, SpectralRadiance, Transmittance, ...)
Env = environment.Environment(Headings, Elevation, Wavelength, SR, Trep, "attenuation_unit", "probability");

% Save env in modtran_dir
origDir = pwd;
cleanup = onCleanup(@() cd(origDir));
cd(modtran_dir);
Env.save(outEnvName);
envPath = fullfile(modtran_dir, [outEnvName, '.mat']);

% Validation printout
fprintf('Created environment: %s\n', envPath);
fprintf('  Headings included: %s\n', mat2str(Headings));
fprintf('  Elevations included (deg, increasing): %s\n', mat2str(Elevation'));
if any_radiant
    fprintf('  Radiance: present (environment named "%s")\n', outEnvName);
else
    fprintf('  Radiance: not present or all-zero (environment named "%s")\n', outEnvName);
end

end

function k = mapKey(zen, azi)
% helper to create stable string-key for containers.Map
% azi may be NaN to indicate "no azimuth" legacy files
if isnan(azi)
    k = sprintf('zen_%d_azi_na', round(zen));
else
    k = sprintf('zen_%d_azi_%d', round(zen), round(azi));
end
end