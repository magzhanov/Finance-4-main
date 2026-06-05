%% simple_RE_paper_notation.m
% Dynare vs Analytical IRFs (RE NK model)
% Shocks: technology (a), cost-push (u), monetary policy (v)
%
% Paper notation:
%   x_t = (a_t, u_t, v_t)'  ,   x_t = A x_{t-1} + B eps_t
%   z_t = (pi_t, i_t, ygap_t, y_t)' = Q x_t
%   y_t = ygap_t + y^n_t,   y^n_t = lambda * a_t
%   r^n_t = chi * a_t, chi = -sigma*lambda*(1-rho_a)

clear; clc; close all;

%% -------------------- Activate Dynare --------------------
dynarePath = 'C:\dynare\4.5.7\matlab';
addpath(dynarePath);

%% -------------------- Plot defaults --------------------
set(groot, 'defaultTextInterpreter', 'latex');
set(groot, 'defaultAxesTickLabelInterpreter', 'latex');
set(groot, 'defaultLegendInterpreter', 'latex');

blueSolid  = {'LineWidth', 1.8};
orangeDash = {'LineWidth', 1.8, 'LineStyle', '--', 'Color', [0.8500 0.3250 0.0980]};

%% -------------------- Calibration (MUST MATCH .mod) --------------------
beta   = 0.99;
sigma  = 1.0;
varphi = 1.0;

kappa  = 0.10;

phi    = 1.50;
phi_x  = 0.50;

rho_a  = 0.90;
rho_u  = 0.60;
rho_v  = 0.50;

H         = 40;      % horizon
shockSize = 1;       % unit innovation
t         = 0:H;

%% -------------------- Flexible-price objects --------------------
lambda = (1 + varphi) / (sigma + varphi);          % y^n_t = lambda * a_t
chi    = -sigma * lambda * (1 - rho_a);            % r^n_t = chi * a_t

%% ======================================================================
% CLOSED-FORM COEFFICIENTS (as in LaTeX)
% We compute (alpha_a, beta_a, gamma_a), (alpha_u, beta_u, gamma_u),
% (alpha_v, beta_v, gamma_v), and then assemble Q.
% ======================================================================

%% -------------------- (A) TFP shock coefficients --------------------
% D_a(rho) = sigma(1-rho) + phi*phi_x + ((phi-rho)*kappa)/(1-beta*rho)
Da = sigma*(1 - rho_a) + phi*phi_x + (phi - rho_a) * kappa / (1 - beta*rho_a);

% From LaTeX:
% ygap_t = [ -sigma*lambda*(1-rho_a) / D_a(rho_a) ] a_t  := alpha_a a_t
% pi_t   = [ -(kappa/(1-beta*rho_a)) * sigma*lambda*(1-rho_a)/D_a ] a_t := beta_a a_t
% i_t    = [ -phi*(phi_x + kappa/(1-beta*rho_a)) * sigma*lambda*(1-rho_a)/D_a ] a_t := gamma_a a_t
alpha_a = (-sigma * lambda * (1 - rho_a)) / Da;
beta_a  = -(kappa/(1 - beta*rho_a)) * (sigma * lambda * (1 - rho_a)) / Da;
gamma_a = -phi * (phi_x + kappa/(1 - beta*rho_a)) * (sigma * lambda * (1 - rho_a)) / Da;

%% -------------------- (B) Cost-push shock coefficients --------------------
% H(rho)  = phi*phi_x + sigma(1-rho)
% D_u(rho)= kappa + ((1-beta*rho)*H(rho))/(phi-rho)
Hu = phi*phi_x + sigma*(1 - rho_u);
Du = kappa + ((1 - beta*rho_u) * Hu) / (phi - rho_u);

% From LaTeX:
% ygap_t = -(1/D_u(rho_u)) u_t := alpha_u u_t
% pi_t   = [H(rho_u)/(phi-rho_u)]*(1/D_u(rho_u)) u_t := beta_u u_t
% i_t    = phi*(H/(phi-rho_u) - phi_x)*(1/D_u) u_t := gamma_u u_t
alpha_u = -1 / Du;
beta_u  = (Hu/(phi - rho_u)) * (1 / Du);
gamma_u = phi * (Hu/(phi - rho_u) - phi_x) * (1 / Du);

%% -------------------- (C) Monetary policy shock coefficients --------------------
% D_v(rho)= kappa(rho-phi)/(1-beta*rho) - sigma(1-rho) - phi*phi_x
Dv = (kappa*(rho_v - phi))/(1 - beta*rho_v) ...
     - sigma*(1 - rho_v) ...
     - phi*phi_x;

% From LaTeX:
% ygap_t = (1/D_v(rho_v)) v_t := alpha_v v_t
% pi_t   = (kappa/(1-beta*rho_v))*(1/D_v) v_t := beta_v v_t
% i_t    = [1 + phi*(phi_x + kappa/(1-beta*rho_v))*(1/D_v)] v_t := gamma_v v_t
alpha_v = 1 / Dv;
beta_v  = (kappa/(1 - beta*rho_v)) * (1 / Dv);
gamma_v = 1 + phi * (phi_x + kappa/(1 - beta*rho_v)) * (1 / Dv);

