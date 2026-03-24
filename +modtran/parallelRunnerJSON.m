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
                    cases(i), i, runs_dir, ...
                    modtran_exe, modtran_data_dir, ...
                    options, false);                                        % forceRerun=false
            end

            results = repmat(struct(), nCases, 1);
            nDone = 0;

            while nDone < nCases
                [idx, r] = fetchNext(f);
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

             % verify output collection and optionally rerun missing cases
            if options.outputMode == "shared" && (options.verifyCollect || options.rerunMissing)
                [missingIdx, missingPatterns] = modtran.parallelRunnerJSON.findMissingCollectedCases( ...
                    cases, results, options.collectDir, options.collectGlob);

                if ~isempty(missingIdx)
                    fprintf("\nMissing collected outputs for %d cases.\n", numel(missingIdx));
                    if options.rerunMissing
                        fprintf("Re-running missing cases (force rerun)...\n");

                        for j = 1:numel(missingIdx)
                            i = missingIdx(j);
                            fprintf("  Re-run case %06d (missing patterns: %s)\n", i, strjoin(missingPatterns{j}, ", "));

                            % Force rerun so it will run even if done.json exists
                            rr = modtran.parallelRunnerJSON.runOneCase( ...
                                cases(i), i, runs_dir, modtran_exe, modtran_data_dir, options, true);

                            results(i) = rr;
                        end

                        % Re-write summary after reruns
                        jsonText = jsonencode(results, "PrettyPrint", true);
                        modtran.parallelRunnerJSON.writeText(summaryPath, jsonText);
                        fprintf("Updated summary written: %s\n", summaryPath);
                    else
                        fprintf("verifyCollect enabled but rerunMissing disabled. No reruns performed.\n");
                    end
                else
                    fprintf("\nNo missing collected outputs detected.\n");
                end
            end

            % dedupe collected files
            if options.outputMode == "shared" && options.dedupeCollect
                fprintf("\nDe-duplicating collected outputs in: %s\n", options.collectDir);
                removed = modtran.parallelRunnerJSON.dedupeCollectedFiles(options.collectDir);
                fprintf("Removed %d duplicate files.\n", removed);
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

            r = struct();
            r.case_index = case_index;
            r.case_name = case_name;
            r.workdir = workdir;
            r.returncode = -999;
            r.elapsed_s = 0;
            r.stdout_path = "";
            r.stderr_path = "";
            r.collected_files = strings(0,1);
            r.skipped = false;
            r.skip_reason = "";

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

            % Dedup: try to acquire exclusive lock
            lockFile = fullfile(workdir, ".lock");
            [locked, lockMsg] = modtran.parallelRunnerJSON.tryAcquireLock(lockFile);
            if ~locked
                r.skipped = true;
                r.skip_reason = "lock_exists";
                r.returncode = 0;
                r.elapsed_s = toc(tStart);
                return;
            end

            % Always release lock at end
            c = onCleanup(@() modtran.parallelRunnerJSON.releaseLock(lockFile));

            input_json = fullfile(workdir, "input.json");
            modtran.parallelRunnerJSON.writeCaseJson(caseObj, input_json);

            stdout_path = fullfile(workdir, "stdout.txt");
            stderr_path = fullfile(workdir, "stderr.txt");
            command_txt = fullfile(workdir, "command.txt");

            args = sprintf('"%s" "%s" "%s" -workpath "%s"', ...
                modtran_exe, input_json, modtran_data_dir, workdir);

            modtran.parallelRunnerJSON.writeText(command_txt, ...
                "MODE: mod6con" + newline + ...
                "ARGS:" + newline + args + newline);

            % Run mod6con
            try
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

            % Collect outputs (shared mode)
            collected = strings(0,1);
            if options.outputMode == "shared" && rc == 0
                prefix = sprintf("%06d_%s", case_index, safe_name);
                collected = modtran.parallelRunnerJSON.collectOutputs(workdir, options.collectGlob, options.collectDir, prefix);
            end
            r.collected_files = collected;

            % Write done marker on success
            if rc == 0
                donePayload = struct("case_index", case_index, "case_name", case_name, "workdir", workdir, "timestamp", char(datetime("now")));
                modtran.parallelRunnerJSON.writeText(doneMarker, jsonencode(donePayload, "PrettyPrint", true));
            end

            % Cleanup workdirs if requested
            if rc == 0
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

        function [missingIdx, missingPatterns] = findMissingCollectedCases(cases, results, collectDir, collectGlob)
            missingIdx = [];
            missingPatterns = {};

            for i = 1:numel(cases)
                % Determine expected prefix based on case NAME (same logic as runOneCase)
                case_name = modtran.parallelRunnerJSON.tryGetCaseName(cases(i), i);
                safe_name = modtran.parallelRunnerJSON.sanitizeFilename(case_name);
                prefix = sprintf("%06d_%s", i, safe_name);

                patternsMissing = strings(0,1);
                for g = collectGlob
                    % we look for at least one match for this case and this glob
                    q = fullfile(collectDir, prefix + "__" + string(g));
                    m = dir(q);
                    if isempty(m)
                        patternsMissing(end+1,1) = string(g);
                    end
                end

                if ~isempty(patternsMissing)
                    missingIdx(end+1,1) = i;
                    missingPatterns{end+1,1} = cellstr(patternsMissing);
                end
            end
        end

        function removed = dedupeCollectedFiles(collectDir)
            removed = 0;

            files = dir(fullfile(collectDir, "*"));
            files = files(~[files.isdir]);

            % Group by prefix = text before "__"
            mp = containers.Map("KeyType","char","ValueType","any");

            for k = 1:numel(files)
                name = string(files(k).name);
                parts = split(name, "__");
                if numel(parts) < 2
                    continue;
                end
                prefix = char(parts(1));
                if ~isKey(mp, prefix)
                    mp(prefix) = files(k);
                else
                    mp(prefix) = [mp(prefix), files(k)];
                end
            end

            keysList = mp.keys;
            for ki = 1:numel(keysList)
                group = mp(keysList{ki});
                if numel(group) <= 1
                    continue;
                end

                % Keep newest file, remove the rest
                [~, idxKeep] = max([group.datenum]);
                for j = 1:numel(group)
                    if j == idxKeep
                        continue;
                    end
                    try
                        delete(fullfile(group(j).folder, group(j).name));
                        removed = removed + 1;
                    catch
                        % ignore delete errors
                    end
                end
            end
        end

        function cases = loadCases(cases_json_path)
            txt = fileread(cases_json_path);
            data = jsondecode(txt);
            if ~isfield(data, "MODTRAN") || ~iscell(data.MODTRAN)
                error("parallelRunnerJSON:format", "Expected top-level key 'MODTRAN' containing a JSON array.");
            end
            cases = data.MODTRAN;
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

        function [ok, msg] = tryAcquireLock(lockFile)
            ok = false;
            msg = "";

            % Ensure parent dir exists
            parent = fileparts(lockFile);
            if ~exist(parent, "dir")
                mkdir(parent);
            end

            % Exclusive create (fails if file exists)
            [fid, errmsg] = fopen(lockFile, "x");
            if fid < 0
                msg = errmsg;
                return;
            end
            fprintf(fid, "locked_at=%s\n", char(datetime("now")));
            fclose(fid);
            ok = true;
        end

        function releaseLock(lockFile)
            if exist(lockFile, "file")
                delete(lockFile);
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
            if ~exist(path, "dir")
                mkdir(path);
            end
        end

        function writeText(path, txt)
            fid = fopen(path, "w");
            if fid < 0
                error("parallelRunnerJSON:io", "Failed to open file for writing: %s", path);
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
    end
end