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
    groups = 1;
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
    for i = 1:height(Tg)
        xi = find(xU==x(i), 1);
        yi = find(yU==y(i), 1);
        % If duplicates exist, take max (often desired for metrics)
        if isnan(Z(yi,xi))
            Z(yi,xi) = z(i);
        else
            Z(yi,xi) = max(Z(yi,xi), z(i));
        end
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

    ax = nexttile(tl, g);
    if options.Interp == "nearest"
        imagesc(ax, xU, yU, Zshow);
        set(ax,'YDir','normal');
    else
        % 'none' => show as pixels but aligned
        imagesc(ax, xU, yU, Zshow);
        set(ax,'YDir','normal');
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
end
end