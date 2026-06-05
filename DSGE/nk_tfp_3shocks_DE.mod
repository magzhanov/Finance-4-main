// nk_tfp_3shocks_DE.mod
// NK with structural TFP + cost-push + MP shocks under Diagnostic Expectations (DE)
// Non-inertial Taylor rule. Linear model.
// Setting theta=0 reproduces the RE benchmark.

var
  pi i ygap a u v              // core: inflation, policy rate, output gap, shocks
  ynat y                       // output identities
  rreal rnat                   // real rate and natural real rate (in deviation form)
  pif pif2 ygf ygf2;           // auxiliary forecast objects for DE revisions
varexo
  eps_a eps_u eps_i;

parameters
  beta sigma varphi kappa
  phi phi_x
  rho_a rho_u rho_v
  theta
  lambda chi;

beta   = 0.99;
sigma  = 1.0;
varphi = 1.0;
kappa  = 0.10;

phi    = 1.50;
phi_x  = 0.50;

rho_a  = 0.90;
rho_u  = 0.60;
rho_v  = 0.50;

// Diagnosticity (theta=0 => RE)
theta  = 0.60;

// flexible-price objects
lambda = (1+varphi)/(sigma+varphi);

// Correct RE natural-rate loading on TFP level (mean reversion term (1-rho_a))
chi    = -sigma*lambda*(1-rho_a);

model(linear);

  // ------------------------------------------------------------------
  // Flexible-price (natural) output and output identity
  // ------------------------------------------------------------------
  ynat = lambda*a;
  y    = ygap + ynat;

  // ------------------------------------------------------------------
  // Auxiliary forecast objects (so that lags represent earlier forecasts)
  //   pif_t  = E_t[pi_{t+1}],     pif(-1) = E_{t-1}[pi_t]
  //   pif2_t = E_t[pi_{t+2}],     pif2(-1)= E_{t-1}[pi_{t+1}]
  //   ygf_t  = E_t[ygap_{t+1}],   ygf2(-1)= E_{t-1}[ygap_{t+1}]
  // ------------------------------------------------------------------
  pif  = pi(+1);
  pif2 = pif(+1);

  ygf  = ygap(+1);
  ygf2 = ygf(+1);

  // ------------------------------------------------------------------
  // Natural real rate under DE (corrected)
  //   rnat_t = -sigma*lambda*(1-rho_a)*a_t  + sigma*lambda*theta*rho_a*eps_a,t
  // ------------------------------------------------------------------
  rnat =
      chi*a
    + sigma*lambda*theta*rho_a*eps_a;

  // ------------------------------------------------------------------
  // Real rate (perceived) under DE
  //   rreal_t = i_t - [ E_t^theta pi_{t+1} + theta( pi_t - E_{t-1}pi_t ) ]
  // where
  //   E_t^theta pi_{t+1} = E_t pi_{t+1} + theta( E_t pi_{t+1} - E_{t-1}pi_{t+1} )
  //                      = pif + theta( pif - pif2(-1) )
  // ------------------------------------------------------------------
  rreal =
      i
    - ( (pif + theta*(pif - pif2(-1))) + theta*(pi - pif(-1)) );

  // ------------------------------------------------------------------
  // IS (output gap) under DE
  //   ygap_t = E_t^theta ygap_{t+1} - (1/sigma)( rreal_t - rnat_t )
  // with
  //   E_t^theta ygap_{t+1} = ygf + theta( ygf - ygf2(-1) )
  // ------------------------------------------------------------------
  ygap =
      (ygf + theta*(ygf - ygf2(-1)))
    - (1/sigma)*(rreal - rnat);

  // ------------------------------------------------------------------
  // NKPC under DE
  //   pi_t = beta E_t^theta pi_{t+1} + kappa ygap_t + u_t
  // ------------------------------------------------------------------
  pi =
      beta*(pif + theta*(pif - pif2(-1)))
    + kappa*ygap
    + u;

  // ------------------------------------------------------------------
  // Taylor rule (no inertia) + MP shock state v
  // ------------------------------------------------------------------
  i = phi*(pi + phi_x*ygap) + v;

  // ------------------------------------------------------------------
  // Exogenous processes (AR(1))
  // ------------------------------------------------------------------
  a = rho_a*a(-1) + eps_a;
  u = rho_u*u(-1) + eps_u;
  v = rho_v*v(-1) + eps_i;

end;

initval;
  pi   = 0;
  i    = 0;
  ygap = 0;
  a    = 0;
  u    = 0;
  v    = 0;
  ynat = 0;
  y    = 0;
  rreal= 0;
  rnat = 0;
  pif  = 0;
  pif2 = 0;
  ygf  = 0;
  ygf2 = 0;
end;

shocks;
  var eps_a; stderr 1;
  var eps_u; stderr 1;
  var eps_i; stderr 1;
end;

// horizons 0..40 inclusive -> 41 points
stoch_simul(order=1, irf=41, nograph);
