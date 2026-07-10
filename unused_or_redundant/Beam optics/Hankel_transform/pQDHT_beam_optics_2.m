% QDHT example: Gaussian beam truncated by circular aperture and propagated
% Based on:
% M. Guizar-Sicairos & J.C. Gutierrez-Vega, JOSA A 21, 53-58 (2004)
% DOI: 10.1364/JOSAA.21.000053

% Current problems:
%   - Always an Airy disk seen at receiver (shouldn't be true I don't
%   think), seems to get more Airy the bigger aperture - untrue???
%   - Spot size at receiver does't seem to change with aperture size, but
%   it should as divergence angle would change.
%   - should probably work out what's happening with c with the current
%   formula. Why doesnt it use the data file from Hankel_transform script?
%   - why is the cut-off at the spot size for the receiver?

% I think this is a nie start for the approach but nothing more.

%% =========================
% Physical parameters
%% =========================
lambda = 1550e-9;
k      = 2*pi/lambda;
z      = 500e3;          % 500 km

w0_tx  = 0.04;           % 1/e^2 intensity radius [m]
a_ap   = 0.1;           % aperture radius [m]

%% =========================
% QDHT parameters
%% =========================


ord = 0;
N   = 700;
R   = 0.35;

alpha = bessel_zeros(ord, N+1);
S = alpha(N+1);

r = alpha(1:N).' * R / S;            % Nx1
v = alpha(1:N).' / (2*pi*R);         % Nx1
V = S/(2*pi*R);

[an, am] = meshgrid(alpha(1:N), alpha(1:N));
C = (2/S) .* besselj(ord, (an.*am)/S) ./ ...                                % what is this????
    (abs(besselj(ord+1,an)).*abs(besselj(ord+1,am)));

m1 = (abs(besselj(ord+1,alpha(1:N))) / R).';   % Nx1
m2 = m1 * R / V;                                % Nx1

%% =========================
% Fields at TX plane
%% =========================
U_inc  = exp(-(r.^2)/(w0_tx^2));                                             % Gaussian amplitude
I_inc  = abs(U_inc).^2;

A      = double(r <= a_ap);
U_exit = U_inc .* A;
I_exit = abs(U_exit).^2;

%% =========================
% Propagation (QDHT, propagate, inverse QDHT)
%% =========================

% Force everything to column vectors
r      = r(:);
v      = v(:);
m1     = m1(:);
m2     = m2(:);
U_exit = U_exit(:);

% Build transform input
F_in = U_exit ./ m1;
F_in = F_in(:);

Fv = C * F_in;

Uexit_v = Fv .* m2;

kt = 2*pi*v;
kz = sqrt(complex(k^2 - kt.^2,0));
H  = exp(1i*kz*z);

Urx_v = Uexit_v .* H;

F_rx_v = Urx_v ./ m2;
F_rx_r = C * F_rx_v;
U_rx   = F_rx_r .* m1;
I_rx   = abs(U_rx).^2;

kt = 2*pi*v;
kz = sqrt(complex(k^2 - kt.^2, 0));
H  = exp(1i*kz*z);

Urx_v = Uexit_v .* H;       % Nx1

F_rx_v = Urx_v ./ m2;
F_rx_r = C * F_rx_v;
U_rx   = F_rx_r .* m1;
I_rx   = abs(U_rx).^2;

% force column vectors (robust)
r = r(:); I_inc = I_inc(:); I_exit = I_exit(:); I_rx = I_rx(:);

%% =========================
% Symmetric (-r,+r)  intensity profiles
%% =========================
r_sym      = [-flipud(r);      r];
I_inc_sym  = [ flipud(I_inc);  I_inc];
I_exit_sym = [ flipud(I_exit); I_exit];
I_rx_sym   = [ flipud(I_rx);   I_rx];

I_inc_sym_n  = I_inc_sym  / max(I_inc_sym);
I_exit_sym_n = I_exit_sym / max(I_exit_sym);
I_rx_sym_n   = I_rx_sym   / max(I_rx_sym);

%% =========================
% Figure 1: radial profiles
%% =========================
figure('Color','w');

subplot(1,3,1);
plot(r_sym, I_inc_sym_n, 'LineWidth',1.8); grid on;
xlabel('r [m]'); ylabel('Normalized intensity');
title('Incident spot (full \pm r)');
xline(-w0_tx,'--k','-w_0'); xline(+w0_tx,'--k','+w_0');
ylim([0 1.05]);

