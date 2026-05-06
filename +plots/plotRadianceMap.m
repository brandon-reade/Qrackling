function plotRadianceMap(Env, wavelength_nm, options)
% Plot spectral radiance vs azimuth/zenith.
%
% Supports:
%   - 3D surface ("surf")
%   - 3D block bars ("bars")
%   - 2D tiled map ("2D" view)
%   - comparison against a reference wavelength (ratio/diff/dB)
% To do:
%   - allow an option to not use shared colours on subplots

    arguments
        Env
        wavelength_nm (1,:) double
        options.AzimuthDeg (:,1) double = (0:5:355)'
        options.ZenithDeg  (:,1) double = (0:5:90)'
        options.Title (1,1) string = ""
        options.UseLogZ (1,1) logical = false

        % View modes
        options.View (1,1) string {mustBeMember(options.View, ["3D","2D"])} = "3D"
        options.Mode (1,1) string {mustBeMember(options.Mode, ["surf", "bars"])} = "surf" % only used for View=3D
        options.BarLineWidth (1,1) double = 2                               % only used for old stem bars (not used by block bars)

        % Figure mode
        options.FigureMode (1,1) string {mustBeMember(options.FigureMode, ["separate","subplots"])} = "separate"
        options.SubplotShape (1,2) double = [NaN NaN]                       % [rows cols], NaN makes it auto
        options.IndependentColorbars (1,1) logical = true                   % if true, each subplot uses its own CLim and colorbar scaling

        % Comparison controls
        options.CompareMode (1,1) string {mustBeMember(options.CompareMode, ["none","ratio","diff","dB"])} = "none"
        options.ReferenceWavelength (1,1) double = NaN                      % use when you want to specify reference explicitly
        options.ReferenceIndex (1,1) double {mustBeInteger, mustBePositive} = 1 % use when ref is just "first wavelength"
        options.OmitReferencePlot (1,1) logical = true

        % 2D controls
        options.TwoDStyle (1,1) string {mustBeMember(options.TwoDStyle, ["tiles","pcolor"])} = "tiles"
        options.ColorLimits (1,2) double = [NaN NaN] % [cmin cmax], NaN makes it automatic
    end

    az = options.AzimuthDeg(:);
    zen = options.ZenithDeg(:);

    [AZ, ZEN] = meshgrid(az, zen);
    EL = 90 - ZEN;

    % compute radiance cube: (nZen x nAz x nW)
    nW = numel(wavelength_nm);
    R = zeros(size(AZ,1), size(AZ,2), nW);
    for iw = 1:nW
        R(:,:,iw) = Env.Interp("spectral_radiance", AZ, EL, wavelength_nm(iw));
    end

    % transform: log or linear radiance base
    if options.UseLogZ
        base = log10(max(R, eps));
        baseLabel = "log10 Spectral radiance (W m^{-2} sr^{-1} nm^{-1})";
    else
        base = R;
        baseLabel = "Spectral radiance (W m^{-2} sr^{-1} nm^{-1})";
    end

    % compute reference base explicitly if requested and not in wavelength list
    refBase = [];
    if options.CompareMode ~= "none" && isfinite(options.ReferenceWavelength)
        % If ref wavelength not exactly in list, compute it explicitly
        if ~any(abs(wavelength_nm - options.ReferenceWavelength) < 1e-9)
            % Compute radiance at reference wavelength on the same grid
            Rref = Env.Interp("spectral_radiance", AZ, EL, options.ReferenceWavelength);
            if options.UseLogZ
                refBase = log10(max(Rref, eps));
            else
                refBase = Rref;
            end
        end
    end

    % comparison transform
    [plotData, plotLabel, legendNames, keepMask] = applyComparison(base, wavelength_nm, options, baseLabel, refBase);

    % apply omit-reference filtering (only meaningful when reference is in-list)
    if exist("keepMask", "var") && ~isempty(keepMask)
        plotData = plotData(:,:,keepMask);
        legendNames = legendNames(keepMask);
    end

    % plotData is (nZen x nAz x nPlots)
    nPlots = size(plotData, 3);

    % Compute edges for "block/tile" look
    az_edges  = localEdges(az(:)');
    zen_edges = localEdges(zen(:)');

    % Decide figure layout
    if options.FigureMode == "subplots"
        fig = figure('Name', "Radiance map(s)");
        if all(isfinite(options.SubplotShape))
            tl = tiledlayout(fig, options.SubplotShape(1), options.SubplotShape(2), ...
                "TileSpacing","compact", "Padding","compact");
        else
            % auto shape: roughly square
            r = ceil(sqrt(nPlots));
            c = ceil(nPlots / r);
            tl = tiledlayout(fig, r, c, "TileSpacing","compact", "Padding","compact");
        end
    else
        tl = [];
    end

    % Determine shared color scaling when using subplots (unless user provides ColorLimits)
    useSharedCLim = (options.FigureMode == "subplots") ...
                && ~options.IndependentColorbars ...
                && any(isnan(options.ColorLimits));
    if useSharedCLim
        shared_cmin = min(plotData(:), [], "omitnan");
        shared_cmax = max(plotData(:), [], "omitnan");
        if ~isfinite(shared_cmin) || ~isfinite(shared_cmax) || shared_cmin == shared_cmax
            shared_cmin = 0; shared_cmax = shared_cmin + 1;
        end
        shared_clim = [shared_cmin, shared_cmax];
    else
        shared_clim = options.ColorLimits;
    end

    for ip = 1:nPlots
        Zplot = plotData(:,:,ip);

        if options.IndependentColorbars || options.FigureMode ~= "subplots"
            cmin = min(Zplot(:), [], "omitnan");
            cmax = max(Zplot(:), [], "omitnan");
            if ~isfinite(cmin) || ~isfinite(cmax) || cmin == cmax
                cmin = 0; cmax = cmin + 1;
            end
            local_clim = [cmin cmax];
        else
            local_clim = shared_clim;
        end

        if options.FigureMode == "subplots"
            ax = nexttile(tl);
            hold(ax, "on");
        end

        %% 3D view
        if options.View == "3D"
            if options.FigureMode ~= "subplots"
                figure('Name', sprintf('Radiance map %s', legendNames(ip)));
                ax = axes(); hold(ax, "on");
            end

            switch options.Mode
                % surf mode
                case "surf"
                    surf(ax, AZ, ZEN, Zplot, 'EdgeColor', 'none');

                % bars mode
                case "bars"
                    cmap = turbo(256);
                    colormap(ax, cmap);

                    % Use shared limits (subplots) or per-plot limits (separate) for color mapping
                    if options.FigureMode == "subplots"
                        zmin = local_clim(1);
                        zmax = local_clim(2);
                    else
                        zmin = min(Zplot(:), [], 'omitnan');
                        zmax = max(Zplot(:), [], 'omitnan');
                        if ~isfinite(zmin) || ~isfinite(zmax) || zmin == zmax
                            zmin = 0; zmax = zmin + 1;
                        end
                    end

                    for iz = 1:numel(zen)
                        for ia = 1:numel(az)
                            zval = Zplot(iz, ia);
                            if ~isfinite(zval), continue; end

                            x0 = az_edges(ia);   x1 = az_edges(ia+1);
                            y0 = zen_edges(iz);  y1 = zen_edges(iz+1);
                            % allow negative bars (difference plots) to extend below 0
                            z0 = min(0, zval);   z1 = max(0, zval);

                            ci = 1 + round(255 * (zval - zmin) / (zmax - zmin));
                            ci = max(1, min(256, ci));
                            faceColor = cmap(ci, :);

                            % top face (cap) at the far end
                            ztop = z1;
                            if zval < 0
                                ztop = z0;
                            end

                            patch(ax, [x0 x1 x1 x0], [y0 y0 y1 y1], [ztop ztop ztop ztop], faceColor, ...
                                'EdgeColor','none', 'FaceAlpha',1.0);

                            % sides
                            localAddSides(ax, x0,x1,y0,y1,z0,z1, faceColor);
                        end
                    end

                    xlim(ax, [az_edges(1) az_edges(end)]);
                    ylim(ax, [zen_edges(1) zen_edges(end)]);
            end

            xlabel(ax, 'Azimuth (deg)');
            ylabel(ax, 'Zenith (deg)');
            zlabel(ax, plotLabel);
            grid(ax, 'on');
            view(ax, 45, 35);

            cb = colorbar(ax);
            ylabel(cb, plotLabel);

            applyCLim(ax, local_clim);
            title(ax, composeTitle(options.Title, legendNames(ip)));

            hold(ax, "off");

        %% 2D view
        else
            if options.FigureMode ~= "subplots"
                figure('Name', sprintf('Radiance map (2D) %s', legendNames(ip)));
                ax = axes(); hold(ax, "on");
            end

            cmap = turbo(256);
            colormap(ax, cmap);

            switch options.TwoDStyle
                case "tiles"
                    % draw filled rectangles for each bin

                    % Use shared limits (subplots) or per-plot limits (separate) for color mapping
                    if options.FigureMode == "subplots"
                        cmin = local_clim(1);
                        cmax = local_clim(2);
                    else
                        cmin = min(Zplot(:), [], 'omitnan');
                        cmax = max(Zplot(:), [], 'omitnan');
                        if ~isfinite(cmin) || ~isfinite(cmax) || cmin == cmax
                            cmin = 0; cmax = cmin + 1;
                        end
                    end

                    for iz = 1:numel(zen)
                        for ia = 1:numel(az)
                            zval = Zplot(iz, ia);
                            if ~isfinite(zval), continue; end

                            x0 = az_edges(ia);   x1 = az_edges(ia+1);
                            y0 = zen_edges(iz);  y1 = zen_edges(iz+1);

                            ci = 1 + round(255 * (zval - cmin) / (cmax - cmin));
                            ci = max(1, min(256, ci));
                            faceColor = cmap(ci, :);

                            patch(ax, [x0 x1 x1 x0], [y0 y0 y1 y1], [1 1 1 1], faceColor, ...
                                'EdgeColor', 'none');
                        end
                    end
                    axis(ax, "tight");

                case "pcolor"
                    % Use surf in 2D projection:
                    surf(ax, AZ, ZEN, zeros(size(Zplot)), Zplot, 'EdgeColor', 'none');
                    view(ax, 2);
            end

            xlabel(ax, 'Azimuth (deg)');
            ylabel(ax, 'Zenith (deg)');
            title(ax, composeTitle(options.Title, legendNames(ip)));

            cb = colorbar(ax);
            ylabel(cb, plotLabel);

            applyCLim(ax, local_clim);

            grid(ax, 'on');
            hold(ax, "off");
        end

        % If we are in subplot mode, keep holding off for that tile only
        if options.FigureMode == "subplots"
            hold(ax, "off");
        end
    end
end

%% Functions

function titleOut = composeTitle(baseTitle, suffix)
    if baseTitle ~= ""
        titleOut = baseTitle + " — " + suffix;
    else
        titleOut = suffix;
    end
end

function applyCLim(ax, cl)
    if numel(cl) == 2 && all(isfinite(cl))
        clim(ax, cl);
    end
end

function edges = localEdges(centers)
    centers = centers(:)';
    N = numel(centers);
    if N == 1
        edges = [centers(1)-0.5, centers(1)+0.5];
        return;
    end
    mids = (centers(1:end-1) + centers(2:end)) / 2;
    first = centers(1) - (mids(1) - centers(1));
    last  = centers(end) + (centers(end) - mids(end));
    edges = [first, mids, last];
end

function localAddSides(ax, x0,x1,y0,y1,z0,z1, faceColor)
    sideColor = 0.85 * faceColor;

    % +x face
    patch(ax, [x1 x1 x1 x1], [y0 y1 y1 y0], [z0 z0 z1 z1], sideColor, 'EdgeColor','none');
    % -x face
    patch(ax, [x0 x0 x0 x0], [y0 y0 y1 y1], [z0 z1 z1 z0], sideColor, 'EdgeColor','none');
    % +y face
    patch(ax, [x0 x1 x1 x0], [y1 y1 y1 y1], [z0 z0 z1 z1], sideColor, 'EdgeColor','none');
    % -y face
    patch(ax, [x0 x1 x1 x0], [y0 y0 y0 y0], [z0 z1 z1 z0], sideColor, 'EdgeColor','none');
end

function [plotData, plotLabel, legendNames, keepMask] = applyComparison(base, wls, options, baseLabel, refBase)
    % base: nZen x nAz x nW, already log or linear depending on UseLogZ
    nW = numel(wls);

    if options.CompareMode == "none"
        plotData = base;
        plotLabel = baseLabel;
        legendNames = "wl=" + string(round(wls)) + "nm";
        keepMask = true(1, nW);
        return;
    end

    % pick reference
    if nargin >= 5 && ~isempty(refBase)
        ref = refBase;
        refIdx = NaN;
        refName = sprintf("%dnm", round(options.ReferenceWavelength));
    else
        if isfinite(options.ReferenceWavelength)
            [~, refIdx] = min(abs(wls - options.ReferenceWavelength));
        else
            refIdx = options.ReferenceIndex;
            if refIdx > nW, error("ReferenceIndex exceeds number of wavelengths."); end
        end
        ref = base(:,:,refIdx);
        refName = sprintf("%dnm", round(wls(refIdx)));
    end

    plotData = zeros(size(base));
    legendNames = strings(1,nW);

    for iw = 1:nW
        cur = base(:,:,iw);
        legendNames(iw) = sprintf("%dnm vs reference=%s", round(wls(iw)), refName);

        switch options.CompareMode
            case "ratio"
                % ratio only makes sense for linear radiance, not log(radiance)
                errorIfLog(options.UseLogZ, "ratio");
                plotData(:,:,iw) = cur ./ max(ref, eps);
                plotLabel = "Radiance ratio (R / R_{ref})";

            case "diff"
                plotData(:,:,iw) = cur - ref;
                plotLabel = baseLabel + " difference (minus ref)";

            case "dB"
                % dB difference is valid in linear space; if UseLogZ=true it's redundant.
                errorIfLog(options.UseLogZ, "dB");
                plotData(:,:,iw) = 10*log10(max(cur, eps) ./ max(ref, eps));
                plotLabel = "Radiance difference (dB): 10log10(R/R_{ref})";
        end
    end

    % Optionally omit reference plot (only if reference is in wls)
    keepMask = true(1, nW);
    if options.OmitReferencePlot && ~isnan(refIdx)
        keepMask(refIdx) = false;
    end
end

function errorIfLog(useLog, modeName)
    if useLog
        error("CompareMode='%s' requires UseLogZ=false (operate in linear radiance).", modeName);
    end
end