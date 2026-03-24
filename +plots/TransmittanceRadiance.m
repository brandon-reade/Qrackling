function out = TransmittanceRadiance(cases, options)
% Overlay plots of MODTRAN radiance and transmittance vs wavelength for one
% or more MODTRAN CSV outputs

% cases: struct array with either...
%   - case(i).file      = full path the MODTRAN CSV
%   - case(i).dir       = folder containing MODTRAN CSVs
%   - case(i).zen_deg   = zenith angle to match (integer token in filename)
%   - case(i).azi_deg   = azimuth angle to match (integer token in filename)
% 
% Optional per-case fields:
%   - case(i).label     = legend label (default is: filename)
%   - case(i).color     = [r g b]
%   - case(i).style     = line style (default is '-')
%   - case(i).width     = line width (default is 1.5)

% options: an optional structure with...
%   - options.useTwoPanels          = true/false (default is true)
%   - options.radianceScale         = float (default is 1/100)              unit conversion to W m-2 sr-1 nm -1 from uW cm-2 sr-1 nm-1
%   - options.showLegend            = true/false (default is true)
%   - options.titlePrefix           = string (default is "")

% Output:
%   - out(i).wav, out(i).tr,  out(i).rad, out(i).meta, out(i).file,...
%   out(i).label 

%% Parsing data from files
% check arguments
    if nargin < 1 || isempty(cases)
        error('cases must be a non-empty struct array.');
    end
    if nargin < 2
        options = struct();
    end
    
    options = setDefaults(options, struct(...
        'useTwoPanels', true, ...
        'radianceScale', 1/100, ...
        'showLegend', true, ...
        'titlePrefix', "" ...
        ));

    n = numel(cases);                                                       % count cases
    out = repmat(struct('wav', [], 'tr', [], 'rad', [],...                  % create structure template and copy it to for n cases as in an nx1 structure array: makes out(i)
        'meta', struct(), 'file', "", 'label', ""), n, 1);

    % For each element in cases, read CSVs and create an out(i)
    for i = 1:n
        current_case = cases(i);

        file = "";

        % check if current case is a file
        if isfield(current_case, 'file') && ~isempty(current_case.file)
            file = string(current_case.file);
        elseif isfield(current_case, 'dir') && ~isempty(current_case.dir)   % check if current case is a dir and if zen/azi degrees provided
            if ~isfield(current_case, 'zen_deg') || ~isfield(current_case, 'azi_deg')
                error('Case %d: when using dir, you must provide a zen_deg and azi_deg.', i);
            end
            file = findModtranFile(string(current_case.dir), current_case.zen_deg, current_case.azi_deg);
        else
            error('Case %d: you must provide either a .file or (.dir + .zen_deg + .azi_deg).', i);
        end
        
        % check if file exists
        if strlength(file) == 0 || ~isfile(file)
            error('Case %d: file does not exist: %s', i, file);
        end
        
        % parse data and check if it was successful
        [wav, tr, rad, meta] = utilities.readModtranFile(file);
        if isempty(wav) || isempty(tr)
            error('Case %d: no numeric data parsed from file: %s', i, file);
        end
        
        % assign values from parsed data
        wav = wav(:);
        tr = tr(:);
        if ~isempty(rad)
            rad = rad(:) * options.radianceScale;
        end

        % remove NaNs
        mask = ~isnan(wav) & ~isnan(tr);
        if ~isempty(rad)
            mask = mask & ~isnan(rad);
        end
        wav = wav(mask);
        tr = tr(mask);
        if ~isempty(rad)
            rad = rad(mask);
        end

        % ensure it is sorted by wavelength
        [wav, idx] = sort(wav);
        tr = tr(idx);
        if ~isempty(rad)
            rad = rad(idx);
        end

        % Label
        label = "";
        if isfield(current_case, 'label') && ~isempty(current_case.label)
            label = string(current_case.label);
        else
            [~, name, ext] = fileparts(file);
            label = name + ext;
        end

        out(i).wav      = wav;
        out(i).tr       = tr;
        out(i).rad      = rad;
        out(i).meta     = meta;
        out(i).file     = file;
        out(i).label    = label;
    end

    %% Plot
    if options.useTwoPanels
        % TWO PANEL SETTINGS
        figure("Color", "w");
        tiledlayout(2, 1, "Padding","compact", "TileSpacing", "compact");

        % set radiance parameters
        ax1 = nexttile;
        hold(ax1, 'on');
        grid(ax1, 'on');
        xlabel(ax1, "Wavelength (nm)");
        ylabel(ax1, "Radiance (W m^{-2} sr^{-1} nm^{-1})");
        title(ax1, strtrim(options.titlePrefix + "Radiance vs Wavelength (nm)"));

        % set transmittance parameters
        ax2 = nexttile;
        hold(ax2, 'on'); grid(ax2, 'on');
        xlabel(ax2, "Wavelength (nm)");
        ylabel(ax2, "Transmittance");
        title(ax2, strtrim(options.titlePrefix + "Transmittance vs Wavelength (nm)"));
        
        % plot cases
        for i = 1:n
            c = cases(i);
    
            [col, ls, lw] = getStyle(c, i);
            if ~isempty(out(i).rad)
                plot(ax1, out(i).wav, out(i).rad, 'Color', col, 'LineStyle', ls, 'LineWidth', lw, ...
                    'DisplayName', out(i).label);
            else
                % If no radiance, skip radiance line but still keep legend entry in trans plot
            end
    
            plot(ax2, out(i).wav, out(i).tr, 'Color', col, 'LineStyle', ls, 'LineWidth', lw, ...
                'DisplayName', out(i).label);
        end
        
        % show legend if desired
        if options.showLegend
            legend(ax2, 'Location', 'best');
            if any(arrayfun(@(s) ~isempty(s.rad), out))
                legend(ax1, 'Location', 'best');
            end
        end
    else
        % SINGLE PANEL SETTINGS
        figure("Color","w");
        ax = axes; hold(ax,'on'); grid(ax,'on');
        xlabel(ax, "Wavelength (nm)");
        title(ax, strtrim(options.titlePrefix + "Transmittance (left) and Radiance (right) vs Wavelength (nm)"));
    
        yyaxis(ax, 'right');
        ylabel(ax, "Radiance (W m^{-2} sr^{-1} nm^{-1})", 'FontWeight', 'bold');
    
        yyaxis(ax, 'left');
        ylabel(ax, "Transmittance", 'FontWeight', 'bold');
        
        % plot cases
        for i = 1:n
            c = cases(i);
            [col, ls, lw] = getStyle(c, i);
    
            yyaxis(ax, 'right');
            if ~isempty(out(i).rad)
                plot(ax, out(i).wav, out(i).rad, 'Color', col, 'LineStyle', '--', 'LineWidth', lw, ...
                    'DisplayName', out(i).label + " (rad)");
            end
    
            yyaxis(ax, 'left');
            plot(ax, out(i).wav, out(i).tr, 'Color', col, 'LineStyle', ls, 'LineWidth', lw, ...
                'DisplayName', out(i).label + " (tr)");
        end
    
        if options.showLegend
            legend(ax, 'Location', 'best');
        end
    end    
