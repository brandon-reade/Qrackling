% Author: Brandon Reade
% Date: 24/03/2026
% run MODTRAN6 JSON cases in parallel

%% Directories
% Derive the repository root
repo_root = utilities.addUserPath('~\Documents\GitHub\Qrackling');  
addpath(fullfile(repo_root));  

% set the file name
filename = "HOGS_moon_Jan3_1am_500mvis_100to10000_zenstep10_azistep30";

% set the json file to input into modtran
cases_json = fullfile(repo_root, "+modtran", "JSON_Cases", ...
    filename, ...
    filename+".json");

% MODTRAN dirs
runs_dir = "E:\MODTRAN_RESULTS\runs_tmp";                                   % choose where to place the results
modtran_exe = "E:\MODTRAN\MODTRAN6\x86_64\mod6con.exe";                     % change to wherever the MODTRAN exe is (depends on install)
modtran_data_dir = "E:\MODTRAN\MOD6DATA";                                   % change to wherver the MODTRAN data files are (depends on install)

% Optional shared collection
collect_dir = "E:\MODTRAN_RESULTS\collect";                                 % choose where to collect the files of interest
collect_glob = "*_scan.csv";                                                % set the files of interest to be the csv scan files

%% Use the parallel runner
results = modtran.parallelRunnerJSON.runCasesParallel( ...
    cases_json, runs_dir, modtran_exe, modtran_data_dir, ...                % configuring files and dirs
    maxWorkers=10, ...                                                      % maximum workers   
    outputMode="shared", ...                                                % outputs are copied into a shared location
    collectDir=collect_dir, ...                                             % dir for desired output files
    collectGlob=collect_glob, ...                                           % file of interest
    keepFailedWorkdirs=false, ...                                           % delete directories of failed runs
    keepWorkdirs=false, ...                                                 % delete directores of all runs
    resume=true, ...                                                        % check for 'done' flag, go to next case if it has been 'done'
    verifyCollect=true,...                                                  % check that all output files are present as expected
    rerunMissing=true, ...                                                  % rerun missing cases if they are missing
    dedupeCollect=true);                                                    % check and remove any duplicate output files