% Author: Brandon Reade
% Date: 14/05/2026
% Last update: 14/05/2026

% Produces a table of passes of a satellite (defined by TLE data) over a
% ground station's location for a given UTC time range.

% Toolboxes:
% - Uses SatComms Toolbox for TLE propagation
% - Uses Aerospace Toolbox to derive if the satellite is sunlit

% Options
%   - Filter based on pass quality
%   - Satellite sun illuminated
%   - Satellite start and end locastoin (e.g. North East to South pass)
%
% To do:
%   - add multiple grading modes (e.g. approx air mass, time above x degrees)
%   - include Sunlit using SatComms toolbox (different method as a fallback if other toolbox unavailable)
%
% Other notes:
%   - We define sunlit here if line from the satellite to the sun is not
%     blocked by the Earth

function passTable = satPassPredictor(tle, ogsLLA, startUTC, stopUTC, options)
    arguments
        tle
        ogsLLA (1,3) double                                                 % [lat_deg, long_deg, alt_m]
        startUTC datetime
        stopUTC datetime

        % options
        options.MinElevationDeg (1,1) double    = 30                        % same default used in +nodes/Ground_Station.m
        options.CoarseStep (1,1) duration       = seconds(30)               % time step used to find a satellite (use for longer sweeps)
        options.FineStep (1,1) duration         = seconds(1)                % time step used to simulate a full sat-pass
        options.OnlySunlit (1,1) logical            = false                 % flag defining if a satellite is sunlit or not (can be used for filtering)

        % pass grading options
        options.GradeWeights struct     = struct("maxElevation",4,...       % score based on priority of: Maximum elevation achieved, mean elevation for the pass, duration of the pass, fraction of time spend above the threshold, sunlit sat
                                        "meanElevation",2,"duration",2,...
                                        "highFrac",2, "sunlitFrac",0)
        options.TargetDuration (1,1) double     = 600                       % estimated satellite pass time
        options.Threshold1Deg (1,1) double      = 40                        % used to find fraction of satellite pass where the OGS is above 40 degrees elevation
        options.Threshold2Deg (1,1) double      = 60                        % used to find fraction of satellite pass where the OGS is above 60 degrees elevation

        % return options
        options.ReturnTimeSeries (1,1) logical = false

    end
    
    % ensure UTC time-handling
    startUTC = enforceUTC(startUTC);
    stopUTC = enforceUTC(stopUTC);

    if stopUTC <= startUTC
        error("stopUTC must be later than the startUTC time.")
    end

    %% 1. Coarse scan to find candidate windows
    [tCoarse, elCoarse, sunlitCoarse, rangeKmCoarse] = ...
        propagateCompute(ogsLLA, tle, startUTC, stopUTC, options.CoarseStep);

    passWindows = findPassWindows(tCoarse, elCoarse, options.MinElevationDeg);

    % if there are no pass windows, return an empty table (no fine pass logic)
    if isempty(passWindows)
        passTable = table();
        return;
    end

    %% 2. Refining each pass window and assigning metrics
    rows = repmat(struct(),0,1);                                            % preallocate so just create an empty structure, repeat it 0 times along the rows and 1 times along the column
    p = 0;

    % Loop to find the pass windows
    for k = 1:size(passWindows,1)
        t0 = passWindows(k,1);                                              % extracts values from 1st column of current row k - START TIME
        t1 = passWindows(k,2);                                              % extracts values from 2nd column of current row k - STOP TIME

        % Expand it slightly incase coarse scan missed part of the pass
        pad = max(options.CoarseStep, seconds(1));
        t0_pad = max(startUTC, t0-pad);
        t1_pad = max(stopUTC, t1+pad);

        % Fine scan for the satellite pass
        [tFine, elFine, sunlitFine, rangeKmFine] = ...                      % tFine now will be a vector containing high resolution time stamps
            propagateCompute(tle, ogsLLA, t0_pad, t1_pad, options.FineStep);
        
        % Define the pass windows in the Fine resolution
        finePassWindows = findPassWindows(tFine, elFine, options.MinElevationDeg);
        if isempty(fineWindows)
            continue;
        end

        % Loops to filter pass windows - can handle multiple passes
        for j = 1:size(fineWindows,1)
            w0 = fineWindows(j,1);                                          % get the start time of the window
            w1 = fineWindows(j,2);                                          % get the end time of the window

            index = (tFine >= w0) & (tFine <= w1);                          % index will become a vector of T or F, marking T for time stamps inside the current sub window

            % check if there are no true data points in index vector
            if ~any(index)
                continue  % skip if no true data points
            end

            % find elevation, timestamps, sunlit flags, and range during
            % subwindow (or the Segment - hence 'Seg')
            elSeg   = elFine(index);
            tSeg    = tFine(index);
            sunSeg  = sunlitFine(index);
            rangeSeg= rangeKmFine(index);

            % Set metrics
            start_T      = tSeg(1);
            stop_T       = tSeg(end);
            dur_s        = seconds(stop_T - start_T);                       % calculate duration of the pass in seconds

            [MaxEl, indexMaxEl] = max(elSeg);                               % find maximum elevation during the pass and the index it occured in
            timeMaxEl = tSeg(indexMaxEl);                                   % use the max elevation index to find the exact timestamp that the maximum occured in
            meanEl = mean(elSeg);                                           % calculate the mean elevation

            fractionTH1 = mean(elSeg >= options.Threshold1Deg);             % Fraction of the pass where elevation is above threshold 1 (default 40 deg)
            fractionTH2 = mean(elSeg >= options.Threshold2Deg);             % Fraction of the pass where elevation is above threshold 2 (default 60 deg)
            fractionSunlit = mean(sunSeg);                                  % Fraction of the pass where the satellite is illuminated by the sun

            minRange_km = min(rangeSeg);
            meanRange_km = mean(rangeSeg);

            % Grade the pass
            grade = gradePass(maxEl, meanEl, dur_s, fractionTH1, fractionTH2, fractionSunlit, options);

            % sunlit filter: if the satellite is never sunlit during the
            % pass then we filter it out (could change to "mostly sunlit")
            if options.OnlySunlit && fractionSunlit <= 0
                continue;
            end

            p = p+1;
            rows(p).pass_index  = p;
            rows(p).startUTC    = start_T;
            rows(p).endUTC      = stop_T;
            rows(p).duration_s  = dur_s;
            rows(p).max_elevation = maxEl;
            rows(p).tMaxUTC     = timeMaxEl;
            rows(p).meanEl_deg  = meanEl;
            rows(p).fracAboveTH1 = fractionTH1;
            rows(p).fracAboveTH2 = fractionTH2;
            rows(p).fracSunlit   = fractionSunlit;
            rows(p).minRange_km = minRange_km;
            rows(p).maxRange_km = maxRange_km;
            rows(p).grade       = grade;

            if options.ReturnTimeSeries
                rows(p).timeUTC     = tSeg;
                rows(p).elevation   = elSeg;
                rows(p).sunlit      = sunSeg;
                rows(p).range_km    = rangeSeg;
            end
        end
    end

    % if there are no passes then return an empty table
    if isempty(rows)
        passTable = table();
        return;
    end

    passTable = struct2table(rows);

    % sort by time (or grade)
    passTable = sortrows(passsTable, "startUTC", "ascend");
    %passTable = sortrows(passTable, "grade", "descend");
