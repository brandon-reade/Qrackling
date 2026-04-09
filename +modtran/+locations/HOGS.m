function p = HOGS(varargin)
    % HOGS (Edinburgh) preset
    p = modtran.locations.LocationPreset();
    p.label = "HOGS";

    % Location
    p.lat   = 55.91450119018555;
    p.lon   = -3.3166000843048096;
    p.alt_m = 100;

    % Geometry sweep defaults
    p.zen_min = 0;  p.zen_max = 90;  p.zen_step = 10;
    p.azi_min = 0;  p.azi_max = 330; p.azi_step = 30;

    % Your "zen=0 LBL safety" defaults
    p.enableLosOverrides = true;
    p.losOverrideMode = "zen0";
    p.forceLblAtZen0IfCorrelatedK = true;

    % Atmosphere (defaults to Winter)
    p.atm_MODEL = "ATM_MIDLAT_WINTER";
    p.M2_RHC = true;

    % Aerosols (defaults to Winter)
    p.visib_km = 5;                                                        % defaults to 5km visibility
    p.season = "winter";
    p.aerosol_model = "urban";
    p.strato_model  = "background";
    p.clouds = "none";

    % Surface & RT
    p.CSALB = "LAMB_URBAN";
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