end


%% Functions
% Finding MODTRAN CSVs from a directory
function file = findModtranFile(modtran_dir, zen_deg, azi_deg)

    % check if the directory exists
    if ~isfolder(modtran_dir)
        error('MODTRAN folder not found: %s', modtran_dir);
    end

    % check if the CSVs exist
    csvFiles = dir(fullfile(modtran_dir, '*Transm*.csv'));
    if isempty(csvFiles)
        csvFiles = dir(fullfile(modtran_dir, '*.csv'));
    end
    if isempty(csvFiles)
        error('No MODTRAN CSVs found in: %s', modtran_dir);
    end

    % Parse the names
    file = "";
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
            azi = NaN;
        else
            azi = str2double(tokAzi{1});
        end
    
        if zen == zen_deg && ( (isnan(azi) && isnan(azi_deg)) || (~isnan(azi) && azi == azi_deg) )
            file = fullfile(csvFiles(k).folder, csvFiles(k).name);
            return;
        end
    end

    % helpful error to show which CSVs are available if given one not found
    fprintf('No MODTRAN CSV matched zen=%g, azi=%g in %s\n', zen_deg, azi_deg, modtran_dir);
    fprintf('Available CSVs:\n');
    for k = 1:numel(csvFiles)
        fprintf('  %s\n', csvFiles(k).name);
    end
    file = "";
end

% setting the colours, styles, widths
function [col, ls, lw] = getStyle(c, idx)
    % default colour cycle
    colors = lines(12);
    
    if isfield(c,'color') && ~isempty(c.color)
        col = c.color;
    else
        col = colors(1 + mod(idx-1, size(colors,1)), :);
    end
    if isfield(c,'style') && ~isempty(c.style)
        ls = c.style;
    else
        ls = '-';
    end
    if isfield(c,'width') && ~isempty(c.width)
        lw = c.width;
    else
        lw = 1.5;
    end
end

% setting the defaults
function s = setDefaults(s, defaults)
    fn = fieldnames(defaults);
    for i = 1:numel(fn)
        f = fn{i};
        if ~isfield(s, f) || isempty(s.(f))
            s.(f) = defaults.(f);
        end
    end
end