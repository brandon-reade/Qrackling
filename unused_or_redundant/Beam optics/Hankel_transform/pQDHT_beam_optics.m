% QDHT example: Gaussian beam truncated by circular aperture and propagated
% Based on:
% M. Guizar-Sicairos & J.C. Gutierrez-Vega, JOSA A 21, 53-58 (2004)
% DOI: 10.1364/JOSAA.21.000053

clear; clc; close all;

%% -----------------------------
%  User parameters (physical)
%% -----------------------------
lambda = 1550e-9;      % wavelength [m] (e.g., 1550 nm comms laser)
k      = 2*pi/lambda;  % wave number [rad/m]

w0     = 0.04;         % Gaussian 1/e^2 intensity radius at transmitter [m]
a_ap   = 0.05;         % aperture radius [m] (hard circular stop)
z      = 500e3;        % propagation distance [m] (example: LEO-to-ground scale)

%% -----------------------------
%  QDHT grid parameters
%% -----------------------------
ord = 0;      % 0th-order Hankel (radially symmetric field)
N   = 600;    % number of radial samples
R   = 0.25;   % max sampled radius [m] in source plane (must exceed aperture)

% Bessel zeros alpha_n of J_ord
% Requires Symbolic/Optimization-free approach via fzero:
alpha = bessel_zeros(ord, N+1);      % alpha(1)...alpha(N+1)
alphaN1 = alpha(N+1);

% QDHT sample grids
r = alpha(1:N).' * R / alphaN1;      % radial points in source plane [m]
v = alpha(1:N).' / (2*pi*R);         % radial spatial frequency [cycles/m]
V = alphaN1/(2*pi*R);                % max sampled spatial frequency
S = alphaN1;                         % same as 2*pi*R*V in this formulation

%% -----------------------------
%  Build transform matrix C and scaling vectors m1, m2
%% -----------------------------
[an, am] = meshgrid(alpha(1:N), alpha(1:N));

C = (2/S) .* besselj(ord, (an.*am)/S) ./ ...
    (abs(besselj(ord+1, an)) .* abs(besselj(ord+1, am)));

m1 = (abs(besselj(ord+1, alpha(1:N))) / R).';   % prepare spatial field -> QDHT vector
m2 = m1 * R / V;                                 % prepare QDHT output -> physical spectrum

%% -----------------------------
%  Source field: Gaussian truncated by aperture
%% -----------------------------
% Field amplitude Gaussian: U(r,0) = exp(-(r^2/w0^2))
% (Intensity then is exp(-2 r^2 / w0^2), so w0 is 1/e^2 intensity radius)
U0 = exp(-(r.^2)/(w0^2));
A  = double(r <= a_ap);      % circular aperture
U0 = U0 .* A;

%% -----------------------------
%  Forward QDHT to get radial spectrum
%% -----------------------------
F_in = U0 ./ m1;             % prepare
Fv   = C .* F_in;             % transformed vector
U0_v = Fv .* m2;             % radial spatial spectrum sampled at v

%% -----------------------------
%  Propagation in spectral domain (angular spectrum in cylindrical symmetry)
%% -----------------------------
% Radial transverse wavenumber:
kt = 2*pi*v;                 % [rad/m]
kz = sqrt(complex(k^2 - kt.^2, 0));   % allow evanescent as complex

H = exp(1i * kz * z);        % transfer function over distance z

Uz_v = U0_v .* H;            % propagated spectrum

%% -----------------------------
%  Inverse QDHT back to spatial domain
%% -----------------------------
Fz_v  = Uz_v ./ m2;          % prepare for inverse
Fz_r  = C * Fz_v;            % inverse (same C for order 0 in this method)
Uz_r  = Fz_r .* m1;          % propagated field in radius

%% -----------------------------
%  Diagnostics
%% -----------------------------
I0 = abs(U0).^2;
Iz = abs(Uz_r).^2;

% Approximate energy-like check in polar coordinates: int |U|^2 2*pi*r dr
E0 = trapz(r, I0 .* 2*pi.*r);
Ez = trapz(r, Iz .* 2*pi.*r);

fprintf('Initial power (arb):   %.6e\n', E0);
fprintf('Propagated power (arb): %.6e\n', Ez);
fprintf('Relative change:        %.3e\n', (Ez-E0)/E0);

%% -----------------------------
%  Plots
%% -----------------------------
figure('Color','w');
subplot(2,2,1);
plot(r, abs(U0), 'LineWidth', 1.5); grid on;
xlabel('r [m]'); ylabel('|U_0(r)|');
title('Source amplitude (Gaussian × aperture)');

subplot(2,2,2);
plot(r, I0/max(I0), 'LineWidth', 1.5); grid on;
xlabel('r [m]'); ylabel('Normalized intensity');
title('Source intensity');

subplot(2,2,3);
plot(v, abs(U0_v), 'LineWidth', 1.5); grid on;
xlabel('v [cycles/m]'); ylabel('|U_0(v)|');
title('Radial spectrum magnitude');

subplot(2,2,4);
plot(r, Iz/max(Iz), 'r', 'LineWidth', 1.5); grid on;
xlabel('r [m]'); ylabel('Normalized intensity');
title(sprintf('Propagated intensity at z = %.1f km', z/1e3));

sgtitle('QDHT beam propagation (0th order)');

%% ==============================================================
%  Local function: first M zeros of J_nu(x)
%% ==============================================================
function z = bessel_zeros(nu, M)
    z = zeros(M,1);
    % asymptotic initial guesses
    for m = 1:M
        x0 = (m + nu/2 - 1/4)*pi;
        % bracket near x0
        a = x0 - pi/4;
        b = x0 + pi/4;
        f = @(x) besselj(nu, x);
        % ensure sign change by expanding bracket if needed
        iter = 0;
        while f(a)*f(b) > 0 && iter < 20
            a = a - pi/8;
            b = b + pi/8;
            iter = iter + 1;
        end
        z(m) = fzero(f, [a b]);
    end
end