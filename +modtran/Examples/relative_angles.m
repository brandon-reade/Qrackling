% Author: Brandon Reade
% Date: 21/03/2026
% Example usage of deriving the extraterrestrial modtran source relative to
% LOS.
repo_root = utilities.addUserPath('~\Documents\GitHub\Qrackling');  
addpath(fullfile(repo_root));                                               

% HOGS
lat = 55.91450119018555;           % deg North
lon = -3.3166000843048096;         % deg East positive (West negative)
alt_m = 100;                       % meters

% Time: 2026-01-03 13:00:00 UTC
utcDT = datetime(2026,1,3,13,0,0,"TimeZone","UTC");

% Define a line-of-sight (LOS)
losZen = 30;   % deg (0=up)
losAz  = 40;   % deg East of North

% Compute geometry
out = modtran.deriveRelativeAngles.computeSunMoonRelativeAngles( ...
    lat, lon, alt_m, utcDT, losZen, losAz);

% Output
fprintf("Observer: lat=%.6f deg, lon=%.6f deg, alt=%.1f m\n", lat, lon, alt_m);
fprintf("UTC time: %s\n\n", char(utcDT));

fprintf("SUN topocentric:\n");
fprintf("  Azimuth (E of N)  = %.6f deg\n", out.sun.topoAz_deg);
fprintf("  Altitude          = %.6f deg\n", out.sun.topoAlt_deg);
fprintf("  Zenith            = %.6f deg\n", out.sun.topoZen_deg);
fprintf("SUN relative to LOS:\n");
fprintf("  relAz (PARM1)     = %.6f deg\n", out.sun.relAz_deg);
fprintf("  relZen (PARM2)    = %.6f deg\n\n", out.sun.relZen_deg);

fprintf("MOON topocentric:\n");
fprintf("  Azimuth (E of N)  = %.6f deg\n", out.moon.topoAz_deg);
fprintf("  Altitude          = %.6f deg\n", out.moon.topoAlt_deg);
fprintf("  Zenith            = %.6f deg\n", out.moon.topoZen_deg);
fprintf("MOON relative to LOS:\n");
fprintf("  relAz (PARM1)     = %.6f deg\n", out.moon.relAz_deg);
fprintf("  relZen (PARM2)    = %.6f deg\n", out.moon.relZen_deg);

% show debug vectors
% disp(out.debug)