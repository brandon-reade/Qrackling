function fig = LinkLossComparison(Results, varargin)
    %plots.compare.LinkLossComparison
    %
    % Compare link loss across multiple nodes.PassSimulationResult objects.
    %
    % Uses repo-accurate total loss from nodes.LossResult:
    %   - Preferred: result.loss.total_loss.dB  (dependent property wrapper)
    %   - Compatible fallback: result.loss.totalLoss().dB
    %
    % Modes:
    %   - "LossVsX"        : total loss (dB) vs Time/Elevation
    %   - "LossVsSKR"      : SKR vs total loss (x=loss dB), SKR on right y-axis.
    %                        Optionally overlay QBER (%) on left y-axis.
    %                        Optionally split SKR into approach/departure branches.
    %   - "ComponentsVsX"  : per-result component loss breakdown using
    %                        result.loss.plotLosses(...)
    %
    % Mask options match PassSimulationResult.plot():
    %   "Elevation" | "Communication" | "Line of sight" | "None"
    %
    % Notes:
    %       'SortByLoss', true        -> forces a single monotonic x curve (loses time order)
    %       'SplitBranches', true     -> explicitly label approach vs departure
    %
    % TODO:
    %   - Improve PlotQBER usability on wide/looped LossVsSKR traces
    
    p = inputParser;
    p.addRequired('Results', @(x) iscell(x) && ~isempty(x));
    
    p.addParameter('Mode', "LossVsX", @(x) isstring(x) || ischar(x));
    p.addParameter('X', "Time", @(x) isstring(x) || ischar(x));  % Time/Elevation (LossVsX, ComponentsVsX)
    p.addParameter('Mask', "Elevation", @(x) isstring(x) || ischar(x));
    
    p.addParameter('Wavelengths', [], @(x) isnumeric(x) || isempty(x));
    p.addParameter('Labels', [], @(x) isstring(x) || iscellstr(x) || isempty(x));
    p.addParameter('Colors', [], @(x) isnumeric(x) || isempty(x));
    p.addParameter('FigureName', "Link Loss Comparison", @(x) isstring(x) || ischar(x));
    p.addParameter('LineWidth', 1.8, @(x) isnumeric(x) && isscalar(x));
    
    p.addParameter('PlotSifted', false, @(x) islogical(x) && isscalar(x)); % LossVsSKR
    p.addParameter('PlotQBER', true, @(x) islogical(x) && isscalar(x));    % LossVsSKR
    
    % SKR-vs-loss controls
    p.addParameter('SortByLoss', false, @(x) islogical(x) && isscalar(x));
    p.addParameter('SplitBranches', false, @(x) islogical(x) && isscalar(x));
    p.addParameter('BranchMode', "maxElevation", @(x) isstring(x) || ischar(x)); % "maxElevation" | "minLoss"
    p.addParameter('BranchLabels', ["Approach","Departure"], @(x) (isstring(x) || iscellstr(x)) && numel(x)==2);
    
    p.parse(Results, varargin{:});
    
    if p.Results.SortByLoss && p.Results.SplitBranches
        error("Choose only one: SortByLoss=true OR SplitBranches=true.");
    end
    
    mode = lower(string(p.Results.Mode));
    N = numel(Results);
    
    labels = localMakeLabels(N, p.Results.Labels, p.Results.Wavelengths);
    
    colors = p.Results.Colors;
    if isempty(colors), colors = lines(N); end
    if size(colors,1) ~= N || size(colors,2) ~= 3
        error('Colors must be an Nx3 RGB array, N=numel(Results).');
    end
    lw = p.Results.LineWidth;
    
    fig = figure('Name', p.Results.FigureName, 'NumberTitle','off');
    
    switch mode
        case "lossvsx"
            ax = axes(fig); hold(ax,'on'); grid(ax,'on');
    
            for i = 1:N
                R = Results{i};
                mask = localMask(R, p.Results.Mask);
    
                [x, xlab] = localGetX(R, p.Results.X);
                LdB = localTotalLossdB(R);
    
                x = x(:); LdB = LdB(:);
                if numel(x) ~= numel(LdB)
                    error("Case %d length mismatch: numel(x)=%d numel(loss)=%d", i, numel(x), numel(LdB));
                end
    
                plot(ax, x(mask), LdB(mask), ...
                    'LineWidth', lw, 'Color', colors(i,:), ...
                    'DisplayName', labels(i));
            end
    
            xlabel(ax, xlab, 'FontWeight','bold');
            ylabel(ax, 'Total link loss (dB)', 'FontWeight','bold');
            title(ax, p.Results.FigureName, 'FontWeight','bold');
            legend(ax, 'Location','best');
    
        case "lossvsskr"
            ax = axes(fig);
            hold(ax,'on');
    
            % Always plot SKR on the RIGHT axis
            % Make right-axis major/minor ticks clearly visible
            yyaxis(ax, "right");
            ax.YAxis(2).MinorTick = 'on';
            ax.YAxis(2).TickDirection = 'out';
            ax.YAxis(2).TickLength = [0.018 0.030];   % [major minor] -> enlarge minor
            ax.YAxis(2).Color = [0.85 0.325 0.098];   % explicit orange for axis + ticks
            ax.YAxis(2).LineWidth = 1.1;
            
            % Ensure minor ticks are actually generated on a log scale
            set(ax, 'YScale', 'log');
            ylabel(ax, 'Key rate (bits/s)', 'FontWeight','bold');
            
            % Ensure grid visually matches logarithmic scaling on SKR axis
            ax.YAxis(2).MinorTick = 'on';     % minor ticks at log sub-decades
            ax.YMinorGrid = 'on';             % show minor horizontal grid lines
            ax.GridAlpha = 0.22;              % major grid intensity
            ax.MinorGridAlpha = 0.14;         % minor grid intensity
            ax.XGrid = 'on';
            ax.YGrid = 'on';
    
            branchLabels = string(p.Results.BranchLabels);
    
            for i = 1:N
                R = Results{i};
                mask = localMask(R, p.Results.Mask);
    
                LdB_full = localTotalLossdB(R);         % full-length
                LdB = LdB_full(mask);
                skr = R.secret_key_rate(mask);
    
                % Optionally plot sifted too
                sift = [];
                if p.Results.PlotSifted
                    sift = R.sifted_key_rate(mask);
                end
    
                if p.Results.SortByLoss
                    [LdB, idx] = sort(LdB);
                    skr = skr(idx);
                    if p.Results.PlotSifted, sift = sift(idx); end
    
                    plot(ax, LdB, skr, ...
                        '-', 'LineWidth', lw, 'Color', colors(i,:), ...
                        'DisplayName', labels(i) + " secret");
    
                    if p.Results.PlotSifted
                        plot(ax, LdB, sift, ...
                            ':', 'LineWidth', 1.2, 'Color', colors(i,:), ...
                            'DisplayName', labels(i) + " sifted");
                    end
    
                elseif p.Results.SplitBranches
                    splitIdxFull = localBranchSplitIndex(R, p.Results.BranchMode, LdB_full);
    
                    % Convert split index (full vector) into masked coordinate
                    maskedPos = find(mask);
                    k = find(maskedPos == splitIdxFull, 1, "first");
    
                    if isempty(k)
                        % Split point not present after masking; fall back to single curve
                        plot(ax, LdB, skr, ...
                            '-', 'LineWidth', lw, 'Color', colors(i,:), ...
                            'DisplayName', labels(i) + " secret");
                        if p.Results.PlotSifted
                            plot(ax, LdB, sift, ...
                                ':', 'LineWidth', 1.2, 'Color', colors(i,:), ...
                                'DisplayName', labels(i) + " sifted");
                        end
                    else
                        % Approach: from start to split
                        plot(ax, LdB(1:k), skr(1:k), ...
                            '-', 'LineWidth', lw, 'Color', colors(i,:), ...
                            'DisplayName', labels(i) + " (" + branchLabels(1) + ")");
    
                        % Departure: from split to end
                        plot(ax, LdB(k:end), skr(k:end), ...
                            '--', 'LineWidth', lw, 'Color', colors(i,:), ...
                            'DisplayName', labels(i) + " (" + branchLabels(2) + ")");
    
                        if p.Results.PlotSifted
                            plot(ax, LdB(1:k), sift(1:k), ...
                                ':', 'LineWidth', 1.2, 'Color', colors(i,:), ...
                                'DisplayName', labels(i) + " sifted (" + branchLabels(1) + ")");
                            plot(ax, LdB(k:end), sift(k:end), ...
                                '-.', 'LineWidth', 1.2, 'Color', colors(i,:), ...
                                'DisplayName', labels(i) + " sifted (" + branchLabels(2) + ")");
                        end
                    end
    
                else
                    % Default: plot in time order (can show loop visually)
                    plot(ax, LdB, skr, ...
                        '-', 'LineWidth', lw, 'Color', colors(i,:), ...
                        'DisplayName', labels(i) + " secret");
    
                    if p.Results.PlotSifted
                        plot(ax, LdB, sift, ...
                            ':', 'LineWidth', 1.2, 'Color', colors(i,:), ...
                            'DisplayName', labels(i) + " sifted");
                    end
                end
            end
    
            % Optional QBER on the LEFT axis
            if p.Results.PlotQBER
                yyaxis(ax, "left");
                ylabel(ax, 'QBER (%)', 'FontWeight','bold');
                ax.YAxis(1).MinorTick = 'off';   % keep left axis from adding dense minor marks
    
                for i = 1:N
                    R = Results{i};
                    mask = localMask(R, p.Results.Mask);
    
                    LdB_full = localTotalLossdB(R);
                    LdB = LdB_full(mask);
    
                    plot(ax, LdB, 100*R.qber(mask), ...
                        '--', 'LineWidth', 1.0, ...
                        'Color', colors(i,:)*0.65 + 0.35, ...
                        'HandleVisibility','off');
                end
            else
                % Hide left axis completely (no ticks, no label, no axis line)
                yyaxis(ax, "left");
                ax.YAxis(1).Visible = "off";
                ax.YAxis(1).Color = 'none';      % prevent left-axis color/grid artifacts
                ax.YAxis(1).TickValues = [];     % no left ticks
                % Ensure right axis remains visible
                yyaxis(ax, "right");
                ax.YAxis(2).Visible = "on";
            end
    
            % IMPORTANT: make RIGHT axis active at end so Y-grid is drawn from log axis
            yyaxis(ax, "right");
            set(ax, 'YScale','log');
            ax.YAxis(2).MinorTick = 'on';
            ax.YMinorGrid = 'on';
            ax.XGrid = 'on';
            ax.YGrid = 'on';
            ax.GridAlpha = 0.22;
            ax.MinorGridAlpha = 0.14;
    
            xlabel(ax, 'Total link loss (dB)', 'FontWeight','bold');
            title(ax, p.Results.FigureName, 'FontWeight','bold');
            legend(ax, 'Location','best');
    
        case "componentsvsx"
            % One panel per system; use LossResult.plotLosses for consistency
            tl = tiledlayout(fig, N, 1, "TileSpacing","compact", "Padding","compact");
            title(tl, p.Results.FigureName);
    
            for i = 1:N
                R = Results{i};
                mask = localMask(R, p.Results.Mask);
                [x, xlab] = localGetX(R, p.Results.X);
    
                ax = nexttile(tl, i);
                cla(ax);
                axes(ax); %#ok<LAXES> % make tile current for legacy plotLosses signature
    
                % LossResult.plotLosses currently accepts:
                %   plotLosses(x_axis, x_label, options)
                % with options.mask only (no options.axes in current repo version).
                R.loss.plotLosses(x, xlab, "mask", mask);
    
                title(ax, labels(i), "Interpreter","none");
                grid(ax,'on');
                xlim(ax, [min(x(mask)), max(x(mask))]);
            end
    
        otherwise
            error("Unknown Mode='%s'. Use 'LossVsX', 'LossVsSKR', or 'ComponentsVsX'.", p.Results.Mode);
    end

