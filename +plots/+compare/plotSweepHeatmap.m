function fig = plotSweepHeatmap(T, options)
% Plot a heatmap of Metric over XVar and YVar, optionally faceted by GroupBy.
%
% Example:
%   plots.sweep.plotSweepHeatmap(T, Metric="TotalSecretKeys", ...
%       XVar="WavelengthNm", YVar="RxDiam_m", GroupBy="TxDiam_m");
%
% Required columns typically produced by runQKDSweep:
%   WavelengthNm, TxDiam_m, RxDiam_m, SweepValue, TotalSecretKeys, etc.

arguments
    T table
    options.Metric (1,1) string
    options.XVar (1,1) string = "WavelengthNm"
    options.YVar (1,1) string = "RxDiam_m"
    options.GroupBy (1,1) string = ""                                       % e.g. "TxDiam_m",  empty means single heatmap
    options.FigureName (1,1) string = "Sweep Heatmap"
    options.ColorScale (1,1) string {mustBeMember(options.ColorScale,["linear","log"])} = "linear"
    options.Interp (1,1) string {mustBeMember(options.Interp,["none","nearest"])} = "none"
    options.Combine (1,1) string {mustBeMember(options.Combine,["max","min","mean"])} = "max"
    options.CLim (1,2) double = [NaN NaN]
    options.Colormap (1,1) string = "turbo"

    % tolerance used when mapping X/Y values into bins
    % This prevents mis-binning due to floating point equality issues.
    options.BinTol (1,1) double {mustBePositive} = 1e-9

    % Interpolation onto a dense grid for nicer continuous imagesc plots
    % When true, candidate wavelengths are interpolated onto a dense uniform grid.
    options.InterpolateToGrid (1,1) logical = false
    options.XGrid (:,1) double = []                                         % optional explicit x-grid
    options.NX (1,1) double {mustBeInteger,mustBePositive} = 400            % points for auto x-grid
    options.YGrid (:,1) double = []                                         % optional explicit y-grid
    options.NY (1,1) double {mustBeInteger,mustBePositive} = 300            % points for auto y-grid
    options.InterpMethod (1,1) string {mustBeMember(options.InterpMethod,["linear","nearest","pchip","makima"])} = "pchip"

    % overlay the original simulated sample locations on top of the heatmap
    options.ShowSamplePoints (1,1) logical = true
end

metric = options.Metric;
xv = options.XVar;
yv = options.YVar;

need = [metric, xv, yv];
for c = need
    if ~ismember(c, string(T.Properties.VariableNames))
        error("Missing column '%s' in T.", c);
    end
end

if strlength(options.GroupBy) > 0 && ~ismember(options.GroupBy, string(T.Properties.VariableNames))
    error("GroupBy column '%s' not in T.", options.GroupBy);
end

if strlength(options.GroupBy) == 0
    % groups must be one entry per row in T
    groups = ones(height(T), 1);
    groupVals = {[]};
else
    [groups, groupVals] = findgroups(T.(options.GroupBy));
end

nG = max(groups);
fig = figure('Name', options.FigureName, 'NumberTitle','off');

tl = tiledlayout(fig, ceil(nG/2), min(2,nG), "TileSpacing","compact", "Padding","compact");
title(tl, options.FigureName);

