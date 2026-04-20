% Author: Brandon Reade
% Date: 19/04/2026
% Summary dashboard for a satellite pass including environment data

function fig = plotOrbitSummary(Result, Env, options)
% Options:
%   Mask              : "Elevation" | "Communication" | "Line of sight" | "None"
%   PolarOverlay      : "none" | "pass_points" | "sky_points" | "sky_field"
%     - none        : just the pass line in polaraxes
%     - pass_points : pass points colored by env value (polaraxes)
%     - sky_points  : all env samples as points (polaraxes) + pass line overlay
%     - sky_field   : continuous field using plots.polarpcolor (cartesian axes) + pass overlay
%                     DOES NOT WORK NEEDS FIXING
%
%   PolarData         : "transmittance" | "attenuation" | "attenuation dB" | "spectral_radiance"
%     - transmittance/attenuation are the same (0..1)
%     - attenuation dB as loss in dB: -10*log10(transmittance)
%
%   WavelengthNm      : scalar wavelength for Env.Interp
%   PolarPointSize    : marker size for polarscatter
%   PolarCLim         : [min max] for color scaling (optional)
%   SurfaceMetric     : metric string for plots.plotOrbitSurface
%   SurfaceYAxis      : "zenith" | "elevation"
%   IncludeTimeSeries : true/false
%   FigureName        : string

arguments
    Result (1,1) nodes.PassSimulationResult
    Env (1,1) environment.Environment

    options.Mask (1,1) string {mustBeMember(options.Mask, ["Elevation","Communication","Line of sight","None"])} = "Elevation"

    options.PolarOverlay (1,1) string {mustBeMember(options.PolarOverlay, ...
        ["none","pass_points","sky_points","sky_field"])} = "sky_points"

    options.PolarData (1,1) string {mustBeMember(options.PolarData, ...
        ["transmittance","attenuation","attenuation dB","spectral_radiance"])} = "transmittance"

    options.WavelengthNm (1,1) double = NaN
    options.PolarPointSize (1,1) double = 18
    options.PolarCLim (1,2) double = [NaN NaN]  % optional explicit color limits

    options.SurfaceMetric (1,1) string = "skr"
    options.SurfaceYAxis (1,1) string {mustBeMember(options.SurfaceYAxis, ["zenith","elevation"])} = "elevation"
    options.SurfacePlotType (1,1) string {mustBeMember(options.SurfacePlotType, ["scatter","trisurf"])} = "scatter"
    options.SurfaceUseLogZ (1,1) logical = true

    options.IncludeTimeSeries (1,1) logical = false
    options.FigureName (1,1) string = "Orbit Summary"
    options.GeoBasemap (1,1) string = "topographic"
end

mask = localMask(Result, options.Mask);

if isnan(options.WavelengthNm)
    options.WavelengthNm = Env.wavelengths(end);
end

fig = figure("Name", options.FigureName, "NumberTitle","off");

% layout
if options.IncludeTimeSeries
    % 2x3: [TS spans 1-2 | polar], [map | 3d | polar]
    tl = tiledlayout(fig, 2, 3, "TileSpacing","compact", "Padding","compact");
else
    % 2x2 with polar spanning right column
    tl = tiledlayout(fig, 2, 2, "TileSpacing","compact", "Padding","compact");
end

%%  Tile: Time series
if options.IncludeTimeSeries
    axTS = nexttile(tl, 1, [1 2]);
    hold(axTS, "on"); grid(axTS, "on");

    yyaxis(axTS, "left");
    plot(axTS, Result.time(mask), Result.secret_key_rate(mask), "-", "LineWidth", 1.4);
    plot(axTS, Result.time(mask), Result.sifted_key_rate(mask), ":", "LineWidth", 1.4);
    ylabel(axTS, "Key rate (bits/s)");
    xlabel(axTS, "Time");

    yyaxis(axTS, "right");
    plot(axTS, Result.time(mask), 100*Result.qber(mask), "-", "LineWidth", 1.0);
    ylabel(axTS, "QBER (%)");

    title(axTS, "Key rates + QBER");
    legend(axTS, ["Secret key rate","Sifted key rate","QBER"], "Location","best");
