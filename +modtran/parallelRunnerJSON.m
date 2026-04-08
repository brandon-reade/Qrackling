% Author: Brandon Reade
% Date: 24/03/2026
% MODTRAN parallel runner for JSON case files
%
% Multi-case file format produced by jsonCaseGenerator.m is:
%  { "MODTRAN": [ case1, case2, ... ] }
%
% For correct usage each per-case input.json must be:
%  { "MODTRAN": [ caseN ] }
%
% To do:
% - fix duplicate matching or remove the redundant duplicate checks
% - remove the reruns and automatically use the method of
%   generating a filtered JSON to get missing data points
% - need to update with the error handling (present in the Python script)

classdef parallelRunnerJSON
    methods (Static)

        function results = runCasesParallel(cases_json, runs_dir, modtran_exe, modtran_data_dir, options)
            arguments
                cases_json (1,1) string
                runs_dir (1,1) string
                modtran_exe (1,1) string
                modtran_data_dir (1,1) string

                % worker options
                options.maxWorkers (1,1) double = max(1, feature("numcores")-1)
                options.timeout_s (1,1) double = NaN

                % file options
                options.outputMode (1,1) string {mustBeMember(options.outputMode,["per-case","shared"])} = "shared"     % shared for outputs being copied into a single location, otherwise per-case folders
                options.collectDir (1,1) string = ""
                options.collectGlob (1,:) string = strings(1,0)

                % verification options
                options.verifyCollect (1,1) logical = true                  % checks if the collection file has all the outputs expected
                options.rerunMissing (1,1) logical = true                   % runs processes for missing collection files
                options.dedupeCollect (1,1) logical = false                 % used to enable deletion of duplicate output files

                % other options
                options.keepWorkdirs (1,1) logical = false
                options.keepFailedWorkdirs (1,1) logical = false
                options.resume (1,1) logical = true                         % if true, skip cases with the 'done' marker

                % elapsed time
                options.printTotalElapsed (1,1) logical = true              % prints total elapsed time for the whole run

                % collection naming controls
                options.collectPrefixMode (1,1) string {mustBeMember(options.collectPrefixMode,["index","index_name"])} = "index_name"
                % "index"      => prefix is "000013"
                % "index_name" => prefix is "000013_<caseName>"

                % strict collection requirement per case
                options.requireCollectedPerCase (1,1) double = 1            % require at least N collected files per case/glob (typically 1)

                % define required outputs in the per-case workdir
                % If MODTRAN returns rc==0 but these files are not present, we treat it as a failure and (optionally) rerun.
                options.requiredWorkdirGlob (1,:) string = strings(1,0)

                % when forceRerun==true, wipe the per-case workdir first (prevents "rc==0 but file missing" from stale state)
                options.cleanWorkdirOnRerun (1,1) logical = true

                % if requiredWorkdirGlob is missing after a run, automatically rerun (within the same call)
                options.rerunIfMissingRequiredOutputs (1,1) logical = true

                % maximum attempts per case for missing required outputs (total attempts = 1 + maxRerunsMissingRequiredOutputs)
                options.maxRerunsMissingRequiredOutputs (1,1) double = 1
            end

            tTotal = tic;

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
                    error("parallelRunnerJSON:collectGlob", "outputMode='shared' requires options.collectGlob.");
                end
            end
            if (options.verifyCollect || options.rerunMissing || options.dedupeCollect) && options.outputMode ~= "shared"
                error("parallelRunnerJSON:verifyMode", "verifyCollect/rerunMissing/dedupeCollect only make sense when outputMode='shared'.");
            end

            cases = modtran.parallelRunnerJSON.loadCases(cases_json);
            nCases = numel(cases);

            fprintf("Cases file:      %s\n", cases_json);
            fprintf("Runs dir:        %s\n", runs_dir);
            fprintf("Cases:           %d\n", nCases);
            fprintf("Workers:         %d\n", options.maxWorkers);
            fprintf("MODTRAN exe:     %s\n", modtran_exe);
            fprintf("MODTRAN data:    %s\n", modtran_data_dir);
            fprintf("Output mode:     %s\n\n", options.outputMode);

            % Start pool
            pool = gcp("nocreate");
            if isempty(pool)
                parpool("Processes", options.maxWorkers);
            else
                % If a pool exists, do not force resize; just use it.
                fprintf("Using existing parallel pool with %d workers.\n\n", pool.NumWorkers);
            end

            % Use parfeval for process-like jobs so we can stream results as they finish
            f = parallel.FevalFuture.empty(0,1);
            for i = 1:nCases
                f(i,1) = parfeval( ...
                    @modtran.parallelRunnerJSON.runOneCase, ...
                    1, ...                                                  % one output: result struct
                    cases{i}, i, runs_dir, ...
                    modtran_exe, modtran_data_dir, ...
                    options, false);                                        % forceRerun=false
            end

            results = repmat(modtran.parallelRunnerJSON.emptyResult(), nCases, 1);
            nDone = 0;

            while nDone < nCases
                try
                    [idx, r] = fetchNext(f);
                catch ME
                    disp(getReport(ME, "extended", "hyperlinks", "off"));
                    rethrow(ME);
                end

                results(idx) = r;
                nDone = nDone + 1;

                if r.skipped
                    status = "SKIP";
                elseif r.returncode == 0
                    status = "OK";
                else
                    status = "FAIL";
                end

                fprintf("[%s] case=%06d elapsed=%7.2fs workdir=%s\n", ...
                    status, r.case_index, r.elapsed_s, r.workdir);
            end

            % Write summary.json
            summaryPath = fullfile(runs_dir, "summary.json");
            jsonText = jsonencode(results, "PrettyPrint", true);
            modtran.parallelRunnerJSON.writeText(summaryPath, jsonText);
            fprintf("\nSummary written: %s\n", summaryPath);

            nFail = sum(arrayfun(@(x) ~x.skipped && x.returncode ~= 0, results));
            fprintf("Failures: %d/%d\n", nFail, nCases);

            % print total elapsed
            if options.printTotalElapsed
                fprintf("Total elapsed: %.2f s\n", toc(tTotal));
            end

            % Dedupe first (helps the missing-check not get confused by duplicates)
            if options.outputMode == "shared" && options.dedupeCollect
                fprintf("\nDe-duplicating collected outputs in: %s\n", options.collectDir);
                removed = modtran.parallelRunnerJSON.dedupeCollectedFiles(options.collectDir);
                fprintf("Removed %d duplicate files.\n", removed);
            end

            % verify output collection and optionally rerun missing cases
            if options.outputMode == "shared" && (options.verifyCollect || options.rerunMissing)
                [missingIdx, missingInfo] = modtran.parallelRunnerJSON.findMissingCollectedCases( ...
                    cases, options.collectDir, options.collectGlob, ...
                    prefixMode=options.collectPrefixMode, ...
                    requireCollectedPerCase=options.requireCollectedPerCase);

                if ~isempty(missingIdx)
                    fprintf("\nMissing collected outputs for %d cases.\n", numel(missingIdx));

                    if options.rerunMissing
                        fprintf("Re-running missing cases (force rerun)...\n");

                        for j = 1:numel(missingIdx)
                            i = missingIdx(j);
                            fprintf("  Re-run case %06d (missing globs: %s)\n", i, strjoin(string(missingInfo{j}.missingGlobs), ", "));

                            % Force rerun so it will run even if done.json exists
                            rr = modtran.parallelRunnerJSON.runOneCase( ...
                                cases{i}, i, runs_dir, modtran_exe, modtran_data_dir, options, true);

                            results(i) = rr;
                        end

                        % Re-write summary after reruns
                        jsonText = jsonencode(results, "PrettyPrint", true);
                        modtran.parallelRunnerJSON.writeText(summaryPath, jsonText);
                        fprintf("Updated summary written: %s\n", summaryPath);

                        if options.printTotalElapsed
                            fprintf("Total elapsed (incl. reruns): %.2f s\n", toc(tTotal));
                        end
                    else
                        fprintf("verifyCollect enabled but rerunMissing disabled. No reruns performed.\n");
                    end
                else
                    fprintf("\nNo missing collected outputs detected.\n");
                end
            end
        end

        function [missingIdx, newJsonPath] = repairMissingFromCollection(cases_json, collect_dir, collect_glob, out_json_path, options)
            % Creates a new JSON containing only missing cases, then optionally runs it.
            %
            % Usage:
            %   [missingIdx, newJson] = modtran.parallelRunnerJSON.repairMissingFromCollection(...)
            %
            % This DOES NOT run MODTRAN by itself; it just generates the filtered JSON.
            % You can then call runCasesParallel on newJsonPath.

            arguments
                cases_json (1,1) string
                collect_dir (1,1) string
                collect_glob (1,:) string
                out_json_path (1,1) string

                options.prefixMode (1,1) string {mustBeMember(options.prefixMode,["index","index_name"])} = "index_name"
                options.requireCollectedPerCase (1,1) double = 1
            end

            cases_json = modtran.parallelRunnerJSON.mustBeFile(cases_json);
            if ~exist(collect_dir, "dir")
                error("parallelRunnerJSON:collectDir", "collect_dir does not exist: %s", collect_dir);
            end

            cases = modtran.parallelRunnerJSON.loadCases(cases_json);

            [missingIdx, ~] = modtran.parallelRunnerJSON.findMissingCollectedCases( ...
                cases, collect_dir, collect_glob, ...
                prefixMode=options.prefixMode, ...
                requireCollectedPerCase=options.requireCollectedPerCase);

            if isempty(missingIdx)
                newJsonPath = "";
                fprintf("No missing cases detected; not writing a repair JSON.\n");
                return;
            end

            % Build a new MODTRAN list with only missing cases
            out = struct();
            out.MODTRAN = cell(1, numel(missingIdx));
            for k = 1:numel(missingIdx)
                out.MODTRAN{k} = cases{missingIdx(k)};
            end
            % jsonencode needs structs/arrays, not cells in some versions; normalize
            out.MODTRAN = [out.MODTRAN{:}];

            newJsonPath = string(out_json_path);
            modtran.parallelRunnerJSON.ensureDir(fileparts(newJsonPath));
            modtran.parallelRunnerJSON.writeText(newJsonPath, jsonencode(out, "PrettyPrint", true));

            fprintf("Wrote repair JSON containing %d missing cases:\n  %s\n", numel(missingIdx), newJsonPath);
        end

        function removed = dedupeCollectedFiles(collectDir)
            % Removes duplicates like:
            %   prefix__example_scan.csv
            %   prefix__example_scan__001.csv
            %
            % Keeps the newest file for each base-name group.

            removed = 0;

            files = dir(fullfile(collectDir, "*"));
            files = files(~[files.isdir]);

            mp = containers.Map("KeyType","char","ValueType","any");

            for k = 1:numel(files)
                name = string(files(k).name);

                % remove trailing "__NNN" before the extension if present
                key = modtran.parallelRunnerJSON.stripTrailingNumericSuffix(name);

                if ~isKey(mp, char(key))
                    mp(char(key)) = files(k);
                else
                    mp(char(key)) = [mp(char(key)), files(k)];
                end
            end

            keysList = mp.keys;
            for ki = 1:numel(keysList)
                group = mp(keysList{ki});
                if numel(group) <= 1
                    continue;
                end

                [~, idxKeep] = max([group.datenum]);
                for j = 1:numel(group)
                    if j == idxKeep
                        continue;
                    end
                    try
                        delete(fullfile(group(j).folder, group(j).name));
                        removed = removed + 1;
                    catch
                    end
                end
            end
        end
    end

    %% Private functions
    methods (Static, Access = private)

        function r = runOneCase(caseObj, case_index, runs_dir, modtran_exe, modtran_data_dir, options, forceRerun)
            tStart = tic;

            case_name = modtran.parallelRunnerJSON.tryGetCaseName(caseObj, case_index);
            safe_name = modtran.parallelRunnerJSON.sanitizeFilename(case_name);
            workdir = fullfile(runs_dir, sprintf("%06d_%s", case_index, safe_name));

            r = modtran.parallelRunnerJSON.emptyResult();
            r.case_index = case_index;
            r.case_name = case_name;
            r.workdir = workdir;

            % If resume enabled and done marker exists, skip
            doneMarker = fullfile(workdir, "done.json");
            if options.resume && ~forceRerun && exist(doneMarker, "file")
                r.skipped = true;
                r.skip_reason = "already_done";
                r.returncode = 0;
                r.elapsed_s = toc(tStart);
                return;
            end

            if exist(workdir, "dir")
                % Keep prior dir (resume support); do not delete automatically.
            else
                mkdir(workdir);
            end

            % If forceRerun and clean requested, wipe workdir contents
            if forceRerun && options.cleanWorkdirOnRerun
                modtran.parallelRunnerJSON.cleanWorkdir(workdir);
            end

            % Dedup: acquire exclusive lock (directory based; no fopen('x') on network shares)
            lockDir = fullfile(workdir, "_lockdir");
            locked = modtran.parallelRunnerJSON.tryAcquireLockDir(lockDir);
            if ~locked
                r.skipped = true;
                r.skip_reason = "lock_exists";
                r.returncode = 0;
                r.elapsed_s = toc(tStart);
                return;
            end

            c = onCleanup(@() modtran.parallelRunnerJSON.releaseLockDir(lockDir)); 

            % Attempt loop: sometimes MODTRAN returns rc==0 but the expected CSV isn't produced.
            % We treat "missing required outputs" as a failure and can rerun after cleaning the workdir.
            attempt = 0;
            maxAttempts = 1 + max(0, options.maxRerunsMissingRequiredOutputs);

            while true
                attempt = attempt + 1;

                input_json = fullfile(workdir, "input.json");
                modtran.parallelRunnerJSON.writeCaseJson(caseObj, input_json);

                stdout_path = fullfile(workdir, "stdout.txt");
                stderr_path = fullfile(workdir, "stderr.txt");
                command_txt = fullfile(workdir, "command.txt");

                args = sprintf('"%s" "%s" "%s" -workpath "%s"', ...
                    modtran_exe, input_json, modtran_data_dir, workdir);

                modtran.parallelRunnerJSON.writeText(command_txt, ...
                    "MODE: mod6con" + newline + ...
                    "ARGS:" + newline + args + newline + ...
                    "ATTEMPT:" + newline + string(attempt) + newline);

                % Run mod6con
                try
                    exeDir = fileparts(modtran_exe);

                    % pushd/popd so relative DLL dependencies resolve
                    oldDir = pwd;
                    cleanupDir = onCleanup(@() cd(oldDir)); 
                    cd(exeDir);

                    if isnan(options.timeout_s)
                        [rc, out] = system(args);
                    else
                        [rc, out] = modtran.parallelRunnerJSON.systemWithTimeout(args, options.timeout_s);
                    end
                catch ME
                    rc = 999;
                    out = getReport(ME, "extended", "hyperlinks", "off");
                end

                % system() merges stdout/stderr; we'll write it to stdout.txt and leave stderr.txt for future enhancement
                modtran.parallelRunnerJSON.writeText(stdout_path, out);
                if ~exist(stderr_path, "file")
                    modtran.parallelRunnerJSON.writeText(stderr_path, "");
                end

                r.stdout_path = stdout_path;
                r.stderr_path = stderr_path;
                r.returncode = rc;

                % If rc==0, verify required outputs exist in workdir (if configured).
                % If missing, optionally clean and rerun.
                missingReq = strings(0,1);
                if rc == 0 && ~isempty(options.requiredWorkdirGlob)
                    [okReq, missingReq] = modtran.parallelRunnerJSON.hasRequiredOutputs(workdir, options.requiredWorkdirGlob);
                    if ~okReq
                        % Mark as failure (even if MODTRAN says rc==0)
                        r.returncode = 998;
                        r.skip_reason = "missing_required_outputs";
                        try
                            modtran.parallelRunnerJSON.writeText(fullfile(workdir, "missing_outputs.txt"), ...
                                "Missing required outputs:" + newline + strjoin(missingReq, newline));
                        catch
                        end

                        if options.rerunIfMissingRequiredOutputs && attempt < maxAttempts
                            % Clean and retry
                            modtran.parallelRunnerJSON.cleanWorkdir(workdir);
                            continue;
                        end
                    end
                end

                % Exit loop if either: rc != 0, or required outputs are present, or we exhausted attempts.
                break;
            end

            % Collect outputs (shared mode)
            collected = strings(0,1);
            if options.outputMode == "shared" && r.returncode == 0
                prefix = modtran.parallelRunnerJSON.casePrefix(case_index, case_name, options.collectPrefixMode);
                collected = modtran.parallelRunnerJSON.collectOutputs(workdir, options.collectGlob, options.collectDir, prefix);
            end
            r.collected_files = collected;

            % Write done marker on success (only if required outputs are OK, too)
            if r.returncode == 0
                donePayload = struct("case_index", case_index, "case_name", case_name, "workdir", workdir, "timestamp", char(datetime("now")));
                modtran.parallelRunnerJSON.writeText(doneMarker, jsonencode(donePayload, "PrettyPrint", true));
            end

            % Cleanup workdirs if requested
            if r.returncode == 0
                if ~options.keepWorkdirs
                    % remove unless we need it for shared collection auditing
                    if options.outputMode ~= "shared"
                        rmdir(workdir, "s");
                    end
                end
            else
                if ~options.keepFailedWorkdirs
                    rmdir(workdir, "s");
                end
            end

            r.elapsed_s = toc(tStart);
        end

        function prefix = casePrefix(case_index, case_name, mode)
            safe_name = modtran.parallelRunnerJSON.sanitizeFilename(case_name);
            if mode == "index"
                prefix = sprintf("%06d", case_index);
            else
                prefix = sprintf("%06d_%s", case_index, safe_name);
            end
        end

        function [missingIdx, missingInfo] = findMissingCollectedCases(cases, collectDir, collectGlob, options)
            arguments
                cases
                collectDir (1,1) string
                collectGlob (1,:) string
                options.prefixMode (1,1) string {mustBeMember(options.prefixMode,["index","index_name"])} = "index_name"
                options.requireCollectedPerCase (1,1) double = 1
            end

            missingIdx = [];
            missingInfo = {};

            for i = 1:numel(cases)
                case_name = modtran.parallelRunnerJSON.tryGetCaseName(cases{i}, i);
                prefix = modtran.parallelRunnerJSON.casePrefix(i, case_name, options.prefixMode);

                miss = struct();
                miss.case_index = i;
                miss.case_name = case_name;
                miss.prefix = prefix;
                miss.missingGlobs = strings(0,1);

                for g = collectGlob
                    q = fullfile(collectDir, prefix + "__" + string(g));
                    m = dir(q);

                    if numel(m) < options.requireCollectedPerCase
                        miss.missingGlobs(end+1,1) = string(g); 
                    end
                end

                if ~isempty(miss.missingGlobs)
                    missingIdx(end+1,1) = i; 
                    missingInfo{end+1,1} = miss; 
                end
            end
        end

        function key = stripTrailingNumericSuffix(filename)
            % filename example:
            %   "000013_...__Transm_..._scan.csv"
            %   "000013_...__Transm_..._scan__001.csv"
            %
            % We want these to map to the same key.
            %
            % rule: if stem ends with "__\d{3}", strip it.

            filename = string(filename);
            [~, stem, ext] = fileparts(filename);

            if ~isempty(regexp(stem, "__\d{3}$", "once"))
                stem = regexprep(stem, "__\d{3}$", "");
            end

            key = stem + ext;
        end

        function cases = loadCases(cases_json_path)
            txt = fileread(cases_json_path);
            data = jsondecode(txt);

            if ~isstruct(data) || ~isfield(data, "MODTRAN")
                error("parallelRunnerJSON:format", "Expected top-level key 'MODTRAN' containing a JSON array.");
            end

            % jsondecode may return a cell array OR a struct array for JSON arrays
            if iscell(data.MODTRAN)
                cases = data.MODTRAN;
                return;
            end

            if isstruct(data.MODTRAN)
                cases = num2cell(data.MODTRAN);   % convert struct array -> cell array of structs
                return;
            end

            error("parallelRunnerJSON:format", "Top-level 'MODTRAN' exists but is not an array.");
        end

        function writeCaseJson(caseObj, out_path)
            % Ensure { "MODTRAN": [ case ] }
            payload = struct();
            if isstruct(caseObj) && isfield(caseObj, "MODTRAN") && iscell(caseObj.MODTRAN)
                payload = caseObj;
            else
                payload.MODTRAN = {caseObj};
            end
            modtran.parallelRunnerJSON.writeText(out_path, jsonencode(payload, "PrettyPrint", true));
        end

        function nm = tryGetCaseName(caseObj, case_index)
            nm = "case_" + string(case_index);
            try
                if isstruct(caseObj) && isfield(caseObj, "MODTRANINPUT") && isfield(caseObj.MODTRANINPUT, "NAME")
                    nm = string(caseObj.MODTRANINPUT.NAME);
                elseif isstruct(caseObj) && isfield(caseObj, "MODTRANINPUT")
                    % sometimes jsondecode yields nested structs differently, keep the default
                end
            catch
                % ignore and keep default
            end
        end

        function s = sanitizeFilename(s, max_len)
            if nargin < 2
                max_len = 120;
            end
            s = string(s);
            s = strtrim(s);
            s = regexprep(s, "[^\w\-. ]+", "_");
            s = regexprep(s, "\s+", "_");
            if strlength(s) > max_len
                s = extractBetween(s, 1, max_len);
            end
            if strlength(s) == 0
                s = "case";
            end
        end

        function ok = tryAcquireLockDir(lockDir)
            % Directory-based lock to avoid fopen(...,"x")
            % Returns ok=true if lock acquired or ok=false if already locked.
            parent = fileparts(lockDir);
            if ~exist(parent, "dir")
                mkdir(parent);
            end
            ok = mkdir(lockDir);  % returns false if it already exists
        end

        function releaseLockDir(lockDir)
            if exist(lockDir, "dir")
                try
                    rmdir(lockDir);
                catch
                end
            end
        end

        function collected = collectOutputs(workdir, globs, dest_dir, prefix)
            collected = strings(0,1);
            if ~exist(dest_dir, "dir")
                mkdir(dest_dir);
            end

            for g = globs
                files = dir(fullfile(workdir, g));
                for k = 1:numel(files)
                    if files(k).isdir
                        continue;
                    end

                    src = fullfile(files(k).folder, files(k).name);

                    % IMPORTANT:
                    % outName = <prefix>__<original_filename>
                    outName = prefix + "__" + string(files(k).name);

                    dst = modtran.parallelRunnerJSON.uniqueDestPath(dest_dir, outName);
                    copyfile(src, dst);
                    collected(end+1,1) = string(dst); 
                end
            end
        end

        function dst = uniqueDestPath(dest_dir, desired_name)
            desired_name = string(desired_name);
            [~, base, ext] = fileparts(desired_name);

            candidate = fullfile(dest_dir, base + ext);
            if ~exist(candidate, "file")
                dst = candidate;
                return;
            end

            i = 1;
            while true
                candidate = fullfile(dest_dir, sprintf("%s__%03d%s", base, i, ext));
                if ~exist(candidate, "file")
                    dst = candidate;
                    return;
                end
                i = i + 1;
            end
        end

        function path = mustBeFile(path)
            path = string(path);
            if ~exist(path, "file")
                error("parallelRunnerJSON:path", "File not found: %s", path);
            end
        end

        function path = mustBeDir(path)
            path = string(path);
            if ~exist(path, "dir")
                error("parallelRunnerJSON:path", "Directory not found: %s", path);
            end
        end

        function path = ensureDir(path)
            path = string(path);
            if strlength(strtrim(path)) == 0
                return;
            end
            if ~exist(path, "dir")
                mkdir(path);
            end
        end

        function writeText(path, txt)
            [fid, errmsg] = fopen(path, "w");
            if fid < 0
                error("parallelRunnerJSON:io", ...
                    "Failed to open file for writing: %s (fopen: %s)", string(path), string(errmsg));
            end
            fwrite(fid, char(txt), "char");
            fclose(fid);
        end

        function [rc, out] = systemWithTimeout(cmd, timeout_s)
            % use PowerShell Start-Process and Wait-Process with timeout.
            % could replace with a Java ProcessBuilder for more control.

            ps = sprintf([ ...
                'powershell -NoProfile -Command ' ...
                '"$p=Start-Process -FilePath cmd.exe -ArgumentList ''/c %s'' -PassThru -NoNewWindow -RedirectStandardOutput $env:TEMP\\m6out.txt -RedirectStandardError $env:TEMP\\m6err.txt;' ...
                'if(-not $p.WaitForExit(%d)){$p.Kill(); exit 124} else {exit $p.ExitCode}"'], ...
                strrep(cmd, '"', '\"'), round(timeout_s*1000));

            [rc, ~] = system(ps);
            outFile = fullfile(getenv("TEMP"), "m6out.txt");
            errFile = fullfile(getenv("TEMP"), "m6err.txt");
            out = "";
            if exist(outFile, "file")
                out = out + string(fileread(outFile));
            end
            if exist(errFile, "file")
                out = out + newline + "STDERR:" + newline + string(fileread(errFile));
            end
        end

        function r = emptyResult()
            r = struct();
            r.case_index = 0;
            r.case_name = "";
            r.workdir = "";
            r.returncode = int32(0);
            r.elapsed_s = 0.0;
            r.stdout_path = "";
            r.stderr_path = "";
            r.collected_files = strings(0,1);
            r.skipped = false;
            r.skip_reason = "";
        end

        function [ok, missingGlobs] = hasRequiredOutputs(workdir, globs)
            ok = true;
            missingGlobs = strings(0,1);
            for g = globs
                m = dir(fullfile(workdir, g));
                if isempty(m)
                    ok = false;
                    missingGlobs(end+1,1) = string(g);
                end
            end
        end

        function cleanWorkdir(workdir)
            if ~exist(workdir, "dir")
                return;
            end
            d = dir(workdir);
            for k = 1:numel(d)
                nm = d(k).name;
                if nm == "." || nm == ".."
                    continue;
                end
                p = fullfile(d(k).folder, nm);
                if d(k).isdir
                    % safer to remove lockdir when forcing rerun
                    try rmdir(p, "s"); catch, end
                else
                    try delete(p); catch, end
                end
            end
        end
    end
end