for g = 1:nG
    Tg = T(groups==g, :);

    x = Tg.(xv);
    y = Tg.(yv);
    z = Tg.(metric);

    xU = unique(x); xU = sort(xU);
    yU = unique(y); yU = sort(yU);

    % Build grid (y rows, x cols)
    Z = nan(numel(yU), numel(xU));

    % For mean-combine, we need sum + count
    if options.Combine == "mean"
        Zsum = zeros(numel(yU), numel(xU));
        Zcnt = zeros(numel(yU), numel(xU));
    end

    % tolerance-based binning
    for i = 1:height(Tg)
        xi = find(abs(xU - x(i)) <= options.BinTol, 1);
        yi = find(abs(yU - y(i)) <= options.BinTol, 1);

        if isempty(xi) || isempty(yi)
            continue;
        end

        zi = z(i);
        if ~isfinite(zi)
            continue;
        end

        if options.Combine == "mean"
            Zsum(yi,xi) = Zsum(yi,xi) + zi;
            Zcnt(yi,xi) = Zcnt(yi,xi) + 1;
        else
            if isnan(Z(yi,xi))
                Z(yi,xi) = zi;
            else
                switch options.Combine
                    case "max"
                        Z(yi,xi) = max(Z(yi,xi), zi);
                    case "min"
                        Z(yi,xi) = min(Z(yi,xi), zi);
                end
            end
        end
    end

    if options.Combine == "mean"
        Z(Zcnt > 0) = Zsum(Zcnt > 0) ./ Zcnt(Zcnt > 0);
        % Z remains NaN where count==0
    end

    if options.ColorScale == "log"
        Zp = Z;
        Zp(Zp <= 0) = nan;  % avoid log of nonpositive
        Zshow = log10(Zp);
        cbarLabel = "log10(" + metric + ")";
    else
        Zshow = Z;
        cbarLabel = metric;
    end

    % ===================== INTERPOLATION START =====================
    % If InterpolateToGrid=true, interpolate sparse candidate wavelengths
    % onto a dense grid for a nicer continuous imagesc plot.
    if options.InterpolateToGrid
        % Choose X and Y grids
        if isempty(options.XGrid)
            xDense = linspace(min(xU), max(xU), options.NX);
        else
            xDense = options.XGrid(:)';
        end

        if isempty(options.YGrid)
            yDense = linspace(min(yU), max(yU), options.NY);
        else
            yDense = options.YGrid(:);
        end

        % Interpolate along X for each Y row
        Zx = nan(numel(yU), numel(xDense));
        for r = 1:numel(yU)
            row = Zshow(r, :);
            valid = isfinite(row);
            if nnz(valid) < 2
                continue; % not enough points to interpolate
            end
            Zx(r, :) = interp1(xU(valid), row(valid), xDense, options.InterpMethod, NaN);
        end

        % Interpolate along Y for each X column
        Zxy = nan(numel(yDense), numel(xDense));
        for c = 1:numel(xDense)
            col = Zx(:, c);
            valid = isfinite(col);
            if nnz(valid) < 2
                continue;
            end
            Zxy(:, c) = interp1(yU(valid), col(valid), yDense, options.InterpMethod, NaN);
        end

        xPlot = xDense;
        yPlot = yDense;
        Zplot = Zxy;
    else
        xPlot = xU;
        yPlot = yU;
        Zplot = Zshow;
    end
    % ====================== INTERPOLATION END ======================

    ax = nexttile(tl, g);
    set(ax,'Color','k');                                                    % black for NaNs
    h = imagesc(ax, xPlot, yPlot, Zplot);
    set(ax,'YDir','normal');

    colormap(ax, feval(options.Colormap));
    if all(isfinite(options.CLim))
        caxis(ax, options.CLim);
    end

    % NaN transparent, so black background shows through
    set(h,'AlphaData', ~isnan(Zplot));

    % for "nearest" interpolation (image object interpolation, not data interpolation)
    if options.Interp == "nearest"
        try
            h.Interpolation = 'nearest';
        catch
            % older MATLAB version so do nothing
        end
    end

    xlabel(ax, xv);
    ylabel(ax, yv);
    grid(ax,'on');

    cb = colorbar(ax);
    cb.Label.String = cbarLabel;

    if strlength(options.GroupBy) > 0
        gv = groupVals(g);
        title(ax, options.GroupBy + "=" + string(gv));
    end

    % ===================== SAMPLE POINTS OVERLAY START =====================
    % Overlay original simulated points so you can see where data is real vs interpolated.
    if options.ShowSamplePoints
        [XX, YY] = meshgrid(xU, yU);
        validPts = isfinite(Zshow);
        hold(ax, 'on');
        plot(ax, XX(validPts), YY(validPts), 'k.', 'MarkerSize', 6);
        hold(ax, 'off');
    end
    % ====================== SAMPLE POINTS OVERLAY END ======================
end
end