classdef rt_options
    properties
        MODTRN (1,1) string = "RT_CORRK_FAST"
        LYMOLC (1,1) logical = false
        T_BEST (1,1) logical = false
        IMULT (1,1) string = "RT_DISORT_AT_OBS"
        DISALB (1,1) logical = true
        NSTR (1,1) double = 8
        SOLCON (1,1) double = 0.0
    end

    methods
        function s = toStructForSource(obj, source)
            src = lower(strtrim(string(source)));

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