%% Pseudo OGS for Goldstone Deep Space Communications Complex (California, USA)
%   - located in the Mojave Desert
%   - primarily a radio-frequency hub for NASA's Deep Space Network
%   - need to add desert windspeed settings
%   - SPOQC has good overhead pass from N to S on: 2026-05-06T10:24:54.941Z (which is ~3:25 am on 06/05/2026 in Goldstone)
function p = Goldstone(varargin)
    p = modtran.locations.LocationPreset();
    p.label = "Goldstone";

    % Location
    p.lat   = 35.4267;
    p.lon   = -116.8900;
    p.alt_m = 950;

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