function [losses, extras] = linkLoss(kind, receiver, transmitter, options)
% linkLoss
%
% Compute cumulative link loss between a transmitter and receiver for
% a specified signal type and set of physical loss mechanisms.
%
% Syntax:
% [losses, extras] = linkLoss(kind, receiver, transmitter, loss, options)
%
% Inputs:
% kind        - string, either "beacon" or "qkd"
% receiver    - nodes.Satellite or nodes.GroundStation object
% transmitter - nodes.Satellite or nodes.GroundStation object
% loss        - cell array of strings specifying loss types to include
% options     - struct with optional fields:
%               .dB         - logical, whether to return loss in dB
%               .SpotSize   - numeric, optional beam spot size
%               .LinkLength - numeric, optional link length
%
% Outputs:
% losses - nodes.LossResult object containing cumulative losses
% extras - struct with additional outputs (e.g., beam width, r0)

    arguments
        kind {mustBeMember(kind, ["beacon", "qkd"])}
        receiver {mustBeA(receiver, ["nodes.Satellite", "nodes.GroundStation"])}
        transmitter {mustBeA(transmitter, ["nodes.Satellite", "nodes.GroundStation"])}

        %the various different kinds of simulatable losses
        options.geometric (1,1) logical = true
        options.turbulence (1,1) logical = true
        options.apt (1,1) logical = true
        options.atmospheric (1,1) logical = true
        options.detection_efficiency (1,1) logical = true
        options.source_efficiency (1,1) logical = true
        options.transmitter_telescope_efficiency (1,1) logical = true
        options.receiver_telescope_efficiency (1,1) logical = true
        options.jitter (1,1) logical = true
        options.filter_efficiency (1,1) logical = true
        options.camera_efficiency (1,1) logical = true
        options.beacon_efficiency (1,1) logical = true

        % spectral filter pulse broadening impact
        options.time_gate_overlap (1,1) logical = true

        % do you want the output in dB?
        options.dB (1,1) logical = false
    end


    %% Geometric loss
    if options.geometric
        [res, spot_size, ~] = nodes.geometricLoss(kind, receiver, transmitter);
        losses = nodes.LossResult('qkd', units.Loss(res, 'geometric'));
    end

    %% Turbulence loss
    if options.turbulence
        switch class(receiver)
            case "nodes.GroundStation"
                direction = nodes.LinkDirection.Downlink;
            case "nodes.Satellite"
                direction = nodes.LinkDirection.Uplink;
        end

        [res, beam_width, r0] = nodes.turbulenceLoss(kind, ...
            receiver, transmitter, direction, "SpotSize", spot_size);

        losses = losses.addLoss(units.Loss(res, 'turbulence'));
    else
        beam_width = spot_size;
        r0 = 0;
    end

    %% Acquisition, pointing, and tracking loss
    if options.apt
        res = nodes.aptLoss(kind, receiver, transmitter);
        losses = losses.addLoss(units.Loss(res, 'apt'));
    end

    %% Atmospheric loss
    if options.atmospheric
        res = nodes.atmosphericLoss(kind, receiver, transmitter, direction);
        losses = losses.addLoss(units.Loss(res, 'atmospheric'));
    end

    %% Transmitter telescope efficiency
    if options.transmitter_telescope_efficiency
        res = transmitter.telescope.effectiveOpticalEfficiencyForSource(transmitter.source);    % includes truncation effect on gaussian beams for relevant sources
        losses = losses.addLoss(units.Loss(res,'transmitter telescope efficiency'));
    end

    %% Receiver telescope efficiency
    if options.receiver_telescope_efficiency
        res = receiver.telescope.optical_efficiency;
        losses = losses.addLoss(units.Loss(res,'receiver telescope efficiency'));
    end

    %% these losses are for QKD links only
    if kind == "qkd"
        %% Detection efficiency
        if options.detection_efficiency
            res = receiver.detector.detection_efficiency;
            losses = losses.addLoss(units.Loss(res,'detection efficiency'));
        end

        %% Source efficiency
        if options.source_efficiency
            res = transmitter.source.efficiency;
            losses = losses.addLoss(units.Loss(res,'source efficiency'));
        end

        %% Timing Jitter
        if options.jitter
            res = receiver.detector.jitter_loss;
            losses = losses.addLoss(units.Loss(res,'jitter'));
        end

        %% Filter efficiency
        % Spectral detuning
        if options.filter_efficiency
            shifted_wavelength = nodes.dopplerShift(receiver, transmitter);
            res = receiver.detector.spectral_filter.computeTransmission(shifted_wavelength)';
            losses = losses.addLoss(units.Loss(res,'filter efficency'));   
        end
        % Time-gate overlap loss (spectral-temporal coupling)
        if options.time_gate_overlap
            gate_efficiency = localTimeGateOverlapEfficiency(receiver, transmitter);
            losses = losses.addLoss(units.Loss(gate_efficiency, 'time gate overlap'));
        end
    end

    %% these losses are for beacon links only
    if kind == "beacon"
        %% camera efficiency
        if options.camera_efficiency
            res = receiver.camera.quantum_efficiency;
            losses = losses.addLoss(units.Loss(res,'camera efficiency'));
        end

        %% beacon efficiency
        if options.beacon_efficiency
            res = transmitter.beacon.power_efficiency;
            losses = losses.addLoss(units.Loss(res,'beacon efficiency'));
        end
    end


    %% Package extras
    extras = struct();
    extras.turbulent_beam_width = beam_width;
    extras.r0 = r0;
    extras.total_loss = losses.totalLoss;
