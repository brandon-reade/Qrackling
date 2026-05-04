classdef LocationPreset
    % Used to build an OGS
    % To do (include all geom functionality):
    % - support zenith injection
    % - support NSTR cap

    properties (SetAccess = public)
        % Site Location
        label (1,1) string = "Generic"
        lat   (1,1) double {mustBeGreaterThanOrEqual(lat,-90), mustBeLessThanOrEqual(lat,90)} = 0
        lon   (1,1) double {mustBeGreaterThanOrEqual(lon,-180), mustBeLessThanOrEqual(lon,180)} = 0
        alt_m (1,1) double {mustBeNonnegative} = 0

        % Geometry defaults
        source (1,1) string = "none"
        zen_min  (1,1) double {mustBeGreaterThanOrEqual(zen_min,0), mustBeLessThanOrEqual(zen_min,180)} = 0
        zen_max  (1,1) double {mustBeGreaterThanOrEqual(zen_max,0), mustBeLessThanOrEqual(zen_max,180)} = 90
        zen_step (1,1) double  = 10
        azi_min  (1,1) double {mustBeGreaterThanOrEqual(azi_min,0), mustBeLessThan(azi_min,360)} = 0
        azi_max  (1,1) double {mustBeGreaterThanOrEqual(azi_max,0), mustBeLessThanOrEqual(azi_max,360)} = 330
        azi_step (1,1) double = 30

        % by default overrides zen0 case to be line-by-line
        enableLosOverrides (1,1) logical = true
        losOverrideMode (1,1) string = "zen0"
        forceLblAtZen0IfCorrelatedK (1,1) logical = true

        % Aerosol defaults
        visib_km (1,1) double {mustBePositive} = 5                          % default is set to be standard for urban
        clouds (1,1) string = "none"
        aerosol_model (1,1) string = "urban"
        strato_model  (1,1) string = "background"
        season (1,1) string = "winter"

        % VSA defaults
        enableVSA (1,1) logical = false                                     
        vsa_cloud_ceiling_km double = []                                   
        vsa_cloud_thickness_km double = []                                  
        vsa_inversion_layer_height_km double = []                          
        vsa_label (1,1) string = ""                                         

        % Atmosphere defaults
        atm_MODEL (1,1) string = "ATM_MIDLAT_WINTER"
        M2_RHC (1,1) logical = true

        % Surface defaults
        CSALB (1,1) string = "LAMB_URBAN"

        % RT defaults
        NSTR (1,1) double {mustBePositive, mustBeInteger} = 8
    end
    methods
        %% Overriding the fields in the struct
        % Example: p = p.apply(struct("visib_km",1.0,"zen_step",5));
        function obj = apply(obj, opts)
            arguments
                obj
                opts (1,1) struct
            end
            f = fieldnames(opts);
            for k = 1:numel(f)
                obj.(f{k}) = opts.(f{k});
            end
        end

        function [geom, atm, aer, surf, rt] = makeParams(obj, utcDT)
            arguments
                obj
                utcDT (1,1) datetime
            end

            % Geometry
            geom = modtran.parameters.geometry(obj.lat, obj.lon, obj.alt_m, utcDT);
            geom.location_label = obj.label;

            geom.source = obj.source;

            geom.zen_min  = obj.zen_min;  geom.zen_max  = obj.zen_max;  geom.zen_step = obj.zen_step;
            geom.azi_min  = obj.azi_min;  geom.azi_max  = obj.azi_max;  geom.azi_step = obj.azi_step;

            geom.enableLosOverrides          = obj.enableLosOverrides;
            geom.losOverrideMode             = obj.losOverrideMode;
            geom.forceLblAtZen0IfCorrelatedK = obj.forceLblAtZen0IfCorrelatedK;

            % Aerosol
            aer = modtran.parameters.aerosol();
            aer.visib_km      = obj.visib_km;
            aer.clouds        = obj.clouds;
            aer.aerosol_model = obj.aerosol_model;
            aer.strato_model  = obj.strato_model;
            aer.season        = obj.season;

            % VSA
            aer.enableVSA = obj.enableVSA;                                
            aer.vsa_cloud_ceiling_km = obj.vsa_cloud_ceiling_km;                                    
            aer.vsa_cloud_thickness_km = obj.vsa_cloud_thickness_km;                                
            aer.vsa_inversion_layer_height_km = obj.vsa_inversion_layer_height_km;                          
            aer.vsa_label = obj.vsa_label;                                 

            % Atmosphere
            atm = modtran.parameters.atmosphere();
            atm.MODEL  = obj.atm_MODEL;
            atm.M2_RHC = obj.M2_RHC;

            % Surface
            surf = modtran.parameters.surface();
            surf.CSALB = obj.CSALB;

            % RT
            rt = modtran.parameters.rt_options();
            rt.NSTR = obj.NSTR;
        end
    end
end