%% optimal_policy.m
% Analytical optimal policy in simple NK under RE:
%  - Ramsey (commitment) using target criterion:  pi_t = -(lambda/kappa)(x_t-x_{t-1})
%  - Optimal discretion:                          pi_t = -(lambda/kappa)x_t
%
% Shock:
%   u_t = rho_u u_{t-1} + eps_u,t,  Var(eps_u)=sigma_u^2
%
% Outputs:
%   - Closed-form coefficients (Ramsey: a,b; Discretion: varphi)
%   - IRFs to a unit cost-push innovation (pi_t and x_t)
%   - Welfare under two notions:
%       (i)  invariant (stationary) metric:   L_infty = Var(pi)+lambda Var(x)
%       (ii) discounted-from-SS metric:       J0 = E0 sum beta^t * 0.5(pi^2+lambda x^2)
%            normalized to be comparable:     L_J = 2(1-beta) J0
%     Note: L_J = L_infty only if initialized at invariant distribution.
%           From steady-state initialization, transient dynamics create a wedge.
%
%   - Residual diagnostics (should be ~ machine precision).

clear; clc; close all;

%% -------------------- Plot defaults (LaTeX) --------------------
set(groot,'defaultTextInterpreter','latex');
set(groot,'defaultAxesTickLabelInterpreter','latex');
set(groot,'defaultLegendInterpreter','latex');

%% -------------------- Calibration --------------------
beta    = 0.99;
kappa   = 0.10;

lambda  = 0.50;    % welfare weight on x_t^2 (lambda>0)

rho_u   = 0.60;    % persistence of cost-push shock
sigma_u = 1.0;     % std dev of eps_u (IRFs use eps_u,0=1 anyway)

H       = 40;      % IRF horizon (0..H)
tol     = 1e-10;

%% =====================================================================
% (1) DISCRETION
% Target: pi_t = -(lambda/kappa) x_t
% Guess:  x_t = varphi u_t
% varphi = 1 / ( beta*(lambda/kappa)*rho_u - (lambda/kappa + kappa) )
% =====================================================================

varphi = 1 / ( beta*(lambda/kappa)*rho_u - (lambda/kappa + kappa) );

%% =====================================================================
% (2) RAMSEY (COMMITMENT)
% Target: pi_t = -(lambda/kappa)(x_t - x_{t-1})
% Conjecture: x_t = a x_{t-1} + b u_t,  |a|<1
%
% Root equation: beta a^2 - (1+beta+kappa^2/lambda)a + 1 = 0
% b = (kappa/lambda) / ( beta(a+rho_u) - (1+beta+kappa^2/lambda) )
% =====================================================================

Aq = beta;
Bq = -(1 + beta + (kappa^2)/lambda);
Cq = 1;

roots_a = roots([Aq Bq Cq]);           % two roots

% pick stable root |a|<1 (clean + correct)
stable_roots = roots_a(abs(roots_a) < 1 - 1e-12);
if isempty(stable_roots)
    % fallback (should not happen for standard calib)
    [~, stable_idx] = min(abs(roots_a));
    a = roots_a(stable_idx);
else
    a = stable_roots(1);
end

b = (kappa/lambda) / ( beta*(a + rho_u) - (1 + beta + (kappa^2)/lambda) );

%% =====================================================================
% (3) INVARIANT (STATIONARY) SECOND MOMENTS + "VARIANCE WELFARE" L_infty
% L_infty = Var(pi) + lambda Var(x)   (under invariant distribution)
%
% Let s = Var(u_t) = sigma_u^2/(1-rho_u^2)
%
% Discretion:
%   Var(x)=varphi^2 s, Var(pi)=(lambda/kappa)^2 Var(x)
%
% Ramsey:
%   v = Var(x_t)     = b^2 s (1+a rho_u)/((1-a^2)(1-a rho_u))
%   Var(Δx)=2((1-a)v - b^2 s rho_u/(1-a rho_u))
%   Var(pi)=(lambda/kappa)^2 Var(Δx)
% =====================================================================

s = sigma_u^2/(1 - rho_u^2);

% --- discretion moments ---
var_x_disc  = (varphi^2) * s;
var_pi_disc = (lambda/kappa)^2 * var_x_disc;
L_disc      = var_pi_disc + lambda*var_x_disc;

% --- Ramsey moments ---
v = (b^2*s*(1 + a*rho_u)) / ((1 - a^2)*(1 - a*rho_u));
var_dx     = 2*((1 - a)*v - (b^2*s*rho_u)/(1 - a*rho_u));
var_pi_ram = (lambda/kappa)^2 * var_dx;
L_ram      = var_pi_ram + lambda*v;

%% =====================================================================
% (4) IRFs to a unit cost-push innovation eps_u,0 = 1
% u_t: u_0=1, u_t=rho_u^t for t>=0 (given u_{-1}=0)
% Discretion: x_t=varphi u_t, pi_t=-(lambda/kappa)x_t
% Ramsey: x_t=a x_{t-1}+b u_t, pi_t=-(lambda/kappa)(x_t-x_{t-1})
% =====================================================================

