% Author: Brandon Reade
% Date: 06/01/2026 (updated)
function varargout = readModtranFile(filename)
% Reads a single MODTRAN scan file
% Usage:
%   [wav, tr] = readModtranFile(filename)                                   % legacy, works as before
%   [wav, tr, rad] = readModtranFile(filename)                              % returns radiance if present (empty otherwise)
%   [wav, tr, rad, meta] = readModtranFile(filename)                        % meta contains parsing info
%
% Parameters:
%   - wav:  wavelength in nm (column vector)
%   - tr:   combined total transmission, chosen column (column vector)
%   - rad:  spectral radiance column (column vector) or [] if not present
%   - meta: struct with optional fields (filename, zenith, elevation,...
%            secz, raw_lines_count, chosen_column, rad_column, ...
%            has_rad, is_dark, etc.) 

% Basic checks
if nargin < 1 || isempty(filename)
    error('readModtranFile requires a filename');
end

meta = struct('filename', filename);
fid = fopen(filename, 'r');
if fid < 0
    error('Failed to open file: %s', filename);
end

dataRows = {};
headerTokens = {};          % last non-numeric token row seen (possible column headers)
lines_read = 0;

% Read file line-by-line
while true
    line = fgetl(fid);
    if ~ischar(line)
        break;
    end
    lines_read = lines_read + 1;
    sline = strtrim(line);
    if isempty(sline)
        continue;
    end

    % Detect header-like lines (contain alphabetic tokens and no numeric tokens)
    % We still try to capture header tokens to find a "total" column
    line_no_commas = strrep(sline, ',', ' ');
    % If there are letters and no numeric tokens, treat as header
    if isempty(sscanf(line_no_commas, '%f')) && ~isempty(regexpi(line_no_commas, '[A-Za-z]'))
        % Split by whitespace/commas/semicolons and capture tokens
        toks = regexp(line_no_commas, '[^\s,;]+', 'match');
        if ~isempty(toks)
            headerTokens = toks;
        end
        continue;
    end

    % Normalize separators and Fortran D exponents
    line2 = strrep(sline, ',', ' ');
    line2 = strrep(line2, ';', ' ');
    line2 = regexprep(line2, '([0-9])([dD])([+\-]?[0-9]+)', '$1E$3');

    % read numeric tokens
    nums = sscanf(line2, '%f')';
    if isempty(nums)
        continue;
    end

    % If first token negative -> end marker in some outputs
    if nums(1) < 0
        break;
    end

    dataRows{end+1} = nums;
end

fclose(fid);
meta.raw_lines_count = numel(dataRows);
meta.header_tokens = headerTokens;

% If no numeric data found
if isempty(dataRows)
    wav = [];
    tr = [];
    rad = [];
    meta.chosen_column = [];
    meta.rad_column = [];
    meta.has_rad = false;
    meta.is_dark = true;
    % dispatch outputs based on nargout
    switch nargout
        case 0
            return;
        case 1
            varargout{1} = struct('wavelength', wav, 'transmittance', tr);
            return;
        case 2
            varargout{1} = wav; varargout{2} = tr; return;
        case 3
            varargout{1} = wav; varargout{2} = tr; varargout{3} = rad; return;
        otherwise
            varargout{1} = wav; varargout{2} = tr; varargout{3} = rad; varargout{4} = meta; return;
    end
end

% Build numeric matrix (pad shorter rows with NaN)
maxCols = max(cellfun(@numel, dataRows));
numRows = numel(dataRows);
numData = NaN(numRows, maxCols);
for r = 1:numRows
    row = dataRows{r};
    numData(r,1:numel(row)) = row;
end

% wavelength is first column
wav = numData(:,1);

% Choose transmittance column (prefer column 2 if between 0..1)
preferred_col = [];
if ~isempty(preferred_col) && preferred_col <= size(numData,2)
    chosen_col = preferred_col;
else
    if size(numData,2) >= 2
        col2 = numData(:,2);
        if ~all(isnan(col2)) && min(col2, [], 'omitnan') >= 0 && max(col2, [], 'omitnan') <= 1
            chosen_col = 2;
        else
            colsWithData = find(~all(isnan(numData)));
            if isempty(colsWithData)
                chosen_col = 2;
            else
                chosen_col = colsWithData(end);
            end
        end
    else
        chosen_col = 1;
    end
end
tr = numData(:, chosen_col);
meta.chosen_column = chosen_col;

% Try to determine a radiance ("total") column:
rad = [];
meta.rad_column = [];
meta.has_rad = false;
meta.is_dark = false;

% If header tokens exist, try to find 'total' token in header
if ~isempty(headerTokens)
    % clean tokens (strip punctuation) and lowercase
    clean = lower(regexprep(headerTokens, '[^A-Za-z0-9]+', ''));
    idx = find(strcmp(clean, 'total'), 1, 'first');
    if ~isempty(idx) && idx <= size(numData,2)
        meta.rad_column = idx;
        rad = numData(:, idx);
    end
end

% Fallback: if rad not found but file has >=10 columns, assume column 10 is "total"
if isempty(rad) && size(numData,2) >= 10
    meta.rad_column = 10;
    rad = numData(:, 10);
end

% If rad still empty, set to empty and mark dark
if isempty(rad)
    meta.has_rad = false;
    meta.rad_column = [];
    rad = [];
else
    % if rad exists check if it is all zeros (then treat as dark)
    if all(isnan(rad)) || all(abs(rad) < eps)
        meta.has_rad = false;
        meta.is_dark = true;
        % keep rad but mark as zero
        if all(isnan(rad))
            rad = [];
        end
    else
        meta.has_rad = true;
        meta.is_dark = false;
    end
end

% Set outputs according to requested number
switch nargout
    case 0
        % nothing
    case 1
        % support old usage where a single struct may be expected
        varargout{1} = struct('wavelength', wav, 'transmittance', tr, 'radiance', rad, 'meta', meta);
    case 2
        varargout{1} = wav;
        varargout{2} = tr;
    case 3
        varargout{1} = wav;
        varargout{2} = tr;
        varargout{3} = rad;
    otherwise
        varargout{1} = wav;
        varargout{2} = tr;
        varargout{3} = rad;
        varargout{4} = meta;
end
end