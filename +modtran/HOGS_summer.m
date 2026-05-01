% Author:   Brandon Reade
% Date:     01/05/2026
% MODTRAN case generator for HOGS summer
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
utcDT = datetime(2026,6,21,4,0,0,"TimeZone","UTC");                          % (year, month, day, hr, min, second) - summer solstice 21st of Juna (~4:30 sunrise)

% Create the HOGS preset
hogs = modtran.locations.HOGS(); 

% LOS sweep
hogs.zen_min  = 0;   hogs.zen_max  = 90;  hogs.zen_step = 10;               % zen min/max/step
hogs.azi_min  = 0;   hogs.azi_max  = 330; hogs.azi_step = 30;               % azi min/max/step

% zenith injections (extra samples)
% hogs.zen_inject_deg = [82 85 88];                                         % (only if LocationPreset supports it)

% make zen=0 use line-by-line to avoid errors
hogs.enableLosOverrides = true;                                             % allow for overrides
hogs.losOverrideMode = "zen0";                                              % choose zenith
hogs.forceLblAtZen0IfCorrelatedK = true;                                    % force line-by-line for zen=0 case
% hogs.forceZenNonZero = true;                                              % (only if LocationPreset supports it)
% hogs.zenEps_deg      = 1e-6;                                              % (only if LocationPreset supports it)
% hogs.capNstrAt8      = true;                                              % (only if LocationPreset supports it)

% Source (sun/moon/none)
hogs.source = "sun";
% hogs.lun_phase_deg = [];                                                 % (only if LocationPreset/geometry supports it)

% Aerosol / clouds (winter scenario)
hogs.visib_km = 5;                                                          % MODTRAN uses 2% contrast visibility
hogs.clouds = "none";
hogs.aerosol_model = "urban";
hogs.strato_model = "background";
hogs.season = "summer";


% Atmosphere (winter scenario)
hogs.atm_MODEL = "ATM_MIDLAT_SUMMER";
hogs.M2_RHC = true;                                                       % humidity correction

% Surface (can be site-only in preset, but safe to override here too)
hogs.CSALB = "LAMB_URBAN";

% RT options
hogs.NSTR = 8;                                                              % 8 gave negative scattering values? Try 16?

% Materialize MODTRAN parameter objects from the preset + utcDT
[geom1, atm, aer, surf, rt] = hogs.makeParams(utcDT);
% aer.vsa_label = "HaarFog";                                                  % include the VSA label if required

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