end

% ---------------- helpers ----------------

function labels = localMakeLabels(N, Labels, Wavelengths)
    if ~isempty(Labels)
        labels = string(Labels);
        if numel(labels) ~= N, error("Labels must have length N."); end
    elseif ~isempty(Wavelengths)
        if numel(Wavelengths) ~= N, error("Wavelengths must have length N."); end
        labels = string(arrayfun(@(x) sprintf('%dnm', round(x)), Wavelengths, 'UniformOutput', false));
    else
        labels = "Case " + (1:N);
    end
end

function mask = localMask(R, mode)
    mode = lower(string(mode));
    switch mode
        case "elevation"
            mask = R.elevation_mask;
        case "communication"
            mask = ~(isnan(R.secret_key_rate) | (R.secret_key_rate <= 0));
        case "line of sight"
            mask = R.elevation > 0;
        case "none"
            mask = true(size(R.elevation));
        otherwise
            error("Mask must be 'Elevation','Communication','Line of sight','None'.");
    end
    mask = logical(mask(:));
end

function [x, xlab] = localGetX(R, xMode)
    xMode = lower(string(xMode));
    switch xMode
        case "time"
            x = R.time(:);
            xlab = "Time";
        case "elevation"
            x = R.elevation(:);
            xlab = "Elevation (deg)";
        otherwise
            error("X must be 'Time' or 'Elevation'.");
    end