end

function eta = localTimeGateOverlapEfficiency(receiver, transmitter)
    % Compute gate overlap efficiency due to doppler shift time-bandwidth effect
    %
    % Uses detector spectral filter width for minimum transform-limited
    % pulse duration, combines with detector timing jitter, and integrates a
    % Gaussian pulse over the detector gate duration.
    %
    % Gaussian FHWM assumptions used:
    %   TBP: Δν * Δt >= 0.441
    %   FWHM_eff = sqrt(FWHM_pulse^2 + FWHM_jitter^2)
    %   η_gate = erf( sqrt(log(2)) * T_gate / FWHM_eff )
    det = receiver.detector;

    % Detector gate width
    if isprop(det, "time_gate_width")
        time_gate_width = double(det.time_gate_width);
    elseif isprop(det, "Time_Gate_Width")
        time_gate_width = double(det.Time_Gate_Width);
    else
        error("Detector time gate width not found.");
    end
    if ~isscalar(time_gate_width) || ~isfinite(time_gate_width) || time_gate_width <= 0
        error("Detector time gate width must be a positive scalar in seconds.");
    end

    % Detector jitter FWHM
    if isprop(det, "jitter")
        jitter_fwhm = double(det.jitter);
    elseif isprop(det, "Jitter")
        jitter_fwhm = double(det.Jitter);
    else
        % if not jitter assume no additional timing broadening from detector
        jitter_fwhm = 0;
    end
    if ~isscalar(jitter_fwhm) || ~isfinite(jitter_fwhm) || jitter_fwhm < 0
        jitter_fwhm = 0;
    end

    % Center wavelength is now Doppler-shifted signal wavelength
    lambda_nm = nodes.dopplerShift(receiver, transmitter);
    lambda_m = double(lambda_nm) * 1e-9;

    % Filter width [m], estimated from non-zero transmission span
    spectral_filter = det.spectral_filter;
    if ~isprop(spectral_filter, "wavelengths") || ~isprop(spectral_filter, "transmission")
        error("Detector spectral_filter must provide wavelengths and transmission.");
    end
    w_nm = double(spectral_filter.wavelengths(:));
    t = double(spectral_filter.transmission(:));
    support = (t ~= 0);
    if ~any(support)
        % no passband means zero signal transmission.
        eta = zeros(size(lambda_m));
        return;
    end
    filter_bw_m = (max(w_nm(support)) - min(w_nm(support))) * 1e-9;         % find the bandwidth in nm from the supported wavelength range
    if ~(isfinite(filter_bw_m) && filter_bw_m > 0)
        error("Spectral filter width inferred as non-positive.");
    end

    % Transform-limited pulse FWHM from TBP (Gaussian)
    c = 299792458; % m/s
    filter_bw_hz = c * filter_bw_m ./ (lambda_m.^2); % Hz                   % find the bandwidth in hz for the supported wavelength range
    pulse_fwhm = 0.441 ./ filter_bw_hz;         % s                         % apply the Gaussian time-bandwidth product (for FWHM., not 1/e^2 Gaussian)

    % Combine pulse broadening with detector jitter (Gaussian beam FWHM)
    fwhm_eff = sqrt(pulse_fwhm.^2 + jitter_fwhm.^2);                        % calculate the full effective FWHM pulse seen at detector (based on Gaussian stats jitter, not 1/e^2)

    % Gate overlap for centered Gaussian pulse
    eta = erf(sqrt(log(2)) .* (time_gate_width ./ fwhm_eff));                         % compute an efficiency for the applied time-gate

    % Clamp numerical noise and ensure row vector shape for consistency with other per-step losses
    eta = max(0, min(1, eta));
    eta = eta(:).';
end