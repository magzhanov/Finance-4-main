// nk_tfp_3shocks.mod
// NK (RE, theta=0) with structural TFP + cost-push + MP shocks
// No Taylor inertia. Linear model.

var pi i ygap a u v ynat y;
varexo eps_a eps_u eps_i;

parameters beta sigma varphi kappa phi phi_x rho_a rho_u rho_v lambda chi;

beta   = 0.99;
sigma  = 1.0;
varphi = 1.0;
kappa  = 0.10;

phi    = 1.50;
phi_x  = 0.50;

rho_a  = 0.90;
rho_u  = 0.60;
rho_v  = 0.50;

// flexible-price objects
lambda = (1+varphi)/(sigma+varphi);
chi    = -sigma*lambda*(1-rho_a);

model(linear);

  // identities
  ynat = lambda*a;
  y    = ygap + ynat;

  // "natural real rate" (TFP-based, corrected)
  // rnat = chi*a is substituted directly below

  // IS (output gap)
  ygap = ygap(+1) - (1/sigma)*( i - pi(+1) - chi*a );

  // NKPC
  pi = beta*pi(+1) + kappa*ygap + u;

  // Taylor rule (no inertia) + MP shock state v
  i = phi*(pi + phi_x*ygap) + v;

  // exogenous processes
  a = rho_a*a(-1) + eps_a;
  u = rho_u*u(-1) + eps_u;
  v = rho_v*v(-1) + eps_i;

end;

initval;
  pi = 0;
  i = 0;
  ygap = 0;
  a = 0;
  u = 0;
  v = 0;
  ynat = 0;
  y = 0;
end;

shocks;
  var eps_a; stderr 1;
  var eps_u; stderr 1;
  var eps_i; stderr 1;
end;

// We want horizons 0..40 inclusive -> 41 points
stoch_simul(order=1, irf=41, nograph);
