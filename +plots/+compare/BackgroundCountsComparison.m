% Author: Brandon Reade
% Date: 11/03/2026

function fig = BackgroundCountsComparison(Results, varargin)
% Compare noise/background count terms.
%
% Expects:
%   Results{i}.noise is struct array with fields:
%     - .values (vector)
%     - .label  (string/char)
%   Results{i}.time
%   and either .elevation_mask or .sifted_key_rate (depending on MaskMode)
%
% Options
%   'Wavelengths' : numeric vector (nm) used to label as "XXXXnm"
%   'Labels'      : overrides Wavelengths
%   'FigureName'  : figure name
%   'MaskMode'    : "elevation" | "active" | "all" (default "elevation")
%   'MaskFcn'     : function handle mask = f(Result_i), overrides MaskMode

    p = inputParser;
    p.addRequired('Results', @(x) iscell(x) && ~isempty(x));
    p.addParameter('Wavelengths', [], @(x) isnumeric(x) || isempty(x));
    p.addParameter('Labels', [], @(x) isstring(x) || iscellstr(x) || isempty(x));
    p.addParameter('FigureName', "Background Counts Comparison", @(x) isstring(x) || ischar(x));
    p.addParameter('MaskMode', "elevation", @(x) isstring(x) || ischar(x));
    p.addParameter('MaskFcn', [], @(x) isempty(x) || isa(x,'function_handle'));
    p.parse(Results, varargin{:});
    
    N = numel(Results);
    
    %% Labels
    if ~isempty(p.Results.Labels)
        labels = string(p.Results.Labels);
    elseif ~isempty(p.Results.Wavelengths)
        w = p.Results.Wavelengths;
        if numel(w) ~= N
            error('Wavelengths must have numel == numel(Results).');
        end
        labels = arrayfun(@(x) sprintf('%dnm', round(x)), w, 'UniformOutput', false);
        labels = string(labels);
    else
        labels = "Case " + (1:N);
    end
    
    %% Precompute masks and x-limits per panel
    masks = cell(1,N);
    
    for i = 1:N
        R = Results{i};
    
        if ~isempty(p.Results.MaskFcn)
            mask = p.Results.MaskFcn(R);
        else
            mode = lower(string(p.Results.MaskMode));
            switch mode
                case "elevation"
                    if ~isprop(R,'elevation_mask') && ~isfield(R,'elevation_mask')
                        error('MaskMode="elevation" requires Results{i}.elevation_mask.');
                    end
                    mask = R.elevation_mask;
                case "active"
                    mask = R.sifted_key_rate > 0;
                case "all"
                    mask = true(size(R.time));
                otherwise
                    error('Unknown MaskMode: %s', mode);
            end
        end
    
        mask = logical(mask(:));
        if numel(mask) ~= numel(R.time(:))
            error('Mask length mismatch for case %d.', i);
        end
        masks{i} = mask;
    end
    
    %% Create figure
    fig = figure('Name', p.Results.FigureName, 'NumberTitle', 'off');
    tiledlayout(1, N, 'TileSpacing','compact');
    
    for i = 1:N
        nexttile; hold on; grid on;
    
        R = Results{i};
        mask = masks{i};
        x_axis = R.time;
    
        n_sources = numel(R.noise);
        n_points  = numel(R.noise(1).values);
        bcr_data  = reshape([R.noise.values], [n_points, n_sources]);
    
        area(x_axis(mask), bcr_data(mask, :));
    
        xlabel('Time', 'FontWeight','bold');
        ylabel('BCR (counts/s)', 'FontWeight','bold');
        title(labels(i), 'FontWeight','bold');
    
        lgd = legend(string({R.noise.label}), 'Location', 'best');
        lgd.NumColumns = 1;
    
        if any(mask)
            xlim([min(x_axis(mask)), max(x_axis(mask))]);
        end
    end
end