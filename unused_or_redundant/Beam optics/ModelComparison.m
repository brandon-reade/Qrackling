% Compare Airy vs truncated-Gaussian far-field divergence and spot size
clear; clc;

repo_root = utilities.addUserPath('~\Documents\GitHub\Qrackling');

%% Inputs
tx_diameter = 0.10;                                                         % aperture diameter [m]
link_length = 500e3;                                                        % link range [m]
truncRatio = 1.12;                                                          % optimized no-turbulence value is 1.12, if we set this any lower the Gaussian assumption for Geo and APT loss becomes inaccurate
trunc_spot_size = tx_diameter / truncRatio;                                 % spot size at the aperture for truncated case
lambda_nm = linspace(200,10000);                                            
pointing_jitter = 1E-6;                                                     % closed loop pointing accuracy [urad]

%% Preallocate
% Divergence angles
theta_airy      = zeros(size(lambda_nm));
theta_airy_1e   = zeros(size(lambda_nm));
theta_diff_lim  = zeros(size(lambda_nm));
theta_trunc     = zeros(size(lambda_nm));

% Spot sizes
spot_airy       = zeros(size(lambda_nm));
spot_diff_lim   = zeros(size(lambda_nm));
spot_trunc      = zeros(size(lambda_nm));

% Loss components
airy_apt_loss        = zeros(size(lambda_nm));
airy_old_geo_loss    = zeros(size(lambda_nm));
airy_geo_loss        = zeros(size(lambda_nm));
trunc_apt_loss       = zeros(size(lambda_nm));
trunc_geo_loss       = zeros(size(lambda_nm));

% Aperture loss
aperture_loss        = calc_aperture_loss(truncRatio);
fprintf("Aperture Loss: %.2f dB", -aperture_loss)

% Total loss
total_airy_loss      = zeros(size(lambda_nm));
total_trunc_loss     = zeros(size(lambda_nm));

%% Calculate for each model type
% Initialise telescopes
telA = AiryTelescope(tx_diameter);
telT = TruncGaussTelescope(tx_diameter, "Truncation_Ratio", truncRatio);

% Loop for each wavelength
for k = 1:numel(lambda_nm)
    wav = lambda_nm(k);

    % set the wavelength
    telA = telA.setWavelength(wav, "Wavelength_Scale", "nano");
    telT = telT.setWavelength(wav, "Wavelength_Scale", "nano"); 

    % Set the divergence angles
    theta_airy(k)     = telA.fov;                                           % classic airy (which we can modulate with quality factor 'm') 
    theta_airy_1e(k)     = 0.674 * telA.fov;                                % airy diffraction limit adjusted to the 1/e^2 intensity boundary instead of the first null 
    theta_trunc(k)    = telT.fov;                                           % truncated gaussian (which we can modulate with quality factor 'm')
    theta_diff_lim(k) = 2.44 * (wav*1e-9) / tx_diameter;                    % explicit airy diffraction limit

    % Calculating spot size
    spot_airy(k)      = tx_diameter + link_length*theta_airy(k);
    spot_diff_lim(k)  = tx_diameter + link_length*theta_diff_lim(k);
    spot_trunc(k) = sqrt( trunc_spot_size^2 + (link_length * theta_trunc(k))^2 ); % Another fine but less accurate assumption is expressed : spot_trunc(k)     = trunc_spot_size + link_length*theta_trunc(k);  

    % calculate losses
    airy_apt_loss(k)         = calc_apt_loss(theta_airy(k), pointing_jitter, true);
    trunc_apt_loss(k)        = calc_apt_loss(theta_trunc(k), pointing_jitter, false);

    airy_geo_loss(k)         = calc_geo_loss(tx_diameter, spot_airy(k), true);
    trunc_geo_loss(k)        = calc_geo_loss(tx_diameter, spot_trunc(k), false);

    total_airy_loss(k)       = airy_apt_loss(k) + airy_geo_loss(k);                     % aperture loss ignored for airy disk modeling in Qrackling
    total_trunc_loss(k)      = trunc_apt_loss(k) + trunc_geo_loss(k) + aperture_loss;   % we can now analyse the aperture loss with truncated gaussian
