%% Pseudo OGS for Blönduós (Iceland)
%   - located near the town of Blönduós
%   - area is characterized by a volcanic basalt landscape and harsh winter weather
%   - NEED TO ADD IN THE REST, NOT READY YET
function p = Blonduos(varargin)
    p = modtran.locations.LocationPreset();
    p.label = "Goldstone";

    % Location
    p.lat   = 65.659;
    p.lon   = -20.278;
    p.alt_m = 5;

    % Geometry sweep defaults
    p.zen_min = 0;  p.zen_max = 90;  p.zen_step = 10;
    p.azi_min = 0;  p.azi_max = 330; p.azi_step = 30;

    % Your "zen=0 LBL safety" defaults
    p.enableLosOverrides = true;
    p.losOverrideMode = "zen0";
    p.forceLblAtZen0IfCorrelatedK = true;

    % Atmosphere (defaults to Summer)
    p.atm_MODEL = "ATM_MIDLAT_SUMMER";
    p.M2_RHC = true;

    % Aerosols (defaults to Summer)
    p.visib_km = 23;                                                        % defaults to 23km visibility
    p.season = "summer";
    p.aerosol_model = "desert";
    p.strato_model  = "background";
    p.clouds = "none";

    % Surface & RT
    p.CSALB = "LAMB_DESERT";
    p.NSTR = 8;

    % Optional overrides via name or value
    if ~isempty(varargin)
        % accept name/value for any public property
        for i = 1:2:numel(varargin)
            name = string(varargin{i});
            value = varargin{i+1};
            p.(name) = value;
        end
    end
end