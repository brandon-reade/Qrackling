function fig = plotDopplerImpact(result, varargin)
% plots.plotDopplerImpact
%
% Visualise Doppler-shift impact on spectral-filter transmission and
% time-gate overlap efficiency for a single PassSimulationResult.
%
% Inputs:
%   result : nodes.PassSimulationResult
%
% Options:
%   'FigureName'   : figure title
%   'Mask'         : "Elevation" | "Communication" | "Line of sight" | "None"
%   'PulseShape'   : currently "gaussian" (TBP=0.441)
%   'ShowTimeAxis' : true -> use result.time on x-axis, false -> sample index
%
% Notes:
%   Uses detector filter transmission curve + nodes.dopplerShift(...) and
%   same Gaussian overlap model used in +nodes/linkLoss.m update.

    p = inputParser;
    p.addRequired('result', @(x) isa(x, 'nodes.PassSimulationResult'));
    p.addParameter('FigureName', "Doppler Impact on Filter + Gate", @(x) isstring(x) || ischar(x));
    p.addParameter('Mask', "Elevation", @(x) isstring(x) || ischar(x));
    p.addParameter('PulseShape', "gaussian", @(x) isstring(x) || ischar(x));
    p.addParameter('ShowTimeAxis', true, @(x) islogical(x) && isscalar(x));
    p.parse(result, varargin{:});

    R = result;
    tx = R.transmitter;
    rx = R.receiver;
    det = rx.detector;
    sf  = det.spectral_filter;

    mask = localMask(R, p.Results.Mask);

    % x-axis
    if p.Results.ShowTimeAxis
        x = R.time(:);
        xlab = "Time";
    else
        x = (1:numel(R.time)).';
        xlab = "Sample index";
    end

    % Doppler-shifted wavelength [nm]
    lambda_nm = nodes.dopplerShift(rx, tx);
    lambda_nm = lambda_nm(:);

    % Filter transmission at shifted wavelength
    sf_shifted_transmission = sf.computeTransmission(lambda_nm).';
    sf_shifted_transmission = sf_shifted_transmission(:);

    % Gate overlap model (mirrors linkLoss helper)
    Tgate = localGetGateWidthSeconds(det);
    jitter_fwhm = localGetJitterFwhmSeconds(det);
    dlam_m = localGetFilterWidthMeters(sf);

    c = 299792458;
    lambda_m = lambda_nm * 1e-9;
    dnu = c * dlam_m ./ (lambda_m.^2);

    switch lower(string(p.Results.PulseShape))
        case "gaussian"
            tbp = 0.441;
        otherwise
            error("PulseShape currently supports only 'gaussian'.");
    end

    pulse_fwhm = tbp ./ dnu;
    fwhm_eff = sqrt(pulse_fwhm.^2 + jitter_fwhm.^2);
    gate_efficiency = erf(sqrt(log(2)) .* (Tgate ./ fwhm_eff));
    gate_efficiency = max(0, min(1, gate_efficiency));

    % Combined filter and gate efficiency
    eta_combined = sf_shifted_transmission .* gate_efficiency;

    % Plot
    fig = figure('Name', p.Results.FigureName, 'NumberTitle', 'off');
    tl = tiledlayout(fig, 3, 1, 'TileSpacing', 'compact', 'Padding', 'compact');
    title(tl, p.Results.FigureName, 'FontWeight', 'bold');

    % 1) Doppler wavelength
    ax1 = nexttile(tl, 1);
    plot(ax1, x(mask), lambda_nm(mask), 'LineWidth', 1.5);
    grid(ax1, 'on');
    ylabel(ax1, '\lambda_{sig} (nm)', 'FontWeight', 'bold');
    title(ax1, 'Doppler-shifted signal wavelength');

    % 2) Filter transmission + gate overlap
    ax2 = nexttile(tl, 2);
    plot(ax2, x(mask), sf_shifted_transmission(mask), '-', 'LineWidth', 1.6, 'DisplayName', '\eta_{filter}');
    hold(ax2, 'on');
    plot(ax2, x(mask), gate_efficiency(mask), '--', 'LineWidth', 1.6, 'DisplayName', '\eta_{gate}');
    grid(ax2, 'on');
    ylabel(ax2, 'Efficiency', 'FontWeight', 'bold');
    legend(ax2, 'Location', 'best');
    title(ax2, 'Filter detuning and gate-overlap factors');

    % 3) Combined impact
    ax3 = nexttile(tl, 3);
    plot(ax3, x(mask), eta_combined(mask), 'LineWidth', 1.8);
    grid(ax3, 'on');
    ylabel(ax3, '\eta_{filter}\times\eta_{gate}', 'FontWeight', 'bold');
    xlabel(ax3, xlab, 'FontWeight', 'bold');
    title(ax3, 'Combined signal efficiency factor');

    % Console summary
    fprintf('Doppler impact summary:\n');
    fprintf('  Gate width: %.2f ps\n', Tgate*1e12);
    fprintf('  Jitter FWHM: %.2f ps\n', jitter_fwhm*1e12);
    fprintf('  Filter width: %.4f nm\n', dlam_m*1e9);
    fprintf('  eta_filter range: [%.3f, %.3f]\n', min(sf_shifted_transmission(mask)), max(sf_shifted_transmission(mask)));
    fprintf('  gate_efficiency range:   [%.3f, %.3f]\n', min(gate_efficiency(mask)), max(gate_efficiency(mask)));
    fprintf('  combined range:   [%.3f, %.3f]\n', min(eta_combined(mask)), max(eta_combined(mask)));
end

% helpers
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

function Tgate = localGetGateWidthSeconds(det)
    if isprop(det, "time_gate_width")
        Tgate = double(det.time_gate_width);
    elseif isprop(det, "Time_Gate_Width")
        Tgate = double(det.Time_Gate_Width);
    else
        error("Detector must expose time gate width.");
    end
end

function j = localGetJitterFwhmSeconds(det)
    if isprop(det, "jitter")
        j = double(det.jitter);
    elseif isprop(det, "Jitter")
        j = double(det.Jitter);
    else
        j = 0;
    end
    if ~isfinite(j) || j < 0, j = 0; end
end

function dlam_m = localGetFilterWidthMeters(sf)
    w_nm = double(sf.wavelengths(:));
    t = double(sf.transmission(:));
    support = (t ~= 0);
    if ~any(support), error("Spectral filter has no non-zero transmission support."); end
    dlam_m = (max(w_nm(support)) - min(w_nm(support))) * 1e-9;
end