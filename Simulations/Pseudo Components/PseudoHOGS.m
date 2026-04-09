function HOGS = PseudoHOGS(Wavelength,options)
%HOGS Construct HOGS
% need to detail the correct OGS parameters and components
% need to implement the Errol_OGS class to give the correct position

arguments
    Wavelength (1,1) double {mustBePositive}
    options.BeaconCamera {mustBeMember(options.BeaconCamera,{'Coarse','Fine'})} = 'Coarse'

    options.DetectorPreset (1,1) string = "PerkinElmer"
    options.RepetitionRate (1,1) double {mustBePositive} = 1e8
    options.TimeGate (1,1) double {mustBePositive} = 2e-9
    options.SpectralFilterWidth (1,1) double {mustBePositive} = 10
    options.Environment = []

    % Nset the telescope acceptance angle (FOV)
    %  - "diffraction" : use diffraction-limited acceptance (FFDC=1), do not set FOV explicitly
    %  - "geometric"   : compute from geometry (FieldStopDiameter & FocalLength), then set FOV
    %  - "direct"      : use FOVDirectRad
    options.FOVMode {mustBeMember(options.FOVMode,["diffraction","geometric","direct"])} = "direct"

    % direct FOV (radians) when FOVMode="direct"
    options.FOVDirectRad (1,1) double {mustBeNonnegative} = 37E-6

    % Parameter for Geometric FOV
    options.FieldDiameter_m (1,1) double {mustBePositive} = 0.04   % e.g. RC700 image field diameter
end

%% parameters and components
%Telescope
Telescope_Diameter = 0.7;                                                   %telescope diameter in m
Telescope_Focal_Length = 8.4;
Telescope_Eyepiece_Focal_Length = 0.076;
Pointing_Jitter = 1E-6;                                                     %pointing error in rads
Optical_Efficiency = (1-0.3^2)*10^(-1.1/10);                                %optical efficiency of telescope (dimensionless), including obscuration and back-end losses

% NEW: decide whether we pass an explicit 'FOV' to the Telescope constructor
% Important: Telescope.SetFOV requires Wavelength is set first.
telArgs = { ...
    'Wavelength', Wavelength, ...
    'Pointing_Jitter', Pointing_Jitter, ...
    'Optical_Efficiency', Optical_Efficiency, ...
    'Focal_Length', Telescope_Focal_Length, ...
    'Eyepiece_Focal_Length', Telescope_Eyepiece_Focal_Length ...
};

switch options.FOVMode
    case "diffraction"
        % do not set so use diffraction-limited acceptance angle

    case "direct"
        % set acceptance directly (radians)
        telArgs = [telArgs, {'FOV', options.FOVDirectRad}];

    case "geometric"
        FOV_geom = 2 * atan(options.FieldDiameter_m / (2 * Telescope_Focal_Length));
        telArgs = [telArgs, {'FOV', FOV_geom}];
end

HOGS_Telescope = components.Telescope(Telescope_Diameter, telArgs{:});

% Detector
Channel_Wavelength = Wavelength;                                    %signal wavelength in nm
Repetition_Rate = options.RepetitionRate;                           %signal rep rate in Hz
Time_Gate = options.TimeGate;                                       %time gate width in s
Spectral_Filter_Width = options.SpectralFilterWidth;                %spectral filter width in nm

HOGS_Detector = components.Detector(Channel_Wavelength, Repetition_Rate,...
    Time_Gate, Spectral_Filter_Width, 'Preset', options.DetectorPreset);

%beacon camera
switch options.BeaconCamera
    case 'Coarse'
Camera_Scope_Diameter = 0.4;
Camera_Scope_Focal_Length = 2.72;
Camera_Scope_Optical_Efficiency = 1-0.39^2;
Camera_Pointing_Precision = 1E-3;
Camera_Telescope = components.Telescope(Camera_Scope_Diameter,...
                            'Wavelength',685,...
                            'Optical_Efficiency',Camera_Scope_Optical_Efficiency,...
                            'Focal_Length',Camera_Scope_Focal_Length,...
                            'Pointing_Jitter',Camera_Pointing_Precision);
Exposure_Time = 0.01;
Spectral_Filter_Width = 10;
HOGS_Camera = AC4040(Camera_Telescope,Exposure_Time,Spectral_Filter_Width);%this is a constructor for the ATIK camera we use
    case 'Fine'
Camera_Scope_Diameter = Telescope_Diameter;
Camera_Scope_Focal_Length = Telescope_Focal_Length;
Camera_Scope_Optical_Efficiency = 1-0.3^2;
Camera_Pointing_Precision = 1E-3;
Camera_Telescope = components.Telescope(Camera_Scope_Diameter,...
                            'Wavelength',685,...
                            'Optical_Efficiency',Camera_Scope_Optical_Efficiency,...
                            'Focal_Length',Camera_Scope_Focal_Length,...
                            'Pointing_Jitter',Camera_Pointing_Precision);
Exposure_Time = 0.001;
Spectral_Filter_Width = 10;
HOGS_Camera = OWL320HS(Camera_Telescope,Exposure_Time,Spectral_Filter_Width);%this is a constructor for the ATIK camera we use
end

%uplink beacon
Beacon_Power = 40E-3;                                                           %power of uplink beacon in W
Beacon_Wavelength = 850;                                                        %uplink beacon wavelength in nm
BeaconPointingPrecision = 1E-6;                                                 %beacon pointing precision (coarse pointing precision) in rads
Beacon_Beam_Divergence =49.9E-6; %7mrad = 0.5 deg is the divergence of RAL's uplink beacon system. 50urad is our uplink beacon divergence
Beacon_Telescope = SetWavelength(HOGS_Telescope,Beacon_Wavelength);
Beacon_Telescope = SetFOV(Beacon_Telescope,Beacon_Beam_Divergence);
%initially, uncertainty in satellite position is 5km and range is roughly
%500km/sin(30), so pointing precision is on the order 5mrads.
BeaconEfficiency = 1;                                                           %beacon optical efficiency (unitless)
HOGSBeacon = beacon.Gaussian_Beacon(Beacon_Telescope,Beacon_Power,Beacon_Wavelength,...
    "Power_Efficiency", BeaconEfficiency, "Pointing_Jitter",  BeaconPointingPrecision);

%a standard enviroment
%for now we assume darkness and 20km visibility
if isempty(options.Environment)
    repo_root = utilities.addUserPath('~\Documents\GitHub\Qrackling');
    envPath = fullfile(repo_root, 'Examples', 'Data', 'atmospheric transmittance', 'Dark Environment 20km.mat');
    Env = environment.Environment.Load(envPath);
else
    Env = options.Environment;
end

%% construct OGS at Errol
HOGS=nodes.Ground_Station(HOGS_Telescope,...
                'Detector',HOGS_Detector,...
                'Camera',HOGS_Camera,...
                'Beacon',HOGSBeacon,...
                'LLA',[55.909723,-3.319995,10],...
                'name','HOGS',...
                'Environment',Env);
end