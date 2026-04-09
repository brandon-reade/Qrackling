% Author: Brandon Reade
% Date: 09/04/2026
% Parallel run for MODTRAN followed by a repair run to find missing data
% points

%% Define directories
% repo root
repo_root = utilities.addUserPath('~\Documents\GitHub\Qrackling');  
addpath(fullfile(repo_root));  

% JSON root
jsonDir = fullfile(repo_root, "+modtran", "JSON_Cases");
json_root = "HOGS_sun_Jan3_8am_1kmvis_300to10000_zenstep10_azistep30";
json_file = "HOGS_sun_Jan3_8am_1kmvis_300to10000_zenstep10_azistep30.json";
cases_json = fullfile(json_root, json_file + ".json");

% MODTRAN roots
runs_dir = "E:\MODTRAN_RESULTS\runs_tmp";
modtran_exe = "E:\MODTRAN\MODTRAN6\x86_64\mod6con.exe";
modtran_data_dir = "E:\MODTRAN\MOD6DATA";

%% Define options
opts = struct();
opts.maxWorkers = 10;

opts.outputMode = "shared";
opts.collectDir = fullfile(repo_root, "+modtran", "Data", "collect_" + filename);
opts.collectGlob = "*_scan.csv";
opts.collectPrefixMode = "index";                                           % collect by case number
opts.requireCollectedPerCase = 1;

opts.dedupeCollect = true;
opts.verifyCollect = true;

% detect "rc==0 but CSV missing" and auto retry per-case:
opts.requiredWorkdirGlob = "*_scan.csv";
opts.rerunIfMissingRequiredOutputs = true;
opts.maxRerunsMissingRequiredOutputs = 2;

% Multi-pass repair with only missing cases JSON:
opts.repairMissing = true;
opts.repairMaxPasses = 2;
opts.repairOutJson = "E:\MODTRAN_RESULTS\collect\missing_only.json";
opts.repairForceLbl = true;                                                 % optional LBL RT Option

modtran.parallelRunnerJSON.runCasesParallel( ...
    cases_json, runs_dir, modtran_exe, modtran_data_dir, opts);