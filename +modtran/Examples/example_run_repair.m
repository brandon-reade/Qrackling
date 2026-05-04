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
filename = "HOGS_sun_Jun21_4am_500mvis_fog_radiative_300to10000_zenstep10_azistep30";
json_file = "HOGS_sun_Jun21_4am_500mvis_fog_radiative_300to10000_zenstep10_azistep30.json";
cases_json = fullfile(jsonDir, filename, json_file);

% MODTRAN roots
runs_dir = "E:\MODTRAN_RESULTS\runs_tmp";
modtran_exe = "E:\MODTRAN\MODTRAN6\x86_64\mod6con.exe";
modtran_data_dir = "E:\MODTRAN\MOD6DATA";

% collection dir
collect_dir = fullfile(repo_root,"+modtran","Data","HOGS", filename);
collect_glob = "*_scan.csv";                                                % file type to collect

%% Define options
opts = struct();
opts.maxWorkers = 12;

opts.outputMode = "shared";
opts.collectDir = collect_dir;
opts.collectGlob = collect_glob;
opts.collectPrefixMode = "index";                                           % collect by case number
opts.requireCollectedPerCase = 1;

opts.dedupeCollect = true;
opts.verifyCollect = true;

% check that there is no "nan" data
opts.checkCollectedQuality = true;
opts.deleteBadCollected = true;

% detect "rc==0 but CSV missing" and auto retry per-case:
opts.requiredWorkdirGlob = "*_scan.csv";
opts.rerunIfMissingRequiredOutputs = true;
opts.maxRerunsMissingRequiredOutputs = 2;

% Multi-pass repair with only missing cases JSON:
opts.repairMissing = true;
opts.repairMaxPasses = 3;
opts.repairOutJson = "E:\MODTRAN_RESULTS\collect\missing_only.json";
opts.repairForceLbl = true;                                                 % optional LBL RT Option

nv = utilities.structToNameValues(opts);
modtran.parallelRunnerJSON.runCasesParallel( ...
    cases_json, runs_dir, modtran_exe, modtran_data_dir, nv{:});

if opts.dedupeCollect
    removed = modtran.parallelRunnerJSON.dedupeCollectedFiles(opts.collectDir);
    fprintf("De-dupe removed: %d\n", removed);
end