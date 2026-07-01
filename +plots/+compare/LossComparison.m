% Author: Brandon Reade
% Date: 11/03/2026

function fig = LossComparison(Results, varargin)
% Plot total and component losses for multiple results.
%
% Expects each Results{i}.loss has:
%   - .Names (cellstr of component names)
%   - .TotalLoss.dB
%   - each component accessible as Results{i}.loss.(name).dB
%
% Options
%   'Wavelengths'  : numeric vector (nm) used to label as "XXXXnm"
%   'Labels'       : string/cellstr labels (overrides Wavelengths)
%   'Colors'       : Nx3 RGB array
%   'FigureName'   : figure name
%   'LineWidth'    : line width
%   'TwoColumns'   : true/false (default true)
%   'MaskMode'     : "elevation" | "active" | "all"  (default "elevation")
%   'MaskFcn'      : function handle mask = f(Result_i), overrides MaskMode

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
    
    %% Colours and Line-width
    colors = p.Results.Colors;
    if isempty(colors)
        colors = lines(N);
    end
    if size(colors,1) ~= N || size(colors,2) ~= 3
        error('Colors must be an Nx3 RGB array, where N = numel(Results).');
    end
    
    lw = p.Results.LineWidth;

    %% Determine various figure parameters
    % loss component list from first result
    loss_names = Results{1}.loss.Names;
    all_loss_types = [{'TotalLoss'}, loss_names(:)'];
    n_plots = numel(all_loss_types);
    
    % Decide tiled layout
    n_cols = 1 + p.Results.TwoColumns;                                      % 2 if TwoColumns=true else 1
    n_rows = ceil(n_plots / n_cols);
    
   % Compute masks first + common x limits based on chosen mask
    masks = cell(1,N);
    
    xmin = [];
    xmax = [];
    
    for i = 1:N
        R = Results{i};
    
        % Determine mask
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
    
        % normalize
        mask = logical(mask(:));
        t = R.time(:);
    
        if numel(mask) ~= numel(t)
            error('Mask length mismatch for case %d.', i);
        end
    
        masks{i} = mask;
    
        % Update x limits in a type-safe way (numeric or datetime)
        if any(mask)
            tmin_i = min(t(mask));
            tmax_i = max(t(mask));
    
            if isempty(xmin)
                xmin = tmin_i;
                xmax = tmax_i;
            else
                xmin = min(xmin, tmin_i);
                xmax = max(xmax, tmax_i);
            end
        end
    end
    
    %% Create figure
    fig = figure('Name', p.Results.FigureName, 'NumberTitle', 'off');
    tiledlayout(n_rows, n_cols, 'TileSpacing', 'compact');
    
    for j = 1:n_plots
        nexttile; hold on; grid on;
    
        loss_name = all_loss_types{j};
        if strcmp(loss_name, 'TotalLoss')
            plot_title = 'Total Loss';
        else
            plot_title = strrep(loss_name, '_', ' ');
            plot_title(1) = upper(plot_title(1));
        end
    
        for i = 1:N
            R = Results{i};
            mask = masks{i};
            x_axis = R.time;
    
            if strcmp(loss_name, 'TotalLoss')
                y = R.loss.total_loss.dB;
            else
                % Retrieve named loss from LossResult
                try
                    lossObj = R.loss.get(loss_name);
                    lossObj = lossObj{1};        % get() returns a cell
                    y = lossObj.dB;
        
                catch
                    warning('Loss "%s" not found for result %d. Skipping.', ...
                            loss_name, i);
                    continue
                end
            end
    
            plot(x_axis(mask), y(mask), 'Color', colors(i,:), ...
                'LineWidth', lw, 'DisplayName', labels(i));
        end
    
        ylabel('Loss (dB)', 'FontWeight', 'bold');
        title(plot_title, 'FontWeight', 'bold', 'FontSize', 11);
        legend('Location', 'best');
    
        if isfinite(xmin) && isfinite(xmax)
            xlim([xmin, xmax]);
        end
    end
end