tgrid = 0:H;
u_irf = rho_u.^tgrid;                 % since eps_u,0=1 and u_{-1}=0

% --- discretion IRFs ---
x_disc  = varphi * u_irf;
pi_disc = -(lambda/kappa) * x_disc;

% --- Ramsey IRFs ---
x_ram  = zeros(1,H+1);
pi_ram = zeros(1,H+1);

x_lag = 0;  % x_{-1}=0 (steady-state / timeless init)
for h = 1:(H+1)
    x_ram(h)  = a*x_lag + b*u_irf(h);
    pi_ram(h) = -(lambda/kappa) * (x_ram(h) - x_lag);
    x_lag     = x_ram(h);
end

%% =====================================================================
% (5) Sanity checks (IRF path residuals should be ~0)
% Discretion NKPC residual:
%   res = pi_t - beta E_t pi_{t+1} - kappa x_t - u_t
% Ramsey residuals:
%   TC:  pi_t + (lambda/kappa)(x_t-x_{t-1}) = 0
%   x-dyn: beta E_t x_{t+1} - (1+beta+kappa^2/lambda)x_t + x_{t-1} = (kappa/lambda)u_t
% =====================================================================

% Expectations under AR(1): E_t u_{t+1} = rho_u u_t
u_lead = [u_irf(2:end), rho_u*u_irf(end)];

% --- discretion NKPC residual ---
pi_disc_lead = -(lambda/kappa) * (varphi * u_lead);
res_NKPC_disc = pi_disc - beta*pi_disc_lead - kappa*x_disc - u_irf;

% --- Ramsey TC residual ---
x_ram_lag = [0, x_ram(1:end-1)];
res_TC_ram = pi_ram + (lambda/kappa)*(x_ram - x_ram_lag);

% --- Ramsey x-dynamics residual using E_t x_{t+1} = a x_t + b E_t u_{t+1} ---
Ex_ram_lead = a*x_ram + b*(rho_u*u_irf);
res_xdyn_ram = beta*Ex_ram_lead - (1 + beta + (kappa^2)/lambda)*x_ram + x_ram_lag - (kappa/lambda)*u_irf;

%% =====================================================================
% (6) IRF plots (cost-push shock)
% =====================================================================

blueSolid = {'LineWidth', 2.0};
redDash   = {'LineWidth', 2.0, 'LineStyle', '--'};

figure('Color','w','Position',[120 120 1100 420]);

subplot(1,2,1);
plot(tgrid, pi_ram, blueSolid{:}); hold on;
plot(tgrid, pi_disc, redDash{:}); grid on; hold off;
xlabel('$h$'); ylabel('$\pi_t$');
title('IRF to cost-push shock: inflation');
legend({'Ramsey (commitment)','Discretion'}, 'Location','best');

subplot(1,2,2);
plot(tgrid, x_ram, blueSolid{:}); hold on;
plot(tgrid, x_disc, redDash{:}); grid on; hold off;
xlabel('$h$'); ylabel('$x_t$');
title('IRF to cost-push shock: output gap');
legend({'Ramsey (commitment)','Discretion'}, 'Location','best');

sgtitle('Analytical IRFs under optimal policy: cost-push shock ($\varepsilon^u_0=1$)');

%% =====================================================================
% (7) DISCOUNTED WELFARE FROM STEADY STATE (Monte Carlo) + NORMALIZATION
%
% Objective from notes:
%   J0 = E0 sum_{t>=0} beta^t * ell_t,  ell_t = 0.5(pi_t^2 + lambda x_t^2)
%
% Comparable normalization:
%   L_J = 2(1-beta) J0
%
% Interpretation:
%   - L_infty is the stationary/invariant metric Var(pi)+lambda Var(x).
%   - L_J is the discounted-from-steady-state objective put in "per-period"
%     units comparable to L_infty.
%   - They coincide only under invariant initialization. From deterministic
%     steady-state initialization, transient dynamics create a wedge.
% =====================================================================

rng(1);                 % reproducibility

Tsim = 5000;            % simulation length for discounted sum
Nsim = 5000;            % number of MC paths
burn = 1000;            % burn-in for ergodic L_infty estimate

betapow = beta.^(0:Tsim-1)';   % beta^t, t=0..Tsim-1

J_disc = zeros(Nsim,1);
J_ram  = zeros(Nsim,1);

Linf_disc_mc = zeros(Nsim,1);
Linf_ram_mc  = zeros(Nsim,1);