end

% Decide tile handles for map/polar/surface depending on layout
if options.IncludeTimeSeries
    axTilePolar = nexttile(tl, 3, [2 1]);                                   % span col3 both rows
    axTileMap   = nexttile(tl, 4, [1 1]);                                   % row2 col1
    axTileSurf  = nexttile(tl, 5, [1 1]);                                   % row2 col2
else
    axTileMap   = nexttile(tl, 1, [1 1]);                                   % row1 col1
    axTileSurf  = nexttile(tl, 3, [1 1]);                                   % row2 col1
    axTilePolar = nexttile(tl, 2, [2 1]);                                   % span right column
end

%% Map tile
posMap = axTileMap.Position;
set(axTileMap, "Visible","off");

panelMap = uipanel(fig, "Units","normalized", "Position", posMap, "BorderType","none");
gx = geoaxes(panelMap, "Units","normalized", "Position",[0.07 00.08 0.8 0.8]);
geobasemap(gx, options.GeoBasemap);
hold(gx, "on");

switch Result.direction
    case nodes.LinkDirection.Downlink
        geoplot(gx, Result.transmitter_location.Latitude, Result.transmitter_location.Longitude);
        geoplot(gx, Result.transmitter_location.Latitude(mask), Result.transmitter_location.Longitude(mask), "g");

        labels = ["Satellite path", options.Mask + " window"];
        rIdx = 1;
        for rx_loc = Result.receiver_location
            axes(gx); %#ok<LAXES>
            nodes.PassSimulationResult.PlotLOS(rx_loc, mean(Result.transmitter_location.Altitude), Result.elevation_limit(1));
            labels(end+1:end+2) = [Result.receiver_name{rIdx}, "Line-of-Sight"];
            rIdx = rIdx + 1;
        end

        legend(gx, labels, "Location","southwest");
        geolimits(gx, mean([Result.receiver_location.Latitude]) + [-4, 4], ...
                      mean([Result.receiver_location.Longitude]) + [-4, 4]);

    otherwise
        geoplot(gx, Result.receiver_location.Latitude, Result.receiver_location.Longitude);
        geoplot(gx, Result.receiver_location.Latitude(mask), Result.receiver_location.Longitude(mask), "g");

        labels = ["Satellite path", options.Mask + " window"];
        tIdx = 1;
        for tx_loc = Result.transmitter_location
            axes(gx); %#ok<LAXES>
            nodes.PassSimulationResult.PlotLOS(tx_loc, mean(Result.receiver_location.Altitude), Result.elevation_limit(1));
            labels(end+1:end+2) = [Result.transmitter_name{tIdx}, "Line-of-Sight"];
            tIdx = tIdx + 1;
        end

        legend(gx, labels, "Location","southwest");
        geolimits(gx, mean([Result.transmitter_location.Latitude]) + [-4, 4], ...
                      mean([Result.transmitter_location.Longitude]) + [-4, 4]);
end
title(gx, "Ground track + window");

%% Polar coordinates tile
posPolar = axTilePolar.Position;
set(axTilePolar, "Visible","off");
panelPolar = uipanel(fig, "Units","normalized", "Position", posPolar, "BorderType","none");

wl = options.WavelengthNm;

