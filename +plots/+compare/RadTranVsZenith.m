function fig = RadTranVsZenith(Envs, varargin)
% Plot spectral radiance + transmittance vs zenith angle.
% Supports:
%   - One env, many wavelengths
%   - Many envs, one wavelength (e.g. day vs night)
%
% Examples
%   % Day vs night at one wavelength
%   plots.compare.RadTranVsZenith({Env_day, Env_night}, ...
%       'Labels', ["Day","Night"], 'Colors', [DAY_COLOR; NIGHT_COLOR], ...
%       'AzimuthDeg', 0, 'ZenithDeg', 0:10:90, 'Wavelengths', 850);
%
%   % One env, multiple wavelengths
%   plots.compare.RadTranVsZenith(Env, ...
%       'Wavelengths', [850 2050 2140 2990], ...
%       'Labels', ["850nm","2050nm","2140nm","2990nm"]);
%
% Name-Value Options
%   'AzimuthDeg'      : scalar azimuth in degrees (default 0)
%   'ZenithDeg'       : vector of zenith angles in degrees (default 0:10:90)
%   'Wavelengths'     : scalar or vector wavelengths in nm (required)
%   'Labels'          : labels for plotted series (optional)
%   'Colors'          : Nx3 RGB array (optional)
%   'LineWidth'       : default 1.5
%   'FigureName'      : optional
%   'TileSpacing'     : default 'compact'
%   'RadianceScale'   : "log" | "linear" (default "log")
%   'ShowMarkers'     : true/false (default false)
%   'TwoPanel'        : true (default) => rad & tran separate tiles
%                      false => single panel, radiance dashed
%   'UseYYAxis'       : when TwoPanel=false, use yyaxis left/right (default true)
%
% Notes
%   If Envs is a single Env and Wavelengths has multiple entries, the series
%   are different wavelengths.
%   If Envs has multiple entries and Wavelengths is scalar, series are different envs.

% Normalize Envs to cell array
if ~iscell(Envs)
    Envs = {Envs};
end

p = inputParser;
p.addRequired('Envs', @(x) iscell(x) && ~isempty(x));
p.addParameter('AzimuthDeg', 0, @(x) isnumeric(x) && isscalar(x));
p.addParameter('ZenithDeg', 0:10:90, @(x) isnumeric(x) && isvector(x));

% Backwards compat: accept 'Wavelength' (scalar) or 'Wavelengths' (scalar/vector)
p.addParameter('Wavelength', [], @(x) isnumeric(x) && (isscalar(x) || isvector(x)));
p.addParameter('Wavelengths', [], @(x) isnumeric(x) && (isscalar(x) || isvector(x)));

p.addParameter('Labels', [], @(x) isstring(x) || iscellstr(x) || isempty(x));
p.addParameter('Colors', [], @(x) isnumeric(x) || isempty(x));
p.addParameter('LineWidth', 1.5, @(x) isnumeric(x) && isscalar(x));
p.addParameter('FigureName', "", @(x) isstring(x) || ischar(x));
p.addParameter('TileSpacing', 'compact', @(x) isstring(x) || ischar(x));
p.addParameter('RadianceScale', "log", @(x) isstring(x) || ischar(x));
p.addParameter('ShowMarkers', false, @(x) islogical(x) && isscalar(x));

p.addParameter('TwoPanel', true, @(x) islogical(x) && isscalar(x));
p.addParameter('UseYYAxis', true, @(x) islogical(x) && isscalar(x));

p.parse(Envs, varargin{:});

azi_deg = p.Results.AzimuthDeg;
zen_deg = p.Results.ZenithDeg(:)';     % row
el_deg  = 90 - zen_deg;
az_vec  = azi_deg * ones(size(el_deg));
lw      = p.Results.LineWidth;

%% Resolve wavelengths
w = p.Results.Wavelengths;
if isempty(w)
    w = p.Results.Wavelength; % allow old name
end
if isempty(w)
    error('Wavelengths (or Wavelength) is required.');
end
w = w(:)'; % row
nW = numel(w);

nE = numel(Envs);

%% Determine "series" dimension:
% - If multiple envs AND multiple wavelengths, ambiguous; require user to choose.
if nE > 1 && nW > 1
    error(['RadTranVsZenith currently supports either (many Envs, 1 wavelength) ' ...
           'OR (1 Env, many wavelengths). You provided %d Envs and %d wavelengths.'], nE, nW);
end

if nE > 1
    nSeries = nE;
    seriesMode = "env";
elseif nW > 1
    nSeries = nW;
    seriesMode = "wavelength";
else
    nSeries = 1;
    seriesMode = "single";
end

%% Labels
labels = p.Results.Labels;
if isempty(labels)
    switch seriesMode
        case "env"
            labels = "Env " + (1:nSeries);
        case "wavelength"
            labels = arrayfun(@(x) sprintf('%dnm', round(x)), w, 'UniformOutput', false);
            labels = string(labels);
        otherwise
            labels = "Case 1";
    end