for n = 1:Nsim

    % ---- simulate u_t from steady state: u_{-1}=0 ----
    epsu  = sigma_u * randn(Tsim,1);
    u_sim = zeros(Tsim,1);
    for tt = 1:Tsim
        if tt == 1
            u_sim(tt) = epsu(tt);
        else
            u_sim(tt) = rho_u*u_sim(tt-1) + epsu(tt);
        end
    end

    % ===================== DISCRETION =====================
    xD  = varphi * u_sim;
    piD = -(lambda/kappa) * xD;

    ellD     = 0.5*(piD.^2 + lambda*(xD.^2));
    J_disc(n)= sum(betapow .* ellD);

    xDb  = xD(burn+1:end);
    piDb = piD(burn+1:end);
    Linf_disc_mc(n) = var(piDb,1) + lambda*var(xDb,1);

    % ===================== RAMSEY (COMMITMENT) =====================
    xR  = zeros(Tsim,1);
    piR = zeros(Tsim,1);

    x_lag = 0; % x_{-1}=0 initialization
    for tt = 1:Tsim
        xR(tt)  = a*x_lag + b*u_sim(tt);
        piR(tt) = -(lambda/kappa) * (xR(tt) - x_lag);
        x_lag   = xR(tt);
    end

    ellR    = 0.5*(piR.^2 + lambda*(xR.^2));
    J_ram(n)= sum(betapow .* ellR);

    xRb  = xR(burn+1:end);
    piRb = piR(burn+1:end);
    Linf_ram_mc(n) = var(piRb,1) + lambda*var(xRb,1);

end

J_disc_hat = mean(J_disc);
J_ram_hat  = mean(J_ram);

Linf_disc_hat = mean(Linf_disc_mc);
Linf_ram_hat  = mean(Linf_ram_mc);

% Normalized discounted welfare comparable to L_infty:
LJ_disc = 2*(1-beta)*J_disc_hat;
LJ_ram  = 2*(1-beta)*J_ram_hat;

%% =====================================================================
% (8) CLEAN SUMMARY OUTPUT (normalized & comparable)
% =====================================================================

% Gains (Discretion - Ramsey)
gain_Linf_abs = L_disc - L_ram;
gain_Linf_pct = 100*gain_Linf_abs / L_disc;

gain_LJ_abs   = LJ_disc - LJ_ram;
gain_LJ_pct   = 100*gain_LJ_abs / LJ_disc;

% Transient wedge from deterministic steady-state init:
% If invariant init:  L_J = L_infty.  Here wedge quantifies deviation.
wedge_disc = LJ_disc - L_disc;
wedge_ram  = LJ_ram  - L_ram;

fprintf('\n==================== RESULTS: OPTIMAL POLICY (RE) ====================\n');
fprintf('Parameters: beta=%.4f, kappa=%.4f, lambda=%.4f, rho_u=%.4f, sigma_u=%.4f\n', ...
    beta,kappa,lambda,rho_u,sigma_u);

fprintf('\nCoefficients:\n');
fprintf('  Discretion:  varphi = % .10f   (x_t = varphi u_t)\n', varphi);
fprintf('  Ramsey:      a      = % .10f,  b = % .10f   (x_t = a x_{t-1} + b u_t)\n', a, b);

fprintf('\nWelfare comparison (two comparable metrics):\n');
fprintf('  L_infty = Var(pi)+lambda Var(x)   (stationary/invariant)\n');
fprintf('  L_J     = 2(1-beta) J0            (discounted-from-SS, normalized)\n\n');

fprintf('  %-12s | %12s | %12s | %12s\n', 'Policy', 'L_infty', 'J0', 'L_J');
fprintf('  %-12s-+-%12s-+-%12s-+-%12s\n', repmat('-',1,12), repmat('-',1,12), repmat('-',1,12), repmat('-',1,12));
fprintf('  %-12s | %12.6f | %12.6f | %12.6f\n', 'Discretion', L_disc, J_disc_hat, LJ_disc);
fprintf('  %-12s | %12.6f | %12.6f | %12.6f\n', 'Ramsey',     L_ram,  J_ram_hat,  LJ_ram);

fprintf('\nCommitment gain (Discretion - Ramsey):\n');
fprintf('  Invariant metric:   ΔL_infty = %.6f   (%.2f%%)\n', gain_Linf_abs, gain_Linf_pct);
fprintf('  Discounted metric:  ΔL_J     = %.6f   (%.2f%%)\n', gain_LJ_abs,   gain_LJ_pct);

fprintf('\nTransient wedge from SS init (wedge = L_J - L_infty):\n');
fprintf('  Discretion:  %.6f\n', wedge_disc);
fprintf('  Ramsey:      %.6f\n', wedge_ram);

fprintf('\nMC ergodic check (L_infty):\n');
fprintf('  Discretion:  L_infty(anal)=%.6f,  L_infty(MC)=%.6f\n', L_disc, Linf_disc_hat);
fprintf('  Ramsey:      L_infty(anal)=%.6f,  L_infty(MC)=%.6f\n', L_ram,  Linf_ram_hat);

fprintf('\nResidual checks (machine precision):\n');
fprintf('  max|NKPC_disc|=%.2e,  max|TC_ram|=%.2e,  max|x-dyn_ram|=%.2e\n', ...
    max(abs(res_NKPC_disc)), max(abs(res_TC_ram)), max(abs(res_xdyn_ram)));
