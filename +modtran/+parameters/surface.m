classdef surface
    % NEED TO ADD MAPPINGS HERE
    properties
        SURFTYPE (1,1) string = "REFL_LAMBER_MODEL"
        NSURF (1,1) double = 1
        CSALB (1,1) string = "LAMB_URBAN"
    end

    methods
        function s = toStruct(obj)
            s = struct();
            s.SURFTYPE = obj.SURFTYPE;
            s.NSURF = obj.NSURF;
            s.SURFP = struct("CSALB", obj.CSALB);
        end
    end
end