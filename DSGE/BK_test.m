%% BK_test.m
% Manual block follows the notes:
%   A0 q_t = A1 E_t[q_{t+1}] + b_t,  q_t = (ygap_t, pi_t)'
%   T = A1^{-1} A0
% Determinacy (unique bounded REE) in this 2-jump-variable block:
%   both eig(T) must be outside unit circle <=> #unstable(T)=2
% and equivalently:
%   kappa*(phi_pi - 1) + (1-beta)*phi_y > 0,
% where phi_pi = phi, phi_y = phi*phi_x.

clear; clc; close all;

%% --- Dynare path (adjust if needed) ---
dynarePath = 'C:\dynare\4.5.7\matlab';
addpath(dynarePath);

modFile = 'nk_tfp_3shocks.mod';

%% --- Parameters (MUST match .mod) ---
beta  = 0.99;
sigma = 1.0;
kappa = 0.10;

phi   = 1.50;   % phi_pi
phi_x = 0.50;   % so phi_y = phi*phi_x

phi_pi = phi;
phi_y  = phi*phi_x;

tol = 1e-8;

%% =====================================================================
% (1) MANUAL TEST (from the notes)
% =====================================================================

A0 = [ 1 + phi_y/sigma,  phi_pi/sigma ;
      -kappa,            1           ];

A1 = [ 1,    1/sigma ;
       0,    beta    ];

T = A1 \ A0;                 % = inv(A1)*A0, but numerically better
eigT = eig(T);

n_unstable_T = sum(abs(eigT) > 1 + tol);
n_jump_manual = 2;           % q_t = (ygap, pi)' are both jump vars

det_ineq = kappa*(phi_pi - 1) + (1 - beta)*phi_y;

fprintf('\n================ MANUAL (NOTES) BK TEST: REDUCED NK BLOCK ================\n');
fprintf('det inequality: kappa*(phi_pi-1)+(1-beta)*phi_y = %.10f\n', det_ineq);

fprintf('eig(T):\n');
for i = 1:numel(eigT)
    fprintf('  %+.10f %+.10fi |abs|=%.10f\n', real(eigT(i)), imag(eigT(i)), abs(eigT(i)));
end
fprintf('unstable roots in T (|lambda|>1): %d (need %d for determinacy)\n', n_unstable_T, n_jump_manual);

if n_unstable_T == n_jump_manual && det_ineq > 0
    manual_status = 'DETERMINATE (unique bounded REE)';
elseif n_unstable_T < n_jump_manual
    manual_status = 'INDETERMINATE (multiple bounded REE / sunspots)';
else
    manual_status = 'NO BOUNDED REE / EXPLOSIVE';
end
fprintf('Manual verdict: %s\n', manual_status);

%% =====================================================================
% (2) DYNARE BUILT-IN BK TEST (typical "check")
% =====================================================================

fprintf('\n================ DYNARE RUN ================\n');
dynare(modFile, 'noclearall');

fprintf('\n================ DYNARE BUILT-IN CHECK(M_,options_,oo_) ================\n');
% This is the standard Dynare BK/eigenvalue diagnostic:
check(M_, options_, oo_);

%% =====================================================================
% (3) DYNARE ROOT COUNT (simple, explicit)
% =====================================================================

eigD = oo_.dr.eigval;
eigD = eigD(:);

qzcrit = options_.qz_criterium;
if isempty(qzcrit)
    qzcrit = 1 + 1e-6;   % Dynare typical default cutoff
end
qzcrit = qzcrit(1);      % force scalar

n_unstable_D = nnz(abs(eigD) > qzcrit);
n_fwrd       = M_.nfwrd;

fprintf('\nDynare root count: unstable=%d, nfwrd=%d (qzcrit=%.8f)\n', ...
    n_unstable_D, n_fwrd, qzcrit);

