function ImportMODTRANData(atmosphere_tag, data_dir)
%%Import all of the data in the files which have a given start to form an array
%%of atmospheric transmittances over wavelength and elevation
% If atmosphere_tag omitted then empty string is used
% if data_dir is omitted then it assumes the current folder

if nargin < 1
    atmosphere_tag = "";
end
if nargin < 2 || isempty(data_dir)
    data_dir = pwd;
end

%% prepare different values of elevation
Elevation = [1,2,5,10,20,30,40,50,60,70,80,85,88,89,90];                    % this set is used by other scripts

% search for raw files in data dir that contain '_zen_<zen>deg' for each elevation
S.Elevation = [];
S.Wavelength = [];
S.Transmittance = [];

% Collect parsed data keyed by elevation
parsed = containers.Map('KeyType', 'double', 'ValueType', 'any');

% list files in data_dir
files = dir(fullfile(data_dir, '*'));
for k = 1:numel(files)
    if files(k).isdir
        continue
    end
    name = files(k).name;

    % look for zen pattern
    tok = regexp(name,'_zen[_-]?(\d+)deg', 'tokens', 'ignorecase');
    if isempty(tok)
        tok = regexp(name, 'zen[_-]?(\d+)', 'tokens', 'ignorecase');
    end
    if isempty(tok)
        continue
    end
    zen = str2double(tok{1}{1});
    elevation = 90 - zen;
    fullpath = fullfile(files(k).folder, name);

    try
        % Prefer the common call signature [wav,tr,meta] if supported
        try
            [wav, tr, meta] = utilities.readModtranFile(fullpath);
            wav = wav(:);
            tr  = tr(:);
        catch
            % If the above fails, try a single-struct return
            s = utilities.readModtranFile(fullpath);
            if isstruct(s) && isfield(s,'wavelength') && isfield(s,'transmittance')
                wav = s.wavelength(:);
                tr  = s.transmittance(:);
                if isfield(s,'meta'), meta = s.meta; else meta = []; end
            elseif iscell(s) && numel(s) >= 2
                wav = s{1}(:);
                tr  = s{2}(:);
                if numel(s) >= 3, meta = s{3}; else meta = []; end
            else
                error('utilities.readModtranFile returned unrecognised output for %s', name);
            end
        end
    catch ME
        warning('Failed to parse %s: %s', name, ME.message);
        continue
    end
    parsed(elevation) = struct('wav', wav(:), 'tr', tr(:), 'meta', meta);   % store parsed
end

if parsed.Count == 0
    error('No raw MODTRAN scan files with ''_zen_<N>deg'' found in %s', data_dir);
end

% determine common wavelength grid
elevs = sort(cell2mat(parsed.keys));
ref = parsed(elevs(1));
ref_wav = ref.wav;
num_wav = numel(ref_wav);
num_el = numel(elevs);

% build transmittance matrix, columns correspond to elevations (in same order as elevs)
Transmittance = nan(num_wav, num_el);
for i = 1:num_el
    el = elevs(i);
    rec = parsed(el);
    wav_i = rec.wav;
    tr_i = rec.tr;
    if numel(wav_i) ~= num_wav || any(wav_i ~= ref_wav)
        % interpolate onto ref_wav
        tr_i = interp1(wav_i, tr_i, ref_wav, 'linear', NaN);
    end
    Transmittance(:, i) = tr_i;
end

% Prepare outputs in the exact variable names expected elsewhere
Elevation = elevs(:)';    % row vector (deg above horizon)
Wavelength = ref_wav(:);  % column vector (nm)

% Save with the correct name so BuildDarkEnvironmentFiles and other
% scripts can find it unchanged.
if isempty(atmosphere_tag)
    SaveName = 'Elevation_Wavelength_Atmospheric_Transmittance.mat';
else
    SaveName = ['Elevation_Wavelength_Atmospheric_Transmittance', char(atmosphere_tag), '.mat'];
end

save(fullfile(data_dir, SaveName), 'Transmittance', 'Wavelength', 'Elevation');

fprintf('Saved %s in %s\n', SaveName, data_dir);
end