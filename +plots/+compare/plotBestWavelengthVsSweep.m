% Author: Brandon Reade
% Date: 22/04/2026
% Plot the best achieved metric vs the sweep parameter, choosing the
% wavelength that is considered the "best" at each sweep point

function fig = plotBestWavelengthVsSweep(T, options)
    % Inputs
    %   T : table returned by runQKDSweep
    %
    % Options
    %   Metric      : table column to optimize and plot (e.g., "TotalSecretKeys", "PeakSKR_bps", "MeanQBER", "MinLoss_dB")
    %   GroupBy     : grouping vars for separate lines (e.g., ["TxDiam_m"])
    %   BestMode    : "max" | "min"   (use "min" for QBER-type metrics)
    %   ShowBestWavelengthLabels : annotate points with best wavelength (nm)
    %   FigureName  : figure title
    %   YScale      : "linear" | "log"

    
    arguments
        T table
        options.Metric (1,1) string = "TotalSecretKeys"
        options.GroupBy (1,:) string = "TxDiam_m"
        options.BestMode (1,1) string {mustBeMember(options.BestMode,["max","min"])} = "max"
        options.ShowBestWavelengthLabels (1,1) logical = false
        options.FigureName (1,1) string = "Best wavelength vs sweep"
        options.YScale (1,1) string {mustBeMember(options.YScale,["linear","log"])} = "linear"
    end
    
    metric = options.Metric;
    
    % Validate required columns
    required = ["SweepValue","SweepVar","WavelengthNm",metric];
    for c = required
        if ~ismember(c, string(T.Properties.VariableNames))
            error("Missing required column '%s' in input table.", c);
        end
    end
    
    % Validate GroupBy columns
    for gb = options.GroupBy
        if ~ismember(gb, string(T.Properties.VariableNames))
            error("GroupBy column '%s' not found in input table.", gb);
        end
    end
    
    % Grouping
    G = findgroups(T(:, cellstr(options.GroupBy)));
    nG = max(G);
    
    fig = figure('Name', options.FigureName, 'NumberTitle','off');
    ax = axes(fig); hold(ax,'on'); grid(ax,'on');
    if options.YScale == "log"
        set(ax,'YScale','log');
    end
    
    colors = lines(max(nG,1));
    
    for g = 1:nG
        Tg = T(G==g, :);
    
        sweepVals = unique(Tg.SweepValue);
        sweepVals = sort(sweepVals);
    
        x = sweepVals(:);
        y = nan(size(x));
        bestW = nan(size(x));
    
        for i = 1:numel(sweepVals)
            sv = sweepVals(i);
            cand = Tg(Tg.SweepValue == sv, :);
    
            vals = cand.(metric);
    
            % drop NaNs to avoid picking them as max/min
            valid = isfinite(vals);
            cand = cand(valid,:);
            vals = vals(valid);
    
            if isempty(vals)
                % no valid data at this sweep point
                y(i) = NaN;
                bestW(i) = NaN;
                continue;
            end
    
            if options.BestMode == "max"
                [~, idx] = max(vals);
            else
                [~, idx] = min(vals);
            end
            best = cand(idx, :);
    
            y(i) = best.(metric);
            bestW(i) = best.WavelengthNm;
        end
    
        lgdLabel = localGroupLabel(Tg, options.GroupBy);
    
        plot(ax, x, y, '-o', ...
            'LineWidth', 1.8, ...
            'Color', colors(g,:), ...
            'DisplayName', lgdLabel);
    
        if options.ShowBestWavelengthLabels
            for i = 1:numel(x)
                if ~isfinite(y(i)) || ~isfinite(bestW(i))
                    continue;
                end
                text(ax, x(i), y(i), sprintf(" %dnm", round(bestW(i))), ...
                    'Color', colors(g,:), 'FontSize', 9);
            end
        end
end

    sv = string(T.SweepVar(1));
    xlabel(ax, sv + " (" + localSweepUnitHint(sv) + ")");
    ylabel(ax, metric);
    title(ax, options.FigureName);
    legend(ax, 'Location','best');
end

function s = localGroupLabel(Tg, groupBy)
    parts = strings(1, numel(groupBy));
    for k = 1:numel(groupBy)
        var = groupBy(k);
        val = Tg.(var)(1);
        parts(k) = var + "=" + string(val);
    end
    s = strjoin(parts, ", ");
end

function u = localSweepUnitHint(sweepVar)
    switch lower(string(sweepVar))
        case "rxdiam"
            u = "m";
        case "txdiam"
            u = "m";
        case "spectralfilterwidthnm"
            u = "nm";
        case "timegatewidth"
            u = "s";
        case "rxfov"
            u = "rad";
        otherwise
            u = "";
    end
end