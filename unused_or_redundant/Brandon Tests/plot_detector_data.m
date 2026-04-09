function plot_detector_data(detector, options)
    % PLOT_DETECTOR_DATA Comprehensive visualization of detector parameters
    %
    % Inputs:
    %   detector - components.Detector object
    %
    % Optional Name-Value Arguments:
    %   'ShowSummary' - Display text summary (default: true)
    %   'SaveFigure' - Save figure to file (default: false)
    %   'FileName' - Output filename if saving (default: 'detector_summary.png')
    %   'PlotPDF' - Plot PDF instead of raw histogram (default: true)
    %
    % Example:
    %   plot_detector_data(my_detector, 'ShowSummary', true);
    
    arguments
        detector components.Detector
        options.ShowSummary (1,1) logical = true
        options.SaveFigure (1,1) logical = false
        options.FileName (1,1) string = "detector_summary.png"
        options.PlotPDF (1,1) logical = true
    end
    
    % Create figure with multiple subplots
    fig = figure('Name', 'Detector Analysis', 'Position', [100, 100, 1200, 900]);
    tiles = tiledlayout(3, 2, 'TileSpacing', 'compact', 'Padding', 'compact');
    
    %% 1. Detection Efficiency vs Wavelength
    nexttile(tiles, 1, [1, 2]);
    if ~isempty(detector.Wavelength_Range) && ~isempty(detector.Efficiencies)
        plot(detector.Wavelength_Range, detector.Efficiencies * 100, 'LineWidth', 2, 'Color', [0, 0.4470, 0.7410]);
        hold on;
        if ~isempty(detector.Wavelength)
            xline(detector.Wavelength, 'g--', 'LineWidth', 2, ...
                'Label', sprintf('Operating: %d nm', round(detector.Wavelength)), ...
                'LabelVerticalAlignment', 'bottom');
            
            % Mark efficiency at operating wavelength
            eff_at_wl = detector.Detection_Efficiency * 100;
            plot(detector.Wavelength, eff_at_wl, 'ro', 'MarkerSize', 10, 'LineWidth', 2);
            text(detector.Wavelength, eff_at_wl, ...
                sprintf('  η = %.1f%%', eff_at_wl), ...
                'VerticalAlignment', 'bottom', 'FontSize', 10, 'FontWeight', 'bold');
        end
        hold off;
        xlabel('Wavelength (nm)', 'FontSize', 12);
        ylabel('Detection Efficiency (%)', 'FontSize', 12);
        title('Detection Efficiency vs Wavelength', 'FontSize', 14, 'FontWeight', 'bold');
        grid on;
        ylim([0, 100]);
    else
        text(0.5, 0.5, 'No efficiency data available', ...
            'HorizontalAlignment', 'center', 'FontSize', 12);
        axis off;
    end
    
    %% 2. Spectral Filter Response
    nexttile(tiles, 3);
    if ~isempty(detector.Spectral_Filter)
        try
            sf = detector.Spectral_Filter;
            wl_range = detector.Wavelength_Range;
            if isempty(wl_range)
                wl_range = linspace(detector.Wavelength - 50, detector.Wavelength + 50, 1000);
            end
            
            % Get transmission (method depends on filter type)
            if isprop(sf, 'Transmission')
                transmission = sf.Transmission(wl_range);
            else
                % For ideal filters, approximate the response
                transmission = ones(size(wl_range));
            end
            
            plot(wl_range, transmission * 100, 'LineWidth', 2, 'Color', [0.8500, 0.3250, 0.0980]);
            xlabel('Wavelength (nm)', 'FontSize', 12);
            ylabel('Transmission (%)', 'FontSize', 12);
            title('Spectral Filter Response', 'FontSize', 14, 'FontWeight', 'bold');
            grid on;
            ylim([0, 105]);
            
            if ~isempty(detector.Wavelength)
                xline(detector.Wavelength, 'g--', 'LineWidth', 1.5);
            end
        catch
            text(0.5, 0.5, 'Filter data not plottable', ...
                'HorizontalAlignment', 'center', 'FontSize', 10);
            axis off;
        end
    else
        text(0.5, 0.5, 'No spectral filter', 'HorizontalAlignment', 'center', 'FontSize', 12);
        axis off;
    end
    
    %% 3. Jitter Histogram/PDF
    nexttile(tiles, 4);
    if ~isempty(detector.Jitter_Histogram)
        num_points = numel(detector.Jitter_Histogram);
        [max_value, max_index] = max(detector.Jitter_Histogram);
        
        if options.PlotPDF && ~isempty(detector.PDF)
            % Plot PDF
            [max_pdf, max_idx_pdf] = max(detector.PDF);
            time_axis = ((1:numel(detector.PDF)) - max_idx_pdf) * detector.Histogram_Bin_Width * 1e12; % in ps
            plot(time_axis, detector.PDF, 'LineWidth', 2, 'Color', [0.4940, 0.1840, 0.5560]);
            ylabel('Probability Density (1/s)', 'FontSize', 12);
        else
            % Plot raw histogram
            time_axis = ((1:num_points) - max_index) * detector.Histogram_Bin_Width * 1e12; % in ps
            plot(time_axis, detector.Jitter_Histogram, 'LineWidth', 2, 'Color', [0.4940, 0.1840, 0.5560]);
            ylabel('Counts', 'FontSize', 12);
        end
        
        xlabel('Time (ps)', 'FontSize', 12);
        title('Timing Jitter', 'FontSize', 14, 'FontWeight', 'bold');
        grid on;
        
        % Add time gate markers if available
        if ~isempty(detector.Time_Gate_Width)
            gate_ps = detector.Time_Gate_Width * 1e12 / 2;
            xline(-gate_ps, 'b--', 'LineWidth', 1.5);
            xline(gate_ps, 'b--', 'LineWidth', 1.5);
        end
        
        % Calculate and display FWHM
        fwhm = detector.CalculateJitter() * 1e12; % in ps
        text(0.98, 0.95, sprintf('FWHM = %.2f ps', fwhm), ...
            'Units', 'normalized', ...
            'HorizontalAlignment', 'right', ...
            'VerticalAlignment', 'top', ...
            'FontSize', 10, 'FontWeight', 'bold', ...
            'BackgroundColor', 'white');
    else
        text(0.5, 0.5, 'No jitter data', 'HorizontalAlignment', 'center', 'FontSize', 12);
        axis off;
    end
    
    %% 4. Jitter Performance Metrics
    nexttile(tiles, 5);
    if ~isempty(detector.PDF) && ~isempty(detector.Repetition_Rate)
        num_jitter_points = numel(detector.PDF);
        [max_value, max_index] = max(detector.PDF);
        jitter_times = ((1:num_jitter_points) - max_index) * detector.Histogram_Bin_Width;
        period = 1 / detector.Repetition_Rate;
        
        plot(jitter_times, detector.PDF, 'LineWidth', 2, 'Color', [0.4660, 0.6740, 0.1880]);
        xlabel('Time (s)', 'FontSize', 12);
        ylabel('PDF', 'FontSize', 12);
        title('Jitter vs Repetition Period', 'FontSize', 14, 'FontWeight', 'bold');
        
        % Time gate
        if ~isempty(detector.Time_Gate_Width)
            xline(-detector.Time_Gate_Width/2, 'b--', 'LineWidth', 1.5);
            xline(detector.Time_Gate_Width/2, 'b--', 'LineWidth', 1.5);
            text(detector.Time_Gate_Width/2, max_value/2, ...
                sprintf('  Gate = %.2g s', detector.Time_Gate_Width), ...
                'VerticalAlignment', 'top', 'Color', 'b', 'FontSize', 9);
        end
        
        % Repetition period
        xline(0, 'r--', 'LineWidth', 1.5);
        xline(period, 'r--', 'LineWidth', 1.5);
        text(period, max_value/2, ...
            sprintf('  Rep Rate = %.2g Hz\n  Period = %.2g s\n  QBER_{jitter} = %.3g%%', ...
            detector.Repetition_Rate, period, 100*detector.QBER_Jitter), ...
            'VerticalAlignment', 'top', 'Color', 'r', 'FontSize', 9);
        
        xlim([-period, 2*period]);
        grid on;
    else
        text(0.5, 0.5, 'No jitter performance data', ...
            'HorizontalAlignment', 'center', 'FontSize', 12);
        axis off;
    end
    
    %% 5. Text Summary
    nexttile(tiles, 6);
    axis off;
    
    if options.ShowSummary
        summary_text = {};
        summary_text{end+1} = '\bf\fontsize{14}Detector Parameters';
        summary_text{end+1} = '\rm\fontsize{11}';
        summary_text{end+1} = '--------------------------------';
        
        if ~isempty(detector.Wavelength)
            summary_text{end+1} = sprintf('Wavelength: %.1f nm', detector.Wavelength);
        end
        
        if ~isempty(detector.Detection_Efficiency)
            summary_text{end+1} = sprintf('Detection Efficiency: %.2f%%', detector.Detection_Efficiency * 100);
        end
        
        if ~isempty(detector.Dark_Count_Rate)
            summary_text{end+1} = sprintf('Dark Count Rate: %.2g Hz', detector.Dark_Count_Rate);
        end
        
        if ~isempty(detector.Dead_Time)
            summary_text{end+1} = sprintf('Dead Time: %.2g s', detector.Dead_Time);
        end
        
        if ~isempty(detector.Time_Gate_Width)
            summary_text{end+1} = sprintf('Time Gate Width: %.2g s', detector.Time_Gate_Width);
        end
        
        if ~isempty(detector.Repetition_Rate)
            summary_text{end+1} = sprintf('Repetition Rate: %.2g Hz', detector.Repetition_Rate);
        end
        
        if ~isempty(detector.Histogram_Bin_Width)
            summary_text{end+1} = sprintf('Histogram Bin Width: %.2g s', detector.Histogram_Bin_Width);
        end
        
        summary_text{end+1} = '';
        summary_text{end+1} = '\bf\fontsize{12}Performance Metrics';
        summary_text{end+1} = '\rm\fontsize{11}';
        summary_text{end+1} = '--------------------------------';
        
        if ~isempty(detector.QBER_Jitter)
            summary_text{end+1} = sprintf('QBER (Jitter): %.4f%%', detector.QBER_Jitter * 100);
        end
        
        if ~isempty(detector.Jitter_Loss)
            summary_text{end+1} = sprintf('Jitter Loss: %.4f', detector.Jitter_Loss);
        end
        
        if ~isempty(detector.Polarisation_Error)
            summary_text{end+1} = sprintf('Polarisation Error: %.4f°', detector.Polarisation_Error);
        end
        
        if ~isempty(detector.Visibility)
            summary_text{end+1} = sprintf('Visibility: %.4f', detector.Visibility);
        end
        
        if ~isempty(detector.Jitter_Histogram)
            fwhm = detector.CalculateJitter() * 1e12;
            summary_text{end+1} = sprintf('Jitter FWHM: %.2f ps', fwhm);
        end
        
        text(0.05, 0.95, strjoin(summary_text, '\n'), ...
            'Units', 'normalized', ...
            'VerticalAlignment', 'top', ...
            'FontName', 'FixedWidth', ...
            'FontSize', 10, ...
            'Interpreter', 'tex');
    end
    
    % Overall title
    title(tiles, 'Detector Comprehensive Analysis', 'FontSize', 16, 'FontWeight', 'bold');
    
    % Save if requested
    if options.SaveFigure
        saveas(fig, options.FileName);
        fprintf('Figure saved to: %s\n', options.FileName);
    end
    
    % Print summary to console
    if options.ShowSummary
        fprintf('\n=== DETECTOR SUMMARY ===\n');
        fprintf('Wavelength: %.1f nm\n', detector.Wavelength);
        fprintf('Detection Efficiency: %.2f%%\n', detector.Detection_Efficiency * 100);
        fprintf('Dark Count Rate: %.2g Hz\n', detector.Dark_Count_Rate);
        fprintf('Dead Time: %.2g s\n', detector.Dead_Time);
        fprintf('QBER (Jitter): %.4f%%\n', detector.QBER_Jitter * 100);
        if ~isempty(detector.Jitter_Histogram)
            fprintf('Jitter FWHM: %.2f ps\n', detector.CalculateJitter() * 1e12);
        end
        fprintf('========================\n\n');
    end
end