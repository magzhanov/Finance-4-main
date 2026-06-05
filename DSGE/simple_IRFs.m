%% simple_IRFs.m
% This script produces 6 figures and saves them as PNG (300 dpi) into
%   ./images  (created automatically next to this .m file).
%
% Core figures:
%   (1) No-lag model IRF: RE vs DE (DE differs only at impact).
%   (2) Lagged-x model IRF (phi>0): RE vs DE (DE persists via x_{t-1}).
%   (3) Paper Fig 2(a) (drop h=0): Actual IRF vs DE forecast, phi=0, h=1..T.
%   (4) Paper Fig 2(b) (drop h=0): TRUE DE IRF vs DE forecast, phi=0.15, h=1..T.
%
% New “hairy” figures (forecast trajectories evolve over time):
%   (5) Hairy plot (no-lag): realized x_t + DE forecast trajectories of length H=12,
%       formed at multiple forecast origins t=0..12.
%   (6) Hairy plot (lagged-x): realized x_t + DE forecast trajectories (H=12),
%       formed at multiple origins t=0..12, with RE forecasts iterated forward.
%
% Models:
%   y_t = rho y_{t-1} + eps_t, with a single shock eps_0 = 1 and eps_t=0 for t>=1.
%
%   No-lag:     x_t = beta * E_t^θ[x_{t+1}] + y_t
%   Lagged-x:   x_t = beta * E_t^θ[x_{t+1}] + phi * x_{t-1} + y_t
%
% Diagnostic expectations operator:
%   E_t^θ[z] = (1+θ) E_t[z] - θ E_{t-1}[z]
% -------------------------------------------------------------------------

clear; clc; close all;

%% -------------------- Robust output folder (next to this script) --------------------
thisFile = mfilename('fullpath');        % full path to this .m (no extension)
[thisDir,~,~] = fileparts(thisFile);     % folder containing the script
outdir = fullfile(thisDir,'images');     % images/ folder next to script
if ~exist(outdir,'dir'); mkdir(outdir); end

%% -------------------- Global plot settings --------------------
set(groot,'defaultTextInterpreter','latex');
set(groot,'defaultAxesTickLabelInterpreter','latex');
set(groot,'defaultLegendInterpreter','latex');

%% -------------------- Parameters --------------------
beta  = 0.99;
rho   = 0.50;
theta = 0.75;

T     = 20;      % IRF horizon (standard figures)
phi   = 0.15;    % lag coefficient in lagged-x model
H     = 12;      % forecast horizon length in hairy plots
Tsim  = 24;      % length of realized simulation for hairy plots
origins = 0:12;  % forecast origins for hairy plots

%% ======================================================================
%% (1) No-lag model: IRF RE vs DE (impact-only bump)
% Build y_t path (t=0..T)
y = zeros(T+1,1);
y(1) = 1;                         % y_0 = 1 (shock eps_0=1), y_-1 = 0
for t = 2:T+1
    y(t) = rho * y(t-1);
end

% Closed-form coefficients (your derivation)
a0 = 1/(1 - beta*rho);
b0 = beta*theta*rho/(1 - beta*rho);

% IRFs
xRE0 = a0 * y;
xDE0 = a0 * y;
xDE0(1) = xDE0(1) + b0;           % diagnostic bump at impact only

h = 0:T;
fig = figure('Name','(1) No-lag IRF: RE vs DE','NumberTitle','off','Position',[100 100 760 440]);
plot(h, xRE0, '-o', 'LineWidth', 1.6, 'MarkerSize', 6); hold on;
plot(h, xDE0, '-s', 'LineWidth', 1.6, 'MarkerSize', 6);
grid on; xlabel('Periods $t$');
title(['No-lag IRF after $\varepsilon_0=1$: RE vs DE. ', ...
       'DE differs only at impact ($t=0$).']);
legend('RE','DE','Location','best');
print(fig, fullfile(outdir,'Keep1_NoLag_IRF_RE_vs_DE.png'), '-dpng','-r300');

%% ======================================================================
%% (2) Lagged-x model: IRF RE vs DE (phi>0)
% Solve for stable root c from beta*c^2 - c + phi = 0
D  = 1 - 4*beta*phi;
c  = (1 - sqrt(D)) / (2*beta);     % stable root |c|<1

% Common coefficient a for lagged recursion
a1 = 1 / (1 - beta*rho - beta*c);

% DE impact jump (your expression)
b1 = beta * theta * a1 * (rho + c) / (1 - beta*c*(1+theta));

% Simulate IRFs (t=0..T), one-time shock eps_0=1
y1 = zeros(T+1,1); y1(1)=1;
xRE1 = zeros(T+1,1);
xDE1 = zeros(T+1,1);