end

%% FUNCTIONS
function t = enforceUTC(t)
    if empty(t.timeZone)
        t.TimeZone = "UTC";
    else
        t = datetime(t, "TimeZone", "UTC");
    end
end

% identify the window where OGS elevation is such so tracking can occur
function windows = findPassWindows(t, elevation, min_elevation)
    mask = elevation > min_elevation;                                       % mask logic, true when elevation is greater than the minimum
    edges = diff([false; mask(:); false]);                                  % pad the mask with false either side so start/end of pass cannot be missed. 'diff' applies the 1, 0, -1 logic across the entire vector
    index_start = find(edges == 1);                                         % Find start pass index:  1 indicates a FALSE to TRUE, the satellite has just become   tracklable in the elevation range
    index_end   = find(edges == -1);                                        % Find stop  pass index: -1 indicates a TRUE to FALSE, the satellite has just become untrackable in the elevation range

    % handle case where the satellite was never above the min. elevation
    if isempty(index_start)
        windows = zeros(0,2);
        return;
    end
    
    windows = [t(index_start), t(index_end)];                               % map the logical tracking indices to the original time vector to create the pass window
end

% grade a satellite pass based on the weighted metrics
function grade = gradePass(max_elevation, mean_elevation, duration_s, fracAboveTH2, fracSunlit, options)
    weights     = options.GradeWeights;
    denominator = weights.maxElevation + weights.meanElevation + weights.duration + weights.highFrac + weights.sunlitFrac;

    % normalize the components 0 to 1
    norm_maxEl  = max(0, min(1, max_elevation / 90));
    norm_meanEl = max(0, min(1, mean_elevation / 90));
    norm_dur    = max(0, min(1, duration_s / options.TargetDuration));
    norm_highFr = max(0, min(1, fracAboveTH2));
    norm_sunlit = max(0, min(1, fracSunlit));

    % calculate the raw grade
    raw_grade = (weights.maxElevation*norm_maxEl + weights.meanElevation*norm_meanEl + weights.duration*norm_dur + weights.highFrac*norm_highFr + weights.sunlitFrac*norm)/denominator;

    % calculate as a percent
    grade = raw_grade * 100;
