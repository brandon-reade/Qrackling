% Author: Brandon Reade
% Date: 22/04/2026
% Sweeps through QKD parameters and run the QKD passes
%
% To do:
%   - Add saving (with summary sheet to understand what the settings where)


function T = runQKDSweep(Env, QKDsystems, options)
    arguments
        Env
        QKDsystems (1,:) struct
    
        options.Protocol = protocol.decoyBB84
    
        % Protocol defaults
        options.RepRateHz (1,1) double = 1e9
        options.MPNs (1,3) double = [0.8 0.3 0]
        options.SPs  (1,3) double = [0.7 0.2 0.1]
        options.StatePrepError (1,1) double = 0.0025
    
        % Receiver config defaults
        options.SpectralFilterWidthNm (1,1) double = 10
        options.ReceiverJitterRad (1,1) double = 1e-6
        options.GroundLLA (1,3) double = [55.909723,-3.319995,10]
        options.GroundName (1,1) string = "Heriot-Watt"
    
        % Sweep definitions
        options.SweepVarName (1,1) string
        options.SweepValues (:,1) double
    
        % wavelength sweep
        options.WavelengthsNm (:,1) double = []
        options.IgnoreRangesNm (:,2) double = zeros(0,2)
    
        % multi-dataset knobs
        options.TxDiameters (:,1) double = []
        options.RxDiameters (:,1) double = []
    
        % detector presets selection
        options.DetectorPresetFcn = []
        options.TimeGateWidthFcn = []
    
        % performance/masking
        options.Mask (1,1) string {mustBeMember(options.Mask, ...
            ["Elevation","Communication","Line of sight","None"])} = "Elevation"
    
        % Satellite Pass comparisons
        % Each case needs:
        %   Name (string)
        %   SatMode ("orbitFile"|"elements")
        %   and its associated fields (OrbitDataFileLocation OR element params)
        options.PassCases (1,:) struct = struct.empty()
    
        % Backwards-compatible single-pass defaults (used if PassCases not provided)
        options.SatMode (1,1) string {mustBeMember(options.SatMode,["orbitFile","elements"])} = "orbitFile"
        options.OrbitDataFileLocation (1,1) string = "500kmSSOrbitLLAT.txt"
    
        % orbital elements mode defaults
        options.StartTime datetime = datetime(2025,12,25,6,40,0)
        options.StopTime  datetime = datetime(2025,12,25,7,20,0)
        options.SampleTime duration = seconds(1)
        options.semiMajorAxis (1,1) double = 600e3 + earthRadius
        options.eccentricity (1,1) double = 0
        options.inclination (1,1) double = 97.065055549
        options.rightAscensionOfAscendingNode (1,1) double = -1.5
        options.argumentOfPeriapsis (1,1) double = 0
        options.trueAnomaly (1,1) double = 0
    
        % Parallel processing
        options.UseParallel (1,1) logical = true
        options.NumWorkers (1,1) double {mustBeInteger, mustBePositive} = 0
        options.ProgressEvery (1,1) double {mustBeInteger, mustBePositive} = 20
    
        % misc
        options.Verbose (1,1) logical = true
    end
    
    %% Build wavelength list
    wlBase = options.WavelengthsNm;
    if isempty(wlBase)
        wlBase = [QKDsystems.Wavelength]';
    end
    wlBase = wlBase(:);
    
    % Apply ignore ranges
    wl = wlBase;
    for k = 1:size(options.IgnoreRangesNm,1)
        lo = options.IgnoreRangesNm(k,1);
        hi = options.IgnoreRangesNm(k,2);
        wl = wl(~(wl >= lo & wl <= hi));
    end
    
    %% Determine dataset outer loops
    txList = options.TxDiameters;
    if isempty(txList), txList = unique([QKDsystems.txDiam]'); end
    
    sweepName = lower(string(options.SweepVarName));
    if sweepName == "rxdiam"
        rxList = 0; % dummy (rxDiam comes from sweep)
    else
        rxList = options.RxDiameters;
        if isempty(rxList), rxList = unique([QKDsystems.rxDiam]'); end
    end
    
    sweepVals = options.SweepValues(:);
    
    %% PassCases
    passCases = options.PassCases;
    if isempty(passCases)
        passCases = localSinglePassCaseFromOptions(options);
    end
    
    %% Create a list of jobs
    jobs = localBuildJobs(passCases, wl, txList, rxList, sweepVals, sweepName);
    
    nJobs = numel(jobs);
    if options.Verbose
        fprintf("Total sweep points: %d\n", nJobs);
    end
    
    %% Parallel pool
    if options.UseParallel
        localEnsurePool(options.NumWorkers);
    end
    
    %% Progress meter
    if options.Verbose
        dq = parallel.pool.DataQueue;
        counter = 0;
        t0 = tic;
        afterEach(dq, @(~) localProgressTick());
    else
        dq = [];
    end
    
        function localProgressTick()
            counter = counter + 1;
            if mod(counter, options.ProgressEvery) == 0 || counter == nJobs
                elapsed = toc(t0);
                rate = counter / max(elapsed, 1e-6);
                remaining = (nJobs - counter) / max(rate, 1e-6);
                fprintf("Progress: %d/%d (%.1f%%) | %.2f pts/s | ETA %.1fs\n", ...
                    counter, nJobs, 100*counter/nJobs, rate, remaining);
            end
        end
    
    %% Run jobs
    rows = cell(nJobs,1);
    
    if options.UseParallel
        parfor j = 1:nJobs
            rows{j} = localRunJob(Env, QKDsystems, options, jobs(j));
            if ~isempty(dq), send(dq, 1); end
        end
    else
        for j = 1:nJobs
            rows{j} = localRunJob(Env, QKDsystems, options, jobs(j));
            if ~isempty(dq), send(dq, 1); end
        end
    end
    
    T = vertcat(rows{:});
end

%% Job execution

function Trow = localRunJob(Env, QKDsystems, options, job)
    % Template matching by wavelength
    sys = localTemplateForWavelength(QKDsystems, job.WavelengthNm);
    sys.Wavelength = job.WavelengthNm;
    
    % dataset knobs
    sys.txDiam = job.TxDiam_m;
    if job.HasRxOuter
        sys.rxDiam = job.RxDiam_m;
    end

    if ~isempty(options.TimeGateWidthFcn)
        sys.TimeGateWidth = options.TimeGateWidthFcn(sys.Wavelength);
    end
    
    % sweep override
    sys = localApplySweep(sys, job.SweepVar, job.SweepValue, options);
    
    % run pass (based on pass case)
    res = localRunOne(Env, sys, options, job.PassCase);
    
    % summarise
    m = localSummarise(res, options.Mask);
    
    % row
    Trow = localRow(sys, job, options, m);
end

function sys = localApplySweep(sys, sweepName, sweepV, options)
    switch lower(string(sweepName))
        case "rxdiam"
            sys.rxDiam = sweepV;
        case "txdiam"
            sys.txDiam = sweepV;
        case "spectralfilterwidthnm"
            sys.SpectralFilterWidthNm = sweepV;
        case "timegatewidth"
            sys.TimeGateWidth = sweepV;
        case "rxfov"
            sys.rxFOV = sweepV;
        otherwise
            error("Unknown SweepVarName='%s'.", sweepName);
    end
    
    if ~isfield(sys,"SpectralFilterWidthNm") || isempty(sys.SpectralFilterWidthNm)
        sys.SpectralFilterWidthNm = options.SpectralFilterWidthNm;
    end
end

function res = localRunOne(Env, sys, options, passCase)
    % Source
    src = components.Source(sys.Wavelength, ...
        'Repetition_Rate', options.RepRateHz, ...
        'MPN_Signal', options.MPNs(1), ...
        'MPN_Decoy', options.MPNs(2), ...
        'Probability_Signal', options.SPs(1), ...
        'Probability_Decoy', options.SPs(2), ...
        'State_Prep_Error', options.StatePrepError);
    
    % Satellite
    txTel = components.Telescope(sys.txDiam);
    sat = localCreateSatelliteFromCase(txTel, src, passCase);
    
    % Detector preset selection
    preset = string(sys.DetectorPreset);
    if ~isempty(options.DetectorPresetFcn)
        preset = string(options.DetectorPresetFcn(sys.Wavelength));
    end
    
    % Detector
    det = components.Detector(sys.Wavelength, options.RepRateHz, ...
        sys.TimeGateWidth, sys.SpectralFilterWidthNm, ...
        'Preset', preset);
    
    % Ground station
    rxTel = components.Telescope(sys.rxDiam, ...
        'FOV', sys.rxFOV, ...
        'Pointing_Jitter', options.ReceiverJitterRad, ...
        'Wavelength', sys.Wavelength);
    
    gs = nodes.Ground_Station(rxTel, ...
        'Detector', det, ...
        'LLA', options.GroundLLA, ...
        'Name', options.GroundName);
    gs.Environment = Env;
    
    res = nodes.QkdPassSimulation(gs, sat, options.Protocol);
end

function sat = localCreateSatelliteFromCase(txTel, src, passCase)
    mode = string(passCase.SatMode);
    
    switch mode
        case "orbitFile"
            sat = nodes.Satellite(txTel, 'Source', src, ...
                'OrbitDataFileLocation', string(passCase.OrbitDataFileLocation));
    
        case "elements"
            sat = nodes.Satellite(txTel, 'Source', src, ...
                'semiMajorAxis', passCase.semiMajorAxis, ...
                'eccentricity', passCase.eccentricity, ...
                'inclination', passCase.inclination, ...
                'rightAscensionOfAscendingNode', passCase.rightAscensionOfAscendingNode, ...
                'argumentOfPeriapsis', passCase.argumentOfPeriapsis, ...
                'trueAnomaly', passCase.trueAnomaly, ...
                'StartTime', passCase.StartTime, ...
                'StopTime', passCase.StopTime, ...
                'sampleTime', passCase.SampleTime);
        otherwise
            error("Unknown SatMode in pass case: %s", mode);
    end
end

%%  Summaries

function m = localSummarise(res, maskMode)
    if numel(res) ~= 1
        res = res(1);
    end
    
    mask = localMask(res, maskMode);
    
    comm = ~(isnan(res.secret_key_rate(:)) | (res.secret_key_rate(:) <= 0));
    use = mask & comm;

    if sum(use) == 0
        m.mean_qber = NaN;
        m.max_qber  = NaN;
    end
    
    [total_secret, total_sifted] = localTotalKeysNoWarn(res, use);
    
    m = struct();
    m.total_secret_keys = total_secret;
    m.total_sifted_keys = total_sifted;
    
    m.peak_skr_bps = localSafeMaxNaN(res.secret_key_rate(mask & comm));
    q = res.qber(mask & comm);
    m.mean_qber = localSafeMeanNaN(q);
    m.max_qber  = localSafeMaxNaN(q);
    
    loss_db = res.loss.TotalLoss().dB();
    ld = loss_db(mask & comm);
    m.mean_loss_db = localSafeMeanNaN(ld);
    m.min_loss_db  = localSafeMinNaN(ld);
    m.max_loss_db  = localSafeMaxNaN(ld);
    
    m.n_comm_samples = sum(use);
    end
    
    function [total_secret, total_sifted] = localTotalKeysNoWarn(res, useMask)
    t = res.time(:);
    skr = res.secret_key_rate(:);
    sift = res.sifted_key_rate(:);
    
    idx = find(useMask(:));
    if numel(idx) < 2
        total_secret = 0;
        total_sifted = 0;
        return;
    end

    tt = t(idx);
    if iscolumn(tt), tt = tt'; end
    
    dt = tt(2:end) - tt(1:end-1);
    dt = [dt, dt(end)];
    
    if ~isnumeric(dt)
        dt = seconds(dt);
    end
    
    total_secret = dot(dt, skr(idx));
    total_sifted = dot(dt, sift(idx));
    end
    
    function mask = localMask(res, mode)
    switch mode
        case "Elevation"
            mask = res.elevation_mask;
        case "Communication"
            mask = ~(isnan(res.secret_key_rate) | (res.secret_key_rate <= 0));
        case "Line of sight"
            mask = res.elevation > 0;
        case "None"
            mask = true(size(res.elevation));
    end
    mask = logical(mask(:));
end

function Trow = localRow(sys, job, options, m)
    preset = string(sys.DetectorPreset);
    if ~isempty(options.DetectorPresetFcn)
        preset = string(options.DetectorPresetFcn(sys.Wavelength));
    end
    
    Trow = table( ...
        string(job.PassCase.Name), ...
        sys.Wavelength, ...
        sys.txDiam, ...
        sys.rxDiam, ...
        preset, ...
        sys.rxFOV, ...
        sys.TimeGateWidth, ...
        sys.SpectralFilterWidthNm, ...
        string(job.SweepVar), ...
        job.SweepValue, ...
        options.Mask, ...
        m.total_secret_keys, ...
        m.total_sifted_keys, ...
        m.peak_skr_bps, ...
        m.mean_qber, ...
        m.max_qber, ...
        m.mean_loss_db, ...
        m.min_loss_db, ...
        m.max_loss_db, ...
        m.n_comm_samples, ...
        'VariableNames', { ...
            'PassCase','WavelengthNm','TxDiam_m','RxDiam_m','DetectorPreset','RxFOV_rad','TimeGate_s','SpectralFilterNm', ...
            'SweepVar','SweepValue','Mask', ...
            'TotalSecretKeys','TotalSiftedKeys','PeakSKR_bps','MeanQBER','MaxQBER', ...
            'MeanLoss_dB','MinLoss_dB','MaxLoss_dB','NCommSamples' ...
        });
end

%% Job builder

function jobs = localBuildJobs(passCases, wl, txList, rxList, sweepVals, sweepName)
    % Flatten all loops into a 1-D job list for parfor.
    % A job is a scalar struct with fixed fields.
    
    % Determine if we have outer rx loop
    hasRxOuter = ~(sweepName == "rxdiam");
    
    nPass = numel(passCases);
    nWl = numel(wl);
    nTx = numel(txList);
    nRx = numel(rxList);
    nSweep = numel(sweepVals);
    
    nJobs = nPass * nWl * nTx * nSweep * nRx;
    jobs(nJobs,1) = struct( ...
        'PassCase', [], ...
        'WavelengthNm', 0, ...
        'TxDiam_m', 0, ...
        'RxDiam_m', 0, ...
        'HasRxOuter', false, ...
        'SweepVar', "", ...
        'SweepValue', 0);
    
    idx = 0;
    
    for p = 1:nPass
        for t = 1:nTx
            for r = 1:nRx
                for s = 1:nSweep
                    for w = 1:nWl
                        idx = idx + 1;
                        jobs(idx).PassCase = passCases(p);
                        jobs(idx).WavelengthNm = wl(w);
                        jobs(idx).TxDiam_m = txList(t);
                        jobs(idx).RxDiam_m = rxList(r);
                        jobs(idx).HasRxOuter = hasRxOuter;
                        jobs(idx).SweepVar = sweepName;
                        jobs(idx).SweepValue = sweepVals(s);
                    end
                end
            end
        end
    end
end

%% Templates / defaults

function sys = localTemplateForWavelength(QKDsystems, w)
    wlist = [QKDsystems.Wavelength];
    [isExact, idx] = ismember(w, wlist);
    if isExact
        sys = QKDsystems(idx);
        return;
    end
    [~, idx] = min(abs(wlist - w));
    sys = QKDsystems(idx);
end

function passCases = localSinglePassCaseFromOptions(options)
    % Build one pass case from legacy SatMode / orbit params
    c = struct();
    c.Name = "default";
    c.SatMode = string(options.SatMode);
    
    if c.SatMode == "orbitFile"
        c.OrbitDataFileLocation = string(options.OrbitDataFileLocation);
    else
        c.StartTime = options.StartTime;
        c.StopTime = options.StopTime;
        c.SampleTime = options.SampleTime;
        c.semiMajorAxis = options.semiMajorAxis;
        c.eccentricity = options.eccentricity;
        c.inclination = options.inclination;
        c.rightAscensionOfAscendingNode = options.rightAscensionOfAscendingNode;
        c.argumentOfPeriapsis = options.argumentOfPeriapsis;
        c.trueAnomaly = options.trueAnomaly;
    end
    
    passCases = c;
end

function localEnsurePool(numWorkers)
    p = gcp('nocreate');
    if isempty(p)
        if numWorkers > 0
            parpool('local', numWorkers);
        else
            parpool('local');
        end
    else
        if numWorkers > 0 && p.NumWorkers ~= numWorkers
            delete(p);
            parpool('local', numWorkers);
        end
    end
end

%% Reducers
function y = localSafeMax(x)
    x = x(:);
    x = x(isfinite(x));
    if isempty(x), y = 0; else, y = max(x); end
end

function y = localSafeMin(x)
    x = x(:);
    x = x(isfinite(x));
    if isempty(x), y = 0; else, y = min(x); end
end

function y = localSafeMean(x)
    x = x(:);
    x = x(isfinite(x));
    if isempty(x), y = 0; else, y = mean(x); end
end

function y = localSafeMaxNaN(x)
x = x(:); x = x(isfinite(x));
if isempty(x), y = NaN; else, y = max(x); end
end

function y = localSafeMinNaN(x)
x = x(:); x = x(isfinite(x));
if isempty(x), y = NaN; else, y = min(x); end
end

function y = localSafeMeanNaN(x)
x = x(:); x = x(isfinite(x));
if isempty(x), y = NaN; else, y = mean(x); end
end