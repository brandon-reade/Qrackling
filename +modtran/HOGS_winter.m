% Author: Brandon Reade
% Date: 24/03/2026
% MODTRAN case generator for HOGS Winter
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

utcDT = datetime(2026,1,3,1,0,0,"TimeZone","UTC");                          % (year, month, day, hr, min, second)
geom1 = modtran.parameters.geometry(lat1, lon1, alt_m1, utcDT);

% LOS sweep
geom1.zen_min = 0;  geom1.zen_max = 90;  geom1.zen_step = 10;               % zen min and max
geom1.azi_min = 0;   geom1.azi_max = 330;  geom1.azi_step = 30;             % azi min and max

% zenith injections (extra samples)
geom1.zen_inject_deg = [82 85 88];                                          % extra zeniths

% Source (sun/moon/none)
geom1.source = "moon";
% geom1.lun_phase_deg = [];                                                 % can optionally set this if source="moon"
                                                                            % otherwise it is calculated

% give it a label for file output naming
geom1.location_label = "HOGS";

%% 2) Aerosol / clouds parameters
aer = modtran.parameters.aerosol();
aer.visib_km = 0.5;                                                         % visibility is given in MODTRAN as %2 contrast (not %5)
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
rt = modtran.parameters.rt_options();                                       % depends on source
rt.NSTR = 16;                                                               % set number of distort streams to 16 (8 gave negative scattering values)

%% 6) Atmosphere parameters
atm = modtran.parameters.atmosphere();
atm.MODEL = "ATM_MIDLAT_WINTER";
atm.M2_RHC = true;                                                          % humidity correction

%% 7) Output files
word = "Transm";

% Recommended: auto-generate a base name that encodes the run setup.
zenStepForName = geom1.zen_step;
aziStepForName = geom1.azi_step;

% make base name where wmin/wmax are always in nm
jsonBase1 = modtran.jsonCaseGenerator.makeJsonBaseName( ...
    geom1.location_label, geom1.source, utcDT, aer.visib_km, aer.clouds, spec.V1, spec.V2, zenStepForName, aziStepForName);


%% Build JSON
json_name_1 = jsonBase1 + ".json";
out_csv_1   = jsonBase1 + "_summary.csv";

[jsonOut1, summaryTable1] = modtran.jsonCaseGenerator.buildAndWrite( ...
    geom1, aer, spec, surf, rt, atm, ...
    word, json_name_1, out_csv_1, ...
    saveDir=saveDir, makeJsonFolder=true);

disp(summarySep{1});