% Author: Brandon Reade
% Date: 11/03/2026

function figs = LossComparison(Results, varargin)
% Plot total and component losses for multiple results.
%
% Expects each Results{i}.loss has:
%   - .Names (cellstr of component names)
%   - .total_loss.dB
%   - each component accessible via Results{i}.loss.get(name){1}.dB
%
% Options
%   'Wavelengths'         : numeric vector (nm) used to label as "XXXXnm"
%   'Labels'              : string/cellstr labels (overrides Wavelengths)
%   'Colors'              : Nx3 RGB array
%   'FigureName'          : figure name
%   'LineWidth'           : line width
%   'TwoColumns'          : true/false (default true)
%   'MaskMode'            : "elevation" | "active" | "all"  (default "elevation")
%   'MaskFcn'             : function handle mask = f(Result_i), overrides MaskMode
%   'OneLossPerFigure'    : true -> one loss type per figure (default false)
%   'MaxSubplotsPerFigure': max loss panels per figure when paginating (default 6)
%   'FigureNamePrefix'    : prefix used for paginated figure names

    p = inputParser;
    p.addRequired('Results', @(x) iscell(x) && ~isempty(x));
    p.addParameter('Wavelengths', [], @(x) isnumeric(x) || isempty(x));
    p.addParameter('Labels', [], @(x) isstring(x) || iscellstr(x) || isempty(x));
    p.addParameter('Colors', [], @(x) isnumeric(x) || isempty(x));
    p.addParameter('FigureName', "Loss Components Comparison", @(x) isstring(x) || ischar(x));
    p.addParameter('LineWidth', 1.5, @(x) isnumeric(x) && isscalar(x));
    p.addParameter('TwoColumns', true, @(x) islogical(x) && isscalar(x));
    p.addParameter('MaskMode', "elevation", @(x) isstring(x) || ischar(x));
    p.addParameter('MaskFcn', [], @(x) isempty(x) || isa(x,'function_handle'));
    p.addParameter('OneLossPerFigure', false, @(x) islogical(x) && isscalar(x));
    p.addParameter('MaxSubplotsPerFigure', 6, @(x) isnumeric(x) && isscalar(x) && x>=1);
    p.addParameter('FigureNamePrefix', "", @(x) isstring(x) || ischar(x));
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
        labels = string(arrayfun(@(x) sprintf('%dnm', round(x)), w, 'UniformOutput', false));
    else
        labels = "Case " + (1:N);
    end

    %% Colours and Line-width
    colors = p.Results.Colors;
    if isempty(colors), colors = lines(N); end
    if size(colors,1) ~= N || size(colors,2) ~= 3
        error('Colors must be an Nx3 RGB array, where N = numel(Results).');
    end
    lw = p.Results.LineWidth;

    %% Loss list
    loss_names = Results{1}.loss.Names;
    all_loss_types = [{'TotalLoss'}, loss_names(:)'];
    n_plots = numel(all_loss_types);

    %% Masks + shared x-limits
    masks = cell(1,N);
    xmin = []; xmax = [];
    for i = 1:N
        R = Results{i};
        if ~isempty(p.Results.MaskFcn)
            mask = p.Results.MaskFcn(R);
        else
            mode = lower(string(p.Results.MaskMode));
            switch mode
                case "elevation", mask = R.elevation_mask;
                case "active",    mask = R.sifted_key_rate > 0;
                case "all",       mask = true(size(R.time));
                otherwise, error('Unknown MaskMode: %s', mode);
            end
        end
        mask = logical(mask(:));
        t = R.time(:);
        if numel(mask) ~= numel(t), error('Mask length mismatch for case %d.', i); end
        masks{i} = mask;
        if any(mask)
            tmin_i = min(t(mask)); tmax_i = max(t(mask));
            if isempty(xmin), xmin = tmin_i; xmax = tmax_i;
            else, xmin = min(xmin,tmin_i); xmax = max(xmax,tmax_i); end
        end
    end

    prefix = string(p.Results.FigureNamePrefix);
    if strlength(prefix)==0, prefix = string(p.Results.FigureName); end

    % determine figure groups
    if p.Results.OneLossPerFigure
        groups = arrayfun(@(k) k, 1:n_plots, 'UniformOutput', false);
    else
        kmax = p.Results.MaxSubplotsPerFigure;
        nGroups = ceil(n_plots / kmax);
        groups = cell(1,nGroups);
        for g = 1:nGroups
            i1 = (g-1)*kmax + 1;
            i2 = min(g*kmax, n_plots);
            groups{g} = i1:i2;
        end
    end

    figs = gobjects(1, numel(groups));

    for g = 1:numel(groups)
        idxs = groups{g};
        n_this = numel(idxs);

        if p.Results.OneLossPerFigure
            figName = sprintf('%s - %s', prefix, localPrettyLossName(all_loss_types{idxs}));
            n_cols = 1; n_rows = 1;
        else
            figName = sprintf('%s (%d/%d)', prefix, g, numel(groups));
            n_cols = 1 + p.Results.TwoColumns;
            n_rows = ceil(n_this / n_cols);
        end

        figs(g) = figure('Name', figName, 'NumberTitle', 'off');
        tiledlayout(n_rows, n_cols, 'TileSpacing', 'compact');

        for jj = 1:n_this
            j = idxs(jj);
            nexttile; hold on; grid on;

            loss_name = all_loss_types{j};
            plot_title = localPrettyLossName(loss_name);

            for i = 1:N
                R = Results{i};
                mask = masks{i};
                x_axis = R.time(:);

                if strcmp(loss_name, 'TotalLoss')
                    y = localLossToDbVector(R.loss.total_loss);
                else
                    try
                        lossObj = R.loss.get(loss_name);
                        lossObj = lossObj{1};
                        y = localLossToDbVector(lossObj);
                    catch
                        warning('Loss "%s" not found for result %d. Skipping.', loss_name, i);
                        continue
                    end
                end

                plot(x_axis(mask), y(mask), 'Color', colors(i,:), ...
                    'LineWidth', lw, 'DisplayName', labels(i));
            end

            ylabel('Loss (dB)', 'FontWeight','bold');
            title(plot_title, 'FontWeight','bold', 'FontSize', 11);
            legend('Location','best');

            if ~isempty(xmin) && ~isempty(xmax), xlim([xmin, xmax]); end
        end
    end
end

function out = localPrettyLossName(loss_name)
    if strcmp(loss_name, 'TotalLoss')
        out = 'Total Loss';
    else
        out = strrep(loss_name, '_', ' ');
        out(1) = upper(out(1));
    end
end

function y = localLossToDbVector(lossObj)
    if any(strcmp(methods(lossObj), "dB"))
        try
            y = lossObj.dB();
            y = y(:);
            return;
        catch
        end
    end
    try
        y = lossObj.dB;
        y = y(:);
        return;
    catch
    end
    error("Unable to extract dB from units.Loss object.");
end