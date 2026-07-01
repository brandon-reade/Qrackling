% Author: Brandon Reade
% Date: 19/04/2026
% Updated: 01/07/2026 
% % 3D plot of orbit pass metric vs angles.

function [ax, h] = plotOrbitSurface(Result, options)
% Options:
%   Mask        : "Elevation" | "Communication" | "Line of sight" | "None"
%   Metric      : "skr" | "sifted" | "qber" | "total_loss_db" | "loss:<name>"
%                where <name> in {"geometric","optical","apt","turbulence","atmospheric"}
%   XAxis       : "heading"
%   YAxis       : "zenith" | "elevation"
%   PlotType    : "scatter" | "trisurf"
%   UseLogZ     : true/false (for rates)
%   Title       : string
%   ColorBy     : "z" | "time" | "none"
%   Axes        : existing axes handle to plot into (optional)
%   PointSize   : scatter marker size

arguments
    Result (1,1) nodes.PassSimulationResult
    options.Mask (1,1) string {mustBeMember(options.Mask, ["Elevation","Communication","Line of sight","None"])} = "Elevation"
    options.Metric (1,1) string = "skr"
    options.XAxis (1,1) string {mustBeMember(options.XAxis, ["heading"])} = "heading"
    options.YAxis (1,1) string {mustBeMember(options.YAxis, ["zenith","elevation"])} = "zenith"
    options.PlotType (1,1) string {mustBeMember(options.PlotType, ["scatter","trisurf"])} = "scatter"
    options.UseLogZ (1,1) logical = false
    options.Title (1,1) string = ""
    options.ColorBy (1,1) string {mustBeMember(options.ColorBy, ["z","time","none"])} = "z"
    options.Axes = []
    options.PointSize (1,1) double = 18
end

mask = localMask(Result, options.Mask);
if ~any(mask)
    warning("Selected mask contains no points.");
    ax = [];
    h = [];
    return
end

% X (heading/azimuthal)
switch options.XAxis
    case "heading"
        x = Result.heading(mask);
        xlab = "Heading / Azimuth (deg)";
end

% Y (elevation or zenith)
switch options.YAxis
    case "elevation"
        y = Result.elevation(mask);
        ylab = "Elevation (deg)";
    case "zenith"
        y = 90 - Result.elevation(mask);
        ylab = "Zenith (deg)";
end

% Z metric (e.g. atmospheric loss)
[z, zlab, cLabel] = localMetric(Result, options.Metric, mask);

% Ensure column vectors for delaunay/trisurf consistency
x = x(:); y = y(:); z = z(:);

if options.UseLogZ
    zPlot = z;
    zPlot(zPlot <= 0) = NaN;
else
    zPlot = z;
end

% Axes
if isempty(options.Axes)
    ax = axes;
else
    ax = options.Axes;
end

hold(ax, "on");
grid(ax, "on");
view(ax, 3);

% Plot
switch options.PlotType
    case "scatter"
        switch options.ColorBy
            case "z"
                c = zPlot;
            case "time"
                t = Result.time(mask);
                t0 = t(1);
                c = seconds(t - t0);
            case "none"
                c = [];
        end

        if isempty(c)
            h = scatter3(ax, x, y, zPlot, options.PointSize, "filled");
        else
            h = scatter3(ax, x, y, zPlot, options.PointSize, c(:), "filled");
            cb = colorbar(ax);
            cb.Label.String = cLabel;
        end

    case "trisurf"
        % surface from scattered points
        tri = delaunay(x,y);
        h = trisurf(tri,x,y,zPlot,...
            "Parent",ax,...
            "EdgeColor","none");
        
        h.CData = zPlot;
        h.FaceColor = "interp";
        
        cb = colorbar(ax);
        cb.Label.String = cLabel;
end

xlabel(ax, xlab);
ylabel(ax, ylab);
zlabel(ax, zlab);

if options.UseLogZ
    set(ax,"ZScale","log")
end

if options.Title ~= ""
    title(ax, options.Title);
elseif options.Metric ~= ""
    title(ax, "Orbit surface: " + options.Metric);
end

end

%% Functions
function mask = localMask(R, mode)
switch mode
    case "Elevation"
        mask = R.elevation_mask;
    case "Communication"
        mask = ~(isnan(R.secret_key_rate) | (R.secret_key_rate <= 0));
    case "Line of sight"
        mask = R.elevation > 0;
    case "None"
        mask = true(size(R.elevation));
end
mask = logical(mask(:));
end

function [z, zlab, cLabel] = localMetric(R, metric, mask)
    m = lower(string(metric));
    
    if m == "skr"
        z = R.secret_key_rate(mask);
        zlab = "Secret key rate (bps)";
        cLabel = "Secret key rate (bps)";
        return
    elseif m == "sifted"
        z = R.sifted_key_rate(mask);
        zlab = "Sifted key rate (bps)";
        cLabel = "Sifted key rate (bps)";
        return
    elseif m == "qber"
        z = 100*R.qber(mask);
        zlab = "QBER (%)";
        cLabel = "QBER (%)";
        return
    elseif m == "total_loss_db"
        lossObj = R.loss.total_loss;                                        % nodes.LossResult method giving units.Loss
        lossDb = localLossToDbArray(lossObj);                               % numeric array
        z = lossDb(mask);
        zlab = "Total loss (dB)";
        cLabel = "Total loss (dB)";
        return
    elseif startsWith(m,"loss:")
        name = lower(extractAfter(m,"loss:"));
        try
            lossObj = R.loss.get(char(name));
            lossObj = lossObj{1};
        catch
            error("Unknown loss component '%s'.",name);
        end
            
            lossDb = localLossToDbArray(lossObj);
    
        z = lossDb(mask);
    
        zlab = name + " loss (dB)";
        cLabel = zlab;
    
        return
    else
        error("Unknown Metric '%s'.", metric);
    end
end

function lossDb = localLossToDbArray(lossObj)
    % Convert units.Loss to numeric dB array regardless of whether dB is a property or a method.
    try
        lossDb = lossObj.dB;
    catch
        % alternate pattern as a method
        lossDb = lossObj.dB();
    end
end