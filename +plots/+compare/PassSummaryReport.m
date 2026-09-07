function T = PassSummaryReport(Results, varargin)
% Summarise and export SatQKD results to txt/csv.
%
% Options:
%   'Wavelengths'   : numeric labels
%   'Labels'        : custom labels
%   'MaskMode'      : "elevation" | "active" | "all"
%   'MaskFcn'       : custom mask function
%   'TxtFile'       : export path
%   'CsvFile'       : export path

    p = inputParser;
    p.addRequired('Results', @(x) iscell(x) && ~isempty(x));
    p.addParameter('Wavelengths', [], @(x) isnumeric(x) || isempty(x));
    p.addParameter('Labels', [], @(x) isstring(x) || iscellstr(x) || isempty(x));
    p.addParameter('MaskMode', "active", @(x) isstring(x) || ischar(x));
    p.addParameter('MaskFcn', [], @(x) isempty(x) || isa(x,'function_handle'));
    p.addParameter('TxtFile', "", @(x) isstring(x) || ischar(x));
    p.addParameter('CsvFile', "", @(x) isstring(x) || ischar(x));
    p.parse(Results, varargin{:});

    N = numel(Results);

    % Labels
    if ~isempty(p.Results.Labels)
        labels = string(p.Results.Labels);
    elseif ~isempty(p.Results.Wavelengths)
        labels = string(arrayfun(@(x) sprintf('%dnm', round(x)), p.Results.Wavelengths, 'UniformOutput', false));
    else
        labels = "Case " + (1:N);
    end

    rows = struct([]);
    for i = 1:N
        R = Results{i};
        mask = localMask(R, p.Results.MaskMode, p.Results.MaskFcn);
        t = R.time(:);

        % dt estimate
        dt = localMeanDtSeconds(t);

        skr = R.secret_key_rate(:);
        sift = R.sifted_key_rate(:);
        qber = R.qber(:);

        [bcr, dcr] = localNoiseTerms(R);

        row = struct();
        row.Label = labels(i);

        % rates/metrics
        row.SKR_max = localSafeMax(skr(mask));
        row.SKR_mean = localSafeMean(skr(mask));
        %row.SKR_sum = localSafeSum(skr(mask));
        row.SK_total_bits = localIntegratedCounts(t, skr, mask);

        row.Sifted_max = localSafeMax(sift(mask));
        row.Sifted_mean = localSafeMean(sift(mask));
        %row.Sifted_sum = localSafeSum(sift(mask));
        row.Sifted_total_bits = localIntegratedCounts(t, sift, mask);

        row.QBER_max = localSafeMax(qber(mask));
        row.QBER_mean = localSafeMean(qber(mask));
        row.QBER_sum = localSafeSum(qber(mask));

        row.BCR_max = localSafeMax(bcr(mask));
        row.BCR_mean = localSafeMean(bcr(mask));
        row.BCR_total_counts = localIntegratedCounts(t, bcr, mask);

        row.DCR_max = localSafeMax(dcr(mask));
        row.DCR_mean = localSafeMean(dcr(mask));
        row.DCR_total_counts = localIntegratedCounts(t, dcr, mask);

        % link geometry
        row.LinkLength_max_m = localGetMaxLinkLength(R, mask);

        % key-established time
        active = mask & (skr > 0) & ~isnan(skr);
        row.KeyTime_total_s = sum(active) * dt;

        % loss summaries (dB)
        yTot = localLossToDbVector(R.loss.total_loss);
        row.TotalLoss_dB_max  = localSafeMax(yTot(mask));
        row.TotalLoss_dB_mean = localSafeMean(yTot(mask));
        row.TotalLoss_dB_sum  = localSafeSum(yTot(mask));
        
        for k = 1:numel(R.loss.Names)
            nm = string(R.loss.Names{k});
            try
                lo = R.loss.get(nm); lo = lo{1};
                y = localLossToDbVector(lo);
                base = matlab.lang.makeValidName(char(nm));
                row.([base '_dB_max']) = localSafeMax(y(mask));
                row.([base '_dB_mean']) = localSafeMean(y(mask));
                row.([base '_dB_sum']) = localSafeSum(y(mask));
            catch
            end
        end

        rows = [rows; row]; %#ok<AGROW>
    end

    T = struct2table(rows);
    disp(T);

    % CSV export
    if strlength(string(p.Results.CsvFile)) > 0
        writetable(T, p.Results.CsvFile);
        fprintf('Saved CSV summary: %s\n', p.Results.CsvFile);
    end

    % TXT export
    if strlength(string(p.Results.TxtFile)) > 0
        fid = fopen(p.Results.TxtFile, 'w');
        if fid < 0, error('Could not open txt file for writing: %s', p.Results.TxtFile); end
        cleanup = onCleanup(@() fclose(fid)); 
        fprintf(fid, 'Pass Summary Report\n\n');
        for i = 1:height(T)
            fprintf(fid, '--- %s ---\n', string(T.Label(i)));
            vars = T.Properties.VariableNames;
            for v = 1:numel(vars)
                if strcmp(vars{v}, 'Label'), continue; end
                fprintf(fid, '%s: %g\n', vars{v}, T{i,v});
            end
            fprintf(fid, '\n');
        end
        fprintf('Saved TXT summary: %s\n', p.Results.TxtFile);
    end
