Name = 'ThorlabsS148C';
Dark_Count_Rate = 250;
Dead_Time = 3.200000000000000e-08;
Jitter_Histogram = [100, 150, 400, 1000, 2000, 1500, 1200, 1000, ...
                    900, 800, 700, 600, 500, 400, 300, 200, 100];
Histogram_Bin_Width = 1.000000000000000e-12;
Wavelength_Range = 1900:1:2200; % detector supports 1200 to 2500 nm


%% Generating Pseudo-efficiencies following a Gaussian Distribution
% Parameters for Gaussian
A = 1;           % Peak efficiency (max value)
mu = 1850;       % Center wavelength (peak of the Gaussian)
sigma = 200;     % Spread (standard deviation)

% Generate efficiency values using Gaussian function
Efficiencies = A * exp(-((Wavelength_Range - mu).^2) / (2 * sigma^2));

save 'ThorlabsS148C.mat' Dark_Count_Rate Dead_Time Efficiencies Histogram_Bin_Width Jitter_Histogram Name Wavelength_Range