%% =====================================================================
% (4) BK REGION PLOTS: two Taylor-rule parameterizations
%   (A) Multiplicative:  i = phi*(pi + phi_x*ygap) + v
%       => phi_pi = phi,  phi_y = phi*phi_x
%       Determinacy: kappa*(phi-1) + (1-beta)*phi*phi_x > 0
%
%   (B) Additive:        i = phi_pi*pi + phi_x*ygap + v
%       => phi_pi free,  phi_y = phi_x
%       Determinacy: kappa*(phi_pi-1) + (1-beta)*phi_x > 0
% =====================================================================

fprintf('\n================ BK REGION PLOTS ================\n');

% ---- grid settings (adjust if you want) ----
N = 500;
phi_min = 0;  phi_max = 3;     % x-axis: phi (or phi_pi)
px_min  = 0; px_max  = 6;     % y-axis: phi_x

phi_grid = linspace(phi_min, phi_max, N);
px_grid  = linspace(px_min,  px_max,  N);
[PHI, PX] = meshgrid(phi_grid, px_grid);

% (A) Multiplicative rule: i = phi*(pi + phi_x*ygap)
D_mult = kappa*(PHI - 1) + (1 - beta).*(PHI.*PX);   % >0 => determinacy

% (B) Additive rule: i = phi_pi*pi + phi_x*ygap
D_add  = kappa*(PHI - 1) + (1 - beta).*PX;          % >0 => determinacy

% ---- baseline point (your calibration) ----
phi0  = phi;     % = 1.50
px0   = phi_x;   % = 0.50

figure('Color','w','Position',[120 120 1200 480]);

% --- Plot 1: (phi, phi_x) under multiplicative rule ---
subplot(1,2,1);

imagesc(phi_grid, px_grid, double(D_mult > 0));
set(gca,'YDir','normal'); hold on; grid on;
colormap(gca, [1 0 0; 0 0 1]);   % [red; blue] for values [0;1]
caxis([0 1]);

% Boundary: D_mult = 0 (keep on plot, remove from legend)
contour(PHI, PX, D_mult, [0 0], 'k', 'LineWidth', 2);

% Baseline point (no text label on plot)
hBase1 = plot(phi0, px0, 'wo', 'MarkerFaceColor','w', ...
    'MarkerEdgeColor','k', 'LineWidth', 1.5);

xlabel('$\phi$');
ylabel('$\phi_x$');
title('Determinacy region: multiplicative Taylor rule');
xlim([phi_min phi_max]); ylim([px_min px_max]);

% Legend (NO boundary entry)
hFail1 = plot(nan, nan, 's', 'MarkerFaceColor',[1 0 0], 'MarkerEdgeColor',[1 0 0]);
hOk1   = plot(nan, nan, 's', 'MarkerFaceColor',[0 0 1], 'MarkerEdgeColor',[0 0 1]);
legend([hFail1, hOk1, hBase1], ...
    {'BK fails (indeterminacy)', 'BK holds (determinacy)', 'baseline'}, ...
    'Location','best');

% --- Plot 2: (phi_pi, phi_x) under additive rule ---
subplot(1,2,2);

imagesc(phi_grid, px_grid, double(D_add > 0));
set(gca,'YDir','normal'); hold on; grid on;
colormap(gca, [1 0 0; 0 0 1]);
caxis([0 1]);

% Boundary: D_add = 0 (keep on plot, remove from legend)
contour(PHI, PX, D_add, [0 0], 'k', 'LineWidth', 2);

% Baseline point (no text label on plot)
hBase2 = plot(phi0, px0, 'wo', 'MarkerFaceColor','w', ...
    'MarkerEdgeColor','k', 'LineWidth', 1.5);

xlabel('$\phi_\pi$');
ylabel('$\phi_x$');
title('Determinacy region: additive Taylor rule');
xlim([phi_min phi_max]); ylim([px_min px_max]);

% Legend (NO boundary entry)
hFail2 = plot(nan, nan, 's', 'MarkerFaceColor',[1 0 0], 'MarkerEdgeColor',[1 0 0]);
hOk2   = plot(nan, nan, 's', 'MarkerFaceColor',[0 0 1], 'MarkerEdgeColor',[0 0 1]);
legend([hFail2, hOk2, hBase2], ...
    {'BK fails (indeterminacy)', 'BK holds (determinacy)', 'baseline'}, ...
    'Location','best');