switch lower(string(options.PolarOverlay))

    case "none"
        pax = localCreatePolarAxes(panelPolar);
        hold(pax, "on");
        polarplot(pax, deg2rad(Result.heading(mask)), Result.elevation(mask), "g-", ...
            "LineWidth", 2, "DisplayName","Pass");
        localFormatPolarAxes(pax);
        title(pax, "Pass (polar)");
        legend(pax, "Location","southoutside");

    case "pass_points"
        pax = localCreatePolarAxes(panelPolar);
        hold(pax, "on");

        th = deg2rad(Result.heading(mask));
        rr = Result.elevation(mask);

        [envVals, cLabel] = localInterpEnvForPlot(Env, options.PolarData, ...
            abs(Result.heading(mask)), abs(Result.elevation(mask)), wl);

        polarscatter(pax, th, rr, options.PolarPointSize, envVals, "filled", ...
            "DisplayName","Pass points");

        % default CLim from full environment dataset
        [cmin,cmax] = localEnvCLim(Env, options.PolarData, wl);
        clim(pax, [cmin cmax]);

        cb = colorbar(pax, "eastoutside");
        cb.Label.String = cLabel;

        % user override
        if all(~isnan(options.PolarCLim))
            clim(pax, options.PolarCLim);
            cmin = options.PolarCLim(1);
            cmax = options.PolarCLim(2);
        end
        localApplyColorbarRange(cb, cmin, cmax);

        localFormatPolarAxes(pax);
        title(pax, "Pass colored by env");
        legend(pax, "Location","southoutside");

    case "sky_points"
        % All environment samples as points + pass line overlay (recommended for correctness)
        pax = localCreatePolarAxes(panelPolar);
        hold(pax, "on");

        [Hgrid, Egrid] = meshgrid(Env.headings, Env.elevations);
        Hq = Hgrid(:);
        Eq = Egrid(:);

        [V, cLabel] = localInterpEnvForPlot(Env, options.PolarData, Hq, Eq, wl);

        polarscatter(pax, deg2rad(Hq), Eq, options.PolarPointSize, V, "filled", ...
            "HandleVisibility","off");

        % default CLim from full environment dataset
        [cmin,cmax] = localEnvCLim(Env, options.PolarData, wl);
        clim(pax, [cmin cmax]);

        cb = colorbar(pax, "eastoutside");
        cb.Label.String = cLabel;

        % user override
        if all(~isnan(options.PolarCLim))
            clim(pax, options.PolarCLim);
            cmin = options.PolarCLim(1);
            cmax = options.PolarCLim(2);
        end
        localApplyColorbarRange(cb, cmin, cmax);

        % Overlay pass line (beacon style)
        polarplot(pax, deg2rad(Result.heading(mask)), Result.elevation(mask), ...
            "g-", "LineWidth", 2, "DisplayName","Pass");

        localFormatPolarAxes(pax);
        title(pax, "Sky points + pass overlay");
        legend(pax, "Location","southoutside");

    case "sky_field" % THIS NEEDS FIXING
        ax = axes(panelPolar, "Units","normalized", "Position",[0.07 0.08 0.8 0.8]);
        hold(ax, "on");
        axis(ax, "equal");
        axis(ax, "off");

        [Hgrid, Egrid] = meshgrid(Env.headings, Env.elevations);
        Hq = Hgrid(:);
        Eq = Egrid(:);

        [V, cLabel] = localInterpEnvForPlot(Env, options.PolarData, Hq, Eq, wl);
        V = reshape(V, size(Hgrid));   % (Ne x Nh)
        V = V.';                       % (Nh x Ne) for polarpcolor

        % Draw field with true env data range (no quantile clipping)
        axes(ax);
        if all(~isnan(options.PolarCLim))
            [axUsed, cb, map] = plots.polarpcolor(Env.headings, Env.elevations, V, ...
                Title = "", ...
                Colourbar = true, ...
                ColourBarLabel = cLabel, ...
                Interpreter = "tex", ...
                Normalisation = options.PolarCLim);
            cmin = options.PolarCLim(1);
            cmax = options.PolarCLim(2);
        else
            [axUsed, cb, map] = plots.polarpcolor(Env.headings, Env.elevations, V, ...
                Title = "", ...
                Colourbar = true, ...
                ColourBarLabel = cLabel, ...
                Interpreter = "tex", ...
                CLimMode = "range");
            [cmin,cmax] = localEnvCLim(Env, options.PolarData, wl);
        end

        localApplyColorbarRange(cb, cmin, cmax);

        % Overlay pass using EXACT same coordinate mapping as polarpcolor
        heading = Result.heading(mask);
        elev    = Result.elevation(mask);

        theta_plot = map.ThetaOffsetDeg + heading;    % 90 + heading
        r_norm = map.normaliseR(elev);

        x = r_norm .* cosd(theta_plot);
        y = r_norm .* sind(theta_plot);

        plot(axUsed, x, y, "g-", "LineWidth", 2, "DisplayName","Pass");

        title(axUsed, "Sky field + pass overlay");
        legend(axUsed, "Location","southoutside");

    otherwise
        error("Unknown PolarOverlay: %s", options.PolarOverlay);
