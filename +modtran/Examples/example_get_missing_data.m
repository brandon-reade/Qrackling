% Author: Brandon Reade
% Date: 26/03/2026 (Updated 09/04/2026)
% Generating a JSON containing missing data from a previous input file 
% and running only missing cases

%% Define directories
% repo root
repo_root = utilities.addUserPath('~\Documents\GitHub\Qrackling');  
addpath(fullfile(repo_root));  

% JSON root
jsonDir = fullfile(repo_root, "+modtran", "JSON_Cases");
filename = "HOGS_sun_Jan3_8am_5kmvis_300to10000_zenstep10_azistep30";
json_file = "HOGS_sun_Jan3_8am_5kmvis_300to10000_zenstep10_azistep30.json";
cases_json = fullfile(jsonDir, filename, json_file);

% MODTRAN roots
runs_dir = "E:\MODTRAN_RESULTS\runs_tmp";
modtran_exe = "E:\MODTRAN\MODTRAN6\x86_64\mod6con.exe";
modtran_data_dir = "E:\MODTRAN\MOD6DATA";

% collection dir
collect_dir = fullfile(repo_root,"+modtran","Data","HOGS", filename);
collect_glob = "*_scan.csv";                                                % file type to collect

% repair root
repair_json = fullfile(runs_dir, "repair_json", filename + "__missing_only.json");

%% Choose options
opts = struct();
opts.skipInitialRun = true;                                                 % skip initial run (assume already done)

opts.outputMode = "shared";
opts.collectDir = collect_dir;
opts.collectGlob = collect_glob;
opts.collectPrefixMode = "index";                                           % collect by index case
opts.requireCollectedPerCase = 1;

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

modtran.parallelRunnerJSON.runCasesParallel( ...
    cases_json, runs_dir, modtran_exe, modtran_data_dir, opts);

if options.dedupeCollect
    removed = modtran.parallelRunnerJSON.dedupeCollectedFiles(options.collectDir);
    fprintf("De-dupe removed: %d\n", removed);
end