end

% Propagate
function [t, elevation, sunlit, range_km] = propagateCompute(tle, ogsLLA, t0, t1, time_step)
    % Note that sunlit computation is toolbox-dependent

    import utilities.satelliteScenarioWrapper

    t0 = enforceUTC(t0);
    t1 = enforceUTC(t1);

    % satellite scenario wrapper
    scenario = satelliteScenarioWrapper(t0, t1, "sampleTime", seconds(step));        % NOT EXACTLY SURE WHAT THIS MEANS - NEED TO CHECK

    % define the ground station
    ogs = groundStation(scenario, ogsLLA(1), ogsLLA(2), ogsLLA(3), "Name", "GS");

    % create a satellite from TLE data - just like in +nodes/Satellite.m
    tleFile = tleToFile(tle);
    sat = satellite(scenario, tleFile, "Name", "SAT");

    % compute access between the satellite and OGS
    access = access(satellite, ogs);

    % get access status (returns times aligned to sample time) and angles
    status = accessStatus(access);
    t = scenario.StartTime + seconds((0:numel(status)-1) * scenario.SampleTime);

    % Compute the azimuth/elevation/range 
    try
        [~, el, r] = aer(gs, sat);  % degrees, degrees, meters
        elevation = el(:);
        rangeKm = (r(:) / 1000);
    catch
        % Fallback if aer is unavailable, approximate elevation from status only
        elevation = double(status(:)) * 90;
        rangeKm = nan(size(elevation));
    end

    % mask elevations when there is no access (blocked or below horizon)
    elevation(~status) = -90

    % NOW INCLUDE SUNLIT FUNCTIONALITY HERE
end

% Turn TLE to a temp file (should probably make this in +utilities)
function tleFile = tleToFile(tleIn)
    % Accept a path or 2-line input

    if (ischar(tleIn) || (isstring(tleIn) && isscalar(tleIn))) && isfile(tleIn)
        tleFile = char(tleIn);
        return;
    end

    tleLines = tleIn;
    if ischar(tleLines)
        tleLines = string(tleLines);
    elseif iscell(tleLines)
        tleLines = string(tleLines);
    end
    tleLines = tleLines(:);

    if isstring(tleLines) && isscalar(tleLines) && contains(tleLines, newline)
        tleLines = splitlines(tleLines);
        tleLines = tleLines(tleLines ~= "");
        tleLines = tleLines(:);
    end

    assert(isstring(tleLines) && numel(tleLines) == 2, ...
        "TLE must be a 2-line string/cellstr, or a path to a .tle file.");

    tleFile = fullfile(tempdir, "qrackling_satPassPredictor.tle");
    fid = fopen(tleFile, "w");
    assert(fid > 0, "Failed to create temp TLE file: %s", tleFile);
    fprintf(fid, "%s\n", tleLines(1));
    fprintf(fid, "%s\n", tleLines(2));
    fclose(fid);
end