subplot(1,3,2);
plot(r_sym, I_exit_sym_n, 'LineWidth',1.8); grid on;
xlabel('r [m]'); ylabel('Normalized intensity');
title('Post-aperture spot (full \pm r)');
xline(-w0_tx,'--k','-w_0'); xline(+w0_tx,'--k','+w_0');
xline(-a_ap,'--r','-a_{ap}'); xline(+a_ap,'--r','+a_{ap}');
ylim([0 1.05]);

subplot(1,3,3);
plot(r_sym, I_rx_sym_n, 'LineWidth',1.8); grid on;
xlabel('r [m]'); ylabel('Normalized intensity');
title(sprintf('Receiver spot (%.0f km)', z/1e3));
ylim([0 1.05]);

sgtitle('Radial intensity profiles');

%% =========================
% Build 2D maps with auto-zoom
%% =========================
Np = 501;
thresh = 1e-3;

L_inc  = max(1.25*get_vis_radius(r,I_inc,thresh),  1.5*w0_tx);
L_exit = max(1.25*get_vis_radius(r,I_exit,thresh), 1.2*a_ap);
L_rx   = max(1.25*get_vis_radius(r,I_rx,thresh),   0.2);

% incident
x1 = linspace(-L_inc,L_inc,Np); [X1,Y1]=meshgrid(x1,x1); R1=sqrt(X1.^2+Y1.^2);
I1 = interp1(r,I_inc,R1,'pchip',0); I1(~isfinite(I1))=0; I1=I1/max(I1(:));

% exit
x2 = linspace(-L_exit,L_exit,Np); [X2,Y2]=meshgrid(x2,x2); R2=sqrt(X2.^2+Y2.^2);
I2 = interp1(r,I_exit,R2,'pchip',0); I2(~isfinite(I2))=0; I2=I2/max(I2(:));

% receiver
x3 = linspace(-L_rx,L_rx,Np); [X3,Y3]=meshgrid(x3,x3); R3=sqrt(X3.^2+Y3.^2);
I3 = interp1(r,I_rx,R3,'pchip',0); I3(~isfinite(I3))=0; I3=I3/max(I3(:));

%% Figure 2: linear scale images
figure('Color','w');
subplot(1,3,1); imagesc(x1,x1,I1); axis image xy; colormap hot; colorbar;
title('Incident (linear)'); xlabel('x [m]'); ylabel('y [m]');

subplot(1,3,2); imagesc(x2,x2,I2); axis image xy; colormap hot; colorbar;
title('Post-aperture (linear)'); xlabel('x [m]'); ylabel('y [m]');

subplot(1,3,3); imagesc(x3,x3,I3); axis image xy; colormap hot; colorbar;
title('Receiver (linear)'); xlabel('x [m]'); ylabel('y [m]');

%% Figure 3: log scale images (dB)
floor_dB = -60;
I1dB = 10*log10(max(I1,10^(floor_dB/10)));
I2dB = 10*log10(max(I2,10^(floor_dB/10)));
I3dB = 10*log10(max(I3,10^(floor_dB/10)));

figure('Color','w');
subplot(1,3,1); imagesc(x1,x1,I1dB,[floor_dB 0]); axis image xy; colormap turbo; colorbar;
title('Incident (log scale, dB)'); xlabel('x [m]'); ylabel('y [m]');

subplot(1,3,2); imagesc(x2,x2,I2dB,[floor_dB 0]); axis image xy; colormap turbo; colorbar;
title('Post-aperture (log scale, dB)'); xlabel('x [m]'); ylabel('y [m]');

subplot(1,3,3); imagesc(x3,x3,I3dB,[floor_dB 0]); axis image xy; colormap turbo; colorbar;
title('Receiver (log scale, dB)'); xlabel('x [m]'); ylabel('y [m]');

%% =========================
% Helpers
%% =========================
function z = bessel_zeros(nu, M)
z = zeros(M,1);
f = @(x) besselj(nu,x);
for m = 1:M
    x0 = (m + nu/2 - 1/4)*pi;
    a = x0 - pi/4; b = x0 + pi/4;
    it = 0;
    while f(a)*f(b) > 0 && it < 30
        a = a - pi/8; b = b + pi/8; it = it + 1;
    end
    z(m) = fzero(f,[a b]);
end
end

function rv = get_vis_radius(r, I, thresh)
In = I / max(I);
idx = find(In >= thresh, 1, 'last');
if isempty(idx), rv = max(r); else, rv = r(idx); end
end