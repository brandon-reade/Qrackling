% Author: Brandon Reade
% Date: 14/05/2026
% UTC pass predictionof SPOQC over HOGS for an entire month
% Optional requirement for satellite sunlit feature: Aerospace toolbox

repo_root = utilities.addUserPath('~\Documents\GitHub\Qrackling');
addpath(repo_root);

tle = [
"1 68423U 26067H   26125.81533466  .00005781  00000-0  28377-3 0  9997"
"2 68423  97.4486  84.9092 0002633  85.9306 274.2229 15.18469238  5516"
];

% Ground station: HOGS (example)
ogsLLA = [55.909723, -3.319995, 10];

startUTC = datetime(2026,6,1,0,0,0,"TimeZone","UTC");
stopUTC  = datetime(2026,7,1,0,0,0,"TimeZone","UTC");

passes = utilities.satPassPredictor( ...
    tle, ogsLLA, startUTC, stopUTC, ...
    MinElevationDeg=30, ...
    CoarseStep=seconds(30), ...
    FineStep=seconds(1), ...
    OnlySunlit=false);

disp(passes(:, ["pass_index","startUTC","endUTC","duration_s","max_elevation","fracAboveTH2","grade"]));

% Rank by score (best passes first)
passesSorted = sortrows(passes, "grade", "descend");
disp(passesSorted(1:min(10,height(passesSorted)), ...
    ["startUTC","max_elevation","duration_s","fracAboveTH2","grade"]));