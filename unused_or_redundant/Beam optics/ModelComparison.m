% Compare Airy vs truncated-Gaussian far-field divergence and spot size
clear; clc;

repo_root = utilities.addUserPath('~\Documents\GitHub\Qrackling');

% Inputs
tx_diameter = 0.30;                                                         % aperture diameter [m]
link_length = 500e3;                                                        % link range [m]
truncRatio = 1.12;                                                          % optimized no-turbulence value
trunc_spot_size = tx_diameter / truncRatio;                                 % spot size at the aperture for truncated case
lambda_nm = linspace(200,4000,761);                                         % calculates every 5nm

% Preallocate
theta_airy      = zeros(size(lambda_nm));
theta_diff_lim  = zeros(size(lambda_nm));
theta_trunc     = zeros(size(lambda_nm));

spot_airy       = zeros(size(lambda_nm));
spot_diff_lim   = zeros(size(lambda_nm));
spot_trunc      = zeros(size(lambda_nm));

telA = AiryTelescope(tx_diameter);
telT = TruncGaussTelescope(tx_diameter, "Truncation_Ratio", truncRatio);

for k = 1:numel(lambda_nm)
    wav = lambda_nm(k);

    telA = telA.setWavelength(wav, "Wavelength_Scale", "nano");
    telT = telT.setWavelength(wav, "Wavelength_Scale", "nano"); 

    theta_airy(k)     = telA.fov; 
    theta_trunc(k)    = telT.fov;
    theta_diff_lim(k) = 2.44 * (wav*1e-9) / tx_diameter;   % explicit diffraction limit

    % Using your repo's spot-size style: d = tx_diameter + link_length*theta
    spot_airy(k)      = tx_diameter + link_length*theta_airy(k);
    spot_diff_lim(k)  = tx_diameter + link_length*theta_diff_lim(k);
    spot_trunc(k) = sqrt( trunc_spot_size^2 + (link_length * theta_trunc(k))^2 ); % this is also a fine but less accurate assumption: spot_trunc(k)     = trunc_spot_size + link_length*theta_trunc(k);  
end

% Plot 1: Divergence
figure('Color','w');
plot(lambda_nm, theta_trunc*1e6, 'LineWidth', 2); hold on;
plot(lambda_nm, theta_airy*1e6,  '--', 'LineWidth', 2);
plot(lambda_nm, theta_diff_lim*1e6, ':', 'LineWidth', 2);
grid on;
xlabel('Wavelength [nm]');
ylabel('Divergence angle [\murad]');
title(sprintf('Far-field divergence vs wavelength (tx_diameter = %.3f m)', tx_diameter));
legend('Truncated Gaussian', 'Airy model (class)', 'Diffraction limit 2.44\lambda/tx_diameter', ...
    'Location','northwest');

% Plot 2: Spot size
figure('Color','w');
plot(lambda_nm, spot_trunc, 'LineWidth', 2); hold on;
plot(lambda_nm, spot_airy,  '--', 'LineWidth', 2);
plot(lambda_nm, spot_diff_lim, ':', 'LineWidth', 2);
grid on;
xlabel('Wavelength [nm]');
ylabel('Spot size d = tx_diameter + link_length\theta [m]');
title(sprintf('Spot size vs wavelength (link_length = %.0f km)', link_length/1e3));
legend('Truncated Gaussian', 'Airy model (class)', 'Diffraction limit baseline', ...
    'Location','northwest');