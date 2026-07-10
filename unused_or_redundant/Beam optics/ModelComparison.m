% Compare Airy vs truncated-Gaussian far-field divergence and spot size
clear; clc;

repo_root = utilities.addUserPath('~\Documents\GitHub\Qrackling');

% Inputs
tx_diameter = 0.10;                                                         % aperture diameter [m]
link_length = 500e3;                                                        % link range [m]
truncRatio = 1.12;                                                          % optimized no-turbulence value is 1.12, if we set this any lower the Gaussian assumption for Geo and APT loss becomes inaccurate
trunc_spot_size = tx_diameter / truncRatio;                                 % spot size at the aperture for truncated case
lambda_nm = linspace(200,10000);                                            
pointing_jitter = 1E-3;                                                     % closed loop pointing accuracy [urad]

% Preallocate
theta_airy      = zeros(size(lambda_nm));
theta_airy_1e   = zeros(size(lambda_nm));
theta_diff_lim  = zeros(size(lambda_nm));
theta_trunc     = zeros(size(lambda_nm));

spot_airy       = zeros(size(lambda_nm));
spot_diff_lim   = zeros(size(lambda_nm));
spot_trunc      = zeros(size(lambda_nm));

airy_apt_loss        = zeros(size(lambda_nm));
airy_old_geo_loss    = zeros(size(lambda_nm));
airy_geo_loss        = zeros(size(lambda_nm));
trunc_apt_loss       = zeros(size(lambda_nm));
trunc_geo_loss       = zeros(size(lambda_nm));

telA = AiryTelescope(tx_diameter);
telT = TruncGaussTelescope(tx_diameter, "Truncation_Ratio", truncRatio);

for k = 1:numel(lambda_nm)
    wav = lambda_nm(k);

    telA = telA.setWavelength(wav, "Wavelength_Scale", "nano");
    telT = telT.setWavelength(wav, "Wavelength_Scale", "nano"); 

    theta_airy(k)     = telA.fov; 
    theta_airy_1e(k)     = 0.668 * telA.fov;
    theta_trunc(k)    = telT.fov;
    theta_diff_lim(k) = 2.44 * (wav*1e-9) / tx_diameter;   % explicit diffraction limit

    % Calculating spot size
    spot_airy(k)      = tx_diameter + link_length*theta_airy(k);
    spot_diff_lim(k)  = tx_diameter + link_length*theta_diff_lim(k);
    spot_trunc(k) = sqrt( trunc_spot_size^2 + (link_length * theta_trunc(k))^2 ); % this is also a fine but less accurate assumption: spot_trunc(k)     = trunc_spot_size + link_length*theta_trunc(k);  

    % calculate losses
    airy_apt_loss(k)         = calc_apt_loss(theta_airy(k), pointing_jitter);
    trunc_apt_loss(k)        = calc_apt_loss(theta_trunc(k), pointing_jitter);

    airy_old_geo_loss(k)     = calc_geo_loss(tx_diameter, spot_airy(k), true);
    airy_geo_loss(k)         = calc_geo_loss(tx_diameter, spot_airy(k), false);
    trunc_geo_loss(k)        = calc_geo_loss(tx_diameter, spot_trunc(k), false);
end

% Plot 1: Divergence
figure('Color','w');
plot(lambda_nm, theta_trunc*1e6, 'LineWidth', 2); hold on;
plot(lambda_nm, theta_airy*1e6, ':', 'LineWidth', 2);
plot(lambda_nm, theta_airy_1e*1e6,  '--', 'LineWidth', 2);
grid on;
xlabel('Wavelength [nm]');
ylabel('Divergence angle [\murad]');
title(sprintf('Far-field divergence vs wavelength (aperture = %.3f m)', tx_diameter));
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
title(sprintf('Spot size vs wavelength (link length = %.0f km)', link_length/1e3));
legend('Truncated Gaussian Diffraction limit', 'Airy Diffraction limit ', ...
    'Location','northwest');

% Plot 3: APT loss
figure('Color','w');
plot(lambda_nm, trunc_apt_loss, 'LineWidth', 2); hold on;
plot(lambda_nm, airy_apt_loss, ':', 'LineWidth', 2);
grid on;
xlabel('Wavelength [nm]');
ylabel('APT Loss [dB]');
title(sprintf('APT loss vs wavelength (link length = %.0f km)', link_length/1e3));
legend('Truncated Gaussian Model', 'Airy Disc ');

% Plot 4: Geo loss
figure('Color','w');
plot(lambda_nm, trunc_geo_loss, 'LineWidth', 2); hold on;
plot(lambda_nm, airy_old_geo_loss,  '--', 'LineWidth', 2);
plot(lambda_nm, airy_geo_loss, ':', 'LineWidth', 2);
grid on;
xlabel('Wavelength [nm]');
ylabel('Geometric Loss [dB]');
title(sprintf('Geometric loss vs wavelength (link length = %.0f km)', link_length/1e3));
legend('Truncated Gaussian Model', 'Airy Diffraction limit (old coefficient) ', 'Airy Diffraction limit (new coefficient)');

%% APT Loss
function [apt_loss] = calc_apt_loss(fov, jitter)
    apt_loss = 10*log10(fov ^ 2 / (jitter ^ 2 + fov ^ 2));
end


%% Geometric Loss
function [geo_loss] = calc_geo_loss(diameter, spot_size, flag)
    if nargin < 3
        flag = false;
    end

    if flag == true
        geo_loss = 10*log10((pi/2) * (diameter ./ spot_size) .^ 2);
    else
        geo_loss = 10*log10((1/2) * (diameter ./ spot_size) .^ 2);
    end
end