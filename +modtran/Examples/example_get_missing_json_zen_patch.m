% Author: Brandon Reade
% Date: 17/04/2026
% Build a missing-only JSON from collectDir state, but patch zen=0 LOS cases
% so OBSZEN is not exactly zero (fixes MODTRAN NaN outputs in some configs)

repo_root = utilities.addUserPath('~\Documents\GitHub\Qrackling');
addpath(fullfile(repo_root));

% Inputs
jsonDir = fullfile(repo_root, "+modtran", "JSON_Cases");
filename = "Goldstone_moon_Jun21_1am_23kmvis_300to10000_zenstep10_azistep30";
json_file = filename + ".json";
cases_json = fullfile(jsonDir, filename, json_file);

collect_dir  = fullfile(repo_root, "+modtran", "Data", "Goldstone", filename);
collect_glob = "*_scan.csv";

% Output
out_dir = "E:\MODTRAN_RESULTS\runs_tmp\repair_json";
out_json = fullfile(out_dir, filename + "__missing_only_zenEps.json");

% Patch controls
zenTol = 1e-12;         % tolerance before changing
zenEps = 1e-3;          % degrees (try 1e-6, 1e-4, 1e-3 if MODTRAN still misbehaves)
renameCases = false;     % tag NAME/CSVPRNT to see the eps-zen repair variant

if ~exist(out_dir, "dir"), mkdir(out_dir); end
if ~exist(collect_dir, "dir")
    error("collect_dir not found: %s", collect_dir);
end
if ~exist(cases_json, "file")
    error("cases_json not found: %s", cases_json);
end

% Load original cases
txt = fileread(cases_json);
data = jsondecode(txt);
if ~isfield(data, "MODTRAN")
    error("Expected top-level 'MODTRAN' array in JSON.");
end

% Normalize into cell array of case structs
if isstruct(data.MODTRAN)
    cases = num2cell(data.MODTRAN);
elseif iscell(data.MODTRAN)
    cases = data.MODTRAN;
else
    error("data.MODTRAN is not a struct array or cell array.");
end

% Find missing indices using the runner's method (prefixMode=index)
missingIdx = [];

for i = 1:numel(cases)
    prefix = sprintf("%06d", i);
    pat = fullfile(collect_dir, prefix + "__" + string(collect_glob));
    m = dir(pat);
    if isempty(m)
        missingIdx(end+1,1) = i;
    end
end

fprintf("Detected missing cases: %d\n", numel(missingIdx));
if isempty(missingIdx)
    fprintf("Nothing to do.\n");
    return;
end

% Build missing-only payload + patch zen=0
out = struct();
out.MODTRAN = cell(1, numel(missingIdx));

nPatched = 0;
for k = 1:numel(missingIdx)
    i = missingIdx(k);
    c = cases{i};

    if isfield(c, "MODTRANINPUT") && isfield(c.MODTRANINPUT, "GEOMETRY")
        g = c.MODTRANINPUT.GEOMETRY;

        % Patch OBSZEN if present and ~0
        if isfield(g, "OBSZEN") && isfinite(g.OBSZEN) && abs(double(g.OBSZEN)) <= zenTol
            g.OBSZEN = double(zenEps);
            c.MODTRANINPUT.GEOMETRY = g;
            nPatched = nPatched + 1;

            % tag name + csv output so you can tell repaired outputs apart
            if renameCases && isfield(c.MODTRANINPUT, "NAME")
                c.MODTRANINPUT.NAME = string(c.MODTRANINPUT.NAME) + "_zenEps";
            end
            if renameCases && isfield(c.MODTRANINPUT, "FILEOPTIONS") && isfield(c.MODTRANINPUT.FILEOPTIONS, "CSVPRNT")
                [p,n,e] = fileparts(string(c.MODTRANINPUT.FILEOPTIONS.CSVPRNT));
                c.MODTRANINPUT.FILEOPTIONS.CSVPRNT = string(fullfile(p, n + "_zenEps" + e));
            end
        end
    end

    out.MODTRAN{k} = c;
end

% jsonencode works best with struct arrays rather than cells
out.MODTRAN = [out.MODTRAN{:}];

% Write
jsonText = jsonencode(out, "PrettyPrint", true);
fid = fopen(out_json, "w");
if fid < 0
    error("Failed to open output JSON for writing: %s", out_json);
end
fwrite(fid, jsonText, "char");
fclose(fid);

fprintf("Wrote missing-only JSON: %s\n", out_json);
fprintf("Patched OBSZEN for %d cases.\n", nPatched);