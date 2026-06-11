% Author: Brandon Reade
% Date: 17/04/2026
% reports problematic files and why

repo_root = utilities.addUserPath('~\Documents\GitHub\Qrackling');
modtran_dir = fullfile(repo_root,...
    '+modtran\Data\HOGS\HOGS_moon_May15_03h05_10kmvis_300to10000_zenstep10_azistep30');

if ~isfolder(modtran_dir)
    error('MODTRAN folder not found: %s', modtran_dir);
end
addpath(fullfile(repo_root));

% Read all CSVs (builder may use more than just "*Transm*")
csvFiles = dir(fullfile(modtran_dir, '*.csv'));
if isempty(csvFiles)
    fprintf('No CSVs found in %s\n', modtran_dir);
    return;
end

problems = struct( ...
    'file', {}, ...
    'has_wav', {}, ...
    'has_tr', {}, ...
    'has_rad', {}, ...
    'wav_min', {}, 'wav_max', {}, ...
    'tr_min', {}, 'tr_max', {}, 'tr_oob_count', {}, ...
    'rad_min', {}, 'rad_max', {}, 'rad_neg_count', {}, ...
    'nan_or_inf', {}, ...
    'error', {} );

for k = 1:numel(csvFiles)
    fname = fullfile(csvFiles(k).folder, csvFiles(k).name);

    try
        [wav, tr, rad, meta] = utilities.readModtranFile(fname);

        has_wav = ~isempty(wav) && any(isfinite(wav));
        has_tr  = ~isempty(tr)  && any(isfinite(tr));
        has_rad = isfield(meta,'has_rad') && meta.has_rad && ~isempty(rad);

        % Basic stats
        wav_min = NaN; wav_max = NaN;
        tr_min  = NaN; tr_max  = NaN;
        rad_min = NaN; rad_max = NaN;

        if has_wav
            wav_min = min(wav, [], 'omitnan');
            wav_max = max(wav, [], 'omitnan');
        end
        if has_tr
            tr_min = min(tr, [], 'omitnan');
            tr_max = max(tr, [], 'omitnan');
        end
        if has_rad
            rad_min = min(rad, [], 'omitnan');
            rad_max = max(rad, [], 'omitnan');
        end

        % Conditions that typically break Environment construction
        tr_oob_count = 0;
        if has_tr
            tr_oob_count = sum((tr < 0 | tr > 1) & isfinite(tr));
        end

        rad_neg_count = 0;
        if has_rad
            rad_neg_count = sum((rad < 0) & isfinite(rad));
        end

        nan_or_inf = false;
        if has_wav && any(~isfinite(wav)), nan_or_inf = true; end
        if has_tr  && any(~isfinite(tr)),  nan_or_inf = true; end
        if has_rad && any(~isfinite(rad)), nan_or_inf = true; end

        % Decide if the file is problematic
        is_problem = false;

        if ~has_wav || ~has_tr
            is_problem = true;
        end
        if tr_oob_count > 0
            is_problem = true;
        end
        if rad_neg_count > 0
            is_problem = true;
        end
        if nan_or_inf
            is_problem = true;
        end

        if is_problem
            problems(end+1) = struct( ... 
                'file', fname, ...
                'has_wav', has_wav, ...
                'has_tr', has_tr, ...
                'has_rad', has_rad, ...
                'wav_min', wav_min, 'wav_max', wav_max, ...
                'tr_min', tr_min, 'tr_max', tr_max, 'tr_oob_count', tr_oob_count, ...
                'rad_min', rad_min, 'rad_max', rad_max, 'rad_neg_count', rad_neg_count, ...
                'nan_or_inf', nan_or_inf, ...
                'error', "" );
        end

    catch ME
        % Any read/parse error is a problem
        problems(end+1) = struct( ... 
            'file', fname, ...
            'has_wav', false, ...
            'has_tr', false, ...
            'has_rad', false, ...
            'wav_min', NaN, 'wav_max', NaN, ...
            'tr_min', NaN, 'tr_max', NaN, 'tr_oob_count', NaN, ...
            'rad_min', NaN, 'rad_max', NaN, 'rad_neg_count', NaN, ...
            'nan_or_inf', true, ...
            'error', string(ME.message) );
    end
end

% Print a simple problem file list
if isempty(problems)
    fprintf("No problematic CSVs found in %s\n", modtran_dir);
else
    fprintf("\nProblematic CSVs (%d of %d):\n", numel(problems), numel(csvFiles));
    for i = 1:numel(problems)
        p = problems(i);
        fprintf("  %s\n", p.file);
        if p.error ~= ""
            fprintf("    ERROR: %s\n", p.error);
            continue;
        end
        if ~p.has_wav, fprintf("    - missing/invalid wavelength column\n"); end
        if ~p.has_tr,  fprintf("    - missing/invalid transmittance column\n"); end
        if p.tr_oob_count > 0
            fprintf("    - transmittance out of [0,1]: count=%d, min=%g, max=%g\n", ...
                p.tr_oob_count, p.tr_min, p.tr_max);
        end
        if p.has_rad && p.rad_neg_count > 0
            fprintf("    - radiance negative: count=%d, min=%g, max=%g\n", ...
                p.rad_neg_count, p.rad_min, p.rad_max);
        end
        if p.nan_or_inf
            fprintf("    - contains NaN/Inf values\n");
        end
    end

    % Optionally save for later inspection
    %save(fullfile(modtran_dir, "csv_problem_report.mat"), "problems");
end