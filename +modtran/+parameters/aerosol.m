classdef aerosol
    properties
        visib_km (1,1) double = 10                                          % note that modtran uses 2% instead of 5% for MOR (visibility)
        clouds (1,1) string = "none"
        aerosol_model (1,1) string = "urban"
        strato_model (1,1) string = "background"
        season (1,1) string = "SEASN_FALL_WINTER"
    end

    methods
        function s = toStruct(obj)
            s = struct();
            s.IHAZE  = modtran.parameters.aerosol.mapAerosolModel(obj.aerosol_model);
            s.IVULCN = modtran.parameters.aerosol.mapStratoModel(obj.strato_model);
            s.ICLD   = modtran.parameters.aerosol.mapCloudModel(obj.clouds);
            s.ISEASN = modtran.parameters.aerosol.mapSeasonModel(obj.season);
            s.VIS    = double(obj.visib_km);
        end
    end

    methods (Static)
        function code = mapCloudModel(key)
            key = lower(strtrim(string(key)));
            m = containers.Map( ...
                ["none","clear","cumulus","altostratus","stratus","stratocumulus","nimbostratus", ...
                 "rain_drizzle","rain_light","rain_moderate","rain_heavy","rain_extreme", ...
                 "cirrus","cirrus_thin"], ...
                ["CLOUD_NONE","CLOUD_NONE","CLOUD_CUMULUS","CLOUD_ALTOSTRATUS","CLOUD_STRATUS","CLOUD_STRATOCUMULUS","CLOUD_NIMBOSTRATUS", ...
                 "CLOUD_RAIN_DRIZZLE","CLOUD_RAIN_LIGHT","CLOUD_RAIN_MODERATE","CLOUD_RAIN_HEAVY","CLOUD_RAIN_EXTREME", ...
                 "CLOUD_CIRRUS","CLOUD_CIRRUS_THIN"] );
            if ~isKey(m,key), error("aerosol:clouds","Unknown cloud model '%s'.", key); end
            code = m(key);
        end

        function code = mapAerosolModel(key)
            key = lower(strtrim(string(key)));
            m = containers.Map( ...
                ["none","clear","rural","rural_dense","maritime_navy","maritime","urban","tropospheric", ...
                 "fog_advective","fog_radiative","desert"], ...
                ["AER_NONE","AER_NONE","AER_RURAL","AER_RURAL_DENSE","AER_MARITIME_NAVY","AER_MARITIME","AER_URBAN","AER_TROPOSPHERIC", ...
                 "AER_FOG_ADVECTIVE","AER_FOG_RADIATIVE","AER_DESERT"] );
            if ~isKey(m,key), error("aerosol:aerosol","Unknown aerosol model '%s'.", key); end
            code = m(key);
        end

        function code = mapStratoModel(key)
            key = lower(strtrim(string(key)));
            m = containers.Map( ...
                ["background","mod_volcanic_aged","high_volcanic_fresh","high_volcanic_aged", ...
                 "mod_volcanic_fresh","mod_volcanic_background","high_volcanic_background","extreme_volcanic_fresh"], ...
                ["STRATO_BACKGROUND","STRATO_MODERATE_VOLCANIC_AGED","STRATO_HIGH_VOLCANIC_FRESH","STRATO_HIGH_VOLCANIC_AGED", ...
                 "STRATO_MODERATE_VOLCANIC_FRESH","STRATO_MODERATE_VOLCANIC_BACKGROUND","STRATO_HIGH_VOLCANIC_BACKGROUND","STRATO_EXTREME_VOLCANIC_FRESH"] );
            if ~isKey(m,key), error("aerosol:strato","Unknown stratospheric model '%s'.", key); end
            code = m(key);
        end

        function code = mapSeasonModel(key)
            key = lower(strtrim(string(key)));
            m = containers.Map( ...
                ["auto","spring","summer","autumn", "winter"], ...
                ["SEASN_AUTO","SEASN_SPRING_SUMMER","SEASN_SPRING_SUMMER",...
                "SEASN_FALL_WINTER", "SEASN_FALL_WINTER"] );
            if ~isKey(m,key), error("aerosol:season","Unknown season model '%s'.", key); end
            code = m(key);
        end
    end
end