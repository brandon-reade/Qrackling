% Author:   Brandon Reade
% Date:     26/03/2026 
% Updated:  17/04/2026
% Generating a JSON containing missing data from a previous input file 
% and running only missing cases

%% Define directories
% repo root
repo_root = utilities.addUserPath('~\Documents\GitHub\Qrackling');  
addpath(fullfile(repo_root));  

% JSON root
jsonDir = fullfile(repo_root, "+modtran", "JSON_Cases");
filename = "Goldstone_moon_Jun21_1am_23kmvis_300to10000_zenstep10_azistep30";
json_file = "Goldstone_moon_Jun21_1am_23kmvis_300to10000_zenstep10_azistep30.json";
cases_json = fullfile(jsonDir, filename, json_file);

% MODTRAN roots
runs_dir = "E:\MODTRAN_RESULTS\runs_tmp";
modtran_exe = "E:\MODTRAN\MODTRAN6\x86_64\mod6con.exe";
modtran_data_dir = "E:\MODTRAN\MOD6DATA";

% collection dir
collect_dir = fullfile(repo_root,"+modtran","Data","Goldstone", filename);
collect_glob = "*_scan.csv";                                                % file type to collect

% repair root
repair_json = fullfile(runs_dir, "repair_json", filename + "__missing_only.json");

%% Choose options
opts = struct();
opts.maxWorkers = 12;
opts.skipInitialRun = true;                                                 % skip initial run (assume already done)

opts.outputMode = "shared";
opts.collectDir = collect_dir;
opts.collectGlob = collect_glob;
opts.collectPrefixMode = "index";                                           % collect by index case
opts.requireCollectedPerCase = 1;

% check that there is no "nan" data
opts.checkCollectedQuality = true;
opts.deleteBadCollected = true;

% force zenith change for "nan" cases
opts.repairForceZenEps = true;
opts.repairZenEps_deg = 1;                                               % try 1e-2 if still NaN

opts.dedupeCollect = true;
opts.verifyCollect = true;

opts.repairForceLbl =  true;                                                % force line-by-line on a repair
opts.repairMissing = true;                                                 % repair based on the missing data points in the collection dir
opts.repairMaxPasses = 3;
opts.repairOutJson = fullfile(runs_dir, "missing_only.json");

% try to "force" problematic cases to generate outputs
opts.requiredWorkdirGlob = "*_scan.csv";
opts.rerunIfMissingRequiredOutputs = true;
opts.maxRerunsMissingRequiredOutputs = 2;

nv = utilities.structToNameValues(opts);
modtran.parallelRunnerJSON.runCasesParallel( ...
    cases_json, runs_dir, modtran_exe, modtran_data_dir, nv{:});

if opts.dedupeCollect
    removed = modtran.parallelRunnerJSON.dedupeCollectedFiles(opts.collectDir);
    fprintf("De-dupe removed: %d\n", removed);
end