end

%% Plots
% Plot 1: Divergence
figure('Color','w');
plot(lambda_nm, theta_trunc*1e6, 'LineWidth', 2); hold on;
plot(lambda_nm, theta_airy*1e6, ':', 'LineWidth', 2);
plot(lambda_nm, theta_airy_1e*1e6,  '--', 'LineWidth', 2);
grid on;
xlabel('Wavelength [nm]');
ylabel('Divergence angle [\murad]');
title(sprintf('Far-field divergence vs wavelength (Aperture = %.2f m, Truncation Ratio = %.2f)', tx_diameter, truncRatio));
legend('Truncated Gaussian', 'Airy Disk', ...
    'Airy 1/e field');

% Plot 2: Spot size
figure('Color','w');
plot(lambda_nm, spot_trunc, 'LineWidth', 2); hold on;
%plot(lambda_nm, spot_airy,  '--', 'LineWidth', 2);
plot(lambda_nm, spot_diff_lim, ':', 'LineWidth', 2);
grid on;
xlabel('Wavelength [nm]');
ylabel('Spot size diameter [m]');
title(sprintf('Spot size vs wavelength (link length = %.0f km, Truncation Ratio = %.2f)', link_length/1e3, truncRatio));
legend('Truncated Gaussian Diffraction limit', 'Airy Diffraction limit ', ...
    'Location','northwest');

% Plot 3: APT loss
figure('Color','w');
plot(lambda_nm, trunc_apt_loss, 'LineWidth', 2); hold on;
plot(lambda_nm, airy_apt_loss, ':', 'LineWidth', 2);
grid on;
xlabel('Wavelength [nm]');
ylabel('APT Loss [dB]');
title(sprintf('APT loss vs wavelength (link length = %.0f km, Truncation Ratio = %.2f)', link_length/1e3, truncRatio));
legend('Truncated Gaussian Model', 'Airy Disc ');

% Plot 4: Geo loss
figure('Color','w');
plot(lambda_nm, trunc_geo_loss, 'LineWidth', 2); hold on;
plot(lambda_nm, airy_geo_loss, ':', 'LineWidth', 2);
grid on;
xlabel('Wavelength [nm]');
ylabel('Geometric Loss [dB]');
title(sprintf('Geometric loss vs wavelength (link length = %.0f km, Truncation Ratio = %.2f)', link_length/1e3, truncRatio));
legend('Truncated Gaussian Model', 'Airy Diffraction limit');

% Plot 5: total loss
figure('Color','w');
plot(lambda_nm, total_trunc_loss, 'LineWidth', 2); hold on;
plot(lambda_nm, total_airy_loss, ':', 'LineWidth', 2);
grid on;
xlabel('Wavelength [nm]');
ylabel('Total Loss [dB]');
title(sprintf('Total loss vs wavelength (link length = %.0f km, Truncation Ratio = %.2f)', link_length/1e3, truncRatio));
legend('Truncated Gaussian Model', 'Airy Model');
%% APT Loss
function [apt_loss] = calc_apt_loss(fov, jitter, flag)
    if nargin < 3
        flag = false;
    end

    if flag == true
        apt_loss = 10*log10(fov ^ 2 / (jitter ^ 2 + fov ^ 2));
    else
        apt_loss = 10*log10(fov ^ 2 / ((4*jitter ^ 2) + fov ^ 2));
    end
end


%% Geometric Loss
function [geo_loss] = calc_geo_loss(diameter, spot_size, flag)
    if nargin < 3
        flag = false;
    end

    if flag == true
        geo_loss = 10*log10((1/8) * (diameter ./ spot_size) .^ 2);
    else
        geo_loss = 10*log10((1/2) * (diameter ./ spot_size) .^ 2);
    end
end

%% Aperture Loss
% This is the probabaility that a photon escapes the aperture
function [aperture_loss] = calc_aperture_loss(truncation_ratio)
    aperture_loss = 10*log10(( ...
        1 - exp(-2 * truncation_ratio^2)...
        ));
end