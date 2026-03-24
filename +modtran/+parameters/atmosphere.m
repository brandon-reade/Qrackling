classdef atmosphere
    properties
        % Atmosphere profile model (MODTRAN enumeration string)
        MODEL (1,1) string = "ATM_MIDLAT_WINTER"

        % Relative humidity correction flag
        M2_RHC (1,1) logical = true

        % CO2 mixing ratio override (0.0 means "use MODTRAN default")
        CO2MX (1,1) double = 0.0
    end

    methods
        function obj = atmosphere(varargin)
        % Constructor supports name/value overrides, e.g.:
        %   atm = modtran.parameters.atmosphere("MODEL","ATM_TROPICAL","M2_RHC",false);
            if nargin > 0
                if mod(nargin,2) ~= 0
                    error("modtran.parameters.atmosphere:ctor", ...
                        "Constructor arguments must be name/value pairs.");
                end
                for k = 1:2:nargin
                    name = string(varargin{k});
                    value = varargin{k+1};
                    if ~isprop(obj, name)
                        error("modtran.parameters.atmosphere:ctor", ...
                            "Unknown property '%s'.", name);
                    end
                    obj.(name) = value;
                end
            end
        end

        function s = toStruct(obj)
        % toStruct
        % Returns the exact struct that will be inserted into the JSON:
        %   MODTRANINPUT.ATMOSPHERE = s;
            s = struct();
            s.MODEL = obj.MODEL;
            s.M2_RHC = obj.M2_RHC;
            s.CO2MX = obj.CO2MX;
        end
    end
end