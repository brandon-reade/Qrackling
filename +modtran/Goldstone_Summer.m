% Author:   Brandon Reade
% Date:     16/04/2026
% Updated:  16/04/2026
% MODTRAN case generator for Goldstone Summer
% Note that visibility in MODTRAN is 2% contrast not 5%

%% 0. Define directories
repo_root = utilities.addUserPath('~\Documents\GitHub\Qrackling');
addpath(fullfile(repo_root));

% Save directory:
saveDir = fullfile(repo_root, "+modtran", "JSON_Cases");

%% 1. Geometry parameters (location + time + LOS sweep + source)
% ----------------------------
% Location 1: Goldstone (Summer)
% ----------------------------
utcDT = datetime(2026,6,21,12,0,0,"TimeZone","UTC");                          % (year, month, day, hr, min, second): 21st of June is Summer Solstice (sunrise at 5:38am, Sunset at 8:05pm)

% Create the HOGS preset
ogs = modtran.locations.Goldstone(); 

% LOS sweep
ogs.zen_min  = 0;   ogs.zen_max  = 90;  ogs.zen_step = 10;               % zen min/max/step
ogs.azi_min  = 0;   ogs.azi_max  = 330; ogs.azi_step = 30;               % azi min/max/step

% zenith injections (extra samples)
% hogs.zen_inject_deg = [82 85 88];                                         % (only if LocationPreset supports it)

% make zen=0 use line-by-line to avoid errors
ogs.enableLosOverrides = true;                                             % allow for overrides
ogs.losOverrideMode = "zen0";                                              % choose zenith
ogs.forceLblAtZen0IfCorrelatedK = true;                                    % force line-by-line for zen=0 case
% hogs.forceZenNonZero = true;                                              % (only if LocationPreset supports it)
% hogs.zenEps_deg      = 1e-6;                                              % (only if LocationPreset supports it)
% hogs.capNstrAt8      = true;                                              % (only if LocationPreset supports it)

% Source (sun/moon/none)
ogs.source = "sun";
% hogs.lun_phase_deg = [];                                                 % (only if LocationPreset/geometry supports it)

% Aerosol / clouds (summer scenario)
ogs.visib_km = 23;                                                          % MODTRAN uses 2% contrast visibility
ogs.clouds = "none";
ogs.season = "summer";                                                      % for Desert deafult wind speed is 10m/s in MODTRAN

% Atmosphere (summer scenario)
ogs.atm_MODEL = "ATM_MIDLAT_SUMMER";
ogs.M2_RHC = true;                                                       % humidity correction

% Surface (can be site-only in preset, but safe to override here too)
ogs.CSALB = "LAMB_URBAN";

% RT options
hogs.NSTR = 8;                                                              % 8 gave negative scattering values? Try 16?

% Materialize MODTRAN parameter objects from the preset + utcDT
[geom1, atm, aer, surf, rt] = ogs.makeParams(utcDT);

%% 2. Spectral parameters (run-specific)
spec = modtran.parameters.spectral();
spec.V1 = 300;
spec.V2 = 10000;
spec.DV = 1;
spec.FWHM = 2.5;

%% 3. Output files
word = "Rad";

% Recommended: auto-generate a base name that encodes the run setup.
zenStepForName = geom1.zen_step;
aziStepForName = geom1.azi_step;

% make base name where wmin/wmax are always in nm
jsonBase1 = modtran.jsonCaseGenerator.makeJsonBaseName( ...
    geom1.location_label, geom1.source, utcDT, aer.visib_km, aer.clouds, ...
    spec.V1, spec.V2, zenStepForName, aziStepForName);

%% 4. Build JSON
json_name_1 = jsonBase1 + ".json";
out_csv_1   = jsonBase1 + "_summary.csv";

[jsonOut1, summaryTable1] = modtran.jsonCaseGenerator.buildAndWrite( ...
    geom1, aer, spec, surf, rt, atm, ...
    word, json_name_1, out_csv_1, ...
    saveDir=saveDir, makeJsonFolder=true);

disp(summaryTable1);