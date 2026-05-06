% roots
repo_root = utilities.addUserPath('~\Documents\GitHub\Qrackling');
addpath(fullfile(repo_root));  
json_root = fullfile(repo_root, "+modtran","JSON_Cases",...
    "HOGS_none_Jan3_1am_200mvis_100to10000_zenstep-1_azistep-1__VIS_SWEEP");
filename = "HOGS_none_Jan3_1am_fog_radiative_100to10000_zenstep-1_azistep-1__VIS_SWEEP";
collect_dir = fullfile(repo_root,"+modtran","Data","HOGS", "not working yet", "redundant", filename);

d = dir(fullfile(collect_dir, "*_scan.csv"));
cases = repmat(struct("file","","label",""), numel(d), 1);

for k = 1:numel(d)
    cases(k).file = fullfile(d(k).folder, d(k).name);

    tok = regexp(d(k).name, '(\d+(?:kmvis|mvis))', 'tokens', 'once');
    if ~isempty(tok)
        cases(k).label = string(tok{1});   % legend shows 200mvis, 650mvis, 1kmvis, etc.
    else
        cases(k).label = string(d(k).name);
    end
end

opts = struct();
opts.useTwoPanels = true;
opts.forceTransmittanceOnly = true;                                         % do not plot radiance even if a numeric column exists
opts.showLegend = true;
opts.titlePrefix = "HOGS visibility sweep - ";

out = plots.TransmittanceRadiance(cases, opts);