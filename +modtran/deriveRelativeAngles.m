% Author: Brandon Reade
% Date: 21/03/2026
% computes relative azimuth/zenith of Sun/Moon w.r.t. user defined LOS

%   Output feeds MODTRAN "PARM1/PARM2" geometry fields:
%     PARM1 = relative azimuth (deg)   in plane normal to LOS (0..360)
%     PARM2 = relative zenith  (deg)   angular separation LOS<->body (0..180)

% Packages required: 
% - Aerospace Toolbox with dependencies...
% - planetEphemeris : geocentric Sun/Moon position in ECI/J2000
%           - requires aeroDataPackage
% - eci2ecef        : rotate ECI/J2000 vector into ECEF/ITRF at UTC time
% - juliandate      : convert datetime -> Julian date
%
%  Conventions:
% - ENU basis stored as [N; E; U] (North, East, Up)
% - Azimuth measured degrees East of North: 0=N, 90=E
% - Zenith: 0=up, 90=horizon
% - Altitude = 90 - zenith

classdef deriveRelativeAngles
    methods (Static)
        function out = computeSunMoonRelativeAngles(lat_deg, lon_deg, alt_m, utcDT, losZen_deg, losAz_deg)
        % Output structure:
        %   out.sun.topoAz_deg     : Sun azimuth at observer (deg E of N)
        %   out.sun.topoAlt_deg    : Sun altitude at observer (deg)
        %   out.sun.topoZen_deg    : Sun zenith at observer (deg)
        %   out.sun.relAz_deg      : Sun relative azimuth wrt LOS (deg)
        %   out.sun.relZen_deg     : Sun relative zenith wrt LOS (deg)
        %
        %   or out.moon.* similarly
        %
        %   out.debug contains intermediate vectors useful for verification

            % Ensure datetime is UTC
            modtran.deriveRelativeAngles.assertUTC(utcDT);

            % Convert observer (lat/lon/alt) to ECEF position vector with 
            % standard WGS84 conversion.
            rObs_ecef_m = modtran.deriveRelativeAngles.geodeticToECEF_WGS84(lat_deg, lon_deg, alt_m);

            % Compute Sun and Moon geocentric position vectors in ECEF
            % 1. planetEphemeris gives Earth-centered ECI/J2000 vectors
            % 2. eci2ecef rotates those vectors into Earth-fixed ECEF/ITRF
            [rSun_ecef_m, rMoon_ecef_m, rSun_eci_m, rMoon_eci_m] = ...
                modtran.deriveRelativeAngles.sunMoonECEF_AeroTB(utcDT);

            % Form topocentric LOS vectors (body - observer)
            rhoSun_ecef_m  = rSun_ecef_m  - rObs_ecef_m;
            rhoMoon_ecef_m = rMoon_ecef_m - rObs_ecef_m;

            % Convert ECEF topocentric vectors into local [N;E;U] frame
            rhoSun_neu_m  = modtran.deriveRelativeAngles.ecefVecToNEU(rhoSun_ecef_m, lat_deg, lon_deg);
            rhoMoon_neu_m = modtran.deriveRelativeAngles.ecefVecToNEU(rhoMoon_ecef_m, lat_deg, lon_deg);

            % Convert local vector to topocentric azimuth/altitude
            [sunAlt_deg,  sunAz_deg]  = modtran.deriveRelativeAngles.neuToAltAz(rhoSun_neu_m);
            [moonAlt_deg, moonAz_deg] = modtran.deriveRelativeAngles.neuToAltAz(rhoMoon_neu_m);

            % Convert altitude to zenith (MODTRAN requires zenith)
            sunZen_deg  = 90 - sunAlt_deg;
            moonZen_deg = 90 - moonAlt_deg;

            % Compute relative angles wrt LOS
            sunRel  = modtran.deriveRelativeAngles.relativeAnglesFromAltAz(losZen_deg, losAz_deg, sunAlt_deg,  sunAz_deg);
            moonRel = modtran.deriveRelativeAngles.relativeAnglesFromAltAz(losZen_deg, losAz_deg, moonAlt_deg, moonAz_deg);

            % Pack outputs
            out = struct();

            out.sun = struct( ...
                "topoAz_deg",  sunAz_deg, ...
                "topoAlt_deg", sunAlt_deg, ...
                "topoZen_deg", sunZen_deg, ...
                "relAz_deg",   sunRel.relAz_deg, ...
                "relZen_deg",  sunRel.relZen_deg);

            out.moon = struct( ...
                "topoAz_deg",  moonAz_deg, ...
                "topoAlt_deg", moonAlt_deg, ...
                "topoZen_deg", moonZen_deg, ...
                "relAz_deg",   moonRel.relAz_deg, ...
                "relZen_deg",  moonRel.relZen_deg);

            % Debug for verification
            out.debug = struct();
            out.debug.rObs_ecef_m    = rObs_ecef_m;
            out.debug.rSun_eci_m     = rSun_eci_m;
            out.debug.rMoon_eci_m    = rMoon_eci_m;
            out.debug.rSun_ecef_m    = rSun_ecef_m;
            out.debug.rMoon_ecef_m   = rMoon_ecef_m;
            out.debug.rhoSun_ecef_m  = rhoSun_ecef_m;
            out.debug.rhoMoon_ecef_m = rhoMoon_ecef_m;
            out.debug.rhoSun_neu_m   = rhoSun_neu_m;
            out.debug.rhoMoon_neu_m  = rhoMoon_neu_m;
        end
    end

    %% FUNCTIONS
    methods (Static, Access = private)

        function assertUTC(utcDT)
        % Ensures datetime has a timezone and is in UTC.
            if utcDT.TimeZone == ""
                error("utcDT must have TimeZone set. Example: datetime(...,'TimeZone','UTC').");
            end
            if ~strcmpi(utcDT.TimeZone, "UTC")
                error("utcDT must be UTC. Got TimeZone='%s'.", utcDT.TimeZone);
            end
        end

        function r_ecef_m = geodeticToECEF_WGS84(lat_deg, lon_deg, alt_m)
        % Converts geodetic latitude/longitude/altitude into ECEF XYZ (meters).
        % WGS84:
        %   a  = semi-major axis
        %   f  = flattening
        %   e2 = eccentricity squared

            a = 6378137.0;                                                  % meters
            f = 1/298.257223563;
            e2 = f*(2-f);

            lat = deg2rad(lat_deg);
            lon = deg2rad(lon_deg);

            sinLat = sin(lat);
            cosLat = cos(lat);

            % Prime vertical radius of curvature
            N = a / sqrt(1 - e2*sinLat*sinLat);

            x = (N + alt_m) * cosLat * cos(lon);
            y = (N + alt_m) * cosLat * sin(lon);
            z = (N*(1 - e2) + alt_m) * sinLat;

            r_ecef_m = [x; y; z];
        end

        function [rSun_ecef_m, rMoon_ecef_m, rSun_eci_m, rMoon_eci_m] = sunMoonECEF_AeroTB(utcDT)
        % Computes Earth-centered position vectors of Sun and Moon in ECEF (m).
        %
        % 1: UTC datetime to Julian date
        % 2: Earth-centered ECI/J2000 vectors from planetEphemeris
        % 3: Rotate ECI to ECEF at the same UTC using eci2ecef
        %
        % - planetEphemeris returns 1x3 vectors (typically km). We convert to m.
        % - eci2ecef returns ECEF vectors (same as the input).

            % Julian date at UTC
            jdUTC = juliandate(utcDT);

            % Get Earth-centered ECI/J2000 position vectors (km) as 1x3
            rSun_eci_km  = planetEphemeris(jdUTC, "Earth", "Sun");
            rMoon_eci_km = planetEphemeris(jdUTC, "Earth", "Moon");

            % Convert to column vectors in meters
            rSun_eci_m  = rSun_eci_km(:)  * 1000.0;
            rMoon_eci_m = rMoon_eci_km(:) * 1000.0;

            % eci2ecef expects a UTC date vector [Y M D H MN S]
            dvUTC = datevec(utcDT);

            % Rotate into ECEF/ITRF (meters)
            rSun_ecef_m  = eci2ecef(dvUTC, rSun_eci_m);
            rMoon_ecef_m = eci2ecef(dvUTC, rMoon_eci_m);
        end

        function v_neu = ecefVecToNEU(v_ecef, lat_deg, lon_deg)
        % Rotates an ECEF vector into local NEU = [North; East; Up] at the
        % observer geodetic lat/lon.
        %
        % - ECEF to ENU rotation returns [E;N;U]
        % - This is reordered into [N;E;U] for consistency

            lat = deg2rad(lat_deg);
            lon = deg2rad(lon_deg);

            % Standard ECEF->ENU rotation matrix (yields [E; N; U])
            R_ecef_to_enu = [ -sin(lon),           cos(lon),            0;
                              -sin(lat)*cos(lon), -sin(lat)*sin(lon),  cos(lat);
                               cos(lat)*cos(lon),  cos(lat)*sin(lon),  sin(lat) ];

            v_enu = R_ecef_to_enu * v_ecef;     % [E; N; U]
            v_neu = [v_enu(2); v_enu(1); v_enu(3)]; % [N; E; U]
        end

        function [alt_deg, az_deg] = neuToAltAz(v_neu)
        % Converts a local [N;E;U] vector into:
        %   - azimuth (deg East of North, 0..360)
        %   - altitude (deg above horizon)
            n = v_neu(1);
            e = v_neu(2);
            u = v_neu(3);

            horiz = hypot(n, e);
            alt_deg = atan2d(u, horiz);
            az_deg  = mod(atan2d(e, n), 360.0);
        end

        function v = altAzToUnitNEU(alt_deg, az_deg)
        % Builds a normalized unit direction vector in [N;E;U] given:
        %   alt_deg = altitude above horizon
        %   az_deg  = azimuth East of North
        %
        % v = | cos(alt)*cos(az);   |
        %     | cos(alt)*sin(az);   |
        %     |     sin(alt)        |

            ca = cosd(alt_deg);
            v = [ ca*cosd(az_deg);
                  ca*sind(az_deg);
                  sind(alt_deg) ];
            v = v / norm(v);
        end

        function out = relativeAnglesFromAltAz(losZen_deg, losAz_deg, bodyAlt_deg, bodyAz_deg)
        %   1. Convert LOS and Body to unit vectors in NEU
        %   2. Relative zenith = acosd(dot(L,B))
        %   3. Project body vector onto plane perpendicular to LOS
        %   4. Create an in-plane coordinate system:
        %       u-axis = projected "up" (or fallback if LOS ~ vertical)
        %       v-axis = cross(LOS, u)
        %   5. relAz = atan2d( dot(Bperp,v), dot(Bperp,u) )

            % Convert LOS zen- to alt
            losAlt_deg = 90 - losZen_deg;

            % Unit vectors
            L = modtran.deriveRelativeAngles.altAzToUnitNEU(losAlt_deg, losAz_deg);
            B = modtran.deriveRelativeAngles.altAzToUnitNEU(bodyAlt_deg, bodyAz_deg);

            % Relative zenith = angular separation
            dotLB = max(-1, min(1, dot(L, B)));
            relZen_deg = acosd(dotLB);

            % Project body into plane normal to LOS
            B_perp = B - dot(B, L) * L;
            nB = norm(B_perp);

            if nB < 1e-12
                % Body direction parallel/anti-parallel to LOS:
                % relative azimuth is undefined; choose 0 by convention.
                relAz_deg = 0.0;
            else
                B_perp = B_perp / nB;

                % Choose a reference "up" direction: local Up axis in NEU is [0;0;1].
                up = [0;0;1];

                % If LOS is nearly vertical: Use East as fallback.
                if abs(dot(up, L)) > 0.999
                    up = [0;1;0];                                           % East axis in NEU ordering
                end

                % Project the reference axis into plane normal to LOS
                u = up - dot(up, L) * L;
                u = u / norm(u);                                            % u => relative azimuth = 0 degrees

                % Second in-plane axis (right-handed)
                v = cross(L, u);                                            % v => relative azimuth = 90 degrees

                % Full-range (360 degrees) azimuth using atan2
                x = dot(B_perp, u);
                y = dot(B_perp, v);
                relAz_deg = mod(atan2d(y, x), 360.0);
            end

            out = struct("relAz_deg", relAz_deg, "relZen_deg", relZen_deg);
        end

    end
end