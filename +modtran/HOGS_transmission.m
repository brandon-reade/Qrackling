% Author:   Brandon Reade
% Date:     10/04/2026
% MODTRAN case generator for HOGS Winter
% Note that visibility in MODTRAN is 2% contrast not 5%

%% 0. Define directories
repo_root = utilities.addUserPath('~\Documents\GitHub\Qrackling');
addpath(fullfile(repo_root));

% Save directory:
saveDir = fullfile(repo_root, "+modtran", "JSON_Cases");

%% 1. Geometry parameters (location + time + LOS sweep + source)
% ----------------------------
% Location 1: HOGS (Edinburgh)
% ----------------------------
utcDT = datetime(2026,1,3,1,0,0,"TimeZone","UTC");                          % (year, month, day, hr, min, second)

% Create the HOGS preset
hogs = modtran.locations.HOGS();

% LOS sweep
hogs.zen_min  = 0;   hogs.zen_max  = 90;  hogs.zen_step = -1;               % zen min/max/step
hogs.azi_min  = 0;   hogs.azi_max  = 330; hogs.azi_step = -1;               % azi min/max/step
hogs.enableLosOverrides = false;                                            

% Source (sun/moon/none)
hogs.source = "none";

% Visibility sweep (km)
visList_km = [0.5, 1, 2, 3, 4, 5, 7, 10, 15, 23];

% Aerosol / clouds (winter scenario) - BASE settings (vis will be overridden by the sweep)
hogs.visib_km = 0.5;                                                      % placeholder base value
hogs.clouds = "none";
hogs.aerosol_model = "urban";
hogs.strato_model = "background";
hogs.season = "winter";

% Atmosphere (winter scenario)
hogs.atm_MODEL = "ATM_MIDLAT_WINTER";


% Materialize MODTRAN parameter objects from the preset + utcDT
[geom1, atm, aer, surf, rt] = hogs.makeParams(utcDT);

% This is the "base aerosol" object for the sweep (clouds/model/etc.)
aerBase = aer;

%% 2. Spectral parameters (run-specific)
spec = modtran.parameters.spectral();
spec.V1 = 100;
spec.V2 = 10000;
spec.DV = 1;
spec.FWHM = 2.5;

%% 3. Output files
word = "Transm";

% For a sweep, don't pretend the file name corresponds to one specific visibility.
% We'll still seed makeJsonBaseName with something stable (e.g. the first visibility),
% then append "__VIS_SWEEP".
jsonBase = modtran.jsonCaseGenerator.makeJsonBaseName( ...
    geom1.location_label, geom1.source, utcDT, visList_km(1), aerBase.clouds, ...
    spec.V1, spec.V2, geom1.zen_step, geom1.azi_step);

json_name = jsonBase + "__VIS_SWEEP.json";
out_csv   = jsonBase + "__VIS_SWEEP_summary.csv";

[jsonOut, summaryTable] = modtran.jsonCaseGenerator.buildAndWriteVisibilitySweep( ...
    geom1, aerBase, visList_km, spec, surf, rt, atm, ...
    word, json_name, out_csv, ...
    saveDir=saveDir, makeJsonFolder=true);

disp(summaryTable);