else
    labels = string(labels);
    if numel(labels) ~= nSeries
        error('Labels must have %d entries (one per plotted series).', nSeries);
    end
end

%% Colours
colors = p.Results.Colors;
if isempty(colors)
    colors = lines(nSeries);
end
if size(colors,1) ~= nSeries || size(colors,2) ~= 3
    error('Colors must be an Nx3 RGB array, where N = number of plotted series (%d).', nSeries);
end

%% Marker handling (must be valid marker or 'none')
marker = 'none';
if p.Results.ShowMarkers
    marker = 'o';
end

%% Figure name
if strlength(string(p.Results.FigureName)) == 0
    if nE == 1 && nW == 1
        figName = sprintf('Env slice at azi=%g deg, %gnm', azi_deg, w(1));
    elseif nE > 1
        figName = sprintf('Env compare at azi=%g deg, %gnm', azi_deg, w(1));
    else
        figName = sprintf('Wavelength compare at azi=%g deg', azi_deg);
    end
else
    figName = char(p.Results.FigureName);
end

fig = figure('Name', figName, 'NumberTitle', 'off');

useLog = lower(string(p.Results.RadianceScale)) == "log";

if p.Results.TwoPanel
    tiledlayout(1, 2, 'TileSpacing', char(p.Results.TileSpacing));

    % Radiance tile
    axR = nexttile; %#ok<NASGU>
    hold on; grid on;

    for k = 1:nSeries
        [Env_k, w_k] = getSeries(Envs, w, seriesMode, k);
        rad = Env_k.interp("spectral_radiance", az_vec, el_deg, w_k);

        if useLog
            semilogy(zen_deg, rad, 'Color', colors(k,:), 'LineWidth', lw, ...
                'DisplayName', labels(k), 'Marker', marker);
        else
            plot(zen_deg, rad, 'Color', colors(k,:), 'LineWidth', lw, ...
                'DisplayName', labels(k), 'Marker', marker);
        end
    end

    xlabel('Zenith (deg)', 'FontWeight', 'bold');
    ylabel('Spectral radiance (W/m^2/sr/nm)', 'FontWeight', 'bold');
    title('Radiance vs Zenith', 'FontWeight', 'bold');
    legend('Location', 'best');

    % Transmittance tile
    axT = nexttile;
    hold on; grid on;

    for k = 1:nSeries
        [Env_k, w_k] = getSeries(Envs, w, seriesMode, k);
        att = Env_k.interp("attenuation", az_vec, el_deg, w_k);

        plot(zen_deg, att, 'Color', colors(k,:), 'LineWidth', lw, ...
            'DisplayName', labels(k), 'Marker', marker);
    end

    xlabel('Zenith (deg)', 'FontWeight', 'bold');
    ylabel('Transmittance (probability)', 'FontWeight', 'bold');
    title('Transmittance vs Zenith', 'FontWeight', 'bold');
    legend('Location', 'best');

else
    % One panel mode: transmittance solid + radiance dashed
    hold on; grid on;

    if p.Results.UseYYAxis
        yyaxis left
    end

    % Transmittance solid
    for k = 1:nSeries
        [Env_k, w_k] = getSeries(Envs, w, seriesMode, k);
        att = Env_k.interp("attenuation", az_vec, el_deg, w_k);

        plot(zen_deg, att, '-', 'Color', colors(k,:), 'LineWidth', lw, ...
            'DisplayName', labels(k), 'Marker', marker);
    end
    ylabel('Transmittance', 'FontWeight', 'bold', 'FontWeight', 'bold');

    if p.Results.UseYYAxis
        yyaxis right
    end

    % Radiance dashed
    for k = 1:nSeries
        [Env_k, w_k] = getSeries(Envs, w, seriesMode, k);
        rad = Env_k.interp("spectral_radiance", az_vec, el_deg, w_k);

        if useLog && ~p.Results.UseYYAxis
        end

        plot(zen_deg, rad, '--', 'Color', colors(k,:), 'LineWidth', lw, ...
            'DisplayName', labels(k), 'Marker', marker);
    end
    ylabel('Radiance (W/m^2/sr/nm)', 'FontWeight', 'bold', 'FontWeight', 'bold');

    xlabel('Zenith (deg)', 'FontWeight', 'bold');
    title('Transmittance (solid) and Radiance (dashed) vs Zenith', 'FontWeight', 'bold');
    legend('Location', 'best');
end

end

% Help Function: pick the Env and wavelength for a given series k
function [Env_k, w_k] = getSeries(Envs, w, seriesMode, k)
switch seriesMode
    case "env"
        Env_k = Envs{k};
        w_k   = w(1);
    case "wavelength"
        Env_k = Envs{1};
        w_k   = w(k);
    otherwise
        Env_k = Envs{1};
        w_k   = w(1);
end
end