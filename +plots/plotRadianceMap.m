function plotRadianceMap(Env, wavelength_nm, options)
% Plot a 3D surface 'map' of the spectral radiance vs azimuth/zenith
% modes:
%   - "surf": 3D surface
%   - "bars": vertical bars
% to do:
%   - comparisons?
%   - options for bars instead of geometric polys
%   - option for circular plane with bars (origin with vectors magnitude
%   showing the radiance values)

    arguments
        Env
        wavelength_nm (1,1) double
        options.AzimuthDeg (:,1) double = (0:5:355)'
        options.ZenithDeg  (:,1) double = (0:5:90)'
        options.Title (1,1) string = ""
        options.UseLogZ (1,1) logical = false
        options.Mode (1,1) string {mustBeMember(options.Mode, ["surf", "bars"])} = "surf"
        options.BarLineWidth (1,1) double = 2
    end

    az = options.AzimuthDeg(:);
    zen = options.ZenithDeg(:);

    [AZ, ZEN] = meshgrid(az, zen);
    EL = 90 - ZEN;

    % Env.Interp expects arrays of headings and elevations (same shape)
    R = Env.Interp("spectral_radiance", AZ, EL, wavelength_nm);

    if options.UseLogZ
        Zplot = log10(max(R, eps));
        zLabel = "log10 Spectral radiance (W m^{-2} sr^{-1} nm^{-1})";
    else
        Zplot = R;
        zLabel = "Spectral radiance (W m^{-2} sr^{-1} nm^{-1})";
    end

    figure('Name', sprintf('Radiance map %dnm', round(wavelength_nm)));
    ax = axes();
    hold(ax, "on");

    switch options.Mode
        case "surf"
            surf(ax, AZ, ZEN, Zplot, 'EdgeColor', 'none');

        case "bars" % block bars
            % Define cell edges from center samples
            azc = az(:)';              % 1 x nAz
            zenc = zen(:);             % nZen x 1
            nAz = numel(azc);
            nZen = numel(zenc);

            % Compute edges so blocks fill between datapoints
            az_edges = localEdges(azc);
            zen_edges = localEdges(zenc');

            % Patch settings
            cmap = turbo(256);
            colormap(ax, cmap);

            zmin = min(Zplot(:), [], 'omitnan');
            zmax = max(Zplot(:), [], 'omitnan');
            if ~isfinite(zmin) || ~isfinite(zmax) || zmin == zmax
                zmin = 0; zmax = zmin + 1;
            end

            % For each cell, draw a rectangular prism from z=0 to z=Z
            for iz = 1:nZen
                for ia = 1:nAz
                    zval = Zplot(iz, ia);
                    if ~isfinite(zval)
                        continue;
                    end

                    x0 = az_edges(ia);   x1 = az_edges(ia+1);
                    y0 = zen_edges(iz);  y1 = zen_edges(iz+1);
                    z0 = 0;              z1 = zval;

                    % Color index based on height
                    ci = 1 + round(255 * (zval - zmin) / (zmax - zmin));
                    ci = max(1, min(256, ci));
                    faceColor = cmap(ci, :);

                    % Draw top face
                    % Top quad vertices:
                    X = [x0 x1 x1 x0];
                    Y = [y0 y0 y1 y1];
                    Z = [z1 z1 z1 z1];

                    patch(ax, X, Y, Z, faceColor, ...
                        'EdgeColor', 'none', ...
                        'FaceAlpha', 1.0);

                    % add sides for a true 3D block feel
                    localAddSides(ax, x0,x1,y0,y1,z0,z1, faceColor);
                end
            end

            % helpful axis limits
            xlim(ax, [az_edges(1) az_edges(end)]);
            ylim(ax, [zen_edges(1) zen_edges(end)]);
    end

    xlabel(ax, 'Azimuth (deg)');
    ylabel(ax, 'Zenith (deg)');
    zlabel(ax, zLabel);
    colorbar(ax);
    grid(ax, 'on');
    view(ax, 45, 35);

    if options.Title ~= ""
        title(ax, options.Title);
    else
        title(ax, sprintf('Spectral radiance at %dnm', round(wavelength_nm)));
    end

    hold(ax, "off");
end

function edges = localEdges(centers)
    % centers: 1 x N increasing (ideally)
    centers = centers(:)';
    N = numel(centers);
    if N == 1
        edges = [centers(1)-0.5, centers(1)+0.5];
        return;
    end
    mids = (centers(1:end-1) + centers(2:end)) / 2;
    first = centers(1) - (mids(1) - centers(1));
    last  = centers(end) + (centers(end) - mids(end));
    edges = [first, mids, last];
end

function localAddSides(ax, x0,x1,y0,y1,z0,z1, faceColor)
    % Draw 4 side faces for a rectangular prism.
    % x: azimuth edges, y: zenith edges, z: [0..height]

    sideColor = 0.85 * faceColor; % slightly darker sides

    % +x face
    patch(ax, [x1 x1 x1 x1], [y0 y1 y1 y0], [z0 z0 z1 z1], sideColor, 'EdgeColor','none');
    % -x face
    patch(ax, [x0 x0 x0 x0], [y0 y0 y1 y1], [z0 z1 z1 z0], sideColor, 'EdgeColor','none');
    % +y face
    patch(ax, [x0 x1 x1 x0], [y1 y1 y1 y1], [z0 z0 z1 z1], sideColor, 'EdgeColor','none');
    % -y face
    patch(ax, [x0 x1 x1 x0], [y0 y0 y0 y0], [z0 z1 z1 z0], sideColor, 'EdgeColor','none');
end