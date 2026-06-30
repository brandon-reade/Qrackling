%% DETECTOR GENERATION FILE

% Dead Time
Dead_Time = 100e-09;

%% Define Regions
% Wavelength Range (nm): 1.8 um to 2.2 um
Wavelength_Range = 1800:1:2200;
idx1 = (Wavelength_Range >= 1800) & (Wavelength_Range <= 2000);             % Region 1: 1.8–2.0 um
idx2 = (Wavelength_Range > 2000) & (Wavelength_Range <= 2200);              % Region 2: 2.0–2.2 um

%% SDE
Efficiencies = zeros(size(Wavelength_Range));
Efficiencies(idx1) = 0.70;                                                  % 1800 - 2000 nm: 70% SDE
Efficiencies(idx2) = interp1([2000 2200], [0.70 0.30], ...                  % 2001 - 2200 nm: SDE falls linearly from 70% to 30%
    Wavelength_Range(idx2), 'linear');

%% DCR
Dark_Count_Rate = zeros(size(Wavelength_Range));

% Fits an exponential growth curve: DCR = A * exp(B * lambda)
DCR_1800 = 1e3;
DCR_2000 = 5e3;
DCR_2200 = 50e3;

% Fit Region 1 (1800 to 2000 nm)
B1 = log(DCR_2000 / DCR_1800) / (2000 - 1800);
A1 = DCR_1800 / exp(B1 * 1800);
Dark_Count_Rate(idx1) = A1 * exp(B1 * Wavelength_Range(idx1));

% Fit Region 2 (2000 to 2200 nm)
B2 = log(DCR_2200 / DCR_2000) / (2200 - 2000);
A2 = DCR_2000 / exp(B2 * 2000);
Dark_Count_Rate(idx2) = A2 * exp(B2 * Wavelength_Range(idx2));


%% Jitter Histogram
% Create histogram for SNSPD
[jitter_hist, bin_width] = create_jitter_histogram(50, ...
    'NumBins', 1001, ...
    'PeakCounts', 10000);

% Verify by checking what CalculateJitter would return
fprintf('\nBin width: %.3e s\n', bin_width);
fprintf('Peak at index: %d\n', find(jitter_hist == max(jitter_hist)));

% set jitter values
Jitter_Histogram = jitter_hist;
Histogram_Bin_Width = bin_width;


%% Name and save
Name = 'SingleQuantum_specs_2um.mat';

save(Name, 'Dark_Count_Rate', 'Dead_Time', 'Efficiencies', ...
           'Histogram_Bin_Width', 'Jitter_Histogram', 'Name', 'Wavelength_Range');