xRE1(1) = a1*y1(1);               % RE: no jump at impact
xDE1(1) = a1*y1(1) + b1;          % DE: jump at impact

for t = 2:T+1
    y1(t)   = rho*y1(t-1);
    xRE1(t) = a1*y1(t) + c*xRE1(t-1);
    xDE1(t) = a1*y1(t) + c*xDE1(t-1);
end

fig = figure('Name','(2) Lagged-x IRF: RE vs DE','NumberTitle','off','Position',[100 100 760 440]);
plot(h, xRE1, '-o', 'LineWidth', 1.6, 'MarkerSize', 6); hold on;
plot(h, xDE1, '-s', 'LineWidth', 1.6, 'MarkerSize', 6);
grid on; xlabel('Periods $t$');
title(['Lagged-$x$ IRF after $\varepsilon_0=1$ ($\phi=0.15$): RE vs DE. ', ...
       'DE persists via $x_{t-1}$.']);
legend('RE','DE','Location','best');
print(fig, fullfile(outdir,'Keep2_LaggedX_IRF_RE_vs_DE_phi015.png'), '-dpng','-r300');

%% ======================================================================
%% (3) Paper Fig 2(a) (drop h=0): Actual IRF vs DE forecast, phi=0, h=1..T
h1 = 1:T;
trueIRF_a = a0 .* rho.^h1;                 % realized path (h>=1)
expDE_a   = (1+theta) .* trueIRF_a;        % E_0^θ[x_h] in no-lag case

fig = figure('Name','(3) Paper Fig 2(a): drop h=0','NumberTitle','off','Position',[100 100 760 440]);
plot(h1, trueIRF_a, '-o', 'LineWidth', 1.6, 'MarkerSize', 6); hold on;
plot(h1, expDE_a,   '-s', 'LineWidth', 1.6, 'MarkerSize', 6);
grid on; xlabel('Horizon $h$');
title(['Paper Fig 2(a) (no-lag, $\phi=0$): realized $x_h$ vs DE forecast $E_0^\theta[x_h]$, $h\ge1$.']);
legend('Actual IRF','DE forecast','Location','best');
print(fig, fullfile(outdir,'Keep6_PaperFig2a_drop_h0.png'), '-dpng','-r300');

%% ======================================================================
%% (4) Paper Fig 2(b) (drop h=0): TRUE DE IRF vs DE forecast, phi=0.15, h=1..T
% TRUE realized DE path for horizons h=1..T is xDE1(2..T+1)
x_true_b = xDE1(2:end);

% DE forecast at t=0 computed STATE-CONDITIONALLY on realized (y0, x0).
% This makes it coincide with the first forecast trajectory in the lagged hairy plot.
Et0   = RE_forecast_path(y1(1), xDE1(1), T, rho, a1, c);   % E_0[x_1..x_T] given realized x_0 (with bump)
Etm10 = RE_forecast_path(0,     0,      T, rho, a1, c);   % E_-1[x_1..x_T] under baseline (y_-1=x_-1=0)

expDE_b = (1+theta)*Et0 - theta*Etm10;                    % E_0^θ[x_1..x_T]

fig = figure('Name','(4) Paper Fig 2(b): drop h=0 (state-conditional)','NumberTitle','off','Position',[100 100 760 440]);
plot(h1, x_true_b, '-o', 'LineWidth', 1.6, 'MarkerSize', 6); hold on;
plot(h1, expDE_b,  '-s', 'LineWidth', 1.6, 'MarkerSize', 6);
grid on; xlabel('Horizon $h$');
title(['Paper Fig 2(b) ($\phi=0.15$): TRUE realized DE path vs DE forecast $E_0^\theta[x_h]$, $h\ge1$ ', ...
       '(forecast is state-conditional on realized $x_0$).']);
legend('Actual (TRUE DE IRF)','DE forecast','Location','best');
print(fig, fullfile(outdir,'Keep7_PaperFig2b_drop_h0_stateconditional.png'), '-dpng','-r300');

%% ======================================================================
%% (5) Hairy plot (NO-LAG): realized path (BLACK) + evolving DE forecasts (length H)
% Simulate realized path under DE after a one-time shock eps_0=1.
% No-lag realized dynamics: x_0 has the bump; for t>=1, x_t = a0 y_t.

% simulate y_t to Tsim
y_sim0 = zeros(Tsim+1,1); y_sim0(1)=1;
for t=2:Tsim+1
    y_sim0(t)=rho*y_sim0(t-1);
end

