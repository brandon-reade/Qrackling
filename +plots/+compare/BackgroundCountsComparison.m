% Author: Brandon Reade
% Date: 11/03/2026
% Last update: 20/08/2026

function fig = BackgroundCountsComparison(Results, varargin)
% Compare noise/background count terms across multiple results.
%
% Expects:
%   Results{i}.noise is struct array with fields:
%     - .values (vector)
%     - .label  (string/char)
%   Results{i}.time
%   and either .elevation_mask or .sifted_key_rate (depending on MaskMode)
%
% Options
%   'Wavelengths'          : numeric vector (nm) used to label as "XXXXnm"
%   'Labels'               : overrides Wavelengths
%   'FigureName'           : figure name
%   'MaskMode'             : "elevation" | "active" | "all" (default "elevation")
%   'MaskFcn'              : function handle mask = f(Result_i), overrides MaskMode
%   'HideZeroContributors' : logical (default true). If true, do not plot
%                            noise terms that are always zero (within ZeroTolerance)
%                            over the plotted/masked interval.
%   'ZeroTolerance'        : numeric scalar >=0 (default 0). Values with
%                            abs(value) <= ZeroTolerance are treated as zero.
%   'CommonYLimits'        : logical (default false). If true, all tiles use
%                            one shared Y axis range for easier visual comparison.
%   'YLimits'              : explicit [ymin ymax] override. If provided, this
%                            takes precedence over auto/common scaling.

    p = inputParser;
    p.addRequired('Results', @(x) iscell(x) && ~isempty(x));
    p.addParameter('Wavelengths', [], @(x) isnumeric(x) || isempty(x));
    p.addParameter('Labels', [], @(x) isstring(x) || iscellstr(x) || isempty(x));
    p.addParameter('FigureName', "Background Counts Comparison", @(x) isstring(x) || ischar(x));
    p.addParameter('MaskMode', "elevation", @(x) isstring(x) || ischar(x));
    p.addParameter('MaskFcn', [], @(x) isempty(x) || isa(x,'function_handle'));

    % New options
    p.addParameter('HideZeroContributors', true, @(x) islogical(x) && isscalar(x));
    p.addParameter('ZeroTolerance', 0, @(x) isnumeric(x) && isscalar(x) && x >= 0);
    p.addParameter('CommonYLimits', false, @(x) islogical(x) && isscalar(x));
    p.addParameter('YLimits', [], @(x) isempty(x) || (isnumeric(x) && numel(x)==2 && x(1) < x(2)));

    p.parse(Results, varargin{:});
    N = numel(Results);

    %% Labels
    if ~isempty(p.Results.Labels)
        labels = string(p.Results.Labels);
        if numel(labels) ~= N, error('Labels must have numel == numel(Results).'); end
    elseif ~isempty(p.Results.Wavelengths)
        w = p.Results.Wavelengths;
        if numel(w) ~= N
            error('Wavelengths must have numel == numel(Results).');
        end
        labels = string(arrayfun(@(x) sprintf('%dnm', round(x)), w, 'UniformOutput', false));
    else
        labels = "Case " + (1:N);
    end

    %% Precompute masks
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

    %% Create figure and compute shared y-limits if requested
    fig = figure('Name', p.Results.FigureName, 'NumberTitle', 'off');
    tiledlayout(1, N, 'TileSpacing','compact', 'Padding','compact');

    yGlobalMax = 0;
    if isempty(p.Results.YLimits) && p.Results.CommonYLimits
        for i = 1:N
            R = Results{i};
            mask = masks{i};
            [bcrData_i, keep_i] = localExtractNoiseMatrix(R, mask, ...
                p.Results.HideZeroContributors, p.Results.ZeroTolerance); %#ok<ASGLU>

            if ~isempty(bcrData_i) && any(mask)
                stackedSum = sum(bcrData_i(mask,:), 2);
                yGlobalMax = max([yGlobalMax; stackedSum(:)]);
            end
        end
    end

    %% Plot each panel
    for i = 1:N
        ax = nexttile; hold(ax,'on'); grid(ax,'on');

        R = Results{i};
        mask = masks{i};
        x_axis = R.time(:);

        [bcrData, keep] = localExtractNoiseMatrix(R, mask, ...
            p.Results.HideZeroContributors, p.Results.ZeroTolerance);

        if isempty(bcrData)
            text(ax, 0.5, 0.5, 'No non-zero contributors to plot', ...
                'Units','normalized', 'HorizontalAlignment','center');
        else
            area(ax, x_axis(mask), bcrData(mask, :));

            keptLabels = string({R.noise(keep).label});
            lgd = legend(ax, keptLabels, 'Location', 'best');
            lgd.NumColumns = 1;
        end

        xlabel(ax, 'Time', 'FontWeight','bold');
        ylabel(ax, 'BCR (counts/s)', 'FontWeight','bold');
        title(ax, labels(i), 'FontWeight','bold');

        if any(mask)
            xlim(ax, [min(x_axis(mask)), max(x_axis(mask))]);
        end

        % Y-limits policy:
        if ~isempty(p.Results.YLimits)
            ylim(ax, p.Results.YLimits);
        elseif p.Results.CommonYLimits
            if yGlobalMax <= 0
                ylim(ax, [0 1]);
            else
                ylim(ax, [0 yGlobalMax * 1.05]); % small headroom
            end
        else
            ylim(ax, 'auto');
        end
    end
end


function [bcrData, keep] = localExtractNoiseMatrix(R, mask, hideZero, zeroTol)
    n_sources = numel(R.noise);
    n_points  = numel(R.noise(1).values);

    bcrDataFull = reshape([R.noise.values], [n_points, n_sources]);

    if ~hideZero
        keep = true(1, n_sources);
        bcrData = bcrDataFull;
        return;
    end

    % Keep contributors that have non-zero magnitude somewhere in masked view
    keep = false(1, n_sources);
    for j = 1:n_sources
        v = bcrDataFull(:, j);
        vm = v(mask);
        keep(j) = any(abs(vm) > zeroTol);
    end

    bcrData = bcrDataFull(:, keep);
end