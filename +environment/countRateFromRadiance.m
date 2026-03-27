% Author: Peter Barrow
%
% Ref: Gruneisen, M. T., Eickhoff, M. L., et al. (2021),
% Adaptive-Optics-Enabled Quantum Communication: A Technique for Daytime
% Space-To-Earth Links, 10.1103/PhysRevApplied.16.014067.
%
% Calculate the number of sky photons coupled into the telescope

function counts = countRateFromRadiance(radiance, FOV, receiver_diameter, ...
    filter_width, integration_time, wavelengths, unit)
    arguments
        radiance {mustBeNumeric}                                            % radiance given in W m-2 sr-1 nm -1
        FOV (1, 1) {mustBeNumeric}
        receiver_diameter (1, 1) {mustBeNumeric}
        filter_width (1, 1) {mustBeNumeric}
        integration_time (1, 1) {mustBeNumeric}
        wavelengths (:, 1) {mustBeNumeric}
        unit units.Magnitude = "nano"
    end

    size_radiance = size(radiance);
    n_wavelengths = numel(wavelengths);

    assert(n_wavelengths == size_radiance(1), ...
        ['Incompatible sizes for radiance and wavelength. ', ...
         'Must be size(radiance) = (A, B) with size(wavelengths) = (1, A)']);

    % CONVERSION TO nm
    %wavelengths_nm = units.Magnitude.Convert(unit, "nano", wavelengths);
    filter_width_nm = units.Magnitude.Convert(unit, "nano", filter_width);     % using filter width in nm means we can keep radiance to nm^-1
    
    % CONVERSION TO m
    wavelengths_m = units.Magnitude.Convert(unit, "none", wavelengths);
    %filter_width_m = units.Magnitude.Convert(unit, "none", filter_width);

    h = 6.62607015*10^-34; % plank's constant
    c = 299792458; % speed of light

    solid_angle = pi * FOV^2 / 4;                                           % where FOV is the FULL ANGLE acceptance
    area = pi * receiver_diameter^2 / 4;                                    % originally didn't have diameter squared? Not sure why.

    % calculate the counts
    counts = ( ...
        radiance .* solid_angle .* area ...
        .* wavelengths_m ...
        .* filter_width_nm ...
        .* integration_time ) ...
        ./ ( h * c);
end