x_sim0 = zeros(Tsim+1,1);
x_sim0(1)=a0*y_sim0(1)+b0;   % realized DE impact
for t=2:Tsim+1
    x_sim0(t)=a0*y_sim0(t);  % thereafter
end

fig = figure('Name','(5) Hairy DE forecasts (no-lag)','NumberTitle','off','Position',[100 100 860 480]);
hold on; grid on;

% Actual realized path (BLACK, thick)
plot(0:Tsim, x_sim0, 'k', 'LineWidth', 2.4);

% Forecast trajectories formed at each origin t0
for t0 = origins
    y_t  = y_sim0(t0+1);
    if t0==0
        y_tm1 = 0;           % y_{-1}=0
    else
        y_tm1 = y_sim0(t0);
    end

    k = (1:H)';
    Et   = a0 * (rho.^k) * y_t;      % RE forecast from t0
    Etm1 = a0 * (rho.^k) * y_tm1;    % RE forecast from t0-1

    DEfc = (1+theta)*Et - theta*Etm1;

    tt = t0 + (0:H);
    xx = [x_sim0(t0+1); DEfc];       % anchor at realized x_t
    plot(tt, xx, 'LineWidth', 1.0);
end

xlabel('Calendar time $t$');
title(['Hairy plot (no-lag): realized $x_t$ (black) and evolving DE forecast trajectories, ', ...
       'length $H=12$, after $\varepsilon_0=1$.']);
legend('Actual realized path','DE forecast trajectories','Location','best');
print(fig, fullfile(outdir,'Hairy_NoLag_DEForecasts_H12.png'), '-dpng','-r300');

%% ======================================================================
%% (6) Hairy plot (LAGGED-x): realized path (BLACK) + evolving DE forecasts (length H)
% Realized DE path uses the lag recursion. Forecasts:
%  - Build RE forecast path from info at t (iterate forward with zero future shocks)
%  - Build RE forecast path from info at t-1
%  - Apply diagnostic operator: (1+θ)Et - θEt-1

% simulate realized y_t to Tsim
y_sim1 = zeros(Tsim+1,1); y_sim1(1)=1;
for t=2:Tsim+1
    y_sim1(t)=rho*y_sim1(t-1);
end

% simulate realized x_t under DE with lag
x_sim1 = zeros(Tsim+1,1);
x_sim1(1)=a1*y_sim1(1)+b1;               % DE impact
for t=2:Tsim+1
    x_sim1(t)=a1*y_sim1(t) + c*x_sim1(t-1);
end

fig = figure('Name','(6) Hairy DE forecasts (lagged-x)','NumberTitle','off','Position',[100 100 860 480]);
hold on; grid on;

% Actual realized path (BLACK, thick)
plot(0:Tsim, x_sim1, 'k', 'LineWidth', 2.4);

for t0 = origins
    y_t  = y_sim1(t0+1);
    x_t  = x_sim1(t0+1);

    if t0==0
        y_tm1 = 0;  x_tm1 = 0;           % baseline for t=-1
    else
        y_tm1 = y_sim1(t0);
        x_tm1 = x_sim1(t0);
    end

    Et   = RE_forecast_path(y_t , x_t , H, rho, a1, c);    % E_t[x_{t+1..t+H}]
    Etm1 = RE_forecast_path(y_tm1, x_tm1, H, rho, a1, c);  % E_{t-1}[x_{t+1..t+H}]

    DEfc = (1+theta)*Et - theta*Etm1;

    tt = t0 + (0:H);
    xx = [x_sim1(t0+1); DEfc];
    plot(tt, xx, 'LineWidth', 1.0);
end

xlabel('Calendar time $t$');
title(['Hairy plot (lagged-$x$, $\phi=0.15$): realized $x_t$ (black) and evolving DE forecast trajectories, ', ...
       'length $H=12$, after $\varepsilon_0=1$.']);
legend('Actual realized path','DE forecast trajectories','Location','best');
print(fig, fullfile(outdir,'Hairy_LaggedX_DEForecasts_H12_phi015.png'), '-dpng','-r300');

%% ======================================================================
%% Local function: RE forecast path under lagged recursion with zero future shocks
function xh = RE_forecast_path(y_t, x_t, H, rho, a, c)
% Returns xh (length H): [E_t x_{t+1}, ..., E_t x_{t+H}] under RE recursion.
% States evolve deterministically with no future shocks:
%   y_{t+k|t} = rho^k y_t
%   x_{t+k|t} = a y_{t+k|t} + c x_{t+k-1|t}
    xh = zeros(H,1);
    y  = y_t;
    x  = x_t;
    for k = 1:H
        y = rho*y;
        x = a*y + c*x;
        xh(k) = x;
    end
end