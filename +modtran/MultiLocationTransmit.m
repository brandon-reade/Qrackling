% Author: Brandon Reade
% Date: 13/04/2026
% MODTRAN case generator for HOGS, Goldstone, and Blonduos
% Note that MODTRAN that visibility in MODTRAN is 2% contast not 5%

%% 0. Define directories
repo_root = utilities.addUserPath('~\Documents\GitHub\Qrackling');  
addpath(fullfile(repo_root));  

% Save directory:
saveDir = fullfile(repo_root, "+modtran", "JSON_Cases");

%% 1. Location parameters (location + time + LOS sweep + source)
% common attributes
source = "none";
rt = modtran.parameters.rt_options();                                       % depends on source
rt.NSTR = 8;                                                                % set number of distort streams to 16 (8 gave negative scattering values)

% ----------------------------
% Location 1: HOGS (Edinburgh)
% ----------------------------
hogs_utcDT = datetime(2026,1,3,1,0,0,"TimeZone","UTC");                          % (year, month, day, hr, min, second)

% Create the HOGS preset
hogs = modtran.locations.HOGS(); 

% Source (sun/moon/none)
hogs.source = source;

% Aerosol / clouds (winter scenario)
hogs.visib_km = 5;                                                          % MODTRAN uses 2% contrast visibility
hogs.clouds = "cirrus";
hogs.season = "winter";

% Atmosphere (winter scenario)
hogs.atm_MODEL = "ATM_MIDLAT_WINTER";

% Materialize MODTRAN parameter objects from the preset + utcDT
hogs.makeParams(hogs_utcDT);

% ---------------------------
% Location 2: Goldstone
% ---------------------------
goldstone_utcDT = datetime(2026,6,29,1,0,0,"TimeZone","UTC");               % 21st June is summer solstice, 29th is full moon (year, month, day, hr, min, second)

% Create the HOGS preset
goldstone = modtran.locations.Goldstone(); 

% Source (sun/moon/none)
goldstone.source = source;

% Aerosol / clouds
goldstone.visib_km = 23;                                                          % MODTRAN uses 2% contrast visibility
goldstone.clouds = "none";
goldstone.season = "summer";

% Atmosphere
goldstone.atm_MODEL = "ATM_MIDLAT_SUMMER";

% Materialize MODTRAN parameter objects from the preset + utcDT
goldstone.makeParams(goldstone_utcDT);

%% 3. Spectral parameters
spec = modtran.parameters.spectral();
spec.V1 = 300;
spec.V2 = 10000;
spec.DV = 1;
spec.FWHM = 2.5;

%% 7) Output files
word = "Transm";

% json base names
jsonBase1 = modtran.jsonCaseGenerator.makeJsonBaseName( ...
    hogs.label, hogs.source, hogs_utcDT, hogs.visib_km, hogs.clouds, spec.V1, spec.V2, hogs.zen_step, hogs.azi_step);
jsonBase2 = modtran.jsonCaseGenerator.makeJsonBaseName( ...
    goldstone.label, goldstone.source, goldstone_utcDT, goldstone.visib_km, goldstone.clouds, spec.V1, spec.V2, goldstone.zen_step, goldstone.azi_step);


%% Build JSON
[jsonOutSep, summarySep] = modtran.jsonCaseGenerator.buildAndWrite( ...
    geoms, aer, spec, surf, rt, atm, ...
    word, "cases.json", "summary.csv", ...
    writeMode="separate", saveDir=saveDir, makeJsonFolder=true, ...
    separateJsonPattern="{tag}.json", ...
    separateCsvPattern="{tag}_summary.csv");

disp(summarySep{1});
disp(summarySep{2});