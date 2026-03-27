% Author: Brandon Reade
% Date: 26/03/2026
% Generating a JSON ocntaining missing data from a previous input file 
% and running only missing cases

%% Inputs
json_root = "E:\MODTRAN_RESULTS\HOGS_moon_Jan3_1am_500mvis_100to10000_zenstep10_azistep30";
filename = "HOGS_moon_Jan3_1am_500mvis_100to10000_zenstep10_azistep30";

cases_json = fullfile(json_root, filename + ".json");

runs_dir = "E:\MODTRAN_RESULTS\runs_tmp";
modtran_exe = "E:\MODTRAN\MODTRAN6\x86_64\mod6con.exe";
modtran_data_dir = "E:\MODTRAN\MOD6DATA";

collect_dir = fullfile(runs_dir, "collect_" + filename);
collect_glob = "*_scan.csv";

repair_json = fullfile(runs_dir, "repair_json", filename + "__missing_only.json");

%% 1. Dedupe first so missing-check is clean
removed = modtran.parallelRunnerJSON.dedupeCollectedFiles(collect_dir);
fprintf("Dedup removed: %d files\n", removed);

%% 2. Build a repair JSON for missing cases
[missingIdx, newJsonPath] = modtran.parallelRunnerJSON.repairMissingFromCollection( ...
    cases_json, collect_dir, collect_glob, repair_json, ...
    prefixMode="index_name", ...
    requireCollectedPerCase=1);

if isempty(missingIdx)
    fprintf("Nothing to repair.\n");
    return;
end

fprintf("Missing case indices:\n");
disp(missingIdx(:)');

%% 3. Run only the missing cases
results_missing = modtran.parallelRunnerJSON.runCasesParallel( ...
    cases_json, runs_dir, modtran_exe, modtran_data_dir, ...
    maxWorkers=8, ...
    outputMode="shared", ...
    collectDir=collect_dir, ...
    collectGlob="*_scan.csv", ...
    requiredWorkdirGlob="*_scan.csv", ...                                   % must exist in workdir
    rerunIfMissingRequiredOutputs=true, ...                                 % rerun if missing csvs
    maxRerunsMissingRequiredOutputs=1, ...                                  % try twice total
    cleanWorkdirOnRerun=true, ...                                           % clear work dirs for reruns
    keepFailedWorkdirs=true, ...
    keepWorkdirs=true);
clear results_missing