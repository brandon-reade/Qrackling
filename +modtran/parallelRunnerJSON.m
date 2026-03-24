% Author: Brandon Reade
% Date: 24/03/2026
% MODTRAN parallel runner for JSON case files

% Multi-case file format produced by jsonCaseGenerator.m is:
%  { "MODTRAN": [ case1, case2, ... ] }

% For correct usage each per-case input.json is must be:
%  { "MODTRAN": [ caseN ] }   

classdef parallelRunnerJSON
    methods (Static)
        function results = runCasesParallel(cases_json, runs_dir, modtran_exe, modtran_data_dir, options)
            arguments
                cases_json  (1,1) string
                runs_dir    (1,1) string
                modtran_exe (1,1) string
                modtran_data_dir (1,1) string

                % options for the user to configure
                options.maxWorkers (1,1) double = max(1, feature("numcores"-1))  % ensure the number of cores on the device is not exceeded
                options.timeout_s (1,1) double = NaN

                options.outputMode (1,1) string {mustBeMember(options.outputMode,...
                    ["per-case", "shared"])} = "per_case"
                options.collectDir (1,1) string = ""
                options.collectGlob (1,:) string = strings(1,0)
                options.keepWorkdirs(1,1) logical = false
                options.keepFailedWorkdirs (1,1) logical = false
                options.resume (1,1) logical = true                         % when true: skip cases with done marker
            end

            cases_json = modtran.parallelRunnerJSON.mustBeFile(cases_json);
            runs_dir = modtran.parallelRunnerJSON.ensureDir(runs_dir);
            modtran_exe = modtran.parallelRunnerJSON.mustBeFile(modtran_exe);
            modtran_data_dir = modtran.parallelRunnerJSON.mustBeDir(modtran_data_dir);

            if options.outputMode == "shared"
                if strlength(strtrim(options.collectDir)) == 0
                    error("parallelRunnerJSON:collectDir", "outputMode='shared' requires options.collectDir.");
                end
                modtran.parallelRunnerJSON.ensureDir(options.collectDir);
                if isempty(options.collectGlob)
                    error("modtran6ParallelRunner:collectGlob", "outputMode='shared' requires options.collectGlob.");
                end
            end
        end
    end


end
