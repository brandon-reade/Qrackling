%% DETECTOR GENERATION FILE
% Cameron's Paper: https://opg.optica.org/directpdfaccess/453e6787-7050-49f7-abddb7114b439727_553200/oe-32-15-26776.pdf?da=1&id=553200&seq=0&mobile=no
% Original Paper: https://opg.optica.org/directpdfaccess/4734725b-919c-461c-bb1ffd5f6ca79297_470770/prj-10-4-1063.pdf?da=1&id=470770&seq=0&mobile=no


% Dark Count Rate
Dark_Count_Rate = 240;

% Dead Time
Dead_Time = 11.60e-09;

% Efficiencies
Efficiencies = 0.63 * ones(1, (3500-2000 + 1));                                         % assumed 63% efficiency for all wavelengths

% Histogram Bin Width
Histogram_Bin_Width = 1.00e-12;                                             % set jitter time unit to pico seconds

% Jitter Histogram
Jitter_Histogram = 14.3 * ones(1,(3500-2000 + 1));                                      % assumed 14.3 pico seconds for each wavelength

% Name
Name = 'SNSPD_NbTiN_2um.mat';

% Wavelength Range
Wavelength_Range = 2000:1:3500; % Range assumed to be 2um to 2.2um

save 'SNSPD_NbTiN_2um.mat' Dark_Count_Rate Dead_Time Efficiencies Histogram_Bin_Width Jitter_Histogram Name Wavelength_Range