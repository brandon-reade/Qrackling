% Author: Brandon Reade
% Date: 21/03/2026
% Example usage of MODTRAN case generator
% Note that MODTRAN that visibility in MODTRAN is 2% contast not 5%

%% 0. Define directories
repo_root = utilities.addUserPath('~\Documents\GitHub\Qrackling');  
addpath(fullfile(repo_root));  

% Save directory:
saveDir = fullfile(repo_root, "+modtran", "JSON_Cases");

%% 1. Geometry parameters (location + time + LOS sweep + source)
% ---------------------------
% Location 1: HOGS (Edinburgh)
% ---------------------------
lat1 = 55.91450119018555;
lon1 = -3.3166000843048096;
alt_m1 = 100;

utcDT = datetime(2026,1,3,13,0,0,"TimeZone","UTC");

geom1 = modtran.parameters.geometry(lat1, lon1, alt_m1, utcDT);

% LOS sweep (example: single case)
geom1.zen_min = 10;  geom1.zen_max = 0;  geom1.zen_step = -1;
geom1.azi_min = 0;   geom1.azi_max = 0;  geom1.azi_step = -1;

% zenith injections (extra samples)
geom1.zen_inject_deg = [85 88];

% Source (sun/moon/none)
geom1.source = "sun";
% geom1.lun_phase_deg = [];                                                 % can optionally set this if source="moon"
                                                                            % otherwise it is calculated

% give it a label for file output naming
geom1.location_label = "HOGS";

% ---------------------------
% Location 2: Example second site
% ---------------------------
lat2 = 56.00000000000000;
lon2 = -3.20000000000000;
alt_m2 = 50;

geom2 = modtran.parameters.geometry(lat2, lon2, alt_m2, utcDT);

% Reuse same LOS sweep for the second location
geom2.zen_min = geom1.zen_min;  geom2.zen_max = geom1.zen_max;  geom2.zen_step = geom1.zen_step;
geom2.azi_min = geom1.azi_min;  geom2.azi_max = geom1.azi_max;  geom2.azi_step = geom1.azi_step;

% zenith injections (extra samples)
geom2.zen_inject_deg = [85 88];

% Choose a different source just to show it is independently configurable
geom2.source = "moon";
% geom2.lun_phase_deg = []; % leave empty to auto-compute

% optional label for the second location
% remove or set it to "" and the generator will use "loc2" automatically
geom2.location_label = "SITE2";

%% 2) Aerosol / clouds parameters
aer = modtran.parameters.aerosol();
aer.visib_km = 10;
aer.clouds = "none";
aer.aerosol_model = "urban";
aer.strato_model = "background";

%% 3. Spectral parameters
spec = modtran.parameters.spectral();
spec.V1 = 100;
spec.V2 = 10000;
spec.DV = 1;
spec.FWHM = 2.5;

%% 4. Surface parameters
surf = modtran.parameters.surface();
surf.CSALB = "LAMB_URBAN";

%% 5. RT options parameters
rt = modtran.parameters.rt_options();

%% 6) Atmosphere parameters
atm = modtran.parameters.atmosphere();
atm.MODEL = "ATM_MIDLAT_WINTER";
atm.M2_RHC = true;
atm.CO2MX = 0.0;

%% 7) Output files
word = "Transm";

% Recommended: auto-generate a base name that encodes the run setup.
% Use a "siteName" appropriate for the output:
%   - for per-location runs: use each location label
%   - for combined runs: use something like "HOGS_SITE2" or "UK_SITES"
zenStepForName = geom1.zen_step;
aziStepForName = geom1.azi_step;

% wmin/wmax are always in nm
jsonBase1 = modtran.jsonCaseGenerator.makeJsonBaseName( ...
    geom1.location_label, geom1.source, utcDT, aer.visib_km, aer.clouds, spec.V1, spec.V2, zenStepForName, aziStepForName);

jsonBase2 = modtran.jsonCaseGenerator.makeJsonBaseName( ...
    geom2.location_label, geom2.source, utcDT, aer.visib_km, aer.clouds, spec.V1, spec.V2, zenStepForName, aziStepForName);

jsonBaseCombined = modtran.jsonCaseGenerator.makeJsonBaseName( ...
    "HOGS_SITE2", "mixed", utcDT, aer.visib_km, aer.clouds, spec.V1, spec.V2, zenStepForName, aziStepForName);

%% OPTION A: Separate JSON files for each location (manual calls)
json_name_1 = jsonBase1 + ".json";
out_csv_1   = jsonBase1 + "_summary.csv";

json_name_2 = jsonBase2 + ".json";
out_csv_2   = jsonBase2 + "_summary.csv";

[jsonOut1, summaryTable1] = modtran.jsonCaseGenerator.buildAndWrite( ...
    geom1, aer, spec, surf, rt, atm, ...
    word, json_name_1, out_csv_1, ...
    saveDir=saveDir, makeJsonFolder=true);

disp(summaryTable1);

[jsonOut2, summaryTable2] = modtran.jsonCaseGenerator.buildAndWrite( ...
    geom2, aer, spec, surf, rt, atm, ...
    word, json_name_2, out_csv_2, ...
    saveDir=saveDir, makeJsonFolder=true);

disp(summaryTable2);

%% OPTION B: Single JSON file containing multiple locations (one combined output folder)
geoms = [geom1; geom2];

json_name_single = jsonBaseCombined + ".json";
out_csv_single   = jsonBaseCombined + "_summary.csv";

[jsonOutSingle, summarySingle] = modtran.jsonCaseGenerator.buildAndWrite( ...
    geoms, aer, spec, surf, rt, atm, ...
    word, json_name_single, out_csv_single, ...
    writeMode="single", saveDir=saveDir, makeJsonFolder=true);

disp(summarySingle);

%% OPTION C: Multiple locations, but write separate files automatically (one call)
% In this mode, buildAndWrite returns cell arrays.
[jsonOutSep, summarySep] = modtran.jsonCaseGenerator.buildAndWrite( ...
    geoms, aer, spec, surf, rt, atm, ...
    word, "cases.json", "summary.csv", ...
    writeMode="separate", saveDir=saveDir, makeJsonFolder=true, ...
    separateJsonPattern="{tag}.json", ...
    separateCsvPattern="{tag}_summary.csv");

disp(summarySep{1});
disp(summarySep{2});