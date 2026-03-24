classdef geometry
    properties
        % Observer
        lat_deg (1,1) double
        lon_deg (1,1) double
        alt_m   (1,1) double

        % Time (UTC)
        utcDT (1,1) datetime

        % LOS sweep definition (degrees)
        zen_min (1,1) double = 0
        zen_max (1,1) double = 0
        zen_step (1,1) double = -1                                          % if -1 use only single value: zen_min
        azi_min (1,1) double = 0
        azi_max (1,1) double = 0
        azi_step (1,1) double = -1                                          % if -1 use only single value: azi_min

        % injected zenith/azimuth values (deg)
        zen_inject_deg double = []                                          % optional extra zenith samples to include in sweep
        azi_inject_deg double = []                                          % optional extra azimuth samples to include in sweep

        % Source selection
        % "sun" | "moon" | "none"                                           "none" is for transmittance only simuations
        source (1,1) string = "moon"

        % lunar phase angle (deg), if empty it autocomputes
        lun_phase_deg double = []  % (0=Full, 90=Half, 180=New)
        
        % multi-location labels
        location_label (1,1) string = ""

    end

    methods (Static, Access=private)
        function phase_deg = computeLunarPhaseDeg_AeroTB(utcDT)
        % Computes lunar phase angle using geocentric vectors:
        %   phase = angle between (Moon to Sun) and (Moon to Earth)

        %   - 0 deg  : Full Moon  (Sun and Earth in same direction as seen from Moon)
        %   - 180 deg: New Moon   (Sun opposite Earth as seen from Moon)
        
            % Ensure UTC input
            if utcDT.TimeZone == "" || ~strcmpi(utcDT.TimeZone,"UTC")
                error("computeLunarPhaseDeg_AeroTB:utc", "utcDT must be UTC with TimeZone='UTC'.");
            end
        
            jdUTC = juliandate(utcDT);
        
            % Earth-centered inertial vectors (ECI/J2000), returned as 1x3 (km)
            rES_km = planetEphemeris(jdUTC, "Earth", "Sun");                % Earth to Sun
            rEM_km = planetEphemeris(jdUTC, "Earth", "Moon");               % Earth to Moon
        
            rES = rES_km(:);   % 3x1
            rEM = rEM_km(:);
        
            % Moon-centered vectors:
            % Moon to Earth is just negative of Earth to Moon
            rME = -rEM;
        
            % Moon to Sun = (Earth to Sun) - (Earth to Moon)
            rMS = rES - rEM;
        
            % Phase angle is the angle between Moon to Sun and Moon to Earth
            cosang = dot(rMS, rME) / (norm(rMS) * norm(rME));
            cosang = max(-1, min(1, cosang));
        
            phase_deg = acosd(cosang);
        end
    end


    methods
        function obj = geometry(lat_deg, lon_deg, alt_m, utcDT)
            obj.lat_deg = lat_deg;
            obj.lon_deg = lon_deg;
            obj.alt_m = alt_m;
            obj.utcDT = utcDT;

            % Ensure TimeZone is set to UTC for consistency
            if obj.utcDT.TimeZone == ""
                error("geometry:utcDT", "utcDT must have TimeZone='UTC'.");
            end
            if ~strcmpi(obj.utcDT.TimeZone,"UTC")
                error("geometry:utcDT", "utcDT must be UTC.");
            end
        end

        function [zens, azis] = sweepArrays(obj)
            if obj.zen_step == -1
                zens = obj.zen_min;
            else
                zens = obj.zen_min:obj.zen_step:obj.zen_max;
            end

            if obj.azi_step == -1
                azis = obj.azi_min;
            else
                azis = obj.azi_min:obj.azi_step:obj.azi_max;
            end

            % inject extra zenith/azimuth values into the sweep
            if ~isempty(obj.zen_inject_deg)
                zens = [zens(:); obj.zen_inject_deg(:)];
            end
            if ~isempty(obj.azi_inject_deg)
                azis = [azis(:); obj.azi_inject_deg(:)];
            end

            % Ensure uniqueness and stable ordering, then sort for readability
            zens = unique(zens, "stable");
            azis = unique(azis, "stable");

            zens = sort(zens);
            azis = sort(azis);
        end
        
        function iday = getIDAY(obj)
            % Returns the integer day-of-month to put into MODTRAN GEOMETRY.IDAY.
                iday = int32(day(obj.utcDT));
        end

        function phase_deg = getLunarPhaseDeg(obj)
        % Returns lunar phase angle in degrees (0=Full, 90=Quarter, 180=New)
        
            if ~isempty(obj.lun_phase_deg)
                phase_deg = double(obj.lun_phase_deg);
                return;
            end
        
            phase_deg = modtran.parameters.geometry.computeLunarPhaseDeg_AeroTB(obj.utcDT);
        end

        function frac = getLunarIlluminatedFraction(obj)
            phi = obj.getLunarPhaseDeg();
            frac = (1 + cosd(phi)) / 2;  % 0..1
        end

        %% BUILDING CASES
        function cases = buildGeometryCases(obj)
            % Returns an array of structs, one per (zen, az) LOS case.
            %
            % Each entry contains:
            %   - geom : MODTRAN GEOMETRY struct (fields ITYPE, H1ALT, OBSZEN...)
            %   - meta : metadata useful for filenames / CSV summary

            [zens, azis] = obj.sweepArrays();

            % Compute Sun/Moon topocentric and relative angles once for the
            % timestamp+observer (the Sun/Moon az/alt don't depend on LOS).
            %
            % Then for each LOS we recompute relative angles.
            cases = struct([]);
            k = 0;

            dayOfMonth = day(obj.utcDT);

            for zi = 1:numel(zens)
                for ai = 1:numel(azis)
                    k = k + 1;

                    losZen = zens(zi);
                    losAz  = azis(ai);

                    % Get both sun and moon relative angles for this LOS.
                    rel = modtran.deriveRelativeAngles.computeSunMoonRelativeAngles( ...
                        obj.lat_deg, obj.lon_deg, obj.alt_m, obj.utcDT, losZen, losAz);

                    % Select which body to use for PARM1/PARM2 based on source
                    src = lower(strtrim(obj.source));
                    haveParms = true;

                    if startsWith(src,"sun")
                        relAz = rel.sun.relAz_deg;
                        relZen = rel.sun.relZen_deg;
                        bodyTopoAz = rel.sun.topoAz_deg;
                        bodyTopoZen = rel.sun.topoZen_deg;
                    elseif startsWith(src,"moon")
                        relAz = rel.moon.relAz_deg;
                        relZen = rel.moon.relZen_deg;
                        bodyTopoAz = rel.moon.topoAz_deg;
                        bodyTopoZen = rel.moon.topoZen_deg;
                    elseif startsWith(src,"none")
                        haveParms = false;
                        relAz = NaN; relZen = NaN;
                        bodyTopoAz = NaN; bodyTopoZen = NaN;
                    else
                        error("geometry:source","Unknown source='%s'. Use 'sun','moon','none'.", obj.source);
                    end

                    % Build MODTRAN GEOMETRY block
                    geom = struct();
                    geom.ITYPE  = 3;
                    geom.H1ALT  = obj.alt_m / 1000.0;  % km
                    geom.H2ALT  = 0.0;
                    geom.OBSZEN = double(losZen);
                    geom.HRANGE = 0.0;
                    geom.BETA   = double(losAz);
                    geom.BCKZEN = 0.0;
                    geom.IDAY   = dayOfMonth;

                    if haveParms
                        geom.IPARM = 2;
                        geom.PARM1 = double(relAz);
                        geom.PARM2 = double(relZen);
                    end
                    
                    % get luar phase angle if moon is the source
                    if startsWith(src,"moon")
                        geom.ANGLEM = obj.getLunarPhaseDeg();
                    end

                    % meta structure
                    meta = struct();
                    meta.lat = obj.lat_deg;
                    meta.lon = obj.lon_deg;
                    meta.alt_m = obj.alt_m;
                    meta.los_zen_deg = double(losZen);
                    meta.los_az_deg  = double(losAz);
                    meta.body_topo_az_deg  = double(bodyTopoAz);
                    meta.body_topo_zen_deg = double(bodyTopoZen);
                    meta.source = obj.source;

                    cases(k).geom = geom; 
                    cases(k).meta = meta; 
                    cases(k).debug = rel.debug; 
                end
            end
        end
    end
end