end

% 3D orbit surface 
axes(axTileSurf);
cla(axTileSurf, "reset");
plots.plotOrbitSurface(Result, ...
    Mask = options.Mask, ...
    Metric = options.SurfaceMetric, ...
    XAxis = "heading", ...
    YAxis = options.SurfaceYAxis, ...
    PlotType = options.SurfacePlotType, ...
    UseLogZ = options.SurfaceUseLogZ, ...
    Title = "3D: " + options.SurfaceMetric + " vs heading/" + options.SurfaceYAxis, ...
    Axes = axTileSurf);

end

%% Functions
function mask = localMask(R, mode)
switch mode
    case "Elevation"
        mask = R.elevation_mask;
    case "Communication"
        mask = ~(isnan(R.secret_key_rate) | (R.secret_key_rate <= 0));
    case "Line of sight"
        mask = R.elevation > 0;
    case "None"
        mask = true(size(R.elevation));
end
mask = logical(mask(:));
end

function localFormatPolarAxes(pax)
set(pax, ...
    'ThetaZeroLocation','top', ...
    'ThetaDir','clockwise', ...
    'ThetaAxisUnits','degrees', ...
    'RDir','reverse', ...
    'RLim',[0,90], ...
    'RTick',[0,30,60,90], ...
    'RTickLabel',{'0^\circ','30^\circ','60^\circ','90^\circ'});
end

function [vals, label] = localInterpEnvForPlot(Env, polarData, headingsDeg, elevationsDeg, wl_nm)
pd = lower(string(polarData));

switch pd
    case {"transmittance","attenuation"}
        vals = Env.Interp("attenuation", headingsDeg, elevationsDeg, wl_nm);
        label = "Transmittance @ " + wl_nm + " nm";

    case "attenuation db"
        t = Env.Interp("attenuation", headingsDeg, elevationsDeg, wl_nm);
        vals = -10*log10(t); % loss in dB
        label = "Atmospheric loss (dB) @ " + wl_nm + " nm";

    case "spectral_radiance"
        vals = Env.Interp("spectral_radiance", headingsDeg, elevationsDeg, wl_nm);
        label = "Spectral radiance (W/m^2 sr nm) @ " + wl_nm + " nm";

    otherwise
        error("Unknown PolarData: %s. Use 'transmittance', 'attenuation dB', or 'spectral_radiance'.", polarData);
end

% guard against log(0) -> inf exploding the color scaling
vals(~isfinite(vals)) = NaN;
end

function [cmin, cmax] = localEnvCLim(Env, polarData, wl_nm)
    [Hgrid, Egrid] = meshgrid(Env.headings, Env.elevations);
    [V, ~] = localInterpEnvForPlot(Env, polarData, Hgrid(:), Egrid(:), wl_nm);
    V = V(isfinite(V));
    cmin = min(V); cmax = max(V);
end

function localApplyColorbarRange(cb, cmin, cmax)
    if isempty(cb) || ~isvalid(cb) || ~isfinite(cmin) || ~isfinite(cmax) || cmin == cmax
        return
    end
    nTicks = 6;
    cb.Ticks = linspace(cmin, cmax, nTicks);
end

function pax = localCreatePolarAxes(panelPolar)
    % leave margins so title/legend/colorbar don't clip
    pax = polaraxes(panelPolar, "Units","normalized", "Position",[0.08 0.09 0.74 0.76]);
end