%% ======================================================================
% STATE SPACE IN PAPER NOTATION
% x_t = A x_{t-1} + B eps_t,   z_t = Q x_t
% ======================================================================

A = diag([rho_a, rho_u, rho_v]);   % transition
B = eye(3);                        % impact of eps_t on x_t

% z_t = (pi_t, i_t, ygap_t, y_t)' and y_t = ygap_t + y^n_t, y^n_t=lambda a_t
Q = [ ...
    beta_a,          beta_u,          beta_v;           % pi_t
    gamma_a,         gamma_u,         gamma_v;          % i_t
    alpha_a,         alpha_u,         alpha_v;          % ygap_t
    alpha_a+lambda,  alpha_u,         alpha_v];         % y_t

fprintf('\n==================== ANALYTICAL STATE SPACE (PAPER NOTATION) ====================\n');
disp('A ='); disp(A);
disp('B ='); disp(B);
disp('Q ='); disp(Q);

%% ======================================================================
% ANALYTICAL IRFs
% Convention: at t=0, shock hits, so x_0 = B * e_j * shockSize
% and for h>=1: x_h = A x_{h-1}
% IRF_z(h) = Q x_h
% ======================================================================

ana = struct();

shockKeys   = {'eps_a','eps_u','eps_i'};  % Dynare shock names
shockTitles = { ...
    'TFP shock ($\varepsilon_t^{a}$)', ...
    'Cost-push shock ($\varepsilon_t^{u}$)', ...
    'Monetary policy shock ($\varepsilon_t^{i}$)'};

for j = 1:3
    x = zeros(3, H+1);

    e = zeros(3,1); e(j) = shockSize;  % eps_0 = e_j
    x(:,1) = B * e;                    % x_0

    for h = 2:(H+1)
        x(:,h) = A * x(:,h-1);         % x_h = A x_{h-1}
    end

    z = Q * x;                         % z_h = Q x_h

    ana(j).pi   = z(1,:);
    ana(j).i    = z(2,:);
    ana(j).ygap = z(3,:);
    ana(j).y    = z(4,:);
end

%% -------------------- Run Dynare --------------------
dynare nk_tfp_3shocks.mod noclearall;

%% -------------------- Extract Dynare IRFs --------------------
dyn = struct();
vars = {'pi','i','ygap','y'};

for j = 1:3
    sk = shockKeys{j};
    for v = 1:numel(vars)
        vn = vars{v};
        field  = [vn '_' sk];                 % e.g. pi_eps_a
        series = oo_.irfs.(field);
        dyn(j).(vn) = series(1:(H+1))';       % row vector 0..H
    end
end

%% -------------------- Comparison plots --------------------
for j = 1:3
    figure('Name', ['Comparison: ' shockTitles{j}], 'Color', 'w');

    subplot(2,2,1);
    plot(t, ana(j).pi, blueSolid{:}); hold on;
    plot(t, dyn(j).pi, orangeDash{:}); grid on; hold off;
    title('Inflation ($\pi_t$)'); xlabel('$h$'); ylabel('dev');
    legend({'Analytical','Dynare'}, 'Location', 'best');

    subplot(2,2,2);
    plot(t, ana(j).i, blueSolid{:}); hold on;
    plot(t, dyn(j).i, orangeDash{:}); grid on; hold off;
    title('Nominal rate ($i_t$)'); xlabel('$h$'); ylabel('dev');
    legend({'Analytical','Dynare'}, 'Location', 'best');

    subplot(2,2,3);
    plot(t, ana(j).ygap, blueSolid{:}); hold on;
    plot(t, dyn(j).ygap, orangeDash{:}); grid on; hold off;
    title('Output gap ($\tilde y_t$)'); xlabel('$h$'); ylabel('dev');
    legend({'Analytical','Dynare'}, 'Location', 'best');

    subplot(2,2,4);
    plot(t, ana(j).y, blueSolid{:}); hold on;
    plot(t, dyn(j).y, orangeDash{:}); grid on; hold off;
    title('Output ($y_t=\tilde y_t+y_t^n$)'); xlabel('$h$'); ylabel('dev');
    legend({'Analytical','Dynare'}, 'Location', 'best');

    sgtitle(['Dynare vs Analytical: ' shockTitles{j}]);
end

%% -------------------- Max abs diffs --------------------
fprintf('\n==================== MAX ABS DIFF (Dynare - Analytical) ====================\n');
for j = 1:3
    fprintf('\nShock: %s\n', shockTitles{j});
    fprintf('  pi   : %.3e\n', max(abs(dyn(j).pi   - ana(j).pi')));
    fprintf('  i    : %.3e\n', max(abs(dyn(j).i    - ana(j).i')));
    fprintf('  ygap : %.3e\n', max(abs(dyn(j).ygap - ana(j).ygap')));
    fprintf('  y    : %.3e\n', max(abs(dyn(j).y    - ana(j).y')));
end

