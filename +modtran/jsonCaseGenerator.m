% Author: Brandon Reade
% Date: 21/03/2026
% MODTRAN JSON case generator class

% to do: change naming scheme for no zen/azi stepping (atm shows as "-1")

classdef jsonCaseGenerator
    methods (Static)

        %% Build and write (normal cases)
        function [jsonOut, summaryTable] = buildAndWrite( ...
                geom, aer, spec, surf, rt, atmosphere, ...
                word, json_name, out_csv, options)

            arguments
                % modtran parameters
                geom (:,1) modtran.parameters.geometry
                aer  (1,1) modtran.parameters.aerosol
                spec (1,1) modtran.parameters.spectral
                surf (1,1) modtran.parameters.surface
                rt   (1,1) modtran.parameters.rt_options
                atmosphere (1,1) modtran.parameters.atmosphere

                % string inputs
                word (1,1) string = "Transm"
                json_name (1,1) string = "modtran_generated_cases.json"
                out_csv (1,1) string = "cases_summary.csv"

                % optional behavior control
                options.writeMode (1,1) string {mustBeMember(options.writeMode,["single","separate"])} = "single"
                options.separateJsonPattern (1,1) string = ""
                options.separateCsvPattern  (1,1) string = ""

                % output folder control
                % If provided, outputs are written to:
                %   <saveDir>/<json_base_name>/{json, csv}
                % where json_base_name = file name without extension.
                options.saveDir (1,1) string = ""
                options.makeJsonFolder (1,1) logical = true
            end

            writeMode = lower(options.writeMode);
            separateJsonPattern = options.separateJsonPattern;
            separateCsvPattern  = options.separateCsvPattern;

            % Convert parameters to structures
            atmStruct = atmosphere.toStruct();
            aerosolsStruct = aer.toStruct();
            spectralStruct = spec.toStruct();
            surfaceStruct  = surf.toStruct();

            % Visibility string
            visStr = modtran.jsonCaseGenerator.formatVisibilityToken(aer.visib_km);

            % separate mode writes one file per geometry object
            if writeMode == "separate"
                jsonOut = cell(numel(geom),1);
                summaryTable = cell(numel(geom),1);

                for gi = 1:numel(geom)

                    % build default output names if patterns are not provided
                    [jsonNameThis, csvNameThis] = modtran.jsonCaseGenerator.resolveSeparateFilenames( ...
                        geom(gi), json_name, out_csv, separateJsonPattern, separateCsvPattern);

                    % apply saveDir behavior
                    [jsonNameThis, csvNameThis] = modtran.jsonCaseGenerator.applySaveDir( ...
                        jsonNameThis, csvNameThis, options.saveDir, options.makeJsonFolder);

                    % Build geometry cases (LOS sweep)
                    geomCases = geom(gi).buildGeometryCases();

                    % multi-location indexing
                    % Unique locations are determined by (lat, lon, alt_m) tuples
                    [locIdxPerCase, locKeyList] = modtran.jsonCaseGenerator.assignLocationIndices(geomCases); %#ok<ASGLU>

                    % optional location label override.
                    % replaces the default "loc{idx}" in the output naming scheme.
                    locationLabel = "";
                    if isprop(geom(gi), "location_label")
                        locationLabel = string(geom(gi).location_label);
                    end
                    useCustomLabel = strlength(strtrim(locationLabel)) > 0;

                    [jsonOut{gi}, summaryTable{gi}] = modtran.jsonCaseGenerator.buildWriteOne( ...
                        geom(gi), geomCases, locIdxPerCase, useCustomLabel, locationLabel, ...
                        aer, spec, surf, rt, atmStruct, aerosolsStruct, spectralStruct, surfaceStruct, ...
                        word, visStr, jsonNameThis, csvNameThis);

                end

                return;
            end

            % single mode combines all geometry objects into one output
            % Build geometry cases from all locations, then assign loc1/loc2/... across the combined list.
            allCases = struct([]);
            allGeomIdx = [];  % tracks which geometry object produced each case (for CSV fields)

            for gi = 1:numel(geom)
                c = geom(gi).buildGeometryCases();
                allCases = [allCases, c];
                allGeomIdx = [allGeomIdx; repmat(gi, numel(c), 1)];
            end

            % multi-location indexing
            [locIdxPerCase, locKeyList] = modtran.jsonCaseGenerator.assignLocationIndices(allCases);

            % apply saveDir behavior
            [json_name, out_csv] = modtran.jsonCaseGenerator.applySaveDir( ...
                json_name, out_csv, options.saveDir, options.makeJsonFolder);

            % In single mode, we do not use per-geometry custom labels unless explicitly set
            [jsonOut, summaryTable] = modtran.jsonCaseGenerator.buildWriteMany( ...
                geom, allCases, allGeomIdx, locIdxPerCase, ...
                aer, spec, surf, rt, atmStruct, aerosolsStruct, spectralStruct, surfaceStruct, ...
                word, visStr, json_name, out_csv);
        end

        %% Build and write visibility sweep case
        function [jsonOut, summaryTable] = buildAndWriteVisibilitySweep( ...
                geom, aerBase, visList_km, spec, surf, rt, atmosphere, ...
                word, json_name, out_csv, options)
        
            arguments
                geom (:,1) modtran.parameters.geometry
                aerBase (1,1) modtran.parameters.aerosol
                visList_km (1,:) double {mustBePositive}
        
                spec (1,1) modtran.parameters.spectral
                surf (1,1) modtran.parameters.surface
                rt   (1,1) modtran.parameters.rt_options
                atmosphere (1,1) modtran.parameters.atmosphere
        
                word (1,1) string = "Transm"
                json_name (1,1) string = "modtran_visibility_sweep.json"
                out_csv (1,1) string = "visibility_sweep_summary.csv"
        
                % output folder control (same as buildAndWrite)
                options.saveDir (1,1) string = ""
                options.makeJsonFolder (1,1) logical = true
            end
        
            % Apply saveDir behavior
            [json_name, out_csv] = modtran.jsonCaseGenerator.applySaveDir( ...
                json_name, out_csv, options.saveDir, options.makeJsonFolder);
        
            % Convert parameters to structures that do not depend on visibility
            atmStruct     = atmosphere.toStruct();
            spectralStruct = spec.toStruct();
            surfaceStruct  = surf.toStruct();
        
            allCases = struct([]);
            allRows  = struct([]);
        
            % accumulate cases across all visibilities.
            % create a fresh aerosol struct per visibility since it changes.
        
            for vi = 1:numel(visList_km)
                vis_km = visList_km(vi);
        
                % Clone aerosol object and override visibility
                aer = aerBase;
                aer.visib_km = vis_km;
        
                aerosolsStruct = aer.toStruct();
        
                % Visibility string/token used in MODTRANINPUT.NAME and CSVPRNT
                visStr = modtran.jsonCaseGenerator.formatVisibilityToken(aer.visib_km);
        
                % Build geometry cases from all locations, then assign loc1/loc2/... across the combined list.
                % IMPORTANT: for a visibility sweep we need consistent loc indexing, so we recompute cases per vis
                % but it will still assign loc indices based on lat/lon/alt tuples.
                allGeomCases = struct([]);
                allGeomIdx   = [];
        
                for gi = 1:numel(geom)
                    c = geom(gi).buildGeometryCases();
                    allGeomCases = [allGeomCases, c]; 
                    allGeomIdx = [allGeomIdx; repmat(gi, numel(c), 1)]; 
                end
        
                [locIdxPerCase, ~] = modtran.jsonCaseGenerator.assignLocationIndices(allGeomCases);
        
                % Build cases for this visibility and append
                [jsonThis, tableThis] = modtran.jsonCaseGenerator.buildWriteManyNoIO( ...
                    geom, allGeomCases, allGeomIdx, locIdxPerCase, ...
                    aer, spec, surf, rt, atmStruct, aerosolsStruct, spectralStruct, surfaceStruct, ...
                    word, visStr);
        
                allCases = [allCases, jsonThis.MODTRAN]; 
                allRows  = [allRows; table2struct(tableThis)]; 
            end
        
            % Final JSON output
            jsonOut = struct();
            jsonOut.MODTRAN = allCases;
        
            % Write JSON
            jsonText = jsonencode(jsonOut, "PrettyPrint", true);
            fid = fopen(json_name, "w");
            if fid < 0
                error("modtran_json:io","Failed to open JSON file '%s' for writing.", json_name);
            end
            fwrite(fid, jsonText, "char");
            fclose(fid);
        
            % Write summary CSV
            summaryTable = struct2table(allRows);
            writetable(summaryTable, out_csv);
        
            fprintf("Generated %d cases (visibility sweep with %d vis values).\n", numel(allCases), numel(visList_km));
            fprintf(" - JSON written to: %s\n", json_name);
            fprintf(" - CSV summary written to: %s\n", out_csv);
        end

        %% Formatting functions
        function token = formatVisibilityToken(visib_km)
            % If >=1 km: "10kmvis"
            % If <1 km : meters to avoid decimals (0.5 -> "500mvis")
            if visib_km >= 1
                if abs(visib_km - round(visib_km)) < 1e-12
                    token = sprintf("%dkmvis", round(visib_km));
                else
                    % avoid long decimal strings
                    token = sprintf("%gkmvis", visib_km);
                    token = replace(token, ".", "p"); % 1.5 converts to 1p5kmvis
                end
            else
                vis_m = round(visib_km * 1000);
                token = sprintf("%dmvis", vis_m);
            end
        end

        function baseName = makeJsonBaseName(siteName, source, utcDT, visib_km, clouds, wmin_nm, wmax_nm, zen_step_deg, azi_step_deg)
            % Creates a base JSON file name:
            % sitename_source_date_time_visibility_cloud_wminNmtoWmaxNm_zenstepX_azistepY
            %
            % Examples:
            %   HOGS_sun_Jan3_1pm_10kmvis_100to10000_zenstep10_azistep10
            %   HOGS_moon_Jan3_1am_500mvis_cirrus_100to10000_zenstep10_azistep10

            siteName = modtran.jsonCaseGenerator.sanitizeToken(siteName);
            source = modtran.jsonCaseGenerator.sanitizeToken(lower(string(source)));

            % Date token: "Jan3"
            dateToken = string(datestr(utcDT, "mmm")) + string(day(utcDT));

            % Time token: "1am", "1pm", "13h30" (use hour + am/pm if minute==0)
            hh = hour(utcDT);
            mm = minute(utcDT);
            if mm == 0
                isPM = hh >= 12;
                hh12 = mod(hh,12);
                if hh12 == 0
                    hh12 = 12;
                end
            
                if isPM
                    suffix = "pm";
                else
                    suffix = "am";
                end
            
                timeToken = string(hh12) + suffix;
            else
                timeToken = sprintf("%02dh%02d", hh, mm);
            end

            visToken = modtran.jsonCaseGenerator.formatVisibilityToken(visib_km);

            cloudsToken = modtran.jsonCaseGenerator.sanitizeToken(lower(string(clouds)));
            includeClouds = strlength(strtrim(cloudsToken)) > 0 && cloudsToken ~= "none";

            % Wavelength tokens (always nm for Qrackling)
            w1 = modtran.jsonCaseGenerator.formatNumericToken(wmin_nm);
            w2 = modtran.jsonCaseGenerator.formatNumericToken(wmax_nm);
            waveToken = w1 + "to" + w2;

            % Step tokens
            zenStepToken = "zenstep" + modtran.jsonCaseGenerator.formatNumericToken(zen_step_deg);
            aziStepToken = "azistep" + modtran.jsonCaseGenerator.formatNumericToken(azi_step_deg);

            if includeClouds
                baseName = siteName + "_" + source + "_" + dateToken + "_" + timeToken + "_" + visToken + "_" + cloudsToken + "_" + waveToken + "_" + zenStepToken + "_" + aziStepToken;
            else
                baseName = siteName + "_" + source + "_" + dateToken + "_" + timeToken + "_" + visToken + "_" + waveToken + "_" + zenStepToken + "_" + aziStepToken;
            end
        end
    end

    %% Private functions
    methods (Static, Access = private)
        % Overriding a defined LOS
        function tf = losMatchesOverride(geomObj, meta)
            if ~isprop(geomObj,"enableLosOverrides") || ~geomObj.enableLosOverrides
                tf = false;
                return;
            end
            tol = geomObj.losMatchTol_deg;
            mode = string(geomObj.losOverrideMode);
    
            if mode == "zen0"
                tf = abs(meta.los_zen_deg) <= tol;
            else % "exact"
                tf = abs(meta.los_zen_deg - geomObj.losZenTarget_deg) <= tol && ...
                     abs(meta.los_az_deg  - geomObj.losAziTarget_deg) <= tol;
            end
        end
    
        % applying an LOS override
        function [geomStructOut, rtStructOut] = applyLosOverrides(geomObj, meta, geomStructIn, rtStructIn)
            geomStructOut = geomStructIn;
            rtStructOut   = rtStructIn;
    
            if ~modtran.jsonCaseGenerator.losMatchesOverride(geomObj, meta)
                return;
            end
    
            % Forcing arbitrarily small non-zero zenith
            if isprop(geomObj,"forceZenNonZero") && geomObj.forceZenNonZero
                if isfield(geomStructOut,"OBSZEN") && abs(geomStructOut.OBSZEN) <= geomObj.losMatchTol_deg
                    geomStructOut.OBSZEN = geomObj.zenEps_deg;
                end
            end
    
            % force LBL at zen=0 If correlated-k is used
            if isprop(geomObj,"forceLblAtZen0IfCorrelatedK") && geomObj.forceLblAtZen0IfCorrelatedK
                % Only trigger for zen~0
                if isfield(geomStructOut,"OBSZEN") && abs(geomStructOut.OBSZEN) <= geomObj.losMatchTol_deg
                    if isfield(rtStructOut,"MODTRN")
                        modtrn = string(rtStructOut.MODTRN);
    
                        % treat any "CORRK" as correlated-k.
                        % Adjust this test to match your enums.
                        if contains(modtrn, "CORRK", "IgnoreCase", true)
                            rtStructOut.MODTRN = geomObj.lblModtrnValue;
                        end
                    end
                end
            end
    
            % Cap NSTR (RT streams) to 8
            if isprop(geomObj,"capNstrAt8") && geomObj.capNstrAt8
                if isfield(rtStructOut,"NSTR") && rtStructOut.NSTR > 8
                    rtStructOut.NSTR = 8;
                end
            end
        end

        function s = formatNumericToken(x)
            s = string(sprintf("%g", x));
            s = replace(s, ".", "p");
            s = replace(s, "+", "");
        end

        function [jsonPathOut, csvPathOut] = applySaveDir(jsonPathIn, csvPathIn, saveDir, makeJsonFolder)
            jsonPathOut = string(jsonPathIn);
            csvPathOut  = string(csvPathIn);

            if strlength(strtrim(saveDir)) == 0
                return;
            end

            saveDir = string(saveDir);

            % Folder name is json file name
            [~, jsonBase, ~] = fileparts(jsonPathOut);
            if makeJsonFolder
                outDir = fullfile(saveDir, jsonBase);
            else
                outDir = saveDir;
            end

            if ~exist(outDir, "dir")
                mkdir(outDir);
            end

            [~, jn, je] = fileparts(jsonPathOut);
            [~, cn, ce] = fileparts(csvPathOut);

            jsonPathOut = fullfile(outDir, jn + je);
            csvPathOut  = fullfile(outDir, cn + ce);
        end

        function t = sanitizeToken(t)
            t = string(t);
            t = strtrim(t);
            if strlength(t) == 0
                return;
            end
            t = replace(t, " ", "_");
            t = regexprep(t, "[^A-Za-z0-9_\-]", ""); % keep filenames safe
        end

        function [jsonOut, summaryTable] = buildWriteOne( ...
                geom, geomCases, locIdxPerCase, useCustomLabel, locationLabel, ...
                aer, spec, surf, rt, atmStruct, aerosolsStruct, spectralStruct, surfaceStruct, ...
                word, visStr, json_name, out_csv)

            cases = cell(1, numel(geomCases));
            rows  = cell(1, numel(geomCases));

            for k = 1:numel(geomCases)
                geomStruct = geomCases(k).geom;
                meta = geomCases(k).meta;

                rtStruct = rt.toStructForSource(meta.source);

                % location token used in filenames ("loc1" default, or custom label like "HOGS")
                if useCustomLabel
                    locToken = locationLabel;
                else
                    locToken = "loc" + string(locIdxPerCase(k));
                end

                % naming scheme:
                %   {word}_loc{loc_idx}_{vis}kmvis_{clouds}_{aerosol_model}_{strato_model}_zen{Z}_azi{A}.csv
                name = sprintf("%s_%s_%s_%s_%s_%s_zen%d_azi%d", ...
                    word, ...
                    locToken, ...
                    visStr, ...
                    aer.clouds, ...
                    aer.aerosol_model, ...
                    aer.strato_model, ...
                    round(meta.los_zen_deg), ...
                    round(meta.los_az_deg));

                csvFile = name + ".csv";

                mi = struct();
                mi.NAME = string(name);
                mi.DESCRIPTION = sprintf("Case %d - LOS zen %.3f az %.3f", ...
                    k, meta.los_zen_deg, meta.los_az_deg);
                mi.CASE = k;

                % apply per-LOS overrides
                [geomStruct, rtStruct] = modtran.jsonCaseGenerator.applyLosOverrides( ...
                    geom, meta, geomStruct, rtStruct);

                mi.RTOPTIONS = rtStruct;
                mi.ATMOSPHERE = atmStruct;
                mi.AEROSOLS = aerosolsStruct;
                mi.GEOMETRY = geomStruct;
                mi.SURFACE = surfaceStruct;
                mi.SPECTRAL = spectralStruct;
                mi.FILEOPTIONS = struct("CSVPRNT", string(csvFile));

                cases{k} = struct("MODTRANINPUT", mi);

                % include location indexing and the explicit label in the CSV
                rows{k} = struct( ...
                    "case_index", k, ...
                    "location_index", double(locIdxPerCase(k)), ...
                    "location_label", string(locToken), ...
                    "lat", meta.lat, ...
                    "lon", meta.lon, ...
                    "alt_m", meta.alt_m, ...
                    "utc", char(geom.utcDT), ...
                    "source", string(meta.source), ...
                    "clouds", string(aer.clouds), ...
                    "visib_km", double(aer.visib_km), ...
                    "aerosol_model", string(aer.aerosol_model), ...
                    "strato_model", string(aer.strato_model), ...
                    "atmos_model", string(atmStruct.MODEL), ...
                    "name", string(name), ...
                    "los_zen_deg", double(meta.los_zen_deg), ...
                    "los_az_deg", double(meta.los_az_deg), ...
                    "rel_az_deg", modtran.jsonCaseGenerator.safeField(geomStruct,"PARM1"), ...
                    "rel_zen_deg", modtran.jsonCaseGenerator.safeField(geomStruct,"PARM2"), ...
                    "body_topo_az_deg", double(meta.body_topo_az_deg), ...
                    "body_topo_zen_deg", double(meta.body_topo_zen_deg), ...
                    "csv", string(csvFile) );
            end

            jsonOut = struct();
            jsonOut.MODTRAN = [cases{:}];

            % Write JSON
            jsonText = jsonencode(jsonOut, "PrettyPrint", true);
            fid = fopen(json_name, "w");
            if fid < 0
                error("modtran_json:io","Failed to open JSON file '%s' for writing.", json_name);
            end
            fwrite(fid, jsonText, "char");
            fclose(fid);

            % Write CSV
            summaryTable = struct2table([rows{:}]);
            writetable(summaryTable, out_csv);

            fprintf("Generated %d cases.\n", numel(geomCases));
            fprintf(" - JSON written to: %s\n", json_name);
            fprintf(" - CSV summary written to: %s\n", out_csv);
        end

        function [jsonOut, summaryTable] = buildWriteMany( ...
                geomList, allCases, allGeomIdx, locIdxPerCase, ...
                aer, spec, surf, rt, atmStruct, aerosolsStruct, spectralStruct, surfaceStruct, ...
                word, visStr, json_name, out_csv)

            cases = cell(1, numel(allCases));
            rows  = cell(1, numel(allCases));

            for k = 1:numel(allCases)
                geomStruct = allCases(k).geom;
                meta = allCases(k).meta;

                gi = allGeomIdx(k);
                geomObj = geomList(gi);

                rtStruct = rt.toStructForSource(meta.source);

                % if geometry object has a label use it; else use loc{idx}
                locationLabel = "";
                if isprop(geomObj, "location_label")
                    locationLabel = string(geomObj.location_label);
                end
                useCustomLabel = strlength(strtrim(locationLabel)) > 0;

                if useCustomLabel
                    locToken = locationLabel;
                else
                    locToken = "loc" + string(locIdxPerCase(k));
                end

                name = sprintf("%s_%s_%s_%s_%s_%s_zen%d_azi%d", ...
                    word, ...
                    locToken, ...
                    visStr, ...
                    aer.clouds, ...
                    aer.aerosol_model, ...
                    aer.strato_model, ...
                    round(meta.los_zen_deg), ...
                    round(meta.los_az_deg));

                csvFile = name + ".csv";

                mi = struct();
                mi.NAME = string(name);
                mi.DESCRIPTION = sprintf("Case %d - geom %d, LOS zen %.3f az %.3f", ...
                    k, gi, meta.los_zen_deg, meta.los_az_deg);
                mi.CASE = k;

                % apply per-LOS overrides
                [geomStruct, rtStruct] = modtran.jsonCaseGenerator.applyLosOverrides( ...
                    geomObj, meta, geomStruct, rtStruct);

                mi.RTOPTIONS = rtStruct;
                mi.ATMOSPHERE = atmStruct;
                mi.AEROSOLS = aerosolsStruct;
                mi.GEOMETRY = geomStruct;
                mi.SURFACE = surfaceStruct;
                mi.SPECTRAL = spectralStruct;
                mi.FILEOPTIONS = struct("CSVPRNT", string(csvFile));

                cases{k} = struct("MODTRANINPUT", mi);

                rows{k} = struct( ...
                    "case_index", k, ...
                    "geom_index", double(gi), ...
                    "location_index", double(locIdxPerCase(k)), ...
                    "location_label", string(locToken), ...
                    "lat", meta.lat, ...
                    "lon", meta.lon, ...
                    "alt_m", meta.alt_m, ...
                    "utc", char(geomObj.utcDT), ...
                    "source", string(meta.source), ...
                    "clouds", string(aer.clouds), ...
                    "visib_km", double(aer.visib_km), ...
                    "aerosol_model", string(aer.aerosol_model), ...
                    "strato_model", string(aer.strato_model), ...
                    "atmos_model", string(atmStruct.MODEL), ...
                    "name", string(name), ...
                    "los_zen_deg", double(meta.los_zen_deg), ...
                    "los_az_deg", double(meta.los_az_deg), ...
                    "rel_az_deg", modtran.jsonCaseGenerator.safeField(geomStruct,"PARM1"), ...
                    "rel_zen_deg", modtran.jsonCaseGenerator.safeField(geomStruct,"PARM2"), ...
                    "body_topo_az_deg", double(meta.body_topo_az_deg), ...
                    "body_topo_zen_deg", double(meta.body_topo_zen_deg), ...
                    "csv", string(csvFile) );
            end

            jsonOut = struct();
            jsonOut.MODTRAN = [cases{:}];

            % Write JSON
            jsonText = jsonencode(jsonOut, "PrettyPrint", true);
            fid = fopen(json_name, "w");
            if fid < 0
                error("modtran_json:io","Failed to open JSON file '%s' for writing.", json_name);
            end
            fwrite(fid, jsonText, "char");
            fclose(fid);

            % Write CSV
            summaryTable = struct2table([rows{:}]);
            writetable(summaryTable, out_csv);

            fprintf("Generated %d cases.\n", numel(allCases));
            fprintf(" - JSON written to: %s\n", json_name);
            fprintf(" - CSV summary written to: %s\n", out_csv);
        end

        function v = safeField(s, fieldName)
            if isfield(s, fieldName)
                v = s.(fieldName);
            else
                v = NaN;
            end
        end

        function [locIdxPerCase, locKeyList] = assignLocationIndices(geomCases)
            n = numel(geomCases);
            locIdxPerCase = zeros(1,n);
            keys = strings(1,n);

            for k = 1:n
                lat = NaN; lon = NaN; alt_m = NaN;

                if isfield(geomCases(k), "meta")
                    if isfield(geomCases(k).meta, "lat"),   lat = geomCases(k).meta.lat; end
                    if isfield(geomCases(k).meta, "lon"),   lon = geomCases(k).meta.lon; end
                    if isfield(geomCases(k).meta, "alt_m"), alt_m = geomCases(k).meta.alt_m; end
                end

                if any(isnan([lat, lon, alt_m]))
                    lat = 0; lon = 0; alt_m = 0;
                end

                keys(k) = sprintf("%.12f|%.12f|%.3f", lat, lon, alt_m);
            end

            locKeyList = strings(0,1);
            for k = 1:n
                idx = find(locKeyList == keys(k), 1, "first");
                if isempty(idx)
                    locKeyList(end+1,1) = keys(k);
                    idx = numel(locKeyList);
                end
                locIdxPerCase(k) = idx;
            end
        end

        function [jsonNameThis, csvNameThis] = resolveSeparateFilenames(geom, json_name, out_csv, jsonPattern, csvPattern)
            % simple filename resolver for separate mode.
            % If patterns are empty, append a location tag to the provided base filenames.

            if isprop(geom,"location_label") && strlength(strtrim(string(geom.location_label))) > 0
                tag = string(geom.location_label);
            else
                tag = sprintf("lat%.4f_lon%.4f_alt%.0f", geom.lat_deg, geom.lon_deg, geom.alt_m);
            end

            if strlength(strtrim(jsonPattern)) > 0
                % Supports "{tag}" substitution
                jsonNameThis = replace(jsonPattern, "{tag}", tag);
            else
                [p,n,e] = fileparts(json_name);
                jsonNameThis = fullfile(p, n + "_" + tag + e);
            end

            if strlength(strtrim(csvPattern)) > 0
                csvNameThis = replace(csvPattern, "{tag}", tag);
            else
                [p,n,e] = fileparts(out_csv);
                csvNameThis = fullfile(p, n + "_" + tag + e);
            end
        end

        function [jsonOut, summaryTable] = buildWriteManyNoIO( ...
                geomList, allCases, allGeomIdx, locIdxPerCase, ...
                aer, spec, surf, rt, atmStruct, aerosolsStruct, spectralStruct, surfaceStruct, ...
                word, visStr)
            % Like buildWriteMany, but DOES NOT write JSON/CSV to disk.
            % to allow for sweep functions (e.g., visibility sweep) and to
            % aggregate many sets of cases into one combined JSON file.
        
            cases = cell(1, numel(allCases));
            rows  = cell(1, numel(allCases));
        
            for k = 1:numel(allCases)
                geomStruct = allCases(k).geom;
                meta = allCases(k).meta;
        
                gi = allGeomIdx(k);
                geomObj = geomList(gi);
        
                rtStruct = rt.toStructForSource(meta.source);
        
                % if geometry object has a label use it, else use loc{idx}
                locationLabel = "";
                if isprop(geomObj, "location_label")
                    locationLabel = string(geomObj.location_label);
                end
                useCustomLabel = strlength(strtrim(locationLabel)) > 0;
        
                if useCustomLabel
                    locToken = locationLabel;
                else
                    locToken = "loc" + string(locIdxPerCase(k));
                end
        
                name = sprintf("%s_%s_%s_%s_%s_%s_zen%d_azi%d", ...
                    word, ...
                    locToken, ...
                    visStr, ...
                    aer.clouds, ...
                    aer.aerosol_model, ...
                    aer.strato_model, ...
                    round(meta.los_zen_deg), ...
                    round(meta.los_az_deg));
        
                csvFile = name + ".csv";
        
                mi = struct();
                mi.NAME = string(name);
                mi.DESCRIPTION = sprintf("Case %d - geom %d, LOS zen %.3f az %.3f", ...
                    k, gi, meta.los_zen_deg, meta.los_az_deg);
                mi.CASE = k;
        
                % apply per-LOS overrides
                [geomStruct, rtStruct] = modtran.jsonCaseGenerator.applyLosOverrides( ...
                    geomObj, meta, geomStruct, rtStruct);
        
                mi.RTOPTIONS = rtStruct;
                mi.ATMOSPHERE = atmStruct;
                mi.AEROSOLS = aerosolsStruct;
                mi.GEOMETRY = geomStruct;
                mi.SURFACE = surfaceStruct;
                mi.SPECTRAL = spectralStruct;
                mi.FILEOPTIONS = struct("CSVPRNT", string(csvFile));
        
                cases{k} = struct("MODTRANINPUT", mi);
        
                rows{k} = struct( ...
                    "case_index", k, ...
                    "geom_index", double(gi), ...
                    "location_index", double(locIdxPerCase(k)), ...
                    "location_label", string(locToken), ...
                    "lat", meta.lat, ...
                    "lon", meta.lon, ...
                    "alt_m", meta.alt_m, ...
                    "utc", char(geomObj.utcDT), ...
                    "source", string(meta.source), ...
                    "clouds", string(aer.clouds), ...
                    "visib_km", double(aer.visib_km), ...
                    "aerosol_model", string(aer.aerosol_model), ...
                    "strato_model", string(aer.strato_model), ...
                    "atmos_model", string(atmStruct.MODEL), ...
                    "name", string(name), ...
                    "los_zen_deg", double(meta.los_zen_deg), ...
                    "los_az_deg", double(meta.los_az_deg), ...
                    "rel_az_deg", modtran.jsonCaseGenerator.safeField(geomStruct,"PARM1"), ...
                    "rel_zen_deg", modtran.jsonCaseGenerator.safeField(geomStruct,"PARM2"), ...
                    "body_topo_az_deg", double(meta.body_topo_az_deg), ...
                    "body_topo_zen_deg", double(meta.body_topo_zen_deg), ...
                    "csv", string(csvFile) );
            end
        
            jsonOut = struct();
            jsonOut.MODTRAN = [cases{:}];
        
            summaryTable = struct2table([rows{:}]);
        end
    end
end