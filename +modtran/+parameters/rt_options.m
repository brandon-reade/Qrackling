classdef rt_options
    properties
        MODTRN (1,1) string = "RT_CORRK_FAST"                               % radiative transfer algorithm
        LYMOLC (1,1) logical = false                                        % when false do not include "Y" species with built-in model profiles
        T_BEST (1,1) logical = false                                        % when false do not use benchmark numeric Voigt line transmittance integration.
        IMULT (1,1) string = "RT_DISORT_AT_OBS"                             % multiple scattering algorithm
        DISALB (1,1) logical = true                                         % if TRUE MODTRAN will generate an atmospheric correction data (<ROOTNAME>. acd) output file.
        NSTR (1,1) double = 8                                               % number of distort streams
        SOLCON (1,1) double = 0.0                                           % scaling of TOA (Top-Of-Atmosphere) solar irradiance (for none set to zero or omit)
    end

    methods
        function s = toStructForSource(obj, source)
            src = lower(strtrim(string(source)));
            
            % choosing RT mode option from source
            if startsWith(src,"sun")
                iemsct = "RT_SOLAR_AND_THERMAL";
            elseif startsWith(src,"moon")
                iemsct = "RT_LUNAR_AND_THERMAL";
            elseif startsWith(src,"none")
                iemsct = "RT_TRANSMITTANCE";
            else
                error("rt_options:source","Unknown source='%s'.", source);
            end

            s = struct();
            s.MODTRN = obj.MODTRN;
            s.LYMOLC = obj.LYMOLC;
            s.T_BEST = obj.T_BEST;
            s.IMULT  = obj.IMULT;
            s.DISALB = obj.DISALB;
            s.NSTR   = obj.NSTR;
            s.SOLCON = obj.SOLCON;
            s.IEMSCT = iemsct;
        end
    end
end