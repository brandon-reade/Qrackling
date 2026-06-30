% Create histogram for 14.3ps SNSPD
[jitter_hist, bin_width] = create_jitter_histogram(14.3, ...
    'NumBins', 1001, ...
    'PeakCounts', 10000);

% Verify by checking what CalculateJitter would return
fprintf('\nBin width: %.3e s\n', bin_width);
fprintf('Peak at index: %d\n', find(jitter_hist == max(jitter_hist)));

%% Step 1: Load the existing preset file
% Replace 'PerkinElmer' with whatever preset you're modifying
load('C:\Users\bsr4001\Documents\GitHub\Qrackling\+components\@Detector\presets\SNSPD_NbTiN_2um.mat');

%% Step 2: Replace the Jitter_Histogram and Histogram_Bin_Width
% Assuming your new data is in 'jitter_hist' and 'bin_width' from your script
Jitter_Histogram = jitter_hist;
Histogram_Bin_Width = bin_width;

%% Step 3: Save back to the .mat file
save('C:\Users\bsr4001\Documents\GitHub\Qrackling\+components\@Detector\presets\SNSPD_NbTiN_2um.mat', ...
    'Dark_Count_Rate', ...
    'Dead_Time', ...
    'Efficiencies', ...
    'Histogram_Bin_Width', ...
    'Jitter_Histogram', ...
    'Wavelength_Range');

fprintf('Updated detector preset with new jitter histogram!\n');