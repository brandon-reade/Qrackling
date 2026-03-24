classdef spectral
    properties
        V1 (1,1) double = 500
        V2 (1,1) double = 5000
        DV (1,1) double = 1.0
        FWHM (1,1) double = 2.5

        XFLAG (1,1) string = "N"
        FLAGS (1,1) string = "NGAA  F"
        MLFLX (1,1) double = -1
        LBMNAM (1,1) string = "T"
        BMNAME (1,1) string = "p1_2013"
    end

    methods
        function s = toStruct(obj)
            s = struct();
            s.V1 = obj.V1;
            s.V2 = obj.V2;
            s.DV = obj.DV;
            s.FWHM = obj.FWHM;
            s.XFLAG = obj.XFLAG;
            s.FLAGS = obj.FLAGS;
            s.MLFLX = obj.MLFLX;
            s.LBMNAM = obj.LBMNAM;
            s.BMNAME = obj.BMNAME;
        end
    end
end