end

function LdB = localTotalLossdB(R)
    % Repo-accurate for current LossResult implementation:
    %   total_loss is a dependent property that wraps totalLoss().
    LR = R.loss;
    
    % Preferred path (current repo): dependent property
    if isprop(LR, "total_loss")
        TL = LR.total_loss;   % units.Loss
        LdB = localLossToDbVector(TL);
        return;
    end
    
    % Backward/forward compatibility: method call
    if any(strcmp(methods(LR), "totalLoss"))
        TL = LR.totalLoss();  % units.Loss
        LdB = localLossToDbVector(TL);
        return;
    end
    
    error("Unable to compute total loss dB: expected result.loss.total_loss or result.loss.totalLoss().");
end

function LdB = localLossToDbVector(TL)
    % Convert units.Loss -> numeric dB vector across API variants:
    %   - property style: TL.dB
    %   - method style:   TL.dB()

    % Preferred: method call if available
    if any(strcmp(methods(TL), "dB"))
        try
            LdB = TL.dB();
            LdB = LdB(:);
            return;
        catch
            % fall through and try property-style access
        end
    end
    % Property-style fallback
    try
        LdB = TL.dB;
        LdB = LdB(:);
        return;
    catch
    end
    
    error("Unable to extract dB from units.Loss. Expected TL.dB() or TL.dB.");
end

function splitIdxFull = localBranchSplitIndex(R, branchMode, LdB_full)
    % Choose a split point for "approach" vs "departure" using full (unmasked) arrays.
    % - maxElevation: split at maximum elevation (common proxy for closest approach)
    % - minLoss:      split at minimum loss (often similar to max elevation)
    
    branchMode = lower(string(branchMode));
    switch branchMode
        case "maxelevation"
            [~, splitIdxFull] = max(R.elevation(:));
        case "minloss"
            [~, splitIdxFull] = min(LdB_full(:));
        otherwise
            error("BranchMode must be 'maxElevation' or 'minLoss'.");
    end
end