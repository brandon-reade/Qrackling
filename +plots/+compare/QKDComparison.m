% Author: Brandon Reade
% Date: 11/03/2026
function fig = QKDComparison(Results, varargin)
%plots.QkdComparison Compare multiple QKD pass results in 3 linked subplots.
%
% Usage
%   plots.compare.QKDComparison(Results)
%   plots.compare.QKDComparison(Results, 'Wavelengths', [2000 2050 ...])
%   plots.compare.QKDComparison(Results, 'Labels', ["Day","Night"])
%   plots.compare.QKDComparison(Results, 'MaskMode', "elevation")  % default
%   plots.compare.QKDComparison(Results, 'MaskMode', "active")     % sifted_key_rate > 0
%   plots.compare.QKDComparison(Results, 'MaskFcn', @(R) R.secret_key_rate > 0)
%
% Inputs
%   Results : cell array of result objects exposing:
%             .time, .sifted_key_rate, .secret_key_rate, .qber
%             and optionally .elevation_mask
%
% Options
%   'Wavelengths' : numeric vector, used to auto-label as "XXXXnm"
%   'Labels'        : string/cellstr labels (overrides Wavelengths)
%   'Colors'        : Nx3 RGB array
%   'FigureName'    : figure name
%   'LineWidth'     : line width
%   'LegendLocationTop'    : legend location for top and middle plots
%   'LegendLocationBottom' : legend location for bottom plot
%   'MaskMode'      : "elevation" | "active" | "all"
%   'MaskFcn'       : function handle: mask = f(Result_i)
%
% Notes on Masking
%   - "elevation": uses Results{i}.elevation_mask (errors if missing)
%   - "active"   : uses Results{i}.sifted_key_rate > 0
%   - "all"      : uses all time points
%   - MaskFcn overrides MaskMode when provided.

p = inputParser;
p.addRequired('Results', @(x) iscell(x) && ~isempty(x));
p.addParameter('Wavelengths', [], @(x) isnumeric(x) || isempty(x));
p.addParameter('Labels', [], @(x) isstring(x) || iscellstr(x) || isempty(x));
p.addParameter('Colors', [], @(x) isnumeric(x) || isempty(x));
p.addParameter('FigureName', "BB84 QKD Comparison", @(x) isstring(x) || ischar(x));
p.addParameter('LineWidth', 1.5, @(x) isnumeric(x) && isscalar(x));
p.addParameter('LegendLocationTop', 'northwest', @(x) ischar(x) || isstring(x));
p.addParameter('LegendLocationBottom', 'northeast', @(x) ischar(x) || isstring(x));
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

%% Colours
colors = p.Results.Colors;
if isempty(colors)
    colors = lines(N);
end
if size(colors,1) ~= N || size(colors,2) ~= 3
    error('Colors must be an Nx3 RGB array, where N = numel(Results).');
end

%% Figure
fig = figure('Name', p.Results.FigureName, 'NumberTitle', 'off');
lw = p.Results.LineWidth;

% Create axes first so we can link them
ax1 = subplot(3,1,1); hold(ax1,'on'); grid(ax1,'on');
ax2 = subplot(3,1,2); hold(ax2,'on'); grid(ax2,'on');
ax3 = subplot(3,1,3); hold(ax3,'on'); grid(ax3,'on');

for i = 1:N
    R = Results{i};

    % Determine mask
    if ~isempty(p.Results.MaskFcn)
        mask = p.Results.MaskFcn(R);
    else
        mode = lower(string(p.Results.MaskMode));
        switch mode
            case "elevation"
                if ~isprop(R, 'elevation_mask') && ~isfield(R, 'elevation_mask')
                    error('MaskMode="elevation" requires Results{i}.elevation_mask.');
                end
                mask = R.elevation_mask;
            case "active"
                mask = R.sifted_key_rate > 0;
            case "all"
                mask = true(size(R.time));
            otherwise
                error('Unknown MaskMode: %s. Use "elevation", "active", or "all".', mode);
        end
    end

    % force same length as time
    mask = logical(mask(:));
    t = R.time(:);

    if numel(mask) ~= numel(t)
        error('Mask length mismatch for case %d: numel(mask)=%d, numel(time)=%d', ...
            i, numel(mask), numel(t));
    end

    plot(ax1, t(mask), R.sifted_key_rate(mask), 'Color', colors(i,:), ...
        'LineWidth', lw, 'DisplayName', labels(i));
    plot(ax2, t(mask), R.secret_key_rate(mask), 'Color', colors(i,:), ...
        'LineWidth', lw, 'DisplayName', labels(i));
    plot(ax3, t(mask), R.qber(mask)*100, 'Color', colors(i,:), ...
        'LineWidth', lw, 'DisplayName', labels(i));
end

ylabel(ax1, 'Sifted Key Rate (bits/s)','FontWeight','bold');
title(ax1,  'QKD Comparison','FontWeight','bold');
legend(ax1, 'Location', p.Results.LegendLocationTop);

ylabel(ax2, 'Secret Key Rate (bits/s)','FontWeight','bold');
legend(ax2, 'Location', p.Results.LegendLocationTop);

ylabel(ax3, 'QBER (%)','FontWeight','bold');
xlabel(ax3, 'Time','FontWeight','bold');
legend(ax3, 'Location', p.Results.LegendLocationBottom);

linkaxes([ax1 ax2 ax3], 'x');
end