end

% helpers
function mask = localMask(R, mode, fcn)
    if ~isempty(fcn), mask = fcn(R); else
        switch lower(string(mode))
            case "elevation", mask = R.elevation_mask;
            case "active",    mask = R.sifted_key_rate > 0;
            case "all",       mask = true(size(R.time));
            otherwise, error('Unknown MaskMode.');
        end
    end
    mask = logical(mask(:));
end
function dt = localMeanDtSeconds(t)
    if numel(t) < 2, dt = 1; return; end
    if isdatetime(t), dt = seconds(median(diff(t)));
    else, dt = median(diff(t)); end
    if ~isfinite(dt) || dt<=0, dt = 1; end
end
function [bcr,dcr] = localNoiseTerms(R)
    n = numel(R.noise);
    bcr = zeros(size(R.time(:))); dcr = zeros(size(R.time(:)));
    for j = 1:n
        lbl = lower(string(R.noise(j).label));
        if contains(lbl, "background"), bcr = R.noise(j).values(:); end
        if contains(lbl, "dark"),       dcr = R.noise(j).values(:); end
    end
end
function m = localGetMaxLinkLength(R, mask)
    m = NaN;
    cands = ["link_length","range","distance"];
    for k = 1:numel(cands)
        nm = cands(k);
        if isprop(R,nm)
            y = R.(nm); y = y(:);
            if numel(y)==numel(mask), m = max(y(mask)); return; end
        end
    end
end
function v = localSafeMax(x), x=x(~isnan(x)); if isempty(x), v=NaN; else, v=max(x); end, end
function v = localSafeMean(x), x=x(~isnan(x)); if isempty(x), v=NaN; else, v=mean(x); end, end
function v = localSafeSum(x), x=x(~isnan(x)); if isempty(x), v=NaN; else, v=sum(x); end, end


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

function nCounts = localIntegratedCounts(t, rate_cps, mask)
    % Integrate rate [counts/s] over masked time to get total counts.
    % Works for datetime or numeric time vectors.

    tt = t(:);
    rr = rate_cps(:);
    mm = logical(mask(:));

    if numel(tt) ~= numel(rr) || numel(tt) ~= numel(mm)
        error('Time/rate/mask length mismatch.');
    end

    idx = find(mm & ~isnan(rr));
    if isempty(idx)
        nCounts = NaN;
        return;
    end
    if numel(idx) == 1
        nCounts = 0; % one sample -> zero interval
        return;
    end

    tSel = tt(idx);
    rSel = rr(idx);

    % dt between adjacent selected samples
    if isdatetime(tSel)
        dt = seconds(diff(tSel));
    else
        dt = diff(tSel);
    end

    % trapezoidal integration
    rMid = 0.5 * (rSel(1:end-1) + rSel(2:end));
    nCounts = sum(rMid .* dt);
end