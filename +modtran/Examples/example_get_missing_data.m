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
    newJsonPath, runs_dir, modtran_exe, modtran_data_dir, ...
    maxWorkers=10, ...
    outputMode="shared", ...
    collectDir=collect_dir, ...
    collectGlob=collect_glob, ...
    keepFailedWorkdirs=true, ...
    keepWorkdirs=true, ...
    resume=false, ...                 % do not skip, this is a targeted rerun JSON
    verifyCollect=true, ...
    rerunMissing=false, ...           % we already filtered to missing
    dedupeCollect=true, ...
    printTotalElapsed=true, ...
    collectPrefixMode="index_name", ...
    requireCollectedPerCase=1);

clear results_missing