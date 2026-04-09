function [jitter_histogram, bin_width] = create_jitter_histogram(jitter_fwhm_ps, options)
    % CREATE_JITTER_HISTOGRAM Creates a Gaussian jitter histogram for Qrackling Detector
    %
    % This function creates a jitter histogram that matches the conventions used
    % in components.Detector class:
    % - Histogram contains RAW COUNTS (not normalized)
    % - Peak is at the center of the array
    % - FWHM is measured empirically from the histogram
    %
    % Inputs:
    %   jitter_fwhm_ps - Target FWHM jitter in picoseconds (e.g., 14.3 for SNSPD)
    %
    % Optional Name-Value Arguments:
    %   'NumBins' - Number of bins in histogram (default: 1001, should be odd)
    %   'SpanFWHM' - How many FWHM to span total (default: 10)
    %   'PeakCounts' - Peak count value (default: 10000)
    %   'VerifyFWHM' - Check that empirical FWHM matches target (default: true)
    
    arguments
        jitter_fwhm_ps double {mustBePositive}
        options.NumBins (1,1) double {mustBePositive, mustBeInteger} = 1001
        options.SpanFWHM (1,1) double {mustBePositive} = 10
        options.PeakCounts (1,1) double {mustBePositive} = 10000
        options.VerifyFWHM (1,1) logical = true
    end
    
    % Ensure odd number of bins (so center bin is at index (N+1)/2)
    num_bins = options.NumBins;
    if mod(num_bins, 2) == 0
        num_bins = num_bins + 1;
        warning('NumBins must be odd. Using %d bins instead.', num_bins);
    end
    
    % Convert FWHM to standard deviation for Gaussian
    % FWHM = 2*sqrt(2*ln(2))*sigma
    sigma_ps = jitter_fwhm_ps / (2 * sqrt(2 * log(2)));
    
    % Calculate bin width: span SpanFWHM * jitter_fwhm_ps over num_bins
    total_span_ps = jitter_fwhm_ps * options.SpanFWHM;
    bin_width_ps = total_span_ps / (num_bins - 1);
    bin_width = bin_width_ps * 1e-12;  % Convert to seconds
    
    % Create time vector centered at zero
    center_idx = ceil(num_bins / 2);
    indices = 1:num_bins;
    time_ps = (indices - center_idx) * bin_width_ps;
    
    % Generate Gaussian distribution
    gaussian = exp(-(time_ps.^2) / (2 * sigma_ps^2));
    
    % Scale to peak counts (raw counts, not normalized)
    jitter_histogram = round(gaussian * options.PeakCounts);
    
    % Ensure minimum count of 1 where gaussian is non-negligible
    threshold = options.PeakCounts * 0.001;  % 0.1% of peak
    jitter_histogram(jitter_histogram == 0 & gaussian*options.PeakCounts > threshold) = 1;
    
    % Verify empirical FWHM matches target
    if options.VerifyFWHM
        empirical_fwhm_ps = calculate_empirical_fwhm(jitter_histogram, bin_width_ps, center_idx);
        fwhm_error_percent = abs(empirical_fwhm_ps - jitter_fwhm_ps) / jitter_fwhm_ps * 100;
        
        if fwhm_error_percent > 5
            warning(['Empirical FWHM (%.2f ps) differs from target (%.2f ps) by %.1f%%.\n' ...
                     'Consider increasing NumBins or adjusting SpanFWHM.'], ...
                     empirical_fwhm_ps, jitter_fwhm_ps, fwhm_error_percent);
        end
    end
    
    % Plot the histogram
    figure('Name', 'Detector Jitter Histogram');
    plot(time_ps, jitter_histogram, 'LineWidth', 2);
    xlabel('Time (ps)');
    ylabel('Counts (raw)');
    title(sprintf('Jitter Histogram (Target FWHM = %.2f ps)', jitter_fwhm_ps));
    grid on;
    
    % Add FWHM markers
    half_max = options.PeakCounts / 2;
    xline(-jitter_fwhm_ps/2, 'r--', 'LineWidth', 1.5, 'Label', 'FWHM');
    xline(jitter_fwhm_ps/2, 'r--', 'LineWidth', 1.5);
    yline(half_max, 'g--', 'Half Max', 'LineWidth', 1.5);
    
    % Calculate empirical FWHM
    empirical_fwhm_ps = calculate_empirical_fwhm(jitter_histogram, bin_width_ps, center_idx);
    
    % Add text annotation
    text(0, options.PeakCounts * 0.9, ...
        sprintf(['Target FWHM = %.2f ps\n' ...
                 'Empirical FWHM = %.2f ps\n' ...
                 'σ = %.2f ps\n' ...
                 'Bin Width = %.3f ps'], ...
                jitter_fwhm_ps, empirical_fwhm_ps, sigma_ps, bin_width_ps), ...
        'HorizontalAlignment', 'center', ...
        'VerticalAlignment', 'top', ...
        'BackgroundColor', 'white', ...
        'EdgeColor', 'black', ...
        'FontSize', 10);
    
    % Console output
    fprintf('Created jitter histogram:\n');
    fprintf('  Target FWHM: %.2f ps\n', jitter_fwhm_ps);
    fprintf('  Empirical FWHM: %.2f ps\n', empirical_fwhm_ps);
    fprintf('  Sigma: %.2f ps\n', sigma_ps);
    fprintf('  Bin width: %.3f ps (%.3e s)\n', bin_width_ps, bin_width);
    fprintf('  Number of bins: %d\n', num_bins);
    fprintf('  Center index: %d\n', center_idx);
    fprintf('  Total counts: %d\n', sum(jitter_histogram));
    fprintf('  Peak counts: %d\n', max(jitter_histogram));
end

function fwhm_ps = calculate_empirical_fwhm(histogram, bin_width_ps, center_idx)
    % Calculate FWHM empirically from histogram by finding half-maximum points
    
    half_max = max(histogram) / 2;
    
    % Find left half-maximum crossing
    left_indices = find(histogram(1:center_idx) >= half_max, 1, 'first');
    if isempty(left_indices)
        left_indices = 1;
    end
    
    % Find right half-maximum crossing
    right_indices = find(histogram(center_idx:end) >= half_max, 1, 'last') + center_idx - 1;
    if isempty(right_indices)
        right_indices = length(histogram);
    end
    
    % Calculate FWHM in bins, then convert to ps
    fwhm_bins = right_indices - left_indices;
    fwhm_ps = fwhm